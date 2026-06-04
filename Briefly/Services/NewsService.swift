import Foundation

struct NewsService {
    private static var cachedArticles: [Article] = []
    private static var cacheTimestamp: Date?
    private static let cacheTTL: TimeInterval = 600

    private let config = AppConfig.shared

    func fetchArticles(
        forceRefresh: Bool = false,
        desiredCount: Int = 20,
        excludingIDs: Set<String> = []
    ) async throws -> [Article] {
        if !forceRefresh,
           excludingIDs.isEmpty,
           let cached = Self.validCachedArticles(now: .now, minimumCount: min(desiredCount, 24)) {
            return Array(cached.prefix(desiredCount))
        }

        guard config.hasNewsAPI else {
            return Article.mocks
        }

        if excludingIDs.isEmpty,
           let edgeURL = config.dailyFeedFunctionURL,
           config.hasSupabase {
            if let edgeArticles = try? await fetchFromEdgeFunction(url: edgeURL, forceRefresh: forceRefresh, desiredCount: desiredCount),
               !edgeArticles.isEmpty {
                Self.storeCache(edgeArticles)
                return Array(edgeArticles.prefix(desiredCount))
            }
        }

        let providers = activeProviders()
        guard !providers.isEmpty else {
            return Article.mocks
        }

        let combinedService = CombinedNewsService(providers: providers)

        let articles: [Article]
        do {
            articles = try await combinedService.fetchFeed(
                categories: NewsCategory.allCases,
                desiredCount: desiredCount,
                forceRefresh: forceRefresh,
                excludingIDs: excludingIDs
            )
        } catch {
            if let stale = Self.staleCachedArticles(desiredCount: desiredCount) {
                return stale
            }
            throw error
        }

        let todayWindow = DayWindow.current()
        let trailingWindow = DayWindow.trailing(hours: 24)

        let todaysArticles = articles
            .filter { article in
                guard let publishedAt = article.publishedAt else { return false }
                return todayWindow.contains(publishedAt)
            }

        let minimumFreshTodayCount = min(desiredCount, 12)
        if todaysArticles.count >= minimumFreshTodayCount {
            let result = Array(todaysArticles.prefix(desiredCount))
            Self.storeCache(result)
            return result
        }

        let carryoverArticles = articles
            .filter { article in
                guard let publishedAt = article.publishedAt else { return false }
                return trailingWindow.contains(publishedAt) && !todayWindow.contains(publishedAt)
            }

        let merged = dedupeByID(todaysArticles + carryoverArticles)

        let result = Array(merged.prefix(desiredCount))
        if result.isEmpty, let stale = Self.staleCachedArticles(desiredCount: desiredCount) {
            return stale
        }
        Self.storeCache(result)
        return result
    }

    private struct EdgeFeedEnvelope: Decodable {
        let generatedAt: Date?
        let source: String?
        let cacheHit: Bool?
        let message: String?
        let articles: [Article]
    }

    private func fetchFromEdgeFunction(url: URL, forceRefresh: Bool, desiredCount: Int) async throws -> [Article] {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []

        // Keep TTL short so the feed feels "live" while still saving device and API cost.
        queryItems.append(URLQueryItem(name: "count", value: String(max(12, desiredCount))))
        queryItems.append(URLQueryItem(name: "ttl", value: forceRefresh ? "30" : "180"))

        // Basic region hints.
        let locale = Locale.autoupdatingCurrent
        if let lang = locale.language.languageCode?.identifier {
            queryItems.append(URLQueryItem(name: "lang", value: lang))
        }
        if let region = locale.region?.identifier.lowercased() {
            queryItems.append(URLQueryItem(name: "country", value: String(region.prefix(2))))
        }

        components?.queryItems = queryItems
        guard let finalURL = components?.url else { return [] }

        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = forceRefresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return [] }
        guard (200...299).contains(http.statusCode) else { return [] }

