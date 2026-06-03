import Foundation

struct ExplainedLink: Equatable {
    let url: URL
    let sourceTitle: String
    let summary: String
    let keyPoints: [String]
    let whyItMatters: String
    let extractedText: String

    var articleProxy: Article {
        Article(
            id: "explained-\(url.absoluteString)",
            headline: sourceTitle,
            source: url.host ?? "External Link",
            imageURL: nil,
            originalURL: url,
            publishedAt: .now,
            summaryCards: [
                summary,
                keyPoints.joined(separator: " "),
                whyItMatters
            ].map {
                $0.isEmpty ? "Briefly couldn't extract enough detail from this link, but you can still ask follow-up questions." : $0
            },
            plainSummary: summary,
            rawDescription: summary,
            rawContent: extractedText,
            category: "Explained Link",
            categories: [.world],
            keywords: [sourceTitle, url.host ?? "link"]
        )
    }
}
