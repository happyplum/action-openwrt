"""Exercise the shipped VLAN table function against busy-status sequences."""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
PATCH = ROOT / "NSY-G68-PLUS/userpatches/target/linux/rockchip/patches-6.12/861-net-dsa-realtek-openwrt.patch"


class VlanTableTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        added = "\n".join(line[1:] for line in PATCH.read_text().splitlines()
                          if line.startswith("+") and not line.startswith("+++"))
        start = added.index("static int rtl8365mb_table_access(")
        function = added[start:added.index("\n}", start) + 2]
        names = set(re.findall(r"\bRTL8365MB_[A-Z0-9_]+\b", function))
        defines = "\n".join(line for line in added.splitlines()
                            if re.match(r"#define\s+(\w+)", line)
                            and re.match(r"#define\s+(\w+)", line).group(1) in names)
        tables = added[added.index("enum rtl8365mb_table {"):
                       added.index("enum rtl8365mb_frame_type {")]
        fixture = (ROOT / "tests/fixtures/rtl8365mb_vlan.c").read_text()
        source = fixture.replace("/* PATCH_CODE */", defines + "\n" + tables + "\n" + function)
        (ROOT / ".tmp").mkdir(exist_ok=True)
        cls.temp = tempfile.TemporaryDirectory(dir=ROOT / ".tmp")
        cls.addClassCleanup(cls.temp.cleanup)
        cfile = Path(cls.temp.name) / "vlan.c"
        cls.binary = Path(cls.temp.name) / "vlan"
        cfile.write_text(source)
        result = subprocess.run(["gcc", "-O2", "-Werror=uninitialized",
                                 "-Werror=maybe-uninitialized", str(cfile),
                                 "-o", str(cls.binary)], capture_output=True, text=True)
        if result.returncode:
            raise AssertionError(result.stderr)

    def run_case(self, name):
        result = subprocess.run([str(self.binary), name], cwd=self.temp.name,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_waits_for_busy_before_command(self):
        self.run_case("pre-busy")

    def test_waits_for_busy_after_command(self):
        self.run_case("post-busy")

    def test_idle_with_address_low_bit_before_command(self):
        self.run_case("pre-idle-low-bit")

    def test_idle_with_address_low_bit_after_command(self):
        self.run_case("post-idle-low-bit")

    def test_permanent_busy_before_command_unlocks_without_reading(self):
        self.run_case("pre-timeout")

    def test_permanent_busy_after_command_unlocks_without_reading(self):
        self.run_case("post-timeout")


if __name__ == "__main__":
    unittest.main()
