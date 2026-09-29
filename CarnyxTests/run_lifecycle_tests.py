#!/usr/bin/env python3
"""Compile the exact checked-out Foundation helper, without any Stripe networking."""
import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--output", type=pathlib.Path, required=True)
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
source = root / "StripePayments/StripePayments/Source/PaymentHandler/STPCatalystRedirectLifecycle.swift"
tests = root / "CarnyxTests/STPCatalystRedirectLifecycleTests.swift"
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
package = out / "lifecycle-package"
(package / "Sources/CatalystRedirectLifecycle").mkdir(parents=True, exist_ok=True)
(package / "Tests/CatalystRedirectLifecycleTests").mkdir(parents=True, exist_ok=True)
shutil.copyfile(source, package / "Sources/CatalystRedirectLifecycle/STPCatalystRedirectLifecycle.swift")
shutil.copyfile(tests, package / "Tests/CatalystRedirectLifecycleTests/STPCatalystRedirectLifecycleTests.swift")
(package / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "CatalystRedirectLifecycle", platforms: [.macOS(.v13)], targets: [
    .target(name: "CatalystRedirectLifecycle"),
    .testTarget(name: "CatalystRedirectLifecycleTests", dependencies: ["CatalystRedirectLifecycle"]),
])
''')
command = ["swift", "test", "--package-path", str(package), "--parallel", "--num-workers", "1"]
with (out / "lifecycle-tests.log").open("w") as log:
    result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
report = {"source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
          "tests_sha256": hashlib.sha256(tests.read_bytes()).hexdigest(),
          "exit_code": result.returncode, "command": command,
          "scope": "Exact production lifecycle helper; Foundation notifications. No UIKit or network execution."}
(out / "lifecycle-result.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
sys.exit(result.returncode)
