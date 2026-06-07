import GoogleMobileAds
import SwiftUI
import UIKit

@main
struct BrieflyApp: App {
    @UIApplicationDelegateAdaptor(BrieflyAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var theme = ThemeManager()

    init() {
        MobileAds.shared.start { status in
            #if DEBUG
            let adapters = status.adapterStatusesByClassName
                .map { "\($0.key)=\($0.value.state.rawValue)" }
                .sorted()
                .joined(separator: ", ")
            print("[AdMob] SDK initialized. Adapters: \(adapters)")
            #endif
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(theme)
                .preferredColorScheme(theme.colorScheme)
                .task {
                    AdPrivacyManager.requestTrackingAuthorizationIfNeeded()
                }
                .onOpenURL { url in
                    appState.handleIncomingURL(url)
                }
                .onReceive(NotificationCenter.default.publisher(for: AppNotifications.remoteNotificationTokenDidChange)) { _ in
                    appState.syncNotificationDevice()
                }
        }
    }
}

final class BrieflyAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        NotificationService.shared.storeDeviceToken(token)
        NotificationCenter.default.post(name: AppNotifications.remoteNotificationTokenDidChange, object: nil)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        #if DEBUG
        print("[Push] Registration failed: \(error.localizedDescription)")
        #endif
    }
}
