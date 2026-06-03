import Foundation

struct SavedArticleRecord: Codable {
    let id: UUID?
    let userID: UUID
    let articleID: String
    let headline: String
    let source: String
    let imageURL: String?
    let originalURL: String?
    let plainSummary: String
    let rawDescription: String
    let rawContent: String
    let category: String
    let summaryCards: [String]
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case articleID = "article_id"
        case headline
        case source
        case imageURL = "image_url"
        case originalURL = "original_url"
        case plainSummary = "plain_summary"
        case rawDescription = "raw_description"
        case rawContent = "raw_content"
        case category
        case summaryCards = "summary_cards"
        case createdAt = "created_at"
    }

    init(article: Article, userID: UUID) {
        id = nil
        self.userID = userID
        articleID = article.id
        headline = article.headline
        source = article.source
        imageURL = article.imageURL?.absoluteString
        originalURL = article.originalURL?.absoluteString
        plainSummary = article.plainSummary
        rawDescription = article.rawDescription
        rawContent = article.rawContent
        category = article.category
        summaryCards = article.summaryCards
        createdAt = nil
    }

    func article() -> Article {
        Article(
            id: articleID,
            headline: headline,
            source: source,
            imageURL: imageURL.flatMap(URL.init(string:)),
            originalURL: originalURL.flatMap(URL.init(string:)),
            publishedAt: createdAt,
            summaryCards: summaryCards,
            plainSummary: plainSummary,
            rawDescription: rawDescription,
            rawContent: rawContent,
            category: category
        )
    }
}
