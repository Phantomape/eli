# Pulse Dodge

Pulse Dodge is a tiny native iOS game built with SwiftUI and SpriteKit. Drag the glowing player, dodge falling hazards, collect sparks, and chase the local high score.

## Open and run

1. Open `PulseDodge.xcodeproj` in Xcode.
2. Select the `PulseDodge` target.
3. Set `Signing & Capabilities > Team` to your Apple Developer team.
4. Change the bundle identifier from `com.example.pulsedodge` to your own reverse-DNS identifier.
5. Set MMP credentials in the target build settings:
   - `APPSFLYER_DEV_KEY`
   - `APPSFLYER_APP_ID` - Apple app id numbers only, without the `id` prefix
   - `ADJUST_APP_TOKEN`
   - `ADJUST_ENVIRONMENT` - `sandbox` or `production`
6. Choose an iPhone simulator or device and press Run.

## App Store quick notes

- AppsFlyer is integrated through Swift Package Manager using the `AppsFlyerLib-Static` product from `AppsFlyerFramework-Static`. The Swift module import remains `AppsFlyerLib`.
- Adjust is integrated through Swift Package Manager using the `AdjustSdk` package.
- AppsFlyer does not start until `APPSFLYER_DEV_KEY` and `APPSFLYER_APP_ID` are set.
- Adjust does not start until `ADJUST_APP_TOKEN` is set.
- ATT is enabled. The app asks once on first active launch; AppsFlyer and Adjust each wait up to 60 seconds for the user's ATT choice before sending attribution.
- `PrivacyInfo.xcprivacy` declares the app's local `UserDefaults` usage for the high score. AppsFlyer 6.14+ includes its own SDK privacy manifest.
- App Store Connect privacy must include AppsFlyer and Adjust SDK data collection once you enable the SDKs with real credentials.
- `ITSAppUsesNonExemptEncryption` is set to `false` in `Info.plist`.
- App icons are generated placeholders. Replace them before submitting if you want a more distinctive store presence.
- For uploads after April 28, 2026, Apple says iOS/iPadOS apps need to be built with the iOS & iPadOS 26 SDK or later.

## Files

- `PulseDodgeApp.swift` - SwiftUI app entry point.
- `ContentView.swift` - Hosts the SpriteKit scene.
- `GameScene.swift` - Complete game loop, touch control, spawning, scoring, collisions, restart flow.
- `PrivacyInfo.xcprivacy` - Privacy manifest.
- `Assets.xcassets` - Accent color and generated app icons.
