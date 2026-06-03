import GoogleMobileAds
import SwiftUI

@main
struct BrieflyApp: App {
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
        }
    }
}
