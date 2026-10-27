import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/build-openwrt-NSY-G68-PLUS.yml"


class NsyReleaseOutputTests(unittest.TestCase):
    def test_release_step_writes_outputs_to_github_output(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        step = re.search(
            r"(?m)^      - name: Generate release tag\n(?P<body>(?:^        .*\n|^\n)*)",
            workflow,
        )
        self.assertIsNotNone(step, "release tag step is missing")
        run = re.search(r"(?m)^        run: \|\n(?P<script>(?:^          .*\n|^\n)*)", step["body"])
        self.assertIsNotNone(run, "release tag run script is missing")
        script = "\n".join(
            line[10:] if line.startswith("          ") else ""
            for line in run["script"].splitlines()
        )
        script = script.replace("${{ env.BOARD }}", "NSY-G68-PLUS")
        script = script.replace("${{ github.output }}", "")

        (ROOT / ".tmp").mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="nsy release ", dir=ROOT / ".tmp") as temp:
            temp_path = Path(temp)
            output = temp_path / "github output file"
            result = subprocess.run(
                [shutil.which("bash"), "-c", script],
                cwd=ROOT,
                env=dict(os.environ, GITHUB_OUTPUT=str(output)),
                capture_output=True,
                text=True,
            )
            contents = output.read_text(encoding="utf-8") if output.exists() else ""

        self.assertEqual(result.returncode, 0, result.stderr)
        tag, name, status = contents.splitlines()
        self.assertRegex(tag, r"^release_tag=NSY-G68-PLUS-\d{4}\.\d{2}$")
        self.assertRegex(name, r"^release_name=NSY-G68-PLUS \d{4}\.\d{2}$")
        self.assertEqual(tag.removeprefix("release_tag=NSY-G68-PLUS-"), name.removeprefix("release_name=NSY-G68-PLUS "))
        self.assertEqual(status, "status=success")


if __name__ == "__main__":
    unittest.main()
