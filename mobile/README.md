# Lightsail Mobile (fully standalone)

Flutter app for **iOS and Android** that provisions Outline on AWS Lightsail
**entirely on the phone** — no Mac backend, no Outline Manager app.

## What it does on-device

1. Calls AWS Lightsail API (create instance, static IP, firewall)
2. SSHs into the instance and installs Outline + Docker
3. Uses the Outline Management API to rename the key to `cursor-key`, set a **2.5TB** data limit, and fetch the `ss://` access key

## Prerequisites

- Flutter SDK (`flutter` on your PATH)
- For iOS: full **Xcode** (not only Command Line Tools) + a simulator or device
- For Android: Android Studio / SDK + emulator or device
- AWS access key with Lightsail permissions

## Run

```bash
export PATH="$HOME/flutter/bin:$PATH"   # if you installed Flutter under ~/flutter
cd mobile
flutter pub get
flutter run            # pick a device
```

## Build installable packages

```bash
cd mobile

# Android APK (sideload)
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk

# iOS (requires Xcode + signing team)
flutter build ios --release
# then open ios/Runner.xcworkspace in Xcode → Product → Archive
```

## First launch

Enter your **AWS Access Key ID** and **Secret Access Key**. They are stored in
the device secure storage (Keychain / Keystore).

## Cloud iOS build (Intel Mac / no App Store Xcode)

If your Mac can’t install current Xcode (common on Intel), build in GitHub Actions:

1. Commit & push (your GitHub token needs the **`workflow`** scope for `.github/workflows/`).
2. GitHub → **Actions** → **iOS standalone build** → **Run workflow**.
3. When it finishes, download **Lightsail-iOS-unsigned** (`Runner.app` zip).

That artifact is **unsigned**. To install on a physical iPhone you still need an Apple Developer team to sign it (Xcode on any Mac that can run a compatible Xcode, or we can add a signed-IPA job later with your `.p12` + provisioning profile secrets).

## Note

This replaces the old companion iOS app that talked to a Mac `npm start`
backend. The Mac `dist/Lightsail.app` remains available for desktop use.
