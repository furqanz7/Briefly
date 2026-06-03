import Foundation

struct GNewsProvider: NewsProvider {
    private let config = AppConfig.shared

    func fetch(category: NewsCategory, pageToken: String?, pageSize: Int, forceRefresh: Bool) async throws -> NewsProviderBatch {
        let page = max(1, Int(pageToken ?? "1") ?? 1)
        let plans = queryPlans(for: category, pageSize: pageSize, page: page)

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

        let nextPage = deduped.count >= pageSize ? "\(page + 1)" : nil
        return NewsProviderBatch(articles: Array(deduped.prefix(pageSize * 2)), nextPageToken: nextPage)
    }

    func search(
        query: String,
        category: NewsCategory,
        pageSize: Int,
        forceRefresh: Bool
    ) async throws -> [Article] {
        let plan = GNewsPlan.search(query: query, max: max(10, pageSize), page: 1)
        return try await fetchPlan(plan, forceRefresh: forceRefresh, defaultCategory: category)
    }

    private func fetchPlan(_ plan: GNewsPlan, forceRefresh: Bool, defaultCategory: NewsCategory) async throws -> [Article] {
        guard let apiURL = URL(string: plan.endpoint) else { return [] }
        var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = [
            .init(name: "apikey", value: config.gnewsAPIKey),
            .init(name: "lang", value: "en"),
            .init(name: "max", value: "\(plan.max)")
        ]
        if let category = plan.category {
            queryItems.append(.init(name: "category", value: category))
        }
        if let country = plan.country {
            queryItems.append(.init(name: "country", value: country))
        }
        if let q = plan.query {
            queryItems.append(.init(name: "q", value: q))
        }
        queryItems.append(.init(name: "page", value: "\(plan.page)"))
        components?.queryItems = queryItems
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.cachePolicy = forceRefresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return [] }
        let payload = try JSONDecoder.supabase.decode(GNewsResponse.self, from: data)
        return payload.articles.compactMap { $0.toArticle(defaultCategory: defaultCategory) }
    }

    private func queryPlans(for category: NewsCategory, pageSize: Int, page: Int) -> [GNewsPlan] {
        let maxCount = max(6, pageSize / 2)
        switch category {
        case .world:
            return [.topHeadlines(category: "world", country: nil, max: maxCount, page: page, query: "Pakistan OR Middle East OR Iran OR Israel")]
        case .politics:
            return [.search(query: "election OR government OR parliament OR polls", max: maxCount, page: page)]
        case .conflict:
            return [.search(query: "war OR conflict OR attack OR strike OR ceasefire", max: maxCount, page: page)]
        case .technology:
            return [.topHeadlines(category: "technology", country: "us", max: maxCount, page: page, query: "AI OR Nvidia OR OpenAI")]
        case .business:
            return [.topHeadlines(category: "business", country: "us", max: maxCount, page: page, query: "market OR startup OR earnings")]
        case .sports:
            return [.topHeadlines(category: "sports", country: "in", max: maxCount, page: page, query: "IPL OR cricket OR football")]
        }
    }
}

private struct GNewsPlan {
    let endpoint: String
    let category: String?
    let country: String?
    let query: String?
    let max: Int
    let page: Int

    static func topHeadlines(category: String, country: String?, max: Int, page: Int, query: String?) -> GNewsPlan {
        GNewsPlan(endpoint: "https://gnews.io/api/v4/top-headlines", category: category, country: country, query: query, max: max, page: page)
    }

    static func search(query: String, max: Int, page: Int) -> GNewsPlan {
        GNewsPlan(endpoint: "https://gnews.io/api/v4/search", category: nil, country: nil, query: query, max: max, page: page)
    }
}

private struct GNewsResponse: Decodable {
    let articles: [GNewsArticleDTO]
}

private struct GNewsArticleDTO: Decodable {
    let title: String?
    let description: String?
    let content: String?
    let url: String?
    let image: String?
    let publishedAt: String?
    let source: GNewsSourceDTO

    func toArticle(defaultCategory: NewsCategory) -> Article? {
        guard let title, !title.isEmpty else { return nil }
        let cleanTitle = HeadlineFormatter.simplify(title)
        let sourceName = source.name ?? "GNews"
        let body = [description, content].compactMap { $0 }.joined(separator: " ")
        let cards = SummaryBuilder.makeCards(from: cleanTitle, source: sourceName, text: body)
        return Article(
            id: url ?? [sourceName, cleanTitle].joined(separator: "::"),
            headline: cleanTitle,
            source: sourceName,
            imageURL: image.flatMap(URL.init(string:)),
            originalURL: url.flatMap(URL.init(string:)),
            publishedAt: publishedAt.flatMap(DateParser.newsDate(from:)),
            summaryCards: cards,
            plainSummary: cards.joined(separator: " "),
            rawDescription: description ?? "",
            rawContent: content ?? body,
            category: defaultCategory.displayName,
            categories: [defaultCategory],
            keywords: []
        )
    }
}

private struct GNewsSourceDTO: Decodable {
    let name: String?
    let url: String?
}
