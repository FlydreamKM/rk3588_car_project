#!/bin/bash
# Build APK script for Smart Car Flutter App
set -e

echo "=================================="
echo "Smart Car APP APK Builder"
echo "=================================="

# Set environment
export PATH="/opt/flutter/bin:/opt/gradle-8.0/bin:$PATH"
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export ANDROID_HOME=/opt/android-sdk
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

cd "$(dirname "$0")/flutter_app"

echo ""
echo "Step 1: Clean build artifacts"
flutter clean

echo ""
echo "Step 2: Get dependencies"
flutter pub get

echo ""
echo "Step 3: Build APK (release)"
flutter build apk --release

echo ""
echo "=================================="
echo "Build complete!"
echo "APK location: build/app/outputs/flutter-apk/app-release.apk"
echo "=================================="
ls -lh build/app/outputs/flutter-apk/app-release.apk 2>/dev/null || echo "APK not found"
