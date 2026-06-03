import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    enum Mode {
        case article(Article)
        case general(newsContext: String)
    }

    @Published var messages: [ChatMessage]
    @Published var draft = ""
    @Published var isSending = false
    let title: String
    let suggestions: [String]

    private let mode: Mode
    private let aiService = AIService()

    init(article: Article) {
        self.mode = .article(article)
        self.title = "Ask Briefly"
        self.suggestions = SummaryBuilder.suggestions(for: article)
        self.messages = [
            ChatMessage(role: .assistant, text: "Hi, I'm Briefly! What can I answer for you?")
        ]
    }

    init(newsContext: String) {
        self.mode = .general(newsContext: newsContext)
        self.title = "General News Question"
        self.suggestions = [
            "What is happening in world news today?",
            "Why are markets moving right now?",
            "What is the biggest sports story today?"
        ]
        self.messages = [
            ChatMessage(role: .assistant, text: "Hi, I'm Briefly! Ask me any general news question.")
        ]
    }

    func send(_ question: String? = nil) async {
        let text = (question ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        draft = ""
        isSending = true
        messages.append(ChatMessage(role: .user, text: text))

        do {
            let answer: String
            switch mode {
            case .article(let article):
                answer = try await aiService.answer(question: text, for: article)
            case .general(let newsContext):
                answer = try await aiService.answerGeneral(question: text, newsContext: newsContext)
            }
            messages.append(ChatMessage(role: .assistant, text: answer))
        } catch {
            messages.append(ChatMessage(role: .assistant, text: fallbackAnswer(for: text)))
        }

        isSending = false
    }

    private func fallbackAnswer(for question: String) -> String {
        switch mode {
        case .article(let article):
            let summary = article.plainSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !summary.isEmpty {
                return "I couldn't explain that clearly yet. Based on the article, \(summary)"
            }
            return "I couldn't explain that clearly yet--try asking in a simpler way."
        case .general(let newsContext):
            let fallback = contextFallback(from: newsContext, question: question)
            if !fallback.isEmpty {
                return fallback
            }
            return "I couldn't explain that clearly yet--try asking in a simpler way."
        }
    }

    private func contextFallback(from newsContext: String, question: String) -> String {
        let summaries = newsContext
            .components(separatedBy: "\n")
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("Summary:") else { return nil }
                return trimmed
                    .replacingOccurrences(of: "Summary:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        guard !summaries.isEmpty else { return "" }

        let lowerQuestion = question.lowercased()
        let selected = summaries.first { summary in
            let lowerSummary = summary.lowercased()
            return lowerQuestion
                .split(separator: " ")
                .contains { token in
                    token.count > 3 && lowerSummary.contains(token)
                }
        } ?? summaries.first

        guard let selected, !selected.isEmpty else { return "" }

        let cleaned = selected
            .replacingOccurrences(of: "\\[[0-9]+ chars\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let snippet = String(cleaned.prefix(320))
        return "I couldn't explain that clearly yet. From today's news context: \(snippet)"
    }
}
