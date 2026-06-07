import Foundation

struct NewsDataTrendingProvider: NewsProvider {
    private let config = AppConfig.shared

    func fetch(
        category: NewsCategory,
        pageToken: String?,
        pageSize: Int,
        forceRefresh: Bool
    ) async throws -> NewsProviderBatch {
        let plans = trendingPlans(for: category, pageSize: pageSize)

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

        return NewsProviderBatch(articles: Array(deduped.prefix(pageSize)), nextPageToken: pageToken)
    }

    private func fetchPlan(
        _ plan: TrendingPlan,
        forceRefresh: Bool,
        defaultCategory: NewsCategory
    ) async throws -> [Article] {
        guard let apiURL = URL(string: "https://newsdata.io/api/1/latest") else { return [] }

        var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = [
            .init(name: "apikey", value: config.newsDataAPIKey),
            .init(name: "category", value: "top"),
            .init(name: "language", value: "en"),
            .init(name: "prioritydomain", value: "top"),
            .init(name: "removeduplicate", value: "1"),
            .init(name: "timeframe", value: "12"),
            .init(name: "size", value: "\(plan.size)")
        ]

        if let q = plan.query {
            queryItems.append(.init(name: "q", value: q))
        }
        if let qInTitle = plan.queryInTitle {
            queryItems.append(.init(name: "qInTitle", value: qInTitle))
        }
        if let country = plan.country {
            queryItems.append(.init(name: "country", value: country))
        }

        components?.queryItems = queryItems
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.cachePolicy = forceRefresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        request.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }

        let payload = try JSONDecoder.supabase.decode(NewsResponse.self, from: data)
        return payload.results.compactMap { $0.toArticle(defaultCategory: defaultCategory) }
    }

    private func trendingPlans(for category: NewsCategory, pageSize: Int) -> [TrendingPlan] {
        let size = max(5, pageSize / 2)

        switch category {
        case .sports:
            return [
                TrendingPlan(queryInTitle: "IPL", country: "in", size: size),
                TrendingPlan(query: "IPL OR cricket OR football OR latest match OR live score", country: "in", size: size)
            ]
        case .politics:
            return [
                TrendingPlan(query: "election OR polls OR parliament OR assembly OR EC", country: "in", size: size),
                TrendingPlan(queryInTitle: "election", country: nil, size: size)
            ]
        case .world:
            return [
                TrendingPlan(query: "Pakistan OR Middle East OR Iran OR Israel OR Ukraine OR Trump", country: nil, size: size),
                TrendingPlan(queryInTitle: "Middle East", country: nil, size: size)
            ]
        case .conflict:
            return [
                TrendingPlan(query: "war OR strike OR attack OR conflict OR ceasefire OR missile", country: nil, size: size),
                TrendingPlan(queryInTitle: "attack", country: nil, size: size)
            ]
        case .technology:
            return [
                TrendingPlan(query: "Nvidia OR OpenAI OR AI OR chips OR Google OR Apple", country: nil, size: size),
                TrendingPlan(queryInTitle: "Nvidia", country: nil, size: size)
            ]
        case .business:
            return [
                TrendingPlan(query: "stock market OR startup OR funding OR earnings OR deal", country: nil, size: size),
                TrendingPlan(queryInTitle: "market", country: nil, size: size)
            ]
        }
    }
}

private struct TrendingPlan {
    let query: String?
    let queryInTitle: String?
    let country: String?
    let size: Int

    init(query: String, country: String?, size: Int) {
        self.query = query
        self.queryInTitle = nil
        self.country = country
        self.size = size
    }

    init(queryInTitle: String, country: String?, size: Int) {
        self.query = nil
        self.queryInTitle = queryInTitle
        self.country = country
        self.size = size
    }
}
