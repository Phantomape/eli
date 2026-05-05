# Pulse Dodge

Pulse Dodge is a tiny native iOS game built with SwiftUI and SpriteKit. Drag the glowing player, dodge falling hazards, collect sparks, and chase the local high score.

## Open and run

1. Open `PulseDodge.xcodeproj` in Xcode.
2. Select the `PulseDodge` target.
3. Set `Signing & Capabilities > Team` to your Apple Developer team.
4. Change the bundle identifier from `com.example.pulsedodge` to your own reverse-DNS identifier.
5. Choose an iPhone simulator or device and press Run.

## App Store quick notes

- The app is offline-only and does not include ads, analytics, networking, login, Game Center, or third-party SDKs.
- `PrivacyInfo.xcprivacy` declares local `UserDefaults` usage for the high score.
- App Store Connect privacy can be answered as no collected data unless you add networking, analytics, ads, accounts, or other data collection later.
- `ITSAppUsesNonExemptEncryption` is set to `false` in `Info.plist`.
- App icons are generated placeholders. Replace them before submitting if you want a more distinctive store presence.
- For uploads after April 28, 2026, Apple says iOS/iPadOS apps need to be built with the iOS & iPadOS 26 SDK or later.

## Files

- `PulseDodgeApp.swift` - SwiftUI app entry point.
- `ContentView.swift` - Hosts the SpriteKit scene.
- `GameScene.swift` - Complete game loop, touch control, spawning, scoring, collisions, restart flow.
- `PrivacyInfo.xcprivacy` - Privacy manifest.
- `Assets.xcassets` - Accent color and generated app icons.
