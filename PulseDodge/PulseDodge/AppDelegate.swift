import AppTrackingTransparency
import AdjustSdk
import AppsFlyerLib
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppsFlyerIntegration.configure()
        AdjustIntegration.configure()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        TrackingAuthorization.requestIfNeeded(
            isEnabled: AppsFlyerIntegration.isConfigured || AdjustIntegration.isConfigured,
            preferAdjustWrapper: AdjustIntegration.isConfigured
        )
        AppsFlyerIntegration.startIfConfigured()
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        AppsFlyerLib.shared().handleOpen(url: url, options: options)
        AdjustIntegration.processDeeplink(url)
        return true
    }

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        AppsFlyerLib.shared().continue(userActivity: userActivity, restorationHandler: nil)
        if let url = userActivity.webpageURL {
            AdjustIntegration.processDeeplink(url)
        }
        return true
    }
}

private enum AppsFlyerIntegration {
    private(set) static var isConfigured = false

    static func configure() {
        guard !isConfigured else { return }
        guard let devKey = AppConfig.string("AppsFlyerDevKey"),
              let appleAppID = AppConfig.string("AppsFlyerAppleAppID"),
              appleAppID.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil else {
            return
        }

        let appsFlyer = AppsFlyerLib.shared()
        appsFlyer.appsFlyerDevKey = devKey
        appsFlyer.appleAppID = appleAppID
        appsFlyer.disableAdvertisingIdentifier = 0

        if #available(iOS 14, *) {
            appsFlyer.waitForATTUserAuthorization(timeoutInterval: 60)
        }

        #if DEBUG
        appsFlyer.isDebug = true
        #else
        appsFlyer.isDebug = false
        #endif

        isConfigured = true
    }

    static func startIfConfigured() {
        guard isConfigured else { return }
        AppsFlyerLib.shared().start()
    }
}

private enum AdjustIntegration {
    private(set) static var isConfigured = false

    static func configure() {
        guard !isConfigured,
              let appToken = AppConfig.string("AdjustAppToken") else {
            return
        }

        let environment = AppConfig.string("AdjustEnvironment")
            .map(adjustEnvironment)
            ?? defaultEnvironment

        guard let adjustConfig = ADJConfig(appToken: appToken, environment: environment) else {
            return
        }

        adjustConfig.attConsentWaitingInterval = 60

        #if DEBUG
        adjustConfig.logLevel = ADJLogLevel.verbose
        #else
        adjustConfig.logLevel = ADJLogLevel.suppress
        #endif

        Adjust.initSdk(adjustConfig)
        isConfigured = true
    }

    static func processDeeplink(_ url: URL) {
        guard isConfigured,
              let deeplink = ADJDeeplink(deeplink: url) else {
            return
        }

        Adjust.processAndResolve(deeplink) { resolvedLink in
            #if DEBUG
            print("Adjust resolved deep link: \(resolvedLink ?? "nil")")
            #endif
        }
    }

    private static var defaultEnvironment: String {
        #if DEBUG
        return ADJEnvironmentSandbox
        #else
        return ADJEnvironmentProduction
        #endif
    }

    private static func adjustEnvironment(_ value: String) -> String {
        switch value.lowercased() {
        case "production", "prod", "release":
            return ADJEnvironmentProduction
        default:
            return ADJEnvironmentSandbox
        }
    }
}

private enum TrackingAuthorization {
    private static var didRequestTrackingAuthorization = false

    static func requestIfNeeded(isEnabled: Bool, preferAdjustWrapper: Bool) {
        guard isEnabled else { return }

        if #available(iOS 14, *) {
            guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined,
                  !didRequestTrackingAuthorization else {
                return
            }

            didRequestTrackingAuthorization = true

            if preferAdjustWrapper {
                Adjust.requestAppTrackingAuthorization { status in
                    log(statusCode: UInt(status))
                }
            } else {
                ATTrackingManager.requestTrackingAuthorization { status in
                    log(statusCode: UInt(status.rawValue))
                }
            }
        }
    }

    private static func log(statusCode: UInt) {
        #if DEBUG
        print("ATT authorization status: \(statusCode)")
        #endif
    }
}

private enum AppConfig {
    static func string(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("$("),
              !trimmed.hasPrefix("<") else {
            return nil
        }

        return trimmed
    }
}
