import Foundation

struct UserSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let userID: UUID
    let email: String
}

struct PasswordRecoverySession: Identifiable, Equatable {
    let id = UUID()
    let accessToken: String
    let refreshToken: String?
    let email: String?
}
