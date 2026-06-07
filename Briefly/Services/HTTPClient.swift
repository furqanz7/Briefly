import Foundation

enum HTTPClient {
    static func data(for request: URLRequest, session: URLSession = .shared) async throws -> (Data, HTTPURLResponse) {
        var request = request
        if request.timeoutInterval >= 60 {
            request.timeoutInterval = 12
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        return (data, http)
    }

    static func requireSuccess(_ data: Data, _ http: HTTPURLResponse) throws -> Data {
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            // Keep errors short; APIs often return large HTML/JSON blobs.
            let trimmed = String(body.prefix(800))
            throw APIError.httpStatus(http.statusCode, trimmed)
        }
        return data
    }
}
