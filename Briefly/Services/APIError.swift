import Foundation

enum APIError: LocalizedError {
    case missingConfiguration(String)
    case invalidResponse
    case httpStatus(Int, String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration(let message):
            return message
        case .invalidResponse:
            return "The server response could not be read."
        case .httpStatus(let status, let body):
            if body.isEmpty { return "HTTP \(status)" }
            return "HTTP \(status): \(body)"
        case .server(let message):
            return message
        }
    }
}
