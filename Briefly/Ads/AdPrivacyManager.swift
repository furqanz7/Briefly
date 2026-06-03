import AppTrackingTransparency
import Foundation
import UIKit

@MainActor
enum AdPrivacyManager {
    static func requestTrackingAuthorizationIfNeeded() {
        guard #available(iOS 14, *) else { return }
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }

        Task {
            await waitUntilApplicationIsActive()
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
    }

    private static func waitUntilApplicationIsActive() async {
        while UIApplication.shared.applicationState != .active {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }
}
