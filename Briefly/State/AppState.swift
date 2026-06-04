import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var session: UserSession?
    @Published var hasCompletedWelcome = UserDefaults.standard.bool(forKey: "hasCompletedWelcome")
    @Published var isBootstrapping = true
    @Published var authNotice: String?
    @Published var passwordRecoverySession: PasswordRecoverySession?

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
            session = (try? await authService.refreshSession(storedSession)) ?? storedSession
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
        Haptics.success()
    }

    func signUp(email: String, password: String) async throws {
        session = try await authService.signUp(email: email, password: password)
        authNotice = nil
        Haptics.success()
    }

    func signInWithApple(idToken: String, nonce: String) async throws {
        session = try await authService.signInWithApple(idToken: idToken, nonce: nonce)
        authNotice = nil
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

        try await authService.deleteAccount(session: session)
        authNotice = "Your account was permanently deleted."
        self.session = nil
        WidgetSnapshotStore.clearAccountWidgets()
        Haptics.success()
    }

    func signOut() {
        authService.signOut()
        Haptics.selection()
        session = nil
        WidgetSnapshotStore.clearAccountWidgets()
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
}
