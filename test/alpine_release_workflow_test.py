"""Exercise release publication guards without contacting GitHub."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
COMMIT = "a" * 40
TAG = "v30.2-alpine.1"


class AlpineReleaseTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.assets = self.directory / "assets"
        self.assets.mkdir()
        self.bin = self.directory / "bin"
        self.bin.mkdir()
        self.state = self.directory / "state.json"
        self.log = self.directory / "calls.jsonl"
        fake = self.bin / "gh"
        fake.write_text("""#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ["FAKE_GH_LOG"], "a") as log:
    log.write(json.dumps(args) + "\\n")
state = json.loads(Path(os.environ["FAKE_GH_STATE"]).read_text())
if args[0] == "api":
    endpoint = next(arg for arg in args if arg.startswith("repos/"))
    if "/commits/" in endpoint:
        commits = state.get("tag_commits", [state["tag_commit"]])
        calls = [json.loads(line) for line in Path(os.environ["FAKE_GH_LOG"]).read_text().splitlines()]
        count = sum(any("/commits/" in arg for arg in call) for call in calls)
        print(commits[min(count - 1, len(commits) - 1)])
    elif "/actions/workflows/" in endpoint:
        print(json.dumps({"workflow_runs": state["runs"]}))
    elif "/releases?" in endpoint:
        print(state.get("draft", ""), end="")
    else:
        sys.exit(2)
""")
        fake.chmod(0o755)
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        GITHUB_REPOSITORY="example/typesense", TMPDIR=str(self.directory),
                        FAKE_GH_STATE=str(self.state), FAKE_GH_LOG=str(self.log))
        self.write_state()
        for name in ["typesense-30.2-r1.apk", "typesense-openrc-30.2-r1.apk",
                     "typesense-server-30.2-alpine.1-linux-musl-amd64.tar.gz",
                     "APKINDEX.tar.gz", "LICENSE.txt", "typesense-alpine.rsa.pub"]:
            (self.assets / name).write_text(name + "\n")
        (self.assets / "BUILD.json").write_text(json.dumps({
            "tag": TAG, "commit": COMMIT, "repository": "example/typesense",
            "upstream_version": "30.2", "package_revision": "1", "architecture": "x86_64",
        }))
        self.write_checksums()

    def write_state(self, **changes):
        state = {"tag_commit": COMMIT, "runs": [{"status": "completed", "conclusion": "success"}]}
        state.update(changes)
        self.state.write_text(json.dumps(state))

    def write_checksums(self):
        lines = [f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n"
                 for path in sorted(self.assets.iterdir()) if path.name != "SHA256SUMS"]
        (self.assets / "SHA256SUMS").write_text("".join(lines))

    def publish(self):
        return subprocess.run(["bash", str(ROOT / "packaging/alpine/publish.sh"), TAG, COMMIT, str(self.assets)],
                              env=self.env, text=True, capture_output=True, timeout=10)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def release_calls(self):
        return [call for call in self.calls() if call[0] == "release"]

    def test_ci_candidate_has_no_release_revision(self):
        result = subprocess.run(["bash", str(ROOT / "packaging/alpine/version.sh")], text=True, capture_output=True, check=True)
        self.assertIn("release=false\n", result.stdout)
        self.assertIn("revision=0\n", result.stdout)

    def test_release_tag_requires_current_version_and_positive_revision(self):
        for tag in ["v30.3-alpine.1", "v30.2-alpine.0", "v30.2-alpine.01", "v30.2", "v30.2-alpine.1\ninjected=true"]:
            with self.subTest(tag=tag):
                result = subprocess.run(["bash", str(ROOT / "packaging/alpine/version.sh"), tag], capture_output=True)
                self.assertNotEqual(0, result.returncode)
        result = subprocess.run(["bash", str(ROOT / "packaging/alpine/version.sh"), "v30.2-alpine.17"],
                                text=True, capture_output=True, check=True)
        self.assertIn("revision=17\n", result.stdout)
        self.assertIn("release=true\n", result.stdout)

    def test_corrupted_asset_prevents_network_access(self):
        (self.assets / "typesense-30.2-r1.apk").write_text("modified")
        self.assertNotEqual(0, self.publish().returncode)
        self.assertEqual([], self.calls())

    def test_manifest_must_cover_every_asset(self):
        manifest = self.assets / "SHA256SUMS"
        manifest.write_text("".join(line for line in manifest.read_text().splitlines(keepends=True)
                                    if not line.endswith("  typesense-30.2-r1.apk\n")))
        self.assertNotEqual(0, self.publish().returncode)
        self.assertEqual([], self.calls())

    def test_manifest_cannot_add_unexpected_paths(self):
        outside = self.directory / "outside"
        outside.write_text("not a release asset")
        with (self.assets / "SHA256SUMS").open("a") as manifest:
            manifest.write(hashlib.sha256(outside.read_bytes()).hexdigest() + "  ../outside\n")
        self.assertNotEqual(0, self.publish().returncode)
        self.assertEqual([], self.calls())

    def test_incomplete_bundle_prevents_release_creation(self):
        (self.assets / "typesense-openrc-30.2-r1.apk").unlink()
        self.write_checksums()
        self.assertNotEqual(0, self.publish().returncode)
        self.assertEqual([], self.calls())

    def test_metadata_must_match_destination_repository(self):
        path = self.assets / "BUILD.json"
        value = json.loads(path.read_text())
        value["repository"] = "other/typesense"
        path.write_text(json.dumps(value))
        self.write_checksums()
        self.assertNotEqual(0, self.publish().returncode)
        self.assertEqual([], self.calls())

    def test_moved_tag_prevents_publication(self):
        self.write_state(tag_commit="b" * 40)
        self.assertNotEqual(0, self.publish().returncode)
        self.assertEqual([], self.release_calls())

    def test_tag_moved_during_checks_prevents_release_creation(self):
        self.write_state(tag_commits=[COMMIT, "b" * 40])
        self.assertNotEqual(0, self.publish().returncode)
        self.assertEqual([], self.release_calls())

    def test_tag_moved_during_upload_prevents_publication(self):
        self.write_state(tag_commits=[COMMIT, COMMIT, "b" * 40])
        self.assertNotEqual(0, self.publish().returncode)
        self.assertEqual(["create", "upload"], [call[1] for call in self.release_calls()])

    def test_failed_standard_suite_prevents_publication(self):
        self.write_state(runs=[{"status": "completed", "conclusion": "failure"}])
        self.assertNotEqual(0, self.publish().returncode)
        self.assertEqual([], self.release_calls())

    def test_published_release_is_never_overwritten(self):
        self.write_state(draft="false")
        self.assertNotEqual(0, self.publish().returncode)
        self.assertEqual([], self.release_calls())

    def test_assets_are_uploaded_before_publication(self):
        result = self.publish()
        self.assertEqual(0, result.returncode, result.stderr)
        calls = self.release_calls()
        self.assertEqual(["create", "upload", "edit"], [call[1] for call in calls])
        self.assertIn("--verify-tag", calls[0])
        self.assertIn("--draft", calls[0])
        self.assertIn("--draft=false", calls[-1])

    def test_existing_draft_can_resume(self):
        self.write_state(draft="true")
        result = self.publish()
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(["upload", "edit"], [call[1] for call in self.release_calls()])


if __name__ == "__main__":
    unittest.main()
