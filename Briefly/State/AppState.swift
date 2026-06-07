import Foundation

enum AppTab: String, Hashable {
    case home
    case sports
    case jobs
    case books
    case more
}

@MainActor
final class AppState: ObservableObject {
    @Published var session: UserSession?
    @Published var hasCompletedWelcome = UserDefaults.standard.bool(forKey: "hasCompletedWelcome")
    @Published var isBootstrapping = true
    @Published var authNotice: String?
    @Published var passwordRecoverySession: PasswordRecoverySession?
    @Published var selectedTab: AppTab = .home
    @Published var pendingNotificationArticle: Article?

    private let authService = AuthService()

    func bootstrap() async {
        guard isBootstrapping else { return }
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-debugHome") {
            hasCompletedWelcome = true
            session = UserSession(
                accessToken: "debug-token",
                refreshToken: nil,
                userID: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
                email: "debug@briefly.local"
            )
            isBootstrapping = false
            return
        }
#endif
        if let storedSession = authService.restoreSession() {
            session = storedSession
            isBootstrapping = false
            syncNotificationDevice()

            Task {
                guard let refreshed = try? await authService.refreshSession(storedSession) else { return }
                if session?.userID == storedSession.userID {
                    session = refreshed
                    syncNotificationDevice()
                }
            }
            return
        }
        isBootstrapping = false
    }

    func completeWelcome() {
        hasCompletedWelcome = true
        UserDefaults.standard.set(true, forKey: "hasCompletedWelcome")
    }

    func signIn(email: String, password: String) async throws {
        session = try await authService.signIn(email: email, password: password)
        authNotice = nil
        syncNotificationDevice()
        Haptics.success()
    }

    func signUp(email: String, password: String) async throws {
        session = try await authService.signUp(email: email, password: password)
        authNotice = nil
        syncNotificationDevice()
        Haptics.success()
    }

    func signInWithApple(idToken: String, nonce: String) async throws {
        session = try await authService.signInWithApple(idToken: idToken, nonce: nonce)
        authNotice = nil
        syncNotificationDevice()
        Haptics.success()
    }


    func requestPasswordReset(email: String) async throws {
        try await authService.requestPasswordReset(email: email)
        authNotice = "If an account exists for that email, Briefly will send a password reset link."
        Haptics.success()
    }

    func updatePassword(newPassword: String) async throws {
        guard let recovery = passwordRecoverySession else {
            throw APIError.server("Open the reset link from your email first.")
        }

        try await authService.updatePassword(accessToken: recovery.accessToken, newPassword: newPassword)
        passwordRecoverySession = nil
        session = nil
        authNotice = "Password updated. Log in with your new password."
        Haptics.success()
    }

    func handleIncomingURL(_ url: URL) {
        if let recovery = passwordRecoverySession(from: url) {
            completeWelcome()
            authService.signOut()
            session = nil
            passwordRecoverySession = recovery
            authNotice = "Choose a new password to finish resetting your account."
            Haptics.selection()
            return
        }

        if let errorMessage = passwordRecoveryError(from: url) {
            completeWelcome()
            authNotice = errorMessage
        }
    }

    func deleteAccount() async throws {
        guard let session else {
            throw APIError.server("No active account to delete.")
        }

        try? await NotificationService.shared.disableDevice(session: session)
        try await authService.deleteAccount(session: session)
        authNotice = "Your account was permanently deleted."
        self.session = nil
        WidgetSnapshotStore.clearAccountWidgets()
        Haptics.success()
    }

    func signOut() {
        let currentSession = session
        authService.signOut()
        Haptics.selection()
        session = nil
        WidgetSnapshotStore.clearAccountWidgets()

        if let currentSession {
            Task {
                try? await NotificationService.shared.disableDevice(session: currentSession)
            }
        }
    }

    func syncNotificationDevice() {
        guard let session else { return }
        Task {
            try? await NotificationService.shared.syncDeviceToken(session: session)
            try? await NotificationService.shared.ensurePreferences(session: session)
        }
    }

    func handleNotificationUserInfo(_ userInfo: [AnyHashable: Any]) {
        completeWelcome()

        let route = stringValue("route", in: userInfo)
            ?? stringValue("type", in: userInfo)
            ?? stringValue("notification_type", in: userInfo)

        switch route {
        case "job_match", "jobs":
            selectedTab = .jobs
        case "sports_live", "sports":
            selectedTab = .sports
        case "reading_goal", "books":
            selectedTab = .books
        case "breaking_essential", "article":
            selectedTab = .home
            pendingNotificationArticle = article(from: userInfo)
        case "daily_brief", "home":
            selectedTab = .home
        default:
            selectedTab = .home
        }
    }

    private func passwordRecoverySession(from url: URL) -> PasswordRecoverySession? {
        guard isPasswordRecoveryURL(url) else { return nil }
        let parameters = callbackParameters(from: url)
        guard parameters["type"] == "recovery",
              let accessToken = parameters["access_token"],
              !accessToken.isEmpty else {
            return nil
        }

        return PasswordRecoverySession(
            accessToken: accessToken,
            refreshToken: parameters["refresh_token"],
            email: parameters["email"]
        )
    }

    private func passwordRecoveryError(from url: URL) -> String? {
        guard isPasswordRecoveryURL(url) else { return nil }
        let parameters = callbackParameters(from: url)
        if let description = parameters["error_description"]?.replacingOccurrences(of: "+", with: " ") {
            return description.removingPercentEncoding ?? description
        }
        if parameters["error"] != nil {
            return "The password reset link is invalid or expired. Please request a new one."
        }
        return nil
    }

    private func isPasswordRecoveryURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "briefly" &&
        url.host?.lowercased() == "auth" &&
        url.path.lowercased().contains("reset-password")
    }

    private func callbackParameters(from url: URL) -> [String: String] {
        var parameters: [String: String] = [:]
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            for item in components.queryItems ?? [] {
                parameters[item.name] = item.value
            }

            if let fragment = components.fragment,
               let fragmentComponents = URLComponents(string: "briefly://callback?\(fragment)") {
                for item in fragmentComponents.queryItems ?? [] {
                    parameters[item.name] = item.value
                }
            }
        }
        return parameters
    }

    private func article(from userInfo: [AnyHashable: Any]) -> Article? {
        guard let headline = stringValue("headline", in: userInfo),
              !headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let category = stringValue("category", in: userInfo) ?? "World"
        let categories = stringArrayValue("categories", in: userInfo)
            .compactMap(NewsCategory.init(providerValue:))

        return Article(
            id: stringValue("article_id", in: userInfo)
                ?? stringValue("id", in: userInfo)
                ?? headline,
            headline: headline,
            source: stringValue("source", in: userInfo) ?? "Briefly",
            imageURL: urlValue(["image_url", "imageURL"], in: userInfo),
            originalURL: urlValue(["original_url", "originalURL", "url"], in: userInfo),
            publishedAt: dateValue(["published_at", "publishedAt"], in: userInfo),
            summaryCards: stringArrayValue("summary_cards", in: userInfo)
                .ifEmpty([stringValue("plain_summary", in: userInfo)].compactMap { $0 }),
            plainSummary: stringValue("plain_summary", in: userInfo)
                ?? stringValue("plainSummary", in: userInfo)
                ?? "",
            rawDescription: stringValue("raw_description", in: userInfo)
                ?? stringValue("rawDescription", in: userInfo)
                ?? "",
            rawContent: stringValue("raw_content", in: userInfo)
                ?? stringValue("rawContent", in: userInfo)
                ?? "",
            category: category,
            categories: categories.isEmpty ? nil : categories,
            keywords: stringArrayValue("keywords", in: userInfo)
        )
    }

    private func stringValue(_ key: String, in userInfo: [AnyHashable: Any]) -> String? {
        if let value = userInfo[AnyHashable(key)] as? String {
            return value
        }
        if let value = userInfo[AnyHashable(key)] {
            return String(describing: value)
        }
        return nil
    }

    private func stringArrayValue(_ key: String, in userInfo: [AnyHashable: Any]) -> [String] {
        if let values = userInfo[AnyHashable(key)] as? [String] {
            return values
        }
        if let values = userInfo[AnyHashable(key)] as? [Any] {
            return values.compactMap { $0 as? String ?? String(describing: $0) }
        }
        if let value = stringValue(key, in: userInfo), !value.isEmpty {
            return value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return []
    }

    private func urlValue(_ keys: [String], in userInfo: [AnyHashable: Any]) -> URL? {
        keys.lazy
            .compactMap { self.stringValue($0, in: userInfo) }
            .compactMap { URL(string: $0) }
            .first
    }

    private func dateValue(_ keys: [String], in userInfo: [AnyHashable: Any]) -> Date? {
        let formatter = ISO8601DateFormatter()
        return keys.lazy
            .compactMap { self.stringValue($0, in: userInfo) }
            .compactMap { formatter.date(from: $0) }
            .first
    }
}

private extension Array {
    func ifEmpty(_ fallback: [Element]) -> [Element] {
        isEmpty ? fallback : self
    }
}
