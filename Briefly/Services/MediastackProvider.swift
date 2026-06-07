import Foundation

struct MediastackProvider: NewsProvider {
    private let config = AppConfig.shared

    func fetch(
        category: NewsCategory,
        pageToken: String?,
        pageSize: Int,
        forceRefresh: Bool
    ) async throws -> NewsProviderBatch {
        let plans = queryPlans(for: category, pageSize: pageSize, pageToken: pageToken)

        let batches = try await withThrowingTaskGroup(of: [Article].self) { group in
            for plan in plans {
                group.addTask {
                    try await fetchPlan(plan, forceRefresh: forceRefresh, defaultCategory: category)
                }
            }

            var merged: [[Article]] = []
            for try await articles in group {
                merged.append(articles)
            }
            return merged
        }
        .flatMap { $0 }

        let deduped = Dictionary(grouping: batches, by: \.id)
            .compactMap { $0.value.max(by: { ($0.publishedAt ?? .distantPast) < ($1.publishedAt ?? .distantPast) }) }
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }

        return NewsProviderBatch(articles: Array(deduped.prefix(pageSize * 2)), nextPageToken: nil)
    }

    func search(
        query: String,
        category: NewsCategory,
        pageSize: Int,
        forceRefresh: Bool
    ) async throws -> [Article] {
        let plan = MediastackQueryPlan(
            categories: category == .sports ? "sports" : category == .business ? "business" : category == .technology ? "technology" : "general",
            keywords: query,
            countries: nil,
            limit: max(10, pageSize),
            offset: nil
        )
        return try await fetchPlan(plan, forceRefresh: forceRefresh, defaultCategory: category)
    }

    private func fetchPlan(
        _ plan: MediastackQueryPlan,
        forceRefresh: Bool,
        defaultCategory: NewsCategory
    ) async throws -> [Article] {
        guard let apiURL = URL(string: "https://api.mediastack.com/v1/news") else { return [] }

        var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false)
        let today = Self.todayDateString()

        var queryItems: [URLQueryItem] = [
            .init(name: "access_key", value: config.mediastackAPIKey),
            .init(name: "languages", value: "en"),
            .init(name: "sort", value: "published_desc"),
            .init(name: "limit", value: "\(plan.limit)"),
            .init(name: "date", value: today)
        ]

        if let categories = plan.categories {
            queryItems.append(.init(name: "categories", value: categories))
        }
        if let keywords = plan.keywords {
            queryItems.append(.init(name: "keywords", value: keywords))
        }
        if let countries = plan.countries {
            queryItems.append(.init(name: "countries", value: countries))
        }
        if let offset = plan.offset {
            queryItems.append(.init(name: "offset", value: "\(offset)"))
        }

        components?.queryItems = queryItems
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.cachePolicy = forceRefresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        request.timeoutInterval = 12

        let (data, http) = try await HTTPClient.data(for: request)
        let okData = try HTTPClient.requireSuccess(data, http)

        let payload = try JSONDecoder.supabase.decode(MediastackResponse.self, from: okData)
        return payload.data.compactMap { $0.toArticle(defaultCategory: defaultCategory) }
    }

    private func queryPlans(for category: NewsCategory, pageSize: Int, pageToken: String?) -> [MediastackQueryPlan] {
        let offset = pageToken.flatMap(Int.init)
        let baseLimit = max(8, pageSize)

        switch category {
        case .world:
            return [
                .init(categories: "general", keywords: "world,global,international,pakistan,middle east,iran,israel", countries: nil, limit: baseLimit + 2, offset: offset),
                .init(categories: "general", keywords: "geopolitics,diplomacy,border,global crisis", countries: nil, limit: baseLimit, offset: nil)
            ]
        case .politics:
            return [
                .init(categories: "general", keywords: "politics,election,parliament,government,polls,assembly", countries: "in,us,gb", limit: baseLimit + 2, offset: offset),
                .init(categories: "general", keywords: "cabinet,minister,senate,congress,vote", countries: nil, limit: baseLimit, offset: nil)
            ]
        case .conflict:
            return [
                .init(categories: "general", keywords: "war,conflict,attack,strike,missile,ceasefire,troops", countries: nil, limit: baseLimit + 2, offset: offset),
                .init(categories: "general", keywords: "gaza,ukraine,iran,israel,border strike,military", countries: nil, limit: baseLimit, offset: nil)
            ]
        case .technology:
            return [
                .init(categories: "technology", keywords: "AI,nvidia,openai,google,apple,chip,software", countries: nil, limit: baseLimit + 2, offset: offset),
                .init(categories: "technology", keywords: "startup,developer,app,model", countries: nil, limit: baseLimit, offset: nil)
            ]
        case .business:
            return [
                .init(categories: "business", keywords: "market,startup,stock,earnings,deal,funding,company", countries: nil, limit: baseLimit + 2, offset: offset),
                .init(categories: "business", keywords: "economy,ipo,valuation,investor", countries: nil, limit: baseLimit, offset: nil)
            ]
        case .sports:
            return [
                .init(categories: "sports", keywords: "ipl,cricket,football,match,tournament,league", countries: "in,gb,au", limit: baseLimit + 2, offset: offset),
                .init(categories: "sports", keywords: "tennis,f1,nba", countries: nil, limit: baseLimit, offset: nil)
            ]
        }
    }

    private static func todayDateString(now: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now)
    }
}

private struct MediastackQueryPlan {
    let categories: String?
    let keywords: String?
    let countries: String?
    let limit: Int
    let offset: Int?
}

private struct MediastackResponse: Decodable {
    let data: [MediastackArticleDTO]
}

private struct MediastackArticleDTO: Decodable {
    let author: String?
    let title: String?
    let description: String?
    let url: String?
    let source: String?
    let image: String?
    let category: String?
    let language: String?
    let country: String?
    let publishedAt: String?

    enum CodingKeys: String, CodingKey {
        case author
        case title
        case description
        case url
        case source
        case image
        case category
        case language
        case country
        case publishedAt = "published_at"
    }

    func toArticle(defaultCategory: NewsCategory) -> Article? {
        guard let title, !title.isEmpty else { return nil }

        let cleanTitle = HeadlineFormatter.simplify(title)
        let sourceName = source ?? "Mediastack"
        let rawBody = [description, author].compactMap { $0 }.joined(separator: " ")
        let cards = SummaryBuilder.makeCards(from: cleanTitle, source: sourceName, text: rawBody)
        let plainSummary = cards.joined(separator: " ")
        let categoryValue = category.flatMap(NewsCategory.init(providerValue:)) ?? defaultCategory
        let publishedDate = publishedAt.flatMap(DateParser.newsDate(from:))
        let keywords = [
            cleanTitle,
            description ?? "",
            category ?? "",
            country ?? "",
            language ?? ""
        ]
            .joined(separator: " ")
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 3 }
            .prefix(10)

        return Article(
            id: url ?? [sourceName, cleanTitle].joined(separator: "::"),
            headline: cleanTitle,
            source: sourceName,
            imageURL: image.flatMap(URL.init(string:)),
            originalURL: url.flatMap(URL.init(string:)),
            publishedAt: publishedDate,
            summaryCards: cards,
            plainSummary: plainSummary,
            rawDescription: description ?? "",
            rawContent: rawBody,
            category: categoryValue.displayName,
            categories: [categoryValue],
            keywords: Array(keywords)
        )
    }
}
