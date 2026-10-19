#!/bin/bash
# 先构建同目录的 App，再启动独立 UI runner；不改动共享单元测试 scheme。
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

derived_path="${LIQUIDMUSIC_DERIVED_DATA:-/tmp/Liquidmusic-build}"
build_arguments=(-project Liquidmusic.xcodeproj -configuration Debug -derivedDataPath "$derived_path")

xcodebuild "${build_arguments[@]}" -scheme Liquidmusic CODE_SIGNING_ALLOWED=NO build
# UI runner 的 Apple 模板签名不能沿用，使用本地 ad-hoc 重签，不调用开发者证书。
xcodebuild "${build_arguments[@]}" -scheme LiquidmusicUITests \
  -destination "platform=macOS,arch=$(uname -m)" \
  TEST_TARGET_NAME=Liquidmusic CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM='' "$@" test
