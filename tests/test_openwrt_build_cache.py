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
    def test_cleanup_keeps_post_job_cache_contents(self):
        cache_paths = re.findall(r"^        path: /builder/openwrt/(.+)$",
                                 ACTION.read_text(), re.MULTILINE)
        self.assertCountEqual(cache_paths, [".ccache", "dl"])
        for board in ("NN6000", "r68s", "SystemReady"):
            workflow = (WORKFLOWS / f"build-openwrt-{board}.yml").read_text(encoding="utf-8")
            self.assertNotRegex(workflow, r"ln -s[^\n]*\.ccache")
            cleanup = next(line.strip() for line in workflow.splitlines() if "ls -A |" in line)
            with self.subTest(board=board), tempfile.TemporaryDirectory() as temp:
                build = Path(temp)
                for path in [*cache_paths, "output", "build_dir"]:
                    (build / path).mkdir()
                    (build / path / "entry").write_bytes(b"data")
                subprocess.run(["bash", "-ec", cleanup], cwd=build, check=True)
                self.assertTrue((build / ".ccache/entry").is_file())
                self.assertEqual((build / "dl/entry").is_file(), board == "r68s")
                self.assertTrue((build / "output/entry").is_file())
                self.assertFalse((build / "build_dir").exists())

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
