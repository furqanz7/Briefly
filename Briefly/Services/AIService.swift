import Foundation

struct AIService {
    private let config = AppConfig.shared

    func answer(question: String, for article: Article) async throws -> String {
        guard config.hasAI else {
            return article.plainSummary.isEmpty
                ? Self.genericFallbackAnswer
                : "I couldn't explain that clearly yet. Based on the article, \(article.plainSummary)"
        }

        switch config.aiProvider {
        case .gemini:
            return try await askGemini(
                prompt: """
                You are Briefly, a casual news explainer. Answer using one or two short sentences. Use simple everyday language and stay grounded in the provided article context.

                Article context:
                \(article.fullChatContext)

                Question:
                \(question)
                """
            )
        case .openAICompatible:
            return try await askOpenAICompatible(
                system: "You are Briefly, a casual news explainer. Answer using one or two short sentences. Use simple everyday language and stay grounded in the provided article context.",
                user: "Article context:\n\(article.fullChatContext)\n\nQuestion: \(question)"
            )
        }
    }

    func answerGeneral(question: String, newsContext: String) async throws -> String {
        guard config.hasAI else {
            return Self.genericFallbackAnswer
        }

        let system = """
        You are Briefly, a simple news explainer.
        Answer in one or two short sentences.
        Use plain everyday language.
        If the topic is moving quickly or uncertain, say that clearly.
        """

        let user = """
        Recent news context:
        \(newsContext)

        General question:
        \(question)
        """

        switch config.aiProvider {
        case .gemini:
            return try await askGemini(prompt: "\(system)\n\n\(user)")
        case .openAICompatible:
            return try await askOpenAICompatible(system: system, user: user)
        }
    }

    func explainLink(content: String, url: URL, title: String?) async throws -> ExplainedLink {
        guard config.hasAI else {
            return ExplainedLink(
                url: url,
                sourceTitle: title ?? (url.host ?? "External article"),
                summary: "I couldn't explain that link clearly yet, but I was able to read some of the page text.",
                keyPoints: [
                    "The link opened successfully.",
                    "Some readable article text was found.",
                    "Try asking Briefly a simpler question about the link."
                ],
                whyItMatters: "The story may still be useful, but Briefly could not turn it into a clear summary right now.",
                extractedText: content
            )
        }

        let sourceTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? (url.host ?? "External article")
        let prompt = """
        You are Briefly, a simple news explainer.
        Read the article text below and respond in JSON with this exact schema:
        {
          "summary": "1 or 2 short sentences",
          "key_points": ["point 1", "point 2", "point 3"],
          "why_it_matters": "1 or 2 short sentences"
        }

        Use plain everyday language.
        Keep the key points tight and useful.

        Title: \(sourceTitle)
        URL: \(url.absoluteString)

        Article text:
        \(content)
        """

        let jsonString: String
        switch config.aiProvider {
        case .gemini:
            jsonString = try await askGemini(prompt: prompt)
        case .openAICompatible:
            jsonString = try await askOpenAICompatible(
                system: "You are Briefly, a simple news explainer that returns valid JSON only.",
                user: prompt
            )
        }

        let parsed = try LinkExplanationParser.parse(jsonString)
        return ExplainedLink(
            url: url,
            sourceTitle: sourceTitle,
            summary: parsed.summary,
            keyPoints: parsed.keyPoints,
            whyItMatters: parsed.whyItMatters,
            extractedText: content
        )
    }

    private func askOpenAICompatible(system: String, user: String) async throws -> String {
        guard let baseURL = config.aiBaseURL else {
            throw APIError.missingConfiguration("Missing AI base URL.")
        }

        let url = baseURL.appending(path: "/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.aiAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = OpenAIRequest(
            model: config.aiModel,
            messages: [
                .init(role: "system", content: system),
                .init(role: "user", content: user)
            ]
        )

        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.server(Self.genericFallbackAnswer)
        }

        guard (200...299).contains(http.statusCode) else {
            throw APIError.server(Self.genericFallbackAnswer)
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        return decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? Self.genericFallbackAnswer
    }

    private func askGemini(prompt: String) async throws -> String {
        guard let baseURL = config.aiBaseURL else {
            throw APIError.missingConfiguration("Missing Gemini base URL.")
        }

        let path = "/models/\(config.aiModel):generateContent?key=\(config.aiAPIKey)"
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "contents": [[
                "parts": [[
                    "text": prompt
                ]]
            ]]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.server(Self.genericFallbackAnswer)
        }

        guard (200...299).contains(http.statusCode) else {
            throw APIError.server(Self.genericFallbackAnswer)
        }

        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = decoded?["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]]
        let text = parts?.first?["text"] as? String
        return text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? Self.genericFallbackAnswer
    }

    private static let genericFallbackAnswer = "I couldn't explain that clearly yet--try asking in a simpler way."
}

private enum LinkExplanationParser {
    struct Payload: Decodable {
        let summary: String
        let keyPoints: [String]
        let whyItMatters: String

        enum CodingKeys: String, CodingKey {
            case summary
            case keyPoints = "key_points"
            case whyItMatters = "why_it_matters"
        }
    }

    static func parse(_ raw: String) throws -> Payload {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^```json\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "^```\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s*```$", with: "", options: .regularExpression)

        guard let data = cleaned.data(using: .utf8) else {
            throw APIError.server("The AI could not format the explained link response.")
        }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return Payload(
            summary: payload.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            keyPoints: payload.keyPoints.prefix(3).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            whyItMatters: payload.whyItMatters.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct OpenAIRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
}

private struct OpenAIResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }

        let message: Message
    }

    let choices: [Choice]
}
