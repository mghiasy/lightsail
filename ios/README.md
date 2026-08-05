# Lightsail iOS

Native SwiftUI app that mirrors the web UI and calls the same Python backend.

## Setup

1. Start the backend on your Mac:

```bash
npm start
```

2. Open the Xcode project:

```bash
open ios/Lightsail.xcodeproj
```

3. Select an iPhone simulator (or your device), then Run.

## Backend URL

Default in `Lightsail/APIClient.swift`:

```swift
static var baseURL = URL(string: "http://127.0.0.1:5173")!
```

- **Simulator:** `127.0.0.1` is fine.
- **Physical iPhone:** change to your Mac’s LAN IP, e.g. `http://192.168.1.20:5173`.

## Notes

- Create / Clean up hit `/api/create-instance` and `/api/cleanup-instance`.
- Provisioning still runs on the Mac (AWS CLI, SSH, Outline Manager).
- Set your Apple Development Team in Xcode Signing if needed.
