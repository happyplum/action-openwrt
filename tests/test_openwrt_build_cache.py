import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github/workflows"
ACTION = ROOT / ".github/actions/openwrt-cache/action.yml"


class BuildCacheTests(unittest.TestCase):
    FIRMWARE = {"NN6000": "firmware-squashfs-sysupgrade.bin",
                "r68s": "firmware-sysupgrade.img.gz",
                "SystemReady": "firmware-rootfs.tar.gz"}

    def test_cleanup_keeps_post_job_cache_contents(self):
        cache_paths = re.findall(r"^        path: /builder/openwrt/(.+)$",
                                 ACTION.read_text(), re.MULTILINE)
        self.assertCountEqual(cache_paths, [".ccache", "dl"])
        for board, firmware in self.FIRMWARE.items():
            workflow = (WORKFLOWS / f"build-openwrt-{board}.yml").read_text(encoding="utf-8")
            self.assertNotRegex(workflow, r"ln -s[^\n]*\.ccache")
            # The runner VM is discarded after the job, so nothing may delete build
            # directories before the post-job cache save reads them.
            self.assertNotRegex(workflow, r"ls -A \|[^\n]*rm -rf")
            clean = next(step for step in re.findall(r"run: \|\n((?:          .*(?:\n|$))+)", workflow)
                         if "FIRMWARE=" in step)
            with self.subTest(board=board), tempfile.TemporaryDirectory() as temp:
                job = Path(temp)
                build = job / "openwrt"
                for path in [*cache_paths, "build_dir"]:
                    (build / path).mkdir(parents=True)
                    (build / path / "entry").write_bytes(b"data")
                (build / "bin/targets/target/subtarget").mkdir(parents=True)
                (build / "bin/targets/target/subtarget" / firmware).write_bytes(b"firmware")
                github_env, github_output = job / "env", job / "output"
                script = clean.replace("${{ github.env }}", str(github_env)) \
                                .replace("${{ github.output }}", str(github_output))
                subprocess.run(["bash", "-ec", script], cwd=job, check=True)
                for path in [*cache_paths, "build_dir"]:
                    self.assertTrue((build / path / "entry").is_file(), path)
                released = [p.name for p in (build / "output").iterdir()]
                self.assertEqual(len(released), 1, released)
                self.assertTrue(released[0].endswith(firmware), released)
                self.assertIn(f"FIRMWARE={build / 'output'}", github_env.read_text())

    @unittest.skipUnless(all(shutil.which(tool) for tool in ("ccache", "gcc", "make", "tar")),
                         "requires ccache and the native build tools")
    def test_archived_compiler_output_is_reused_in_next_build(self):
        with tempfile.TemporaryDirectory() as temp:
            build = Path(temp)
            cache = build / ".ccache"
            (build / "dl").mkdir()
            binaries = build / "staging_dir/host/bin"
            binaries.mkdir(parents=True)
            (binaries / "ccache").symlink_to(shutil.which("ccache"))
            (build / "unit.c").write_text("int answer(void) { return 42; }\n")
            (build / "Makefile").write_text("all:\n\tccache gcc -c unit.c -o unit.o\n")
            env = dict(os.environ, CCACHE_DIR=str(cache), CCACHE_COMPILERCHECK="content",
                       CCACHE_STATSLOG=str(build / "stats"), RUNNER_TEMP=temp,
                       GITHUB_STEP_SUMMARY=str(build / "summary"))
            compile_cmd = ["bash", str(ROOT / ".github/scripts/compile-openwrt.sh"), "2"]
            subprocess.run(compile_cmd, cwd=build, env=env, check=True)
            self.assertIn("cache_miss", (build / "stats").read_text())
            subprocess.run(["tar", "-cf", "cache.tar", ".ccache"], cwd=build, check=True)
            shutil.rmtree(cache)
            (build / "unit.o").unlink()
            (build / "stats").unlink()
            subprocess.run(["tar", "-xf", "cache.tar"], cwd=build, check=True)
            subprocess.run(compile_cmd, cwd=build, env=env, check=True)
            self.assertRegex((build / "stats").read_text(), r"(direct|preprocessed)_cache_hit")


if __name__ == "__main__":
    unittest.main()
