import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
PATCH = ROOT / "NSY-G68-PLUS/patch/12-smartdns-build-vars.patch"


class SmartDNSBuildVarsTests(unittest.TestCase):
    def test_ui_recipe_keeps_multiword_cross_compiler_in_make_environment(self):
        patch = PATCH.read_text(encoding="utf-8")
        lines = patch.splitlines()
        recipe_start = next((index for index, line in enumerate(lines)
                             if line.startswith("+\t+$(CARGO_PKG_VARS)")), None)
        self.assertIsNotNone(recipe_start, "patch must update the smartdns-ui recipe command")
        recipe = "\n".join(line[1:] for line in lines[recipe_start:recipe_start + 4])

        (ROOT / ".tmp").mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ROOT / ".tmp") as temp:
            root = Path(temp)
            bindir = root / "bin"
            bindir.mkdir()
            capture = root / "make-env"
            make = bindir / "make"
            make.write_text("#!/bin/sh\nprintf '%s' \"$CC\" > \"$CAPTURE\"\n", encoding="utf-8")
            make.chmod(0o755)
            compiler = bindir / "aarch64-openwrt-linux-musl-gcc"
            compiler.write_text("#!/bin/sh\nprintf '%s\\n' \"$CC\" \"$@\" > \"$BROKEN_CAPTURE\"\n",
                                encoding="utf-8")
            compiler.chmod(0o755)

            command = recipe.lstrip("\t").removeprefix("+").replace("$(CARGO_PKG_VARS)", "")
            command = command.replace('$(CARGO_BUILD_ARGS)', "--profile release")
            command = command.replace('$(TARGET_CC)', "ccache aarch64-openwrt-linux-musl-gcc")
            command = command.replace('$$(PATH)', "$PATH")
            command = command.replace('$(CARGO_HOME)', str(root / "cargo"))
            command = command.replace('$(PKG_BUILD_DIR)', str(root / "build"))
            env = dict(os.environ, PATH=str(bindir), CAPTURE=str(capture))
            result = subprocess.run([shutil.which("bash"), "-c", command], env=env,
                                    text=True, capture_output=True, timeout=10)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(capture.read_text(encoding="utf-8"),
                             "ccache aarch64-openwrt-linux-musl-gcc")

            capture.unlink()
            broken_capture = root / "broken-command"
            unquoted = command.replace('CC="ccache aarch64-openwrt-linux-musl-gcc"',
                                       "CC=ccache aarch64-openwrt-linux-musl-gcc")
            result = subprocess.run([shutil.which("bash"), "-c", unquoted],
                                    env=dict(env, BROKEN_CAPTURE=str(broken_capture)),
                                    text=True, capture_output=True, timeout=10)

            self.assertEqual(result.returncode, 0, result.stderr)
            args = broken_capture.read_text(encoding="utf-8").splitlines()
            self.assertEqual(args[0], "ccache")
            self.assertTrue(any(arg.startswith("PATH=") for arg in args))
            self.assertIn("AWS_LC_SYS_CFLAGS=-O0", args)
            self.assertIn("make", args)
            self.assertFalse(capture.exists())


if __name__ == "__main__":
    unittest.main()
