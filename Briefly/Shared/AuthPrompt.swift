import Foundation

struct AuthPrompt: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let buttonTitle: String

    init(title: String, message: String, buttonTitle: String = "Sign In or Create Account") {
        self.title = title
        self.message = message
        self.buttonTitle = buttonTitle
    }
}
