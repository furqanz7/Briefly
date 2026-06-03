import Foundation

struct Article: Identifiable, Codable, Equatable {
    let id: String
    let headline: String
    let source: String
    let imageURL: URL?
    let originalURL: URL?
    let publishedAt: Date?
    let summaryCards: [String]
    let plainSummary: String
    let rawDescription: String
    let rawContent: String
    let category: String
    let categories: [NewsCategory]
    let keywords: [String]

    init(
        id: String,
        headline: String,
        source: String,
        imageURL: URL?,
        originalURL: URL?,
        publishedAt: Date?,
        summaryCards: [String],
        plainSummary: String,
        rawDescription: String,
        rawContent: String,
        category: String,
        categories: [NewsCategory]? = nil,
        keywords: [String] = []
    ) {
        self.id = id
        self.headline = headline
        self.source = source
        self.imageURL = imageURL
        self.originalURL = originalURL
        self.publishedAt = publishedAt
        self.summaryCards = summaryCards
        self.plainSummary = plainSummary
        self.rawDescription = rawDescription
        self.rawContent = rawContent

        let baseKeywords = keywords.isEmpty
            ? Article.extractKeywords(from: [headline, plainSummary, rawDescription, rawContent, category])
            : keywords
        let cleanedKeywords = Article.cleanKeywords(baseKeywords)
        let providedCategories = categories ?? []
        let resolvedCategories = providedCategories.isEmpty
            ? [NewsCategory(providerValue: category.lowercased())].compactMap { $0 }
            : providedCategories
        let inferredCategories = Article.inferCategories(from: [headline, plainSummary, rawDescription, rawContent, category] + cleanedKeywords)
        let mergedCategories = inferredCategories.isEmpty
            ? Article.mergeCategories(primary: resolvedCategories, secondary: [])
            : inferredCategories
        self.categories = mergedCategories.isEmpty ? [.world] : mergedCategories
        self.category = self.categories.first?.displayName ?? category

        self.keywords = cleanedKeywords
    }

    var searchText: String {
        ([headline, plainSummary, rawDescription, rawContent, category, source] + keywords + categories.map(\.displayName))
            .joined(separator: " ")
            .lowercased()
    }

    var chatContext: String {
        briefChatContext
    }

