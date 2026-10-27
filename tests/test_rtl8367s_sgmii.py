"""Execute the SGMII functions from the shipped kernel patch against regmap mocks."""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
PATCH = ROOT / "NSY-G68-PLUS/userpatches/target/linux/rockchip/patches-6.12/862-net-dsa-realtek-add-sgmii-amd-hsgmii-support-for-rtl8365mb.patch"


class SgmiiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        added = "\n".join(line[1:] for line in PATCH.read_text().splitlines()
                          if line.startswith("+") and not line.startswith("+++"))
        functions = []
        for name in ("sds_poll_busy", "sds_indacs_write", "sds_indacs_read", "get_chip_option",
                     "ext_init_sgmii", "ext_sgmii_nway"):
            start = added.index("static int rtl8365mb_" + name + "(")
            end = added.index("\n}", start) + 2
            functions.append(added[start:end])
        tables = added[added.index("struct rtl8365mb_sds_init {"):]
        tables = tables[:tables.index("static int rtl8365mb_sds_poll_busy")]
        defines = "\n".join(re.findall(r"^#define[^\n]+", added, re.M))
        fixture = (ROOT / "tests/fixtures/rtl8367s_sgmii.c").read_text()
        source = fixture.replace("/* PATCH_CODE */", defines + "\n" + tables + "\n" + "\n".join(functions))
        (ROOT / ".tmp").mkdir(exist_ok=True)
        cls.temp = tempfile.TemporaryDirectory(dir=ROOT / ".tmp")
        cls.addClassCleanup(cls.temp.cleanup)
        cfile = Path(cls.temp.name) / "sgmii.c"
        cls.binary = Path(cls.temp.name) / "sgmii"
        cfile.write_text(source)
        result = subprocess.run(["gcc", "-O2", "-Werror=uninitialized",
                                 "-Werror=maybe-uninitialized", str(cfile),
                                 "-o", str(cls.binary)], capture_output=True, text=True)
        if result.returncode:
            raise AssertionError(result.stderr)

    def run_case(self, name):
        result = subprocess.run([str(self.binary), name], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_extint_register_selection(self):
        self.run_case("extint")

    def test_indirect_read_preserves_data(self):
        self.run_case("read")

    def test_indirect_read_errors(self):
        self.run_case("read-errors")

    def test_indirect_write_errors(self):
        self.run_case("write-errors")

    def test_indirect_busy_timeout(self):
        self.run_case("timeout")

    def test_nway_running_read_error(self):
        self.run_case("nway-error")

    def test_nway_preserves_other_bits(self):
        self.run_case("nway")


if __name__ == "__main__":
    unittest.main()
