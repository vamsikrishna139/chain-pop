#!/bin/bash
# Automating the Android Headless CLI Testing flow after system-images download concludes.

export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
export PATH="$HOME/development/flutter/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"

echo "Waiting for any previous sdkmanager locks to finish downloading..."
# The previous command initiated through the agent terminates when the download is done.

# Create the virtual device automatically
echo "Creating Android Virtual Device (AVD)..."
echo "no" | avdmanager create avd -n test_emu -k "system-images;android-34;google_apis;arm64-v8a" --force

echo "Booting Android Emulator in headless mode..."
emulator -avd test_emu -no-window -no-audio -gpu swiftshader_indirect &
EMULATOR_PID=$!

echo "Waiting for Emulator to fully boot up..."
sleep 15
adb wait-for-device

# Loop until Android OS properties signal boot has completed
BOOT_STATUS=""
while [[ -z "$BOOT_STATUS" || "$BOOT_STATUS" != "1" ]]; do
    sleep 5
    BOOT_STATUS=$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\\r')
    echo "Boot status: ${BOOT_STATUS:-Booting...}"
done

echo "Emulator is ready!"
echo "Installing and running Regression Tests against the live Android environment..."

# Run Dart integration/unit test natively on the device
flutter test test/regression_test.dart -d emulator-5554 > android_emulator_test_results.txt 2>&1

echo "Done running!"
cat android_emulator_test_results.txt

echo "Cleaning up..."
kill $EMULATOR_PID