    var briefChatContext: String {
        [
            "Headline: \(headline)",
            "Source: \(source)",
            "Category: \(category)",
            "Keywords: \(keywords.prefix(8).joined(separator: ", "))",
            "Summary: \(plainSummary)"
        ]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    var fullChatContext: String {
        let trimmedBody = rawContent
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bodySnippet = String(trimmedBody.prefix(1200))

        return [
            briefChatContext,
            bodySnippet.isEmpty ? nil : "Body: \(bodySnippet)"
        ]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case headline
        case source
        case imageURL
        case originalURL
        case publishedAt
        case summaryCards
        case plainSummary
        case rawDescription
        case rawContent
        case category
        case categories
        case keywords
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let headline = try container.decode(String.self, forKey: .headline)
        let source = try container.decode(String.self, forKey: .source)
        let imageURL = try container.decodeIfPresent(URL.self, forKey: .imageURL)
        let originalURL = try container.decodeIfPresent(URL.self, forKey: .originalURL)
        let publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt)
        let summaryCards = try container.decode([String].self, forKey: .summaryCards)
        let plainSummary = try container.decode(String.self, forKey: .plainSummary)
        let rawDescription = try container.decode(String.self, forKey: .rawDescription)
        let rawContent = try container.decode(String.self, forKey: .rawContent)
        let category = try container.decode(String.self, forKey: .category)
        let categories = try container.decodeIfPresent([NewsCategory].self, forKey: .categories)
        let keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []

        self.init(
            id: id,
            headline: headline,
            source: source,
            imageURL: imageURL,
            originalURL: originalURL,
            publishedAt: publishedAt,
            summaryCards: summaryCards,
            plainSummary: plainSummary,
            rawDescription: rawDescription,
            rawContent: rawContent,
            category: category,
            categories: categories,
            keywords: keywords
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(headline, forKey: .headline)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(imageURL, forKey: .imageURL)
        try container.encodeIfPresent(originalURL, forKey: .originalURL)
        try container.encodeIfPresent(publishedAt, forKey: .publishedAt)
        try container.encode(summaryCards, forKey: .summaryCards)
        try container.encode(plainSummary, forKey: .plainSummary)
        try container.encode(rawDescription, forKey: .rawDescription)
        try container.encode(rawContent, forKey: .rawContent)
        try container.encode(category, forKey: .category)
        try container.encode(categories, forKey: .categories)
        try container.encode(keywords, forKey: .keywords)
    }

    func withCategories(_ categories: [NewsCategory]) -> Article {
        Article(
            id: id,
            headline: headline,
            source: source,
            imageURL: imageURL,
            originalURL: originalURL,
            publishedAt: publishedAt,
            summaryCards: summaryCards,
            plainSummary: plainSummary,
            rawDescription: rawDescription,
            rawContent: rawContent,
            category: categories.first?.displayName ?? category,
            categories: categories,
            keywords: keywords
        )
    }

    static let mocks: [Article] = [
        Article(
            id: "1",
            headline: "This chip startup wants AI to run cheaper",
            source: "Mock Wire",
            imageURL: URL(string: "https://images.unsplash.com/photo-1518770660439-4636190af475?auto=format&fit=crop&w=1200&q=80"),
            originalURL: URL(string: "https://example.com/article-1"),
            publishedAt: .now,
            summaryCards: [
                "A small chip company says it found a way to make AI servers use less power and spend less money. That matters because running big models is still painfully expensive for most teams.",
                "The startup is pitching its hardware to cloud providers that need more speed without buying endless new machines. If it works, smaller AI products could launch faster and at lower prices.",
                "Investors like the idea because demand for AI computing is still climbing every quarter. The bigger question is whether the company can build enough hardware before larger rivals copy the approach."
            ],
            plainSummary: "A chip startup is promising cheaper AI computing for cloud companies.",
            rawDescription: "A chip startup says it can make AI workloads much cheaper.",
            rawContent: "A chip startup says it can lower the cost of AI computing by redesigning how workloads move through servers. The pitch is simple: less wasted power, more efficient performance, and a lower bill for companies training or serving large AI models.",
            category: "Technology",
            categories: [.technology],
            keywords: ["AI", "chips", "cloud", "startup"]
        ),
        Article(
            id: "2",
            headline: "A fintech app is turning invoices into cash",
            source: "Mock Ledger",
            imageURL: URL(string: "https://images.unsplash.com/photo-1554224155-6726b3ff858f?auto=format&fit=crop&w=1200&q=80"),
            originalURL: URL(string: "https://example.com/article-2"),
            publishedAt: .now.addingTimeInterval(-7200),
            summaryCards: [
                "This startup lets small businesses get paid sooner instead of waiting weeks for invoices to clear. It fronts the money now, then collects the payment later for a fee.",
                "That can help companies cover payroll, rent, and supplier bills without taking a traditional bank loan. It is basically invoice factoring, but packaged like a clean modern app.",
                "The upside is faster cash flow for businesses that are growing but still tight on money. The risk is that bad customers or late payments can quickly make the model much harder to run."
            ],
            plainSummary: "A fintech startup is helping small businesses unlock invoice cash faster.",
            rawDescription: "The company advances invoice payments for a fee.",
            rawContent: "The company advances money against unpaid invoices and then collects from the end customer later. That gives small businesses quick working capital without a standard loan application.",
            category: "Business",
            categories: [.business],
            keywords: ["fintech", "invoices", "cash flow", "small business"]
        ),
        Article(
            id: "3",
            headline: "Global leaders are scrambling after new border strike",
            source: "Mock World Desk",
            imageURL: URL(string: "https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=1200&q=80"),
            originalURL: URL(string: "https://example.com/article-3"),
            publishedAt: .now.addingTimeInterval(-10800),
            summaryCards: [
                "Several governments are reacting after a border strike raised fears of a wider conflict. Officials are pushing for quick talks before the situation gets worse.",
                "Markets and energy prices often react fast when a regional fight looks like it could spread. That is why investors and diplomats are both watching closely.",
                "The key question now is whether this stays a limited clash or pulls in more countries. That will decide how serious the global fallout becomes."
            ],
            plainSummary: "A new border strike is raising fears of a wider conflict.",
            rawDescription: "Leaders are urging restraint after the latest attack.",
            rawContent: "Leaders across several countries are calling for restraint after a border strike triggered new fears of escalation. Diplomats are trying to stop the crisis from widening while military forces remain on alert.",
            category: "War / Conflict",
            categories: [.conflict, .world],
            keywords: ["war", "conflict", "border", "strike", "diplomats"]
        )
    ]

    private static func extractKeywords(from texts: [String]) -> [String] {
        let stopWords: Set<String> = [
            "the", "and", "for", "with", "that", "this", "from", "have", "will", "into", "their", "about",
            "after", "before", "while", "where", "which", "what", "when", "your", "they", "them", "just",
            "says", "said", "news", "story", "today", "more", "less"
        ]

        let tokens = texts
            .joined(separator: " ")
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 2 && !stopWords.contains($0) }

        var counts: [String: Int] = [:]
        for token in tokens {
            counts[token, default: 0] += 1
        }

        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .prefix(8)
            .map(\.key)
    }

