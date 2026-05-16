#!/bin/bash
# Setup script for building Smart Car Flutter APP APK on Ubuntu/Debian
set -e

echo "=================================="
echo "Smart Car APP - Build Environment Setup"
echo "=================================="

# Check OS
if ! command -v apt-get &> /dev/null; then
    echo "Error: This script is for Debian/Ubuntu only"
    exit 1
fi

# 1. Install dependencies
echo ""
echo "Step 1: Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    openjdk-17-jdk \
    wget \
    cmake \
    ninja-build \
    libgtk-3-dev

# 2. Install Flutter
echo ""
echo "Step 2: Installing Flutter SDK..."
if [ ! -d "/opt/flutter" ]; then
    sudo git clone -b stable --depth 1 https://github.com/flutter/flutter.git /opt/flutter
    sudo chmod -R 777 /opt/flutter
fi

export PATH="/opt/flutter/bin:$PATH"

# 3. Configure Flutter mirrors (China)
echo ""
echo "Step 3: Configuring Flutter mirrors..."
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

# 4. Install Android SDK
echo ""
echo "Step 4: Installing Android SDK..."
export ANDROID_HOME=/opt/android-sdk
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

if [ ! -d "$ANDROID_HOME" ]; then
    sudo mkdir -p $ANDROID_HOME/cmdline-tools
    cd $ANDROID_HOME/cmdline-tools
    sudo wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
    sudo unzip -q commandlinetools-linux-11076708_latest.zip
    sudo mv cmdline-tools latest
    sudo rm commandlinetools-linux-11076708_latest.zip
    sudo chmod -R 777 $ANDROID_HOME
fi

# 5. Accept licenses and install SDK components
echo ""
echo "Step 5: Installing Android SDK components..."
yes | sdkmanager --licenses || true
sdkmanager "platforms;android-34"
sdkmanager "build-tools;34.0.0"
sdkmanager "platform-tools"

# 6. Verify Flutter
echo ""
echo "Step 6: Verifying Flutter installation..."
flutter doctor

# 7. Build APK
echo ""
echo "Step 7: Building APK..."
cd "$(dirname "$0")/flutter_app"
flutter clean
flutter pub get
flutter build apk --release

echo ""
echo "=================================="
echo "Build complete!"
echo "APK: flutter_app/build/app/outputs/flutter-apk/app-release.apk"
echo "=================================="
echo ""
echo "Install on your phone:"
echo "  adb install flutter_app/build/app/outputs/flutter-apk/app-release.apk"
