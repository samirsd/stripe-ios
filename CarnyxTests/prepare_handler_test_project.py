#!/usr/bin/env python3
"""Generate an owned Catalyst app-hosted XCTest project; never build or launch it."""
import argparse
import hashlib
import json
import pathlib
import shutil
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument("--output", required=True, type=pathlib.Path)
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
out = args.output.resolve()
project = out / "CarnyxStripeHandlerTests.xcodeproj"
(project / "xcshareddata/xcschemes").mkdir(parents=True, exist_ok=True)
(out / "Host").mkdir(parents=True, exist_ok=True)
(out / "Tests").mkdir(parents=True, exist_ok=True)
fixture = root / "StripePayments/StripePaymentsTests/STPPaymentHandlerCatalystRedirectTests.swift"
shutil.copyfile(fixture, out / "Tests/STPPaymentHandlerCatalystRedirectTests.swift")
(out / "Host/AppDelegate.swift").write_text('''import UIKit
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
''')

def oid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def encode(value, indent=0):
    pad = "\t" * indent
    if isinstance(value, dict):
        return "{\n" + "".join(pad + "\t" + json.dumps(str(k)) + " = " + encode(v, indent + 1) + ";\n" for k, v in value.items()) + pad + "}"
    if isinstance(value, list):
        return "(\n" + "".join(pad + "\t" + encode(v, indent + 1) + ",\n" for v in value) + pad + ")"
    return json.dumps(str(value))

objects = {}
def add(object_key, isa, **fields):
    objects[oid(object_key)] = {"isa": isa, **fields}
    return oid(object_key)

