import Foundation

struct NewsAPIProvider: NewsProvider {
    private let config = AppConfig.shared

    func fetch(
        category: NewsCategory,
        pageToken: String?,
        pageSize: Int,
        forceRefresh: Bool
    ) async throws -> NewsProviderBatch {
        let plan = requestPlan(for: category, pageSize: pageSize, pageToken: pageToken)
        let articles = try await fetchPlan(plan, forceRefresh: forceRefresh, defaultCategory: category)
        let nextPage = articles.count >= pageSize ? "\(plan.page + 1)" : nil
        return NewsProviderBatch(articles: articles, nextPageToken: nextPage)
    }

    func search(
        query: String,
        category: NewsCategory,
        pageSize: Int,
        forceRefresh: Bool
    ) async throws -> [Article] {
        let plan = NewsAPIRequestPlan.everything(
            query: query,
            fromDate: Self.todayDateString(),
            pageSize: max(10, pageSize),
            page: 1
        )
        return try await fetchPlan(plan, forceRefresh: forceRefresh, defaultCategory: category)
    }

    private func fetchPlan(
        _ plan: NewsAPIRequestPlan,
        forceRefresh: Bool,
        defaultCategory: NewsCategory
    ) async throws -> [Article] {
        guard let apiURL = URL(string: plan.endpoint) else { return [] }

        var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = [
            .init(name: "apiKey", value: config.newsAPIOrgKey),
            .init(name: "language", value: "en"),
            .init(name: "pageSize", value: "\(plan.pageSize)"),
            .init(name: "page", value: "\(plan.page)")
        ]

        if let category = plan.category {
            queryItems.append(.init(name: "category", value: category))
        }
        if let country = plan.country {
            queryItems.append(.init(name: "country", value: country))
        }
        if let query = plan.query {
            queryItems.append(.init(name: "q", value: query))
        }
        if let fromDate = plan.fromDate {
            queryItems.append(.init(name: "from", value: fromDate))
        }
        if let sortBy = plan.sortBy {
            queryItems.append(.init(name: "sortBy", value: sortBy))
        }

        components?.queryItems = queryItems
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.cachePolicy = forceRefresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        request.timeoutInterval = 12

        let (data, http) = try await HTTPClient.data(for: request)
        let okData = try HTTPClient.requireSuccess(data, http)

        let payload = try JSONDecoder.supabase.decode(NewsAPIResponse.self, from: okData)
        return payload.articles.compactMap { $0.toArticle(defaultCategory: defaultCategory) }
    }

    private func requestPlan(for category: NewsCategory, pageSize: Int, pageToken: String?) -> NewsAPIRequestPlan {
        let page = max(1, Int(pageToken ?? "1") ?? 1)
        let today = Self.todayDateString()

        switch category {
        case .business:
            return .topHeadlines(category: "business", country: "us", pageSize: pageSize, page: page, query: "startup OR earnings OR market OR funding")
        case .technology:
            return .topHeadlines(category: "technology", country: "us", pageSize: pageSize, page: page, query: "AI OR Nvidia OR OpenAI OR chips")
        case .sports:
            return .topHeadlines(category: "sports", country: "in", pageSize: pageSize, page: page, query: "IPL OR cricket OR football")
        case .world:
            return .everything(query: "Pakistan OR Middle East OR Iran OR Israel OR global OR international", fromDate: today, pageSize: pageSize, page: page)
        case .politics:
            return .everything(query: "election OR government OR parliament OR senate OR congress OR polls", fromDate: today, pageSize: pageSize, page: page)
        case .conflict:
            return .everything(query: "war OR conflict OR strike OR attack OR missile OR ceasefire OR troops", fromDate: today, pageSize: pageSize, page: page)
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

private struct NewsAPIRequestPlan {
    let endpoint: String
    let category: String?
    let country: String?
    let query: String?
    let fromDate: String?
    let sortBy: String?
    let pageSize: Int
    let page: Int

    static func topHeadlines(category: String, country: String, pageSize: Int, page: Int, query: String?) -> NewsAPIRequestPlan {
        NewsAPIRequestPlan(
            endpoint: "https://newsapi.org/v2/top-headlines",
            category: category,
            country: country,
            query: query,
            fromDate: nil,
            sortBy: nil,
            pageSize: pageSize,
            page: page
        )
    }

    static func everything(query: String, fromDate: String, pageSize: Int, page: Int) -> NewsAPIRequestPlan {
        NewsAPIRequestPlan(
            endpoint: "https://newsapi.org/v2/everything",
            category: nil,
            country: nil,
            query: query,
            fromDate: fromDate,
            sortBy: "publishedAt",
            pageSize: pageSize,
            page: page
        )
    }
}

private struct NewsAPIResponse: Decodable {
    let articles: [NewsAPIArticleDTO]
}

private struct NewsAPIArticleDTO: Decodable {
    let source: NewsAPISourceDTO
    let title: String?
    let description: String?
    let url: String?
    let urlToImage: String?
    let publishedAt: String?
    let content: String?

    func toArticle(defaultCategory: NewsCategory) -> Article? {
        guard let title, !title.isEmpty else { return nil }

        let cleanTitle = HeadlineFormatter.simplify(title)
        let sourceName = source.name ?? source.id ?? "NewsAPI"
        let rawBody = [description, content].compactMap { $0 }.joined(separator: " ")
        let cards = SummaryBuilder.makeCards(from: cleanTitle, source: sourceName, text: rawBody)
        let plainSummary = cards.joined(separator: " ")
        let publishedDate = publishedAt.flatMap(DateParser.newsDate(from:))
        let keywords = [
            cleanTitle,
            description ?? "",
            content ?? "",
            defaultCategory.displayName
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
            imageURL: urlToImage.flatMap(URL.init(string:)),
            originalURL: url.flatMap(URL.init(string:)),
            publishedAt: publishedDate,
            summaryCards: cards,
            plainSummary: plainSummary,
            rawDescription: description ?? "",
            rawContent: content ?? rawBody,
            category: defaultCategory.displayName,
            categories: [defaultCategory],
            keywords: Array(keywords)
        )
    }
}

private struct NewsAPISourceDTO: Decodable {
    let id: String?
    let name: String?
}
