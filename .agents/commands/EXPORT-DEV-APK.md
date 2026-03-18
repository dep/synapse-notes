# Export Dev Mobile App (Android APK)

## Description

Build and install a development APK onto a connected Android device. This uses the debug keystore and produces a development-ready app, not a signed production APK.

## Prerequisites

- Android SDK / `adb` available (`brew install android-platform-tools` if missing)
- A physical device connected via USB with USB debugging enabled, **or** an emulator running

## Step-by-Step

### 1. Build the development APK

```bash
cd mobile/android && ./gradlew assembleDebug
```

Output: `mobile/android/app/build/outputs/apk/debug/app-debug.apk`

### 2. Install onto connected device

```bash
adb install -r mobile/android/app/build/outputs/apk/debug/app-debug.apk
```

`-r` reinstalls over an existing version. Remove `-r` for a fresh install.

### 3. Launch the app

```bash
adb shell monkey -p com.dnnypck.mobile -c android.intent.category.LAUNCHER 1
```

## Expected Output

```
Installing...
Success
```

## Artifacts

- Development APK: `mobile/android/app/build/outputs/apk/debug/app-debug.apk`

## One-Liner

```bash
cd mobile/android && ./gradlew assembleDebug && cd ../.. && \
adb install -r mobile/android/app/build/outputs/apk/debug/app-debug.apk && \
adb shell monkey -p com.dnnypck.mobile -c android.intent.category.LAUNCHER 1
```