        let payload = try JSONDecoder.supabase.decode(EdgeFeedEnvelope.self, from: data)
        return payload.articles
    }

    private static func validCachedArticles(now: Date, minimumCount: Int) -> [Article]? {
        guard let cacheTimestamp, cachedArticles.count >= minimumCount else { return nil }
        guard now.timeIntervalSince(cacheTimestamp) < cacheTTL else { return nil }
        return cachedArticles
    }

    private static func staleCachedArticles(desiredCount: Int) -> [Article]? {
        guard !cachedArticles.isEmpty else { return nil }
        return Array(cachedArticles.prefix(desiredCount))
    }

    private static func storeCache(_ articles: [Article]) {
        guard !articles.isEmpty else { return }
        cachedArticles = articles
        cacheTimestamp = .now
    }

    private func activeProviders() -> [NewsProvider] {
        var providers: [NewsProvider] = []

        if config.hasNewsDataAPI {
            providers.append(NewsDataProvider())
            providers.append(NewsDataTrendingProvider())
        }

        if config.hasMediastackAPI {
            providers.append(MediastackProvider())
        }

        if config.hasNewsAPIOrg {
            providers.append(NewsAPIProvider())
        }

        if config.hasGNewsAPI {
            providers.append(GNewsProvider())
        }

        if config.hasGuardianAPI {
            providers.append(GuardianProvider())
        }

        if config.hasWorldNewsAPI {
            providers.append(WorldNewsAPIProvider())
        }

        if config.hasNewYorkTimesAPI {
            providers.append(NewYorkTimesProvider())
        }

        return providers
    }

    func searchArticles(
        query: String,
        preferredCategories: Set<NewsCategory> = [],
        desiredCount: Int = 24
    ) async -> [Article] {
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedQuery.isEmpty else { return [] }

        let providers = activeProviders()
        guard !providers.isEmpty else { return [] }

        let categories = preferredCategories.isEmpty
            ? inferredCategories(for: cleanedQuery)
            : Array(preferredCategories)
        let pageSize = max(10, Int(ceil(Double(desiredCount) / Double(max(categories.count, 1)))))

        let batches = await withTaskGroup(of: [Article].self) { group in
            for category in categories {
                for provider in providers {
                    group.addTask {
                        do {
                            return try await provider.search(
                                query: cleanedQuery,
                                category: category,
                                pageSize: pageSize,
                                forceRefresh: true
                            )
                        } catch {
                            return []
                        }
                    }
                }
            }

            var merged: [[Article]] = []
            for await articles in group {
                merged.append(articles)
            }
            return merged
        }
        .flatMap { $0 }

        return Array(dedupeByID(batches)
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
            .prefix(desiredCount))
    }

    private func inferredCategories(for query: String) -> [NewsCategory] {
        let normalized = query.lowercased()
        var categories: [NewsCategory] = []

        if normalized.contains("ipl") || normalized.contains("cricket") || normalized.contains("score") || normalized.contains("match") || normalized.contains("football") {
            categories.append(.sports)
        }
        if normalized.contains("iran") || normalized.contains("war") || normalized.contains("gaza") || normalized.contains("israel") || normalized.contains("ukraine") || normalized.contains("missile") {
            categories.append(contentsOf: [.conflict, .world])
        }
        if normalized.contains("trump") || normalized.contains("speech") || normalized.contains("election") || normalized.contains("poll") || normalized.contains("government") {
            categories.append(.politics)
        }
        if normalized.contains("bitcoin") || normalized.contains("crypto") || normalized.contains("stock") || normalized.contains("market") || normalized.contains("crash") || normalized.contains("oil") {
            categories.append(.business)
        }
        if normalized.contains("ai") || normalized.contains("nvidia") || normalized.contains("openai") || normalized.contains("apple") || normalized.contains("google") {
            categories.append(.technology)
        }

        var seen = Set<NewsCategory>()
        let unique = categories.filter { seen.insert($0).inserted }
        return unique.isEmpty ? NewsCategory.allCases : unique
    }

    private func dedupeByID(_ articles: [Article]) -> [Article] {
        var byID: [String: Article] = [:]
        for article in articles {
            if let existing = byID[article.id] {
                let mergedCategories = mergeCategories(existing.categories + article.categories)
                if (article.publishedAt ?? .distantPast) > (existing.publishedAt ?? .distantPast) {
                    byID[article.id] = article.withCategories(mergedCategories)
                } else {
                    byID[article.id] = existing.withCategories(mergedCategories)
                }
            } else {
                byID[article.id] = article
            }
        }
        return Array(byID.values)
    }

    private func mergeCategories(_ categories: [NewsCategory]) -> [NewsCategory] {
        var seen = Set<NewsCategory>()
        var merged: [NewsCategory] = []

        for category in categories {
            guard !seen.contains(category) else { continue }
            seen.insert(category)
            merged.append(category)
        }

        return merged
    }
}

struct NewsResponse: Decodable {
    let results: [NewsArticleDTO]
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case results
        case nextPage
    }
}

struct NewsArticleDTO: Decodable {
    let articleID: String?
    let title: String?
    let link: String?
    let description: String?
    let content: String?
    let imageURL: String?
    let sourceID: String?
    let sourceName: String?
    let pubDate: String?
    let category: [String]?
    let keywords: [String]?

    enum CodingKeys: String, CodingKey {
        case articleID = "article_id"
        case title
        case link
        case description
        case content
        case imageURL = "image_url"
        case sourceID = "source_id"
        case sourceName = "source_name"
        case pubDate
        case category
        case keywords
    }

    func toArticle(defaultCategory: NewsCategory) -> Article? {
        guard let title, !title.isEmpty else { return nil }

        let cleanTitle = HeadlineFormatter.simplify(title)
        let source = sourceName ?? sourceID ?? "News Desk"
        let body = [description, content].compactMap { $0 }.joined(separator: " ")
        let cards = SummaryBuilder.makeCards(from: cleanTitle, source: source, text: body)
        let plain = cards.joined(separator: " ")
        let parsedDate = pubDate.flatMap(DateParser.newsDate(from:))
        let categories = normalizedCategories(defaultCategory: defaultCategory)

        return Article(
            id: articleID ?? UUID().uuidString,
            headline: cleanTitle,
            source: source,
            imageURL: imageURL.flatMap(URL.init(string:)),
            originalURL: link.flatMap(URL.init(string:)),
            publishedAt: parsedDate,
            summaryCards: cards,
            plainSummary: plain,
            rawDescription: description ?? "",
            rawContent: content ?? body,
            category: categories.first?.displayName ?? defaultCategory.displayName,
            categories: categories,
            keywords: normalizedKeywords(fallbackText: [cleanTitle, body, categories.map(\.displayName).joined(separator: " ")].joined(separator: " "))
        )
    }