    private static func cleanKeywords(_ keywords: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for keyword in keywords {
            let cleaned = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            let normalized = cleaned.lowercased()
            guard !cleaned.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            ordered.append(cleaned)
        }

        return ordered
    }

    private static func inferCategories(from texts: [String]) -> [NewsCategory] {
        let text = texts
            .joined(separator: " ")
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        let rules: [(NewsCategory, [(String, Int)])] = [
            (.conflict, [
                ("war", 8), ("conflict", 8), ("attack", 6), ("strike", 6), ("missile", 6),
                ("military", 5), ("troops", 5), ("ceasefire", 6), ("gaza", 7), ("israel", 5),
                ("iran", 5), ("ukraine", 6), ("hormuz", 7), ("border", 4), ("hostage", 5),
                ("shot", 6), ("dead", 5), ("killed", 6), ("murder", 6), ("violence", 5)
            ]),
            (.politics, [
                ("election", 8), ("poll", 6), ("vote", 6), ("parliament", 6), ("government", 5),
                ("minister", 5), ("senate", 6), ("congress", 6), ("president", 5), ("trump", 7),
                ("biden", 6), ("modi", 6), ("white house", 7), ("speech", 4), ("policy", 4),
                ("leader", 4), ("party", 5), ("lawmaker", 6), ("mp", 5)
            ]),
            (.sports, [
                ("ipl", 10), ("cricket", 8), ("match", 4), ("score", 5), ("fixture", 5),
                ("tournament", 5), ("league", 5), ("football", 7), ("tennis", 7), ("fifa", 7),
                ("nba", 7), ("nfl", 7), ("f1", 7), ("wicket", 7), ("runs", 6), ("goal", 6)
            ]),
            (.technology, [
                ("ai", 8), ("artificial intelligence", 8), ("openai", 9), ("nvidia", 8),
                ("chip", 7), ("semiconductor", 7), ("software", 5), ("app", 4), ("iphone", 6),
                ("google", 5), ("microsoft", 5), ("apple", 5), ("startup", 4), ("robot", 5)
            ]),
            (.business, [
                ("market", 7), ("stock", 7), ("stocks", 7), ("bitcoin", 8), ("crypto", 7),
                ("oil", 7), ("earnings", 7), ("company", 4), ("funding", 6), ("ipo", 7),
                ("economy", 6), ("inflation", 7), ("fed", 7), ("bank", 5), ("rupee", 5),
                ("dollar", 5), ("tariff", 5), ("revenue", 5)
            ]),
            (.world, [
                ("world", 4), ("global", 5), ("international", 5), ("middle east", 7),
                ("pakistan", 5), ("china", 5), ("russia", 5), ("europe", 5), ("eu", 5),
                ("united nations", 6), ("diplomacy", 5), ("summit", 4)
            ])
        ]

        let scored = rules.compactMap { category, terms -> (NewsCategory, Int)? in
            let score = terms.reduce(0) { partial, rule in
                partial + (Article.matches(rule.0, in: text) ? rule.1 : 0)
            }
            return score >= 5 ? (category, score) : nil
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 { return lhs.0.displayName < rhs.0.displayName }
                return lhs.1 > rhs.1
            }
            .prefix(3)
            .map(\.0)
    }

    private static func mergeCategories(primary: [NewsCategory], secondary: [NewsCategory]) -> [NewsCategory] {
        var seen = Set<NewsCategory>()
        var merged: [NewsCategory] = []

        for category in primary + secondary {
            guard !seen.contains(category) else { continue }
            seen.insert(category)
            merged.append(category)
        }

        return merged
    }

    private static func matches(_ term: String, in text: String) -> Bool {
        if term.contains(" ") {
            return text.contains(term)
        }

        return text.range(of: "\\b\(NSRegularExpression.escapedPattern(for: term))\\b", options: .regularExpression) != nil
    }
}
