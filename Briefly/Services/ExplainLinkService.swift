import Foundation

struct ExplainLinkService {
    private let aiService = AIService()

    func explain(urlString: String) async throws -> ExplainedLink {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            throw APIError.server("Enter a valid article URL starting with http:// or https://.")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.server("Could not load that link right now.")
        }

        let html = String(decoding: data, as: UTF8.self)
        let extracted = HTMLTextExtractor.extractReadableText(from: html)
        guard extracted.count > 180 else {
            throw APIError.server("Briefly could not extract enough readable text from that page.")
        }

        return try await aiService.explainLink(
            content: extracted,
            url: url,
            title: HTMLTextExtractor.extractTitle(from: html)
        )
    }
}

enum HTMLTextExtractor {
    static func extractTitle(from html: String) -> String? {
        guard let range = html.range(
            of: "<title[^>]*>(.*?)</title>",
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return nil
        }

        return clean(html[range].replacingOccurrences(
            of: "<title[^>]*>|</title>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        ))
    }

    static func extractReadableText(from html: String) -> String {
        var sanitized = html
        let patterns = [
            "<script[\\s\\S]*?</script>",
            "<style[\\s\\S]*?</style>",
            "<noscript[\\s\\S]*?</noscript>",
            "<svg[\\s\\S]*?</svg>"
        ]

        for pattern in patterns {
            sanitized = sanitized.replacingOccurrences(
                of: pattern,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        sanitized = sanitized.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )

        sanitized = sanitized
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")

        let cleaned = clean(sanitized)
        let fragments = cleaned
            .split(separator: ".")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 35 }

        return fragments.prefix(18).joined(separator: ". ") + "."
    }

    private static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
