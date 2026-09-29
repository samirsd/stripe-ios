#!/usr/bin/env python3
"""Prepare a local Catalyst XCTest package; deliberately does not launch/build it."""
import argparse
import json
import pathlib
import shutil

parser = argparse.ArgumentParser()
parser.add_argument("--output", required=True, type=pathlib.Path)
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
out = args.output.resolve()
(out / "Tests/CatalystHandlerTests").mkdir(parents=True, exist_ok=True)
shutil.copyfile(root / "StripePayments/StripePaymentsTests/STPPaymentHandlerCatalystRedirectTests.swift", out / "Tests/CatalystHandlerTests/STPPaymentHandlerCatalystRedirectTests.swift")
# JSON quoting is also valid Swift string-literal quoting for these filesystem paths.
(out / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "CarnyxStripeHandlerTests", platforms: [.iOS(.v15)],
    dependencies: [.package(name: "Stripe", path: ''' + json.dumps(str(root)) + ''')],
    targets: [.testTarget(name: "CatalystHandlerTests", dependencies: [.product(name: "StripePayments", package: "Stripe")])])
''')
print(out)
