import Foundation

struct ChatMessage: Identifiable, Equatable {
    enum Role {
        case assistant
        case user
    }

    let id = UUID()
    let role: Role
    let text: String
}
