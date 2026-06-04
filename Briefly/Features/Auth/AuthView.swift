import AuthenticationServices
import CryptoKit
import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var email = ""
    @State private var password = ""
    @State private var isLogin = true
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var isSendingReset = false
    @State private var appleCoordinator = AppleSignInCoordinator()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(isLogin ? "Welcome back" : "Create account")
                        .font(.system(size: 36, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.text(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text("Sync saved stories, books, job activity, and reading progress across every device.")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(BrieflyTheme.secondaryText)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 16) {
                    AuthField(title: "Email", text: $email, keyboardType: .emailAddress)
                    AuthField(title: "Password", text: $password, isSecure: true)
                }

                if let authNotice = appState.authNotice {
                    Text(authNotice)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Haptics.impact(.medium)
                    Task { await submit() }
                } label: {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        }
                        Text(isLogin ? "Log In" : "Sign Up")
                    }
                    .font(.system(size: 17, weight: .heavy))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(BrieflyTheme.actionGradient)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .disabled(isSubmitting || isSendingReset)
                .buttonStyle(.plain)

                if isLogin {
                    Button {
                        Task { await sendPasswordReset() }
                    } label: {
                        HStack(spacing: 8) {
                            if isSendingReset {
                                ProgressView()
                                    .tint(BrieflyTheme.accent)
                            }
                            Text("Forgot password?")
                        }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BrieflyTheme.accent)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(isSubmitting || isSendingReset)
                }

                SignInWithAppleButton(.continue) { request in
                    appleCoordinator.prepare(request: request)
                } onCompletion: { result in
                    Task {
                        await handleAppleSignIn(result)
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .frame(maxWidth: .infinity)

                Button(isLogin ? "Need an account? Sign up" : "Already have an account? Log in") {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        isLogin.toggle()
                        errorMessage = nil
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BrieflyTheme.accent)
                .frame(maxWidth: .infinity, alignment: .center)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 32)
            .frame(minHeight: UIScreen.main.bounds.height - 80, alignment: .top)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(BrieflyTheme.premiumBackground)
        .ignoresSafeArea(.container, edges: .bottom)
        .sheet(item: $appState.passwordRecoverySession) { recoverySession in
            ResetPasswordSheet(recoverySession: recoverySession)
        }
    }

    private func submit() async {
        guard email.contains("@"), password.count >= 6 else {
            errorMessage = "Use a valid email and a password with at least 6 characters."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            if isLogin {
                try await appState.signIn(email: email, password: password)
            } else {
                try await appState.signUp(email: email, password: password)
            }
            errorMessage = nil
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }

    private func sendPasswordReset() async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.contains("@") else {
            errorMessage = "Enter your email address first, then tap Forgot password."
            return
        }

        isSendingReset = true
        defer { isSendingReset = false }

        do {
            try await appState.requestPasswordReset(email: trimmedEmail)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let token = try appleCoordinator.handle(result: result)
            try await appState.signInWithApple(idToken: token, nonce: appleCoordinator.rawNonce)
            errorMessage = nil
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }
}


private struct ResetPasswordSheet: View {
    let recoverySession: PasswordRecoverySession
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Set a new password")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(BrieflyTheme.text(colorScheme))

                    Text("Choose a new password for your Briefly account.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(BrieflyTheme.secondaryText)
                }

                VStack(spacing: 16) {
                    AuthField(title: "New password", text: $password, isSecure: true)
                    AuthField(title: "Confirm password", text: $confirmPassword, isSecure: true)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        }
                        Text("Update Password")
                    }
                    .font(.system(size: 17, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(BrieflyTheme.actionGradient)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .disabled(isSubmitting)
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(22)
            .background(BrieflyTheme.premiumBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        appState.passwordRecoverySession = nil
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
            }
        }
        .interactiveDismissDisabled(isSubmitting)
    }

    private func submit() async {
        guard password.count >= 6 else {
            errorMessage = "Use a password with at least 6 characters."
            return
        }
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await appState.updatePassword(newPassword: password)
            errorMessage = nil
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }
}

private struct AuthField: View {
    let title: String
    @Binding var text: String
    var isSecure = false
    var keyboardType: UIKeyboardType = .default
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(BrieflyTheme.secondaryText)
                .textCase(.uppercase)

            Group {
                if isSecure {
                    SecureField(title, text: $text)
                } else {
                    TextField(title, text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(keyboardType)
                }
            }
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(BrieflyTheme.text(colorScheme))
            .tint(BrieflyTheme.accent)
            .padding(18)
            .background(BrieflyTheme.cardBase.opacity(0.96))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(BrieflyTheme.divider.opacity(0.9), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}

private struct AppleSignInCoordinator {
    fileprivate var rawNonce = ""

    mutating func prepare(request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        rawNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func handle(result: Result<ASAuthorization, Error>) throws -> String {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                throw APIError.server("Apple Sign In could not finish. Please try again.")
            }
            return token
        case .failure(let error):
            throw error
        }
    }

    private static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length

        while remaining > 0 {
            let bytes: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if status != errSecSuccess {
                    random = UInt8.random(in: 0...UInt8.max)
                }
                return random
            }

            bytes.forEach { byte in
                if remaining == 0 { return }
                if byte < charset.count {
                    result.append(charset[Int(byte)])
                    remaining -= 1
                }
            }
        }

        return result
    }
}