    private func normalizedCategories(defaultCategory: NewsCategory) -> [NewsCategory] {
        let mapped = (category ?? []).compactMap(NewsCategory.init(providerValue:))
        return mapped.isEmpty ? [defaultCategory] : Array(Set(mapped + [defaultCategory]))
    }

    private func normalizedKeywords(fallbackText: String) -> [String] {
        if let keywords, !keywords.isEmpty {
            return keywords
        }

        return fallbackText
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 3 }
            .prefix(8)
            .map { $0 }
    }
}

enum HeadlineFormatter {
    static func simplify(_ title: String) -> String {
        let normalized = normalize(title)

        if normalized.count <= 88 {
            return normalized
        }

        for separator in [" | ", " - ", " — ", " – ", ": "] {
            let parts = normalized.components(separatedBy: separator)
            if let first = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines),
               first.count >= 24,
               first.count <= 88 {
                return first
            }
        }

        return trimAtWordBoundary(normalized, limit: 88)
    }

    private static func normalize(_ title: String) -> String {
        let compact = title
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let withoutSourceSuffix = stripLikelySourceSuffix(from: compact)
        return withoutSourceSuffix
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripLikelySourceSuffix(from title: String) -> String {
        for separator in [" | ", " - ", " — ", " – "] {
            let parts = title.components(separatedBy: separator)
            guard parts.count == 2 else { continue }

            let left = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let right = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)

            if looksLikeSourceName(right), left.count >= 16 {
                return left
            }
        }

        return title
    }

    private static func looksLikeSourceName(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= 28 else { return false }

        let lower = text.lowercased()
        let sourceTokens = [
            "news", "times", "post", "journal", "reuters", "bloomberg",
            "guardian", "wire", "desk", "cnn", "bbc", "cnbc", "fox",
            "economist", "mint", "hindu", "today", "express"
        ]

        if sourceTokens.contains(where: { lower.contains($0) }) {
            return true
        }

        let words = text.split(separator: " ")
        return words.count <= 4 && words.allSatisfy { word in
            guard let scalar = word.unicodeScalars.first else { return false }
            return CharacterSet.uppercaseLetters.contains(scalar)
        }
    }

    private static func trimAtWordBoundary(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }

        let cutoffIndex = text.index(text.startIndex, offsetBy: limit)
        let prefix = String(text[..<cutoffIndex])

        if let lastSpace = prefix.lastIndex(of: " "), prefix.distance(from: prefix.startIndex, to: lastSpace) >= 24 {
            return String(prefix[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return prefix.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SummaryBuilder {
    static func makeCards(from headline: String, source: String, text: String) -> [String] {
        let sentences = splitIntoSentences(text)
        var cards: [String] = []
        var index = 0

        while cards.count < 3 {
            let seed = [
                sentences[safe: index],
                sentences[safe: index + 1]
            ]
            .compactMap { $0 }
            .joined(separator: " ")

            let fallback = fallbackSentence(headline: headline, source: source, index: cards.count)
            let raw = seed.isEmpty ? fallback : seed
            cards.append(normalizeCard(raw, fallback: fallback))
            index += 2
        }

        return cards
    }

    static func suggestions(for article: Article) -> [String] {
        let fragments = article.headline.split(separator: " ").prefix(3).joined(separator: " ")
        return [
            "Why does this story matter?",
            "What should I watch next with \(fragments)?",
            "Explain this like I'm new to it"
        ]
    }

    private static func splitIntoSentences(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { ".!?".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "\($0)." }
    }

    private static func normalizeCard(_ raw: String, fallback: String) -> String {
        var words = raw.split(separator: " ").map(String.init)
        if words.count < 28 {
            words += fallback.split(separator: " ").map(String.init)
        }
        if words.count > 35 {
            words = Array(words.prefix(35))
        }
        return words.joined(separator: " ")
    }

    private static func fallbackSentence(headline: String, source: String, index: Int) -> String {
        switch index {
        case 0:
            return "\(headline) is getting attention because it could change what people expect next. \(source) says the story matters because the effects may spread beyond one company or one market."
        case 1:
            return "The bigger picture is that this story connects to money, power, or public opinion in a real way. That makes it more than a one-day headline for people following the news."
        default:
            return "What happens next will decide whether this stays a short-term headline or grows into something bigger. That is why people are watching for the next update."
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

enum DateParser {
    static func newsDate(from value: String) -> Date? {
        if let date = withFractionalSeconds.date(from: value) {
            return date
        }
        if let date = withoutFractionalSeconds.date(from: value) {
            return date
        }
        return legacyNewsDate.date(from: value)
    }

    private static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let withoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let legacyNewsDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
