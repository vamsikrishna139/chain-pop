#!/bin/bash

# Setup Paths
export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
# Attempt to find Flutter in common locations if the script's path is wrong
FLUTTER_PATH="$HOME/development/flutter/bin"
export PATH="$FLUTTER_PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"

echo "Step 1: Building new Chain Pop APK..."
if ! command -v flutter &> /dev/null
then
    echo "Error: Flutter could not be found. Please check if it's installed at $FLUTTER_PATH"
    exit 1
fi

flutter build apk --release

echo "Step 2: Booting Android GUI Emulator..."
emulator -avd test_emu -gpu swiftshader_indirect &
EMULATOR_PID=$!

echo "Waiting for Android OS to boot..."
sleep 10
adb wait-for-device

while [[ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]]; do
    sleep 3
done

echo "Step 3: Installing the new APK..."
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
adb -s emulator-5554 install -r "$APK_PATH"

echo "Step 4: Launching Chain Pop..."
adb -s emulator-5554 shell am start -n com.example.chain_pop/com.example.chain_pop.MainActivity

echo "Success! The game is running."
wait $EMULATOR_PID
