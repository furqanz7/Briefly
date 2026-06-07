import Foundation

struct AuthService {
    private let config = AppConfig.shared

    func restoreSession() -> UserSession? {
        KeychainStore.loadSession()
    }

    func signOut() {
        KeychainStore.clear()
    }

    func deleteAccount(session: UserSession) async throws {
        guard let url = config.deleteAccountFunctionURL else {
            throw APIError.missingConfiguration("Add your Supabase project configuration to enable account deletion.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["user_id": session.userID.uuidString.lowercased()])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            throw APIError.server(parseMessage(from: data) ?? "Could not delete your account.")
        }

        KeychainStore.clear()
    }


    func requestPasswordReset(email: String) async throws {
        guard let baseURL = config.supabaseURL else {
            throw APIError.missingConfiguration("Password reset is unavailable right now. Please try again later.")
        }
        guard let redirectURL = config.passwordRecoveryRedirectURL else {
            throw APIError.missingConfiguration("Password reset is not configured correctly.")
        }

        let url = baseURL.appending(path: "/auth/v1/recover").appending(queryItems: [
            URLQueryItem(name: "redirect_to", value: redirectURL.absoluteString)
        ])
        try await requestWithoutResponse(url: url, method: "POST", body: ["email": email])
    }

    func updatePassword(accessToken: String, newPassword: String) async throws {
        guard let baseURL = config.supabaseURL else {
            throw APIError.missingConfiguration("Password update is unavailable right now. Please try again later.")
        }

        let url = baseURL.appending(path: "/auth/v1/user")
        try await requestWithoutResponse(
            url: url,
            method: "PUT",
            body: ["password": newPassword],
            authorizationToken: accessToken
        )
        KeychainStore.clear()
    }

    func signIn(email: String, password: String) async throws -> UserSession {
        guard let baseURL = config.supabaseURL else {
            throw APIError.missingConfiguration("Sign in is unavailable right now. Please try again later.")
        }

        let url = baseURL.appending(path: "/auth/v1/token").appending(queryItems: [
            URLQueryItem(name: "grant_type", value: "password")
        ])
        let body = ["email": email, "password": password]
        let response: AuthResponse = try await post(url: url, body: body)
        let session = try response.session(emailFallback: email)
        try KeychainStore.save(session: session)
        return session
    }

    func signUp(email: String, password: String) async throws -> UserSession {
        guard let baseURL = config.supabaseURL else {
            throw APIError.missingConfiguration("Sign up is unavailable right now. Please try again later.")
        }

        let url = baseURL.appending(path: "/auth/v1/signup")
        let body = ["email": email, "password": password]
        let response: AuthResponse = try await post(url: url, body: body)
        let session = try response.session(emailFallback: email)
        try KeychainStore.save(session: session)
        return session
    }

    func signInWithApple(idToken: String, nonce: String) async throws -> UserSession {
        guard let baseURL = config.supabaseURL else {
            throw APIError.missingConfiguration("Apple Sign In is unavailable right now. Please try again later.")
        }

        let url = baseURL.appending(path: "/auth/v1/token").appending(queryItems: [
            URLQueryItem(name: "grant_type", value: "id_token")
        ])
        let body: [String: Any] = [
            "provider": "apple",
            "token": idToken,
            "id_token": idToken,
            "nonce": nonce
        ]

        let response: AuthResponse = try await post(url: url, body: body)
        let session = try response.session(emailFallback: "Apple User")
        try KeychainStore.save(session: session)
        return session
    }

    func refreshSession(_ session: UserSession) async throws -> UserSession {
        guard let baseURL = config.supabaseURL else {
            return session
        }

        guard let refreshToken = session.refreshToken, !refreshToken.isEmpty else {
            return session
        }

        let url = baseURL.appending(path: "/auth/v1/token").appending(queryItems: [
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ])
        let body = ["refresh_token": refreshToken]
        let response: AuthResponse = try await post(url: url, body: body, authorizationToken: refreshToken)
        let refreshed = try response.session(emailFallback: session.email)
        try KeychainStore.save(session: refreshed)
        return refreshed
    }

    private func requestWithoutResponse(
        url: URL,
        method: String,
        body: [String: Any],
        authorizationToken: String? = nil
    ) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 12
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        let authToken = authorizationToken ?? config.supabaseAnonKey
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            throw APIError.server(parseMessage(from: data) ?? "The request could not be completed.")
        }
    }

    private func post<T: Decodable>(url: URL, body: [String: Any], authorizationToken: String? = nil) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        let authToken = authorizationToken ?? config.supabaseAnonKey
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            throw APIError.server(parseMessage(from: data) ?? "Authentication failed.")
        }

        return try JSONDecoder.supabase.decode(T.self, from: data)
    }

    private func parseMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["msg"] as? String ?? json["error_description"] as? String ?? json["message"] as? String
    }
}

private struct AuthResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let user: AuthUser?
    let session: AuthSessionEnvelope?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case user
        case session
    }

    func session(emailFallback: String) throws -> UserSession {
        if let session {
            return UserSession(
                accessToken: session.accessToken,
                refreshToken: session.refreshToken,
                userID: session.user.id,
                email: session.user.email ?? emailFallback
            )
        }

        if let accessToken, let user {
            return UserSession(
                accessToken: accessToken,
                refreshToken: refreshToken,
                userID: user.id,
                email: user.email ?? emailFallback
            )
        }

        throw APIError.server("Supabase returned no session. If email confirmation is enabled, disable it for this assignment flow or complete verification first.")
    }
}

private struct AuthSessionEnvelope: Decodable {
    let accessToken: String
    let refreshToken: String?
    let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case user
    }
}

private struct AuthUser: Decodable {
    let id: UUID
    let email: String?
}
