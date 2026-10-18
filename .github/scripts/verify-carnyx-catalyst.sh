#!/bin/bash
set -euo pipefail
: "${CI_RUN_ROOT:?isolated workspace required}"
: "${CI_REPO_ROOT:?isolated tracked source required}"
cd "${CI_REPO_ROOT}"
python3 CarnyxTests/run_lifecycle_tests.py --output "${CI_RUN_ROOT}/lifecycle"
xcodebuild -jobs 2 -scmProvider system -scheme StripePaymentSheet \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "${CI_RUN_ROOT}/DerivedData" \
  -clonedSourcePackagesDirPath "${CI_RUN_ROOT}/SourcePackages" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
xcodebuild -jobs 2 -scmProvider system -scheme StripePaymentSheet \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath "${CI_RUN_ROOT}/DerivedData" \
  -clonedSourcePackagesDirPath "${CI_RUN_ROOT}/SourcePackages" \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
python3 CarnyxTests/prepare_handler_test_project.py --output "${CI_RUN_ROOT}/handler-package"
cd "${CI_RUN_ROOT}/handler-package"
xcodebuild -jobs 2 -scmProvider system -project "${CI_RUN_ROOT}/handler-package/CarnyxStripeHandlerTests.xcodeproj" -scheme CarnyxStripeHandlerTests \
  -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' \
  -parallel-testing-enabled NO \
  -derivedDataPath "${CI_RUN_ROOT}/HandlerDerivedData" \
  -clonedSourcePackagesDirPath "${CI_RUN_ROOT}/HandlerSourcePackages" \
  -resultBundlePath "${CI_RUN_ROOT}/handler-tests.xcresult" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test
