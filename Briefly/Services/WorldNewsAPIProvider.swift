import Foundation

struct WorldNewsAPIProvider: NewsProvider {
    private let config = AppConfig.shared

    func fetch(category: NewsCategory, pageToken: String?, pageSize: Int, forceRefresh: Bool) async throws -> NewsProviderBatch {
        guard let apiURL = URL(string: "https://api.worldnewsapi.com/search-news") else {
            return NewsProviderBatch(articles: [], nextPageToken: nil)
        }

        var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false)
        let offset = max(0, Int(pageToken ?? "0") ?? 0)
        components?.queryItems = [
            .init(name: "api-key", value: config.worldNewsAPIKey),
            .init(name: "language", value: "en"),
            .init(name: "offset", value: "\(offset)"),
            .init(name: "number", value: "\(pageSize)"),
            .init(name: "earliest-publish-date", value: isoStartOfDay()),
            .init(name: "text", value: query(for: category))
        ]

        guard let url = components?.url else {
            return NewsProviderBatch(articles: [], nextPageToken: nil)
        }

        var request = URLRequest(url: url)
        request.cachePolicy = forceRefresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return NewsProviderBatch(articles: [], nextPageToken: nil)
        }

        let payload = try JSONDecoder.supabase.decode(WorldNewsResponse.self, from: data)
        let articles = payload.news.compactMap { $0.toArticle(defaultCategory: category) }
        let nextOffset = articles.count >= pageSize ? "\(offset + pageSize)" : nil
        return NewsProviderBatch(articles: articles, nextPageToken: nextOffset)
    }

    private func query(for category: NewsCategory) -> String {
        switch category {
        case .world: return "Pakistan OR Middle East OR Iran OR Israel OR world"
        case .politics: return "election OR government OR parliament OR polls"
        case .conflict: return "war OR conflict OR attack OR strike OR ceasefire"
        case .technology: return "AI OR Nvidia OR OpenAI OR technology"
        case .business: return "market OR startup OR company OR earnings"
        case .sports: return "IPL OR cricket OR football OR sports"
        }
    }

    private func isoStartOfDay(now: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: calendar.startOfDay(for: now))
    }
}

private struct WorldNewsResponse: Decodable {
    let news: [WorldNewsArticleDTO]
}

private struct WorldNewsArticleDTO: Decodable {
    let id: Int?
    let title: String?
    let text: String?
    let summary: String?
    let url: String?
    let image: String?
    let publishDate: String?
    let authors: [String]?
    let sourceCountry: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case text
        case summary
        case url
        case image
        case publishDate = "publish_date"
        case authors
        case sourceCountry = "source_country"
    }

    func toArticle(defaultCategory: NewsCategory) -> Article? {
        guard let title, !title.isEmpty else { return nil }
        let cleanTitle = HeadlineFormatter.simplify(title)
        let body = [summary, text].compactMap { $0 }.joined(separator: " ")
        let cards = SummaryBuilder.makeCards(from: cleanTitle, source: "World News API", text: body)
        return Article(
            id: id.map(String.init) ?? url ?? cleanTitle,
            headline: cleanTitle,
            source: "World News API",
            imageURL: image.flatMap(URL.init(string:)),
            originalURL: url.flatMap(URL.init(string:)),
            publishedAt: publishDate.flatMap(DateParser.newsDate(from:)),
            summaryCards: cards,
            plainSummary: cards.joined(separator: " "),
            rawDescription: summary ?? "",
            rawContent: text ?? body,
            category: defaultCategory.displayName,
            categories: [defaultCategory],
            keywords: (authors ?? []) + [sourceCountry ?? ""]
        )
    }
}
