import json
import os
import re
import subprocess
import textwrap
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch


WORKFLOW = Path(__file__).resolve().parents[1] / ".github/workflows/delete-older-releases-workflows.yml"
RUNS_ENDPOINT = "repos/test/firmware/actions/runs"
NOW = datetime(2026, 11, 18, 15, 37, tzinfo=timezone.utc)


class CleanupWorkflowRunsTests(unittest.TestCase):
    def setUp(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        step = re.search(
            r"(?m)^      - name: Delete expired workflow runs\n"
            r"(?:^        .*\n)*?^        run: \|\n(?P<script>(?:^          .*\n|^\n)*)",
            workflow,
        )
        self.assertIsNotNone(step, "daily cleanup run script is missing")
        self.script = compile(textwrap.dedent(step["script"]), str(WORKFLOW), "exec")

    def test_deletes_only_expired_completed_runs_across_all_pages(self):
        pages = [
            {"workflow_runs": [
                self.run_record(1, "failure", 4),
                self.run_record(2, "failure", 3),
                self.run_record(3, "success", 7),
                self.run_record(4, "success", 8),
            ]},
            {"workflow_runs": [
                self.run_record(5, "cancelled", 3),
                self.run_record(6, "cancelled", 4),
                self.run_record(7, None, 40, status="in_progress"),
                self.run_record(8, "timed_out", 4),
                self.run_record(9, "skipped", 4),
                self.run_record(10, None, 40, status="queued"),
            ]},
        ]
        with (
            patch.dict(os.environ, GITHUB_REPOSITORY="test/firmware"),
            patch("time.time", return_value=NOW.timestamp()),
            patch("subprocess.check_output", return_value=json.dumps(pages)) as list_runs,
            patch("subprocess.run", return_value=subprocess.CompletedProcess([], 0)) as delete_run,
        ):
            exec(self.script, {})

        list_runs.assert_called_once_with(
            ["gh", "api", "--paginate", "--slurp", f"{RUNS_ENDPOINT}?per_page=100"], text=True
        )
        self.assertEqual([call.args[0][-1] for call in delete_run.call_args_list], [
            f"{RUNS_ENDPOINT}/1", f"{RUNS_ENDPOINT}/4", f"{RUNS_ENDPOINT}/6",
            f"{RUNS_ENDPOINT}/8", f"{RUNS_ENDPOINT}/9",
        ])
        self.assertTrue(all("DELETE" in call.args[0] for call in delete_run.call_args_list))

    def test_failed_list_never_attempts_deletion(self):
        with (
            patch.dict(os.environ, GITHUB_REPOSITORY="test/firmware"),
            patch("subprocess.check_output", side_effect=subprocess.CalledProcessError(1, "gh")),
            patch("subprocess.run") as delete_run,
        ):
            with self.assertRaises(subprocess.CalledProcessError):
                exec(self.script, {})

        delete_run.assert_not_called()

    @staticmethod
    def run_record(run_id, conclusion, age, status="completed"):
        return {
            "id": run_id,
            "status": status,
            "conclusion": conclusion,
            "updated_at": (NOW - timedelta(days=age)).isoformat(),
        }


if __name__ == "__main__":
    unittest.main()
