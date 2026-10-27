import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
BOARD = ROOT / "NSY-G68-PLUS"
DTS_DIR = Path("target/linux/rockchip/files/arch/arm64/boot/dts/rockchip")
NETWORK_DIR = Path("target/linux/rockchip/armv8/base-files/etc/board.d")


class NsySwitchModeTests(unittest.TestCase):
    def setUp(self):
        (ROOT / ".tmp").mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=ROOT / ".tmp")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source/NSY-G68-PLUS"
        self.build = self.root / "openwrt"
        self.assets = self.root / "remote/NSY-G68-PLUS"
        self.source.mkdir(parents=True)
        self.assets.mkdir(parents=True)
        for suffix in ("", ".dsa", ".switch"):
            shutil.copyfile(BOARD / f".config{suffix}", self.source / f".config{suffix}")
        self.original_config = (self.source / ".config").read_bytes()
        for mode in ("", "-dsa", "-switch"):
            name = DTS_DIR / f"rk3568-nsy-g68-plus{mode}.dts"
            self.copy_asset(name)
        for mode in ("", ".dsa", ".switch"):
            self.copy_asset(NETWORK_DIR / f"02_network{mode}")
        (self.assets / "patch").mkdir()
        (self.build / "target/linux/rockchip/image").mkdir(parents=True)
        (self.build / "target/linux/rockchip/image/armv8.mk").write_text("")
        (self.build / "target/linux/rockchip/Makefile").write_text("KERNEL_PATCHVER:=6.12\n")
        (self.build / ".config").write_text("stale build configuration\n")
        text = (BOARD / "diy-part2.sh").read_text(encoding="utf-8")
        setup = text.split("# 修正自动编译 openwrt 时 rust")[0]
        device = text[text.index("# 添加 G68-Plus 设备定义"):text.index("# 应用 patch 目录")]
        (self.source / "diy-part2.sh").write_text(
            setup + device + '\nprintf done > mode-done\n', encoding="utf-8")
        self.env = dict(os.environ)
        self.env.pop("SWMODE", None)

    def copy_asset(self, name):
        dest = self.assets / "userpatches" / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(BOARD / "userpatches" / name, dest)

    def use_local_assets(self):
        shutil.copytree(self.assets / "userpatches", self.source / "userpatches")
        (self.source / "patch").mkdir()

    def run_setup(self, mode=None):
        env = dict(self.env)
        if mode is not None:
            env["SWMODE"] = mode
        return subprocess.run(["bash", str(self.source / "diy-part2.sh")],
                              cwd=self.build, env=env, text=True,
                              capture_output=True, timeout=15)

    def assert_mode(self, mode, result):
        self.assertEqual(result.returncode, 0, result.stderr)
        for active, template in (
            (DTS_DIR / "rk3568-nsy-g68-plus.dts", DTS_DIR / f"rk3568-nsy-g68-plus-{mode}.dts"),
            (NETWORK_DIR / "02_network", NETWORK_DIR / f"02_network.{mode}"),
        ):
            self.assertEqual((self.build / active).read_bytes(),
                             (self.assets / "userpatches" / template).read_bytes())
        for mode_template in ("02_network.dsa", "02_network.switch"):
            self.assertFalse((self.build / NETWORK_DIR / mode_template).exists(),
                             f"runtime board.d must not execute {mode_template}")
        self.assertEqual((self.build / ".config").read_bytes(),
                         (BOARD / f".config.{mode}").read_bytes())
        self.assertEqual((self.source / ".config").read_bytes(), self.original_config)
        image = (self.build / "target/linux/rockchip/image/armv8.mk").read_text()
        expected = "kmod-dsa-rtl8365mb" if mode == "dsa" else "kmod-switch-rtl8367b"
        other = "kmod-switch-rtl8367b" if mode == "dsa" else "kmod-dsa-rtl8365mb"
        self.assertIn(f"DEVICE_PACKAGES := {expected}", image)
        self.assertNotIn(other, image)

    def test_default_uses_dsa_in_active_build_tree(self):
        self.use_local_assets()
        self.assert_mode("dsa", self.run_setup())

    def test_explicit_switch_uses_matching_active_files(self):
        self.use_local_assets()
        self.assert_mode("switch", self.run_setup("switch"))

    def test_cloned_assets_reach_active_build_tree(self):
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        git = bin_dir / "git"
        git.write_text('''#!/bin/bash
case "$1" in
    clone) cp -r "$NSY_PATCH_FIXTURE" "${!#}/NSY-G68-PLUS" ;;
    sparse-checkout) exit 0 ;;
    *) exit 99 ;;
esac
''')
        git.chmod(0o755)
        self.env.update(PATH=str(bin_dir) + os.pathsep + self.env["PATH"],
                        NSY_PATCH_FIXTURE=str(self.assets))
        self.assert_mode("dsa", self.run_setup("dsa"))

    def test_missing_mode_config_stops_before_device_generation(self):
        self.use_local_assets()
        (self.source / ".config.dsa").unlink()
        result = self.run_setup("dsa")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.build / "mode-done").exists())
        self.assertEqual((self.source / ".config").read_bytes(), self.original_config)

    def test_mismatched_kernel_stops_before_board_overlay(self):
        self.use_local_assets()
        (self.build / "target/linux/rockchip/Makefile").write_text("KERNEL_PATCHVER:=6.18\n")
        result = self.run_setup("dsa")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("6.12", result.stderr)
        self.assertFalse((self.build / DTS_DIR / "rk3568-nsy-g68-plus.dts").exists())

    def test_image_patch_failure_stops_build(self):
        text = (BOARD / "diy-part2.sh").read_text(encoding="utf-8")
        patching = text[text.index("# 应用 patch 目录"):text.index('echo "编译 执行完成"')]
        (self.build / "patch").mkdir()
        (self.build / "patch/required.patch").write_text("required patch\n")
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        git = bin_dir / "git"
        git.write_text('''#!/bin/bash
case "$2" in
    --stat) exit 0 ;;
    --check) [[ "$PATCH_FAILURE" != check ]] ;;
    *) [[ "$PATCH_FAILURE" != apply ]] ;;
esac
''')
        git.chmod(0o755)
        for failure in ("check", "apply"):
            with self.subTest(failure=failure):
                result = subprocess.run(
                    ["bash", "-c", patching + '\nprintf continued > patch-done\n'],
                    cwd=self.build, env=dict(self.env, PATCH_FAILURE=failure,
                                            PATH=str(bin_dir) + os.pathsep + self.env["PATH"]),
                    text=True, capture_output=True, timeout=15)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.build / "patch-done").exists())


if __name__ == "__main__":
    unittest.main()
