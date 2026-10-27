"""Run the shipped VLAN state functions against register-backed boundary mocks."""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PATCH = ROOT / "NSY-G68-PLUS/userpatches/target/linux/rockchip/patches-6.12/861-net-dsa-realtek-openwrt.patch"


class VlanStateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.added = "\n".join(line[1:] for line in PATCH.read_text().splitlines()
                              if line.startswith("+") and not line.startswith("+++"))
        functions = []
        for name in ("buf_vlan4k", "vlan4k_buf", "vlan4k_set", "buf_vlanmc",
                     "vlanmc_buf", "vlanmc_set", "vlan_add", "vlan_del",
                     "port_bridge_join", "port_bridge_leave", "vlan_filtering"):
            match = re.search(r"static (?:int|void)\s+rtl8365mb_" + name + r"\(", cls.added)
            start = match.start()
            functions.append(cls.added[start:cls.added.index("\n}", start) + 2])
        macros = cls.added[:cls.added.index("enum rtl8365mb_table {")]
        start = cls.added.index("enum rtl8365mb_frame_type {")
        enums = cls.added[start:cls.added.index("};", start) + 2]
        start = cls.added.index("struct rtl8365mb_vlan_undo {")
        undo = cls.added[start:cls.added.index("};", start) + 2]
        fixture = (ROOT / "tests/fixtures/rtl8365mb_vlan_state.c").read_text()
        source = fixture.replace("/* PATCH_CODE */", macros + enums + "\n" + undo + "\n" + "\n".join(functions))
        (ROOT / ".tmp").mkdir(exist_ok=True)
        cls.temp = tempfile.TemporaryDirectory(dir=ROOT / ".tmp")
        cls.addClassCleanup(cls.temp.cleanup)
        cfile = Path(cls.temp.name) / "state.c"
        cls.binary = Path(cls.temp.name) / "state"
        cfile.write_text(source)
        result = subprocess.run(["gcc", "-O2", "-Werror=uninitialized",
                                 "-Werror=maybe-uninitialized", str(cfile), "-o", str(cls.binary)],
                                capture_output=True, text=True)
        if result.returncode:
            raise AssertionError(result.stderr)

    def run_case(self, name):
        result = subprocess.run([str(self.binary), name], cwd=self.temp.name,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_even_pvid_delete(self): self.run_case("delete-even")
    def test_odd_pvid_delete(self): self.run_case("delete-odd")
    def test_pvid_write_preserves_reserved_and_neighbor_bits(self): self.run_case("write-pvid")
    def test_remove_pvid_flag_keeps_membership(self): self.run_case("revoke-pvid")
    def test_noncurrent_vlan_update_keeps_pvid(self): self.run_case("noncurrent")
    def test_aware_bridge_leave(self): self.run_case("leave-aware")
    def test_unaware_bridge_leave(self): self.run_case("leave-unaware")
    def test_leave_isolation_failure(self): self.run_case("fail-isolation")
    def test_leave_peer_isolation_failure(self): self.run_case("fail-peer-isolation")
    def test_leave_pvid_failure(self): self.run_case("fail-pvid")
    def test_leave_frame_failure(self): self.run_case("fail-frame")
    def test_delete_first_errno(self): self.run_case("errno-first")
    def test_delete_second_errno(self): self.run_case("errno-second")
    def test_delete_both_errno(self): self.run_case("errno-both")
    def test_delete_success(self): self.run_case("errno-none")

    def test_join_failure_restores_isolation(self):
        for stage in ("first", "middle", "self", "read"):
            for suffix in ("", "-applied"):
                with self.subTest(stage=stage, suffix=suffix):
                    self.run_case("join-" + stage + suffix)

    def test_join_rollback_failure_logs_original_errno(self):
        self.run_case("join-self-rollback")

    def test_new_mc_uses_decoded_4k_members_and_reuses_slots(self):
        self.run_case("mixed-format")

    def test_add_failure_restores_all_vlan_fields(self):
        for kind in ("new", "existing"):
            for stage in ("mc-read", "mc-write", "pvid-read", "frame-read",
                          "pvid-write", "frame-write", "4k-read", "4k-write"):
                for suffix in ("", "-applied"):
                    with self.subTest(kind=kind, stage=stage, suffix=suffix):
                        self.run_case("add-" + kind + "-" + stage + suffix)
        self.run_case("add-existing-revoke-4k-write-applied")

    def test_add_rollback_failure_logs_original_errno(self):
        self.run_case("add-existing-4k-write-rollback")

    def test_table_lock_initialized_before_vlan_init(self):
        setup = self.added[self.added.index("user_ports = dsa_user_ports(ds);"):]
        self.assertLess(setup.index("mutex_init(&mb->table_lock)"),
                        setup.index("rtl8365mb_vlan_init(ds)"))


if __name__ == "__main__":
    unittest.main()
