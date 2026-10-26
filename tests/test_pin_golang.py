import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
DEVICES = ("NN6000", "R68S", "NSY-G68-PLUS", "SystemReady")


class PinGolangTests(unittest.TestCase):
    def setUp(self):
        (ROOT / ".tmp").mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=ROOT / ".tmp")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = dict(os.environ, PIN_FIXTURE=str(self.root / "recipe"))
        self.env["PATH"] = str(self.root / "bin") + os.pathsep + self.env["PATH"]
        self.write("feeds/packages/lang/golang/golang1.26/Makefile", "old recipe\n")
        self.write("feeds/packages/net/keep/Makefile", "unrelated package\n")
        for package in ("golang", "golang-bootstrap", "golang1.27"):
            self.write(f"recipe/lang/golang/{package}/Makefile", "new recipe\n")
        self.write("recipe/lang/golang/golang-values.mk", "GO_DEFAULT_VERSION:=1.27\n")
        self.write("recipe/lang/golang/golang1.27/Makefile",
                   "GO_VERSION_MAJOR_MINOR:=1.27\nGO_VERSION_PATCH:=2\n")
        links = self.root / "package/feeds/packages"
        links.mkdir(parents=True)
        (links / "golang1.26").symlink_to("../../../feeds/packages/lang/golang/golang1.26")
        (links / "golang-foreign").symlink_to("../../../feeds/packages/net/keep")
        self.write("bin/git", """#!/bin/bash
set -eu
case "$3" in
    fetch) [[ ${PIN_FAIL:-} != fetch ]] ;;
    archive) tar --mtime=2000-01-01 -cf - -C "$PIN_FIXTURE" lang/golang ;;
    *) exit 99 ;;
esac
""", executable=True)
        self.write("scripts/feeds", """#!/bin/bash
set -eu
echo "$*" >> feeds-calls
case "$*" in
    'update -i packages')
        [[ ${PIN_FAIL:-} != index ]] || exit 23
        [[ ${PIN_FAIL:-} != empty-index ]] || exit 0
        [[ ${PIN_FAIL:-} != stale-index ]] || exit 0
        if [[ -f feeds/packages.index && ! feeds/packages/lang/golang/golang/Makefile -nt feeds/packages.index ]]; then
            exit 0
        fi
        printf '%s\\n' \\
            'Source-Makefile: feeds/packages/lang/golang/golang/Makefile' \\
            'Build-Depends/host: golang1.27/host' \\
            'Source-Makefile: feeds/packages/lang/golang/golang1.27/Makefile' \\
            'Source: go1.27.2.src.tar.gz' > feeds/packages.index ;;
    'install -p packages golang golang1.27')
        [[ ${PIN_FAIL:-} != install ]] || exit 24
        [[ ${PIN_FAIL:-} != missing-link ]] || exit 0
        for package in golang golang1.27 golang-bootstrap; do
            ln -s "../../../feeds/packages/lang/golang/$package" "package/feeds/packages/$package"
        done ;;
    *) exit 99 ;;
esac
""", executable=True)

    def write(self, name, text, executable=False):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        if executable:
            path.chmod(0o755)

    def run_pin(self, failure=""):
        return subprocess.run(["bash", str(ROOT / "pin-golang.sh")], cwd=self.root,
                              env=dict(self.env, PIN_FAIL=failure), text=True,
                              capture_output=True, timeout=15)

    def test_old_go_exits_and_unrelated_packages_survive(self):
        for _ in range(2):
            result = self.run_pin()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Pinned OpenWrt Go 1.27.2", result.stdout)
            self.assertFalse((self.root / "feeds/packages/lang/golang/golang1.26").exists())
            self.assertFalse((self.root / "package/feeds/packages/golang1.26").is_symlink())
            self.assertTrue((self.root / "package/feeds/packages/golang-foreign/Makefile").is_file())
            for package in ("golang", "golang1.27", "golang-bootstrap"):
                link = self.root / "package/feeds/packages" / package
                self.assertEqual(link.resolve(), self.root / "feeds/packages/lang/golang" / package)
            self.assertEqual(list((self.root / "tmp").iterdir()), [])

    def test_fetch_or_recipe_failure_preserves_old_tree(self):
        for failure in ("fetch", "bad-recipe"):
            with self.subTest(failure=failure):
                if failure == "bad-recipe":
                    self.write("recipe/lang/golang/golang-values.mk", "GO_DEFAULT_VERSION:=1.26\n")
                result = self.run_pin(failure)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue((self.root / "feeds/packages/lang/golang/golang1.26/Makefile").is_file())
                self.assertTrue((self.root / "package/feeds/packages/golang1.26").is_symlink())
                self.assertEqual(list((self.root / "tmp").iterdir()), [])

    def test_index_and_install_failures_stop_the_script(self):
        for failure in ("index", "empty-index", "install", "missing-link"):
            with self.subTest(failure=failure):
                result = self.run_pin(failure)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("Pinned OpenWrt", result.stdout)

    def old_index(self):
        self.write("feeds/packages.index",
                   "Source-Makefile: feeds/packages/lang/golang/golang/Makefile\n"
                   "Build-Depends/host: golang1.26/host\n"
                   "Source-Makefile: feeds/packages/lang/golang/golang1.27/Makefile\n"
                   "Source: go1.27.1.src.tar.gz\n")

    def test_old_archive_timestamp_does_not_reuse_cached_index(self):
        self.old_index()
        result = self.run_pin()
        self.assertEqual(result.returncode, 0, result.stderr)
        index = (self.root / "feeds/packages.index").read_text()
        self.assertIn("Build-Depends/host: golang1.27/host", index)
        self.assertIn("Source: go1.27.2.src.tar.gz", index)

    def test_successful_index_command_with_stale_versions_is_rejected(self):
        self.old_index()
        result = self.run_pin("stale-index")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("Pinned OpenWrt", result.stdout)

    def test_all_diy2_callers_order_and_failure_propagation(self):
        shutil.copyfile(ROOT / "pin-golang.sh", self.root / "pin-golang.sh")
        for device in DEVICES:
            with self.subTest(device=device):
                text = (ROOT / device / "diy-part2.sh").read_text(encoding="utf-8")
                calls = [line for line in text.splitlines() if "/../pin-golang.sh" in line]
                self.assertEqual(len(calls), 1)
                call = calls[0]
                self.assertLess(text.rindex("./scripts/feeds update -a"), text.index(call))
                self.assertLess(text.index(call), text.rindex("./scripts/feeds install -a"))
                self.write(f"{device}/entry.sh", '#!/bin/bash\nSCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"\n'
                           + call + '\necho continued > continued\n')
                result = subprocess.run(["bash", str(self.root / device / "entry.sh")],
                                        cwd=self.root, env=dict(self.env, PIN_FAIL="fetch"),
                                        capture_output=True, timeout=15)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.root / "continued").exists())


if __name__ == "__main__":
    unittest.main()
