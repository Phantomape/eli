# App Store Checklist

## Before archive

- Install the currently accepted Xcode version for App Store uploads.
- Open `PulseDodge.xcodeproj`.
- In the `PulseDodge` target, set your Apple Developer Team.
- Replace `PRODUCT_BUNDLE_IDENTIFIER = com.example.pulsedodge` with your own bundle id.
- Run on at least one iPhone simulator and one physical iPhone.
- Replace placeholder icons if desired.
- Update version/build numbers if this is not the first build.

## App Store Connect

- Create the app record with the same bundle id.
- Add a privacy policy URL. Apple requires one for iOS apps.
- App Privacy: this build collects no data and has no tracking.
- Category: Games.
- Age rating: no violence beyond abstract shape collisions.
- Encryption/export compliance: no non-exempt encryption.
- Upload screenshots for required device sizes.

## Archive

1. Select `Any iOS Device`.
2. Product > Archive.
3. Distribute App > App Store Connect > Upload.
4. Wait for processing, attach the build, then submit for review.
