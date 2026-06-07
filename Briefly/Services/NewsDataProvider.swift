import Foundation

struct NewsDataProvider: NewsProvider {
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
        let plan = QueryPlan(
            categoryValue: category.providerCategory,
            query: query,
            country: nil,
            size: max(10, pageSize),
            pageToken: nil
        )
        return try await fetchPlan(plan, forceRefresh: forceRefresh, defaultCategory: category)
    }

    private func fetchPlan(
        _ plan: QueryPlan,
        forceRefresh: Bool,
        defaultCategory: NewsCategory
    ) async throws -> [Article] {
        guard let apiURL = URL(string: "https://newsdata.io/api/1/latest") else { return [] }

        var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = [
            .init(name: "apikey", value: config.newsDataAPIKey),
            .init(name: "language", value: "en"),
            .init(name: "prioritydomain", value: "top"),
            .init(name: "removeduplicate", value: "1"),
            .init(name: "timeframe", value: "24"),
            .init(name: "size", value: "\(plan.size)")
        ]

        if let categoryValue = plan.categoryValue {
            queryItems.append(.init(name: "category", value: categoryValue))
        }
        if let query = plan.query {
            queryItems.append(.init(name: "q", value: query))
        }
        if let queryInTitle = plan.queryInTitle {
            queryItems.append(.init(name: "qInTitle", value: queryInTitle))
        }
        if let country = plan.country {
            queryItems.append(.init(name: "country", value: country))
        }
        if let pageToken = plan.pageToken {
            queryItems.append(.init(name: "page", value: pageToken))
        }

        components?.queryItems = queryItems
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.cachePolicy = forceRefresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        request.timeoutInterval = 12

        let (data, http) = try await HTTPClient.data(for: request)
        let okData = try HTTPClient.requireSuccess(data, http)

        let payload = try JSONDecoder.supabase.decode(NewsResponse.self, from: okData)
        return payload.results.compactMap { $0.toArticle(defaultCategory: defaultCategory) }
    }

    private func queryPlans(for category: NewsCategory, pageSize: Int, pageToken: String?) -> [QueryPlan] {
        let baseSize = max(8, pageSize)

        switch category {
        case .sports:
            return [
                QueryPlan(categoryValue: "sports", query: "IPL OR cricket OR football OR match OR league OR tournament", country: "in", size: baseSize + 2, pageToken: pageToken),
                QueryPlan(categoryValue: "sports", query: "football OR NBA OR NFL OR tennis OR F1", country: nil, size: baseSize, pageToken: nil),
                QueryPlan(categoryValue: "top", query: "IPL OR cricket OR sports OR football", country: nil, size: baseSize, pageToken: nil)
            ]
        case .politics:
            return [
                QueryPlan(categoryValue: "politics", query: "election OR parliament OR government OR minister OR vote", country: "in", size: baseSize + 2, pageToken: pageToken),
                QueryPlan(categoryValue: "politics", query: "election OR senate OR congress OR cabinet OR polls", country: nil, size: baseSize, pageToken: nil),
                QueryPlan(categoryValue: "top", query: "election OR politics OR government", country: nil, size: baseSize, pageToken: nil)
            ]
        case .world:
            return [
                QueryPlan(categoryValue: "world", query: "Pakistan OR Middle East OR Iran OR Israel OR China OR Russia OR global", country: nil, size: baseSize + 2, pageToken: pageToken),
                QueryPlan(categoryValue: "top", query: "world OR global OR international OR pakistan OR middle east", country: nil, size: baseSize, pageToken: nil)
            ]
        case .conflict:
            return [
                QueryPlan(categoryValue: "top", query: "war OR conflict OR strike OR attack OR missile OR troops OR ceasefire", country: nil, size: baseSize + 2, pageToken: pageToken),
                QueryPlan(categoryValue: "world", query: "Iran OR Israel OR Gaza OR Ukraine OR military OR border strike", country: nil, size: baseSize, pageToken: nil)
            ]
        case .technology:
            return [
                QueryPlan(categoryValue: "technology", query: "AI OR Nvidia OR OpenAI OR chips OR software OR Apple OR Google", country: nil, size: baseSize + 2, pageToken: pageToken),
                QueryPlan(categoryValue: "top", query: "AI OR Nvidia OR tech OR software OR startup", country: nil, size: baseSize, pageToken: nil)
            ]
        case .business:
            return [
                QueryPlan(categoryValue: "business", query: "startup OR stock OR market OR funding OR company OR earnings", country: nil, size: baseSize + 2, pageToken: pageToken),
                QueryPlan(categoryValue: "business", query: "stock market OR earnings OR startup OR deal", country: "in", size: baseSize, pageToken: nil),
                QueryPlan(categoryValue: "top", query: "business OR market OR startup OR company", country: nil, size: baseSize, pageToken: nil)
            ]
        }
    }
}

private struct QueryPlan {
    let categoryValue: String?
    let query: String?
    let queryInTitle: String? = nil
    let country: String?
    let size: Int
    let pageToken: String?
}
