import GoogleMobileAds
import SwiftUI
import UIKit
import UserNotifications

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
                .onReceive(NotificationCenter.default.publisher(for: AppNotifications.remoteNotificationWasOpened)) { notification in
                    appState.handleNotificationUserInfo(notification.userInfo ?? [:])
                }
        }
    }
}

final class BrieflyAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        NotificationCenter.default.post(
            name: AppNotifications.remoteNotificationWasOpened,
            object: nil,
            userInfo: response.notification.request.content.userInfo
        )
    }
}
