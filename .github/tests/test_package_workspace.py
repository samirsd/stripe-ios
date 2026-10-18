"""Exercise the actual CI preparation boundary without fetching dependencies."""
import json
import os
import shutil
from pathlib import Path
import subprocess
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[2]
PACKAGE_NAME = 'stripe-ios'
SCRIPT = REPOSITORY / ".github/scripts/prepare-package-workspace.sh"


class PackageWorkspaceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.checkout = self.root / "checkout"
        self.checkout.mkdir()
        (self.checkout / "Package.swift").write_bytes((REPOSITORY / "Package.swift").read_bytes())
        subprocess.run(["git", "init", "-q", str(self.checkout)], check=True)
        subprocess.run(["git", "-C", str(self.checkout), "add", "Package.swift"], check=True)
        subprocess.run(["git", "-C", str(self.checkout), "-c", "user.name=CI fixture",
            "-c", "user.email=ci-fixture@example.invalid", "commit", "-qm", "fixture"], check=True)
        # These must never become the dependencies/configuration of the CI copy.
        (self.root / "LoggingKit").mkdir()
        (self.root / "LoggingKit/Package.swift").write_text("stale sibling logging dependency")
        (self.checkout / ".swiftpm").mkdir()
        (self.checkout / ".swiftpm/unsafe-local-mirror").write_text("untracked configuration")
        self.environment_file = self.root / "github-env"
        self.environment = dict(os.environ, GITHUB_WORKSPACE=str(self.checkout),
            GITHUB_REPOSITORY="samirsd/" + PACKAGE_NAME, GITHUB_RUN_ID="123", GITHUB_RUN_ATTEMPT="1",
            RUNNER_TEMP=str(self.root / "runner"), GITHUB_ENV=str(self.environment_file), USE_LOCAL_PACKAGES="0",
            SWIFTPM_MODULECACHE_OVERRIDE=str(self.root / "module-cache"),
            CLANG_MODULE_CACHE_PATH=str(self.root / "module-cache"),
            SWIFT_MODULE_CACHE_PATH=str(self.root / "module-cache"),
            )
        subprocess.run(["bash", str(SCRIPT)], env=self.environment, check=True)
        self.values = dict(line.split("=", 1) for line in self.environment_file.read_text().splitlines())
        self.package = Path(self.values["CI_REPO_ROOT"])

    def test_only_tracked_source_is_copied_without_main_siblings(self):
        self.assertEqual((self.package / "Package.swift").read_bytes(), (REPOSITORY / "Package.swift").read_bytes())
        self.assertFalse((self.package / ".swiftpm").exists())
        self.assertFalse((self.package.parent / "LoggingKit").exists())
        self.assertFalse((self.package / ".git").exists())
        for key, value in self.values.items():
            if key.startswith("CI_") and key != "CI_RUN_ROOT":
                self.assertTrue(Path(value).is_relative_to(Path(self.values["CI_RUN_ROOT"])))

    def test_archive_failure_still_exposes_the_isolated_cleanup_root(self):
        self.environment_file.unlink()
        shutil.rmtree(self.checkout / ".git")
        failed = subprocess.run(["bash", str(SCRIPT)],
            env=dict(self.environment, GIT_CEILING_DIRECTORIES=str(self.checkout.parent)),
            capture_output=True, text=True)
        self.assertNotEqual(failed.returncode, 0)
        values = dict(line.split("=", 1) for line in self.environment_file.read_text().splitlines())
        self.assertEqual(values, {"CI_RUN_ROOT": self.values["CI_RUN_ROOT"]})
        self.assertTrue(Path(values["CI_RUN_ROOT"]).is_relative_to(self.root / "runner"))

    def test_remote_resolution_reuses_noninteractive_ssh_without_global_changes(self):
        environment = dict(self.environment, **self.values)
        # --get-url exercises Git's actual rewrite without contacting GitHub.
        resolved = subprocess.check_output(["git", "ls-remote", "--get-url",
            "https://github.com/samirsd/AudioIOKit.git"], env=environment, text=True).strip()
        self.assertEqual(resolved, "git@github.com:samirsd/AudioIOKit.git")
        helpers = subprocess.check_output(["git", "config", "--get-all", "credential.helper"],
            env=environment, text=True).splitlines()
        self.assertEqual(helpers[-1], "")  # Reset any inherited interactive helper.
        self.assertEqual(environment["GIT_TERMINAL_PROMPT"], "0")
        self.assertEqual(environment["GIT_SSH_COMMAND"], "ssh -o BatchMode=yes -o ConnectTimeout=15 -o ConnectionAttempts=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=3")

    def test_actual_manifest_selects_remote_dependencies_and_full_products(self):
        output = subprocess.check_output(["swift", "package", "--package-path", str(self.package), "dump-package"],
            env=self.environment, text=True)
        manifest = json.loads(output)
        self.assertFalse(any(dependency.get("fileSystem") for dependency in manifest["dependencies"]))
        targets = {target["name"] for target in manifest["targets"]}
        self.assertTrue({"StripePayments", "StripePaymentSheet", "StripeCore", "Stripe3DS2"}.issubset(targets))
        products = {product["name"]: product for product in manifest["products"]}
        self.assertEqual(products["StripePaymentSheet"]["targets"], ["StripePaymentSheet"])
        self.assertEqual(products["StripePayments"]["targets"], ["StripePayments"])


    def test_workflow_keeps_real_verification_and_contains_outputs(self):
        workflow = (REPOSITORY / ".github/workflows/carnyx-catalyst-qualification.yml").read_text()
        verify = (REPOSITORY / ".github/scripts/verify-carnyx-catalyst.sh").read_text()
        helper = (REPOSITORY / "CarnyxTests/run_lifecycle_tests.py").read_text()
        self.assertIn("codex/carnyx-stripe-26.12-base", workflow)
        self.assertIn("codex/carnyx-catalyst-redirect", workflow)
        self.assertIn('runs-on: [self-hosted, macOS, ARM64, carnyx, carnyx-catalyst-redirect-v1]', workflow)
        self.assertNotIn('runs-on: [self-hosted, macOS, ARM64, carnyx]', workflow)
        self.assertNotIn("--branch main", workflow + verify)
        self.assertIn("bash .github/scripts/prepare-package-workspace.sh", workflow)
        self.assertIn('bash "${CI_REPO_ROOT}/.github/scripts/verify-carnyx-catalyst.sh"', workflow)
        self.assertIn("if: always()", workflow)
        self.assertIn("python3 CarnyxTests/run_lifecycle_tests.py", verify)
        self.assertIn('"swift", "test", "--jobs", "2"', helper)
        self.assertEqual(verify.count("-scheme StripePaymentSheet"), 2)
        self.assertIn("generic/platform=iOS", verify)
        self.assertIn("generic/platform=macOS,variant=Mac Catalyst", verify)
        self.assertIn("ARCHS=arm64 x86_64", verify)
        self.assertIn("python3 CarnyxTests/prepare_handler_test_package.py", verify)
        self.assertIn("-scheme CarnyxStripeHandlerTests-Package", verify)
        self.assertIn("platform=macOS,variant=Mac Catalyst,arch=arm64", verify)
        self.assertIn("CODE_SIGNING_ALLOWED=NO", verify)
        self.assertIn("CODE_SIGNING_REQUIRED=NO test", verify)
        self.assertNotIn("--skip", workflow + verify + helper)
        self.assertNotIn("--filter", workflow + verify + helper)
        self.assertNotIn("-only-testing", verify)
        for option in ("scratch", "cache", "config", "security"):
            self.assertIn("--" + option + "-path", helper)
        for option in ("derivedDataPath", "clonedSourcePackagesDirPath", "resultBundlePath"):
            self.assertIn("-" + option, verify)




if __name__ == "__main__":
    unittest.main()
