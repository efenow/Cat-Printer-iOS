# Cat-Printer iOS (Sideload, no jailbreak)

This repository now includes a native iOS wrapper that reuses the existing Cat-Printer Web UI and implements the same local API (`/query`, `/set`, `/devices`, `/connect`, `/print`) with CoreBluetooth.

## What is included

- Native iOS app shell (SwiftUI + WKWebView)
- Local custom URL-scheme backend (`catprinter://`) for static files and API calls
- CoreBluetooth printer driver implementation for supported Cat-Printer models
- Same print protocol/command flow used by the Python implementation
- Persistent settings storage compatible with the current frontend behavior

## Prerequisites

- macOS with Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Apple ID (free is OK for personal sideloading)
- Optional: AltStore/SideStore for alternate sideload workflows

## Build the iOS app

1. Open Terminal and go to repository root.
2. Generate the Xcode project:
   ```bash
   cd ios
   xcodegen generate
   ```
3. Open `ios/CatPrinterIOS.xcodeproj` in Xcode.
4. Select the `CatPrinterIOS` target.
5. Set your own Bundle Identifier (Signing & Capabilities).
6. Choose your Team (Apple ID signing team).
7. Connect your iPhone (or use wireless debugging).
8. Choose your device as the run target and press **Run**.

## Trust the app on device

After installation, on your iPhone:

1. Open **Settings → General → VPN & Device Management**.
2. Select your developer profile.
3. Tap **Trust**.

## How to use

1. Launch **Cat Printer iOS**.
2. Tap **Refresh devices** (or enable unknown device test mode if needed).
3. Select your printer from the list and connect.
4. Import/prepare your image or text in the built-in UI.
5. Adjust energy, quality, threshold, and orientation settings.
6. Tap **Print**.

## Supported functionality

- BLE scan/connect workflow
- Device list and model-prefix matching
- Persistent settings (`scan_time`, `energy`, `quality`, `flip`, theme/accessibility toggles, etc.)
- PBM bitmap printing with protocol-compatible packet flow
- Dry-run mode support

## Notes

- iOS exposes BLE device IDs as UUIDs (not MAC addresses), which are used in the connect flow.
- The app keeps the existing web UI behavior by serving all assets directly from the app bundle.
- For free Apple ID signing, app validity may expire and require reinstalling.