host_ref = add("host-source", "PBXFileReference", lastKnownFileType="sourcecode.swift", path="Host/AppDelegate.swift", sourceTree="<group>")
test_ref = add("test-source", "PBXFileReference", lastKnownFileType="sourcecode.swift", path="Tests/STPPaymentHandlerCatalystRedirectTests.swift", sourceTree="<group>")
app_ref = add("app-product", "PBXFileReference", explicitFileType="wrapper.application", includeInIndex=0, path="CarnyxStripeHandlerHost.app", sourceTree="BUILT_PRODUCTS_DIR")
bundle_ref = add("test-product", "PBXFileReference", explicitFileType="wrapper.cfbundle", includeInIndex=0, path="CatalystHandlerTests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
host_build = add("host-build", "PBXBuildFile", fileRef=host_ref)
test_build = add("test-build", "PBXBuildFile", fileRef=test_ref)
package = add("stripe-package", "XCLocalSwiftPackageReference", relativePath=str(root))
payments = add("payments-product", "XCSwiftPackageProductDependency", package=package, productName="StripePayments")
payments_build = add("payments-build", "PBXBuildFile", productRef=payments)
common = {"SWIFT_VERSION": "5.0", "SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "15.0",
          "MACOSX_DEPLOYMENT_TARGET": "12.0",
          "SUPPORTS_MACCATALYST": "YES", "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
          "TARGETED_DEVICE_FAMILY": "2", "GENERATE_INFOPLIST_FILE": "YES",
          "CODE_SIGNING_ALLOWED": "NO", "CODE_SIGNING_REQUIRED": "NO"}

def configs(name, settings):
    entries = []
    for config in ["Debug", "Release"]:
        build = dict(common, **settings)
        build.update({"SWIFT_OPTIMIZATION_LEVEL": "-Onone" if config == "Debug" else "-O", "ENABLE_TESTABILITY": "YES" if config == "Debug" else "NO"})
        if config == "Debug":
            build["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG $(inherited)"
            build["ONLY_ACTIVE_ARCH"] = "YES"
        entries.append(add(name + config, "XCBuildConfiguration", name=config, buildSettings=build))
    return add(name + "configs", "XCConfigurationList", buildConfigurations=entries, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")

host_sources = add("host-sources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=[host_build], runOnlyForDeploymentPostprocessing=0)
test_sources = add("test-sources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=[test_build], runOnlyForDeploymentPostprocessing=0)
host_frameworks = add("host-frameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
test_frameworks = add("test-frameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[payments_build], runOnlyForDeploymentPostprocessing=0)
host = add("host-target", "PBXNativeTarget", name="CarnyxStripeHandlerHost", productName="CarnyxStripeHandlerHost", productReference=app_ref,
    productType="com.apple.product-type.application", buildPhases=[host_sources, host_frameworks], buildRules=[], dependencies=[],
    buildConfigurationList=configs("host", {"PRODUCT_BUNDLE_IDENTIFIER": "com.carnyx.qa.StripeHandlerHost", "PRODUCT_NAME": "$(TARGET_NAME)", "INFOPLIST_KEY_UILaunchScreen_Generation": "YES"}))
proxy = add("host-proxy", "PBXContainerItemProxy", containerPortal=oid("project"), proxyType=1, remoteGlobalIDString=host, remoteInfo="CarnyxStripeHandlerHost")
dependency = add("host-dependency", "PBXTargetDependency", target=host, targetProxy=proxy)
tests = add("tests-target", "PBXNativeTarget", name="CatalystHandlerTests", productName="CatalystHandlerTests", productReference=bundle_ref,
    productType="com.apple.product-type.bundle.unit-test", buildPhases=[test_sources, test_frameworks], buildRules=[], dependencies=[dependency], packageProductDependencies=[payments],
    buildConfigurationList=configs("tests", {"PRODUCT_BUNDLE_IDENTIFIER": "com.carnyx.qa.StripeHandlerTests", "PRODUCT_NAME": "$(TARGET_NAME)",
        "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/CarnyxStripeHandlerHost.app/Contents/MacOS/CarnyxStripeHandlerHost", "BUNDLE_LOADER": "$(TEST_HOST)",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"]}))
products = add("products", "PBXGroup", name="Products", sourceTree="<group>", children=[app_ref, bundle_ref])
main = add("main", "PBXGroup", sourceTree="<group>", children=[host_ref, test_ref, products])
add("project", "PBXProject", attributes={"LastUpgradeCheck": "2650", "TargetAttributes": {tests: {"TestTargetID": host}}},
    buildConfigurationList=configs("project", {}), compatibilityVersion="Xcode 14.0", developmentRegion="en", knownRegions=["en", "Base"],
    mainGroup=main, productRefGroup=products, projectDirPath="", projectRoot="", targets=[host, tests], packageReferences=[package])
(project / "project.pbxproj").write_text("// !$*UTF8*$!\n" + encode({"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": oid("project")}) + "\n")
scheme = ET.Element("Scheme", {"LastUpgradeVersion": "2650", "version": "1.3"})
def reference(parent, target, name):
    return ET.SubElement(parent, "BuildableReference", {"BuildableIdentifier": "primary", "BlueprintIdentifier": target, "BuildableName": name,
        "BlueprintName": "CatalystHandlerTests" if target == tests else "CarnyxStripeHandlerHost", "ReferencedContainer": "container:CarnyxStripeHandlerTests.xcodeproj"})
action = ET.SubElement(scheme, "BuildAction", {"parallelizeBuildables": "YES", "buildImplicitDependencies": "YES"})
entries = ET.SubElement(action, "BuildActionEntries")
for target, name in [(host, "CarnyxStripeHandlerHost.app"), (tests, "CatalystHandlerTests.xctest")]:
    entry = ET.SubElement(entries, "BuildActionEntry", {"buildForTesting": "YES", "buildForRunning": "NO", "buildForProfiling": "NO", "buildForArchiving": "NO", "buildForAnalyzing": "YES"})
    reference(entry, target, name)
action = ET.SubElement(scheme, "TestAction", {"buildConfiguration": "Debug", "selectedDebuggerIdentifier": "Xcode.DebuggerFoundation.Debugger.LLDB", "selectedLauncherIdentifier": "Xcode.IDEFoundation.Launcher.LLDB", "shouldUseLaunchSchemeArgsEnv": "YES"})
entry = ET.SubElement(ET.SubElement(action, "Testables"), "TestableReference", {"skipped": "NO"})
reference(entry, tests, "CatalystHandlerTests.xctest")
reference(ET.SubElement(action, "MacroExpansion"), host, "CarnyxStripeHandlerHost.app")
ET.indent(scheme)
ET.ElementTree(scheme).write(project / "xcshareddata/xcschemes/CarnyxStripeHandlerTests.xcscheme", encoding="UTF-8", xml_declaration=True)
print(project)
