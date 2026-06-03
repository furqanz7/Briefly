import Foundation

struct SearchService {
    private let aiService = AIService()
    private let newsService = NewsService()

    func search(
        query: String,
        in articles: [Article],
        preferredCategories: Set<NewsCategory> = []
    ) async -> SearchResult {
        let normalizedQuery = normalized(query)
        guard !normalizedQuery.isEmpty else {
            return .articles(filtered(articles, preferredCategories: preferredCategories))
        }

        let queryIntent = SearchIntent(query: normalizedQuery)
        let candidateArticles = filtered(articles, preferredCategories: preferredCategories)
        let localRanked = rankedArticles(candidateArticles, intent: queryIntent)
        let remotePreferredCategories = preferredCategories.isEmpty
            ? queryIntent.preferredCategories
            : preferredCategories

        if localRanked.count >= 4 && (score(article: localRanked[0], intent: queryIntent) >= 12) {
            return .articles(localRanked)
        }

        let remoteArticles = await newsService.searchArticles(
            query: queryIntent.providerQuery,
            preferredCategories: remotePreferredCategories,
            desiredCount: 36
        )
        let combinedRanked = rankedArticles(dedupe(candidateArticles + remoteArticles), intent: queryIntent)

        if !combinedRanked.isEmpty {
            return .articles(combinedRanked)
        }

        let newsContext = articles.prefix(12).map(\.chatContext).joined(separator: "\n\n")
        let fallback = (try? await aiService.answerGeneral(question: query, newsContext: newsContext))
            ?? "I couldn't find a matching article right now, but this topic is still worth checking again shortly."
        return .aiFallback(query: query, answer: fallback)
    }

    private func filtered(_ articles: [Article], preferredCategories: Set<NewsCategory>) -> [Article] {
        guard !preferredCategories.isEmpty else { return articles }
        return articles.filter { !preferredCategories.isDisjoint(with: Set($0.categories)) }
    }

    private func rankedArticles(_ articles: [Article], intent: SearchIntent) -> [Article] {
        articles
            .map { (article: $0, score: score(article: $0, intent: intent)) }
            .filter { $0.score >= intent.minimumScore }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return (lhs.article.publishedAt ?? .distantPast) > (rhs.article.publishedAt ?? .distantPast)
                }
                return lhs.score > rhs.score
            }
            .map(\.article)
    }

    private func score(article: Article, intent: SearchIntent) -> Int {
        var total = 0
        let normalizedHeadline = normalized(article.headline)
        let normalizedSummary = normalized(article.plainSummary)
        let normalizedCategory = normalized(article.category)
        let normalizedContent = normalized(article.rawDescription + " " + article.rawContent)
        let normalizedKeywords = normalized(article.keywords.joined(separator: " "))
        let fullText = [normalizedHeadline, normalizedSummary, normalizedContent, normalizedKeywords, normalizedCategory, normalized(article.source)]
            .joined(separator: " ")

        if normalizedHeadline.contains(intent.query) { total += 18 }
        if normalizedSummary.contains(intent.query) { total += 10 }
        if normalizedContent.contains(intent.query) { total += 8 }
        if normalizedKeywords.contains(intent.query) { total += 8 }
        if normalizedCategory.contains(intent.query) { total += 3 }

        let articleTokens = Set(fullText.split(separator: " ").map(String.init))
        let matchedRequired = intent.requiredTokens.filter { articleTokens.contains($0) || fullText.contains($0) }
        let matchedExpanded = intent.expandedTokens.filter { articleTokens.contains($0) || fullText.contains($0) }
        total += matchedRequired.count * 7
        total += matchedExpanded.count * 3

        if !intent.requiredTokens.isEmpty && matchedRequired.count == intent.requiredTokens.count {
            total += 12
        }

        if !intent.preferredCategories.isDisjoint(with: Set(article.categories)) {
            total += 8
        }

        if let publishedAt = article.publishedAt {
            let age = Date().timeIntervalSince(publishedAt)
            if age <= 6 * 60 * 60 {
                total += 5
            } else if age <= 24 * 60 * 60 {
                total += 3
            }
        }

        return total
    }

    private func dedupe(_ articles: [Article]) -> [Article] {
        var byID: [String: Article] = [:]
        for article in articles {
            let key = article.originalURL?.absoluteString ?? article.id
            if let existing = byID[key] {
                if (article.publishedAt ?? .distantPast) > (existing.publishedAt ?? .distantPast) {
                    byID[key] = article
                }
            } else {
                byID[key] = article
            }
        }
        return Array(byID.values)
    }

    private func normalized(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct SearchIntent {
    let query: String
    let requiredTokens: Set<String>
    let expandedTokens: Set<String>
    let preferredCategories: Set<NewsCategory>
    let providerQuery: String

    var minimumScore: Int {
        requiredTokens.count <= 1 ? 8 : 11
    }

    init(query: String) {
        self.query = query

        let stopWords: Set<String> = ["the", "and", "for", "with", "what", "why", "how", "who", "are", "is", "was", "were", "today", "latest", "right", "now", "news"]
        let baseTokens = query
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 2 && !stopWords.contains($0) }

        var expansions = Set(baseTokens)
        var categories = Set<NewsCategory>()

        func add(_ words: [String], category: NewsCategory? = nil) {
            expansions.formUnion(words)
            if let category { categories.insert(category) }
        }

        if baseTokens.contains("ipl") {
            add(["ipl", "cricket", "match", "score", "league"], category: .sports)
        }
        if baseTokens.contains("score") || baseTokens.contains("match") {
            add(["score", "match", "won", "beat", "defeated"], category: .sports)
        }
        if baseTokens.contains("iran") || baseTokens.contains("war") {
            add(["iran", "war", "conflict", "middle", "east", "israel", "nuclear", "talks"], category: .conflict)
            categories.insert(.world)
        }
        if baseTokens.contains("trump") {
            add(["trump", "president", "speech", "white", "house", "campaign"], category: .politics)
        }
        if baseTokens.contains("bitcoin") || baseTokens.contains("crypto") {
            add(["bitcoin", "crypto", "btc", "coinbase", "market"], category: .business)
        }
        if baseTokens.contains("crash") {
            add(["crash", "falls", "drops", "selloff", "slump", "plunge"], category: .business)
        }

        self.requiredTokens = Set(baseTokens)
        self.expandedTokens = expansions
        self.preferredCategories = categories
        self.providerQuery = baseTokens.isEmpty ? query : baseTokens.joined(separator: " ")
    }
}
