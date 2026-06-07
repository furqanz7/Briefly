import Foundation

struct GuardianProvider: NewsProvider {
    private let config = AppConfig.shared

    func fetch(category: NewsCategory, pageToken: String?, pageSize: Int, forceRefresh: Bool) async throws -> NewsProviderBatch {
        let page = max(1, Int(pageToken ?? "1") ?? 1)
        guard let url = requestURL(for: category, pageSize: pageSize, page: page) else {
            return NewsProviderBatch(articles: [], nextPageToken: nil)
        }

        var request = URLRequest(url: url)
        request.cachePolicy = forceRefresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        request.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return NewsProviderBatch(articles: [], nextPageToken: nil)
        }

        let payload = try JSONDecoder.supabase.decode(GuardianEnvelope.self, from: data)
        let articles = payload.response.results.compactMap { $0.toArticle(defaultCategory: category) }
        let nextPage = payload.response.currentPage < payload.response.pages ? "\(payload.response.currentPage + 1)" : nil
        return NewsProviderBatch(articles: articles, nextPageToken: nextPage)
    }

    private func requestURL(for category: NewsCategory, pageSize: Int, page: Int) -> URL? {
        guard let apiURL = URL(string: "https://content.guardianapis.com/search") else { return nil }
        var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false)
        let query = queryHint(for: category)
        components?.queryItems = [
            .init(name: "api-key", value: config.guardianAPIKey),
            .init(name: "page-size", value: "\(pageSize)"),
            .init(name: "page", value: "\(page)"),
            .init(name: "order-by", value: "newest"),
            .init(name: "from-date", value: todayDateString()),
            .init(name: "show-fields", value: "headline,trailText,thumbnail,bodyText"),
            .init(name: "q", value: query)
        ]
        return components?.url
    }

    private func queryHint(for category: NewsCategory) -> String {
        switch category {
        case .world: return "Pakistan OR Middle East OR Iran OR Israel OR world"
        case .politics: return "election OR government OR parliament OR politics"
        case .conflict: return "war OR conflict OR strike OR attack OR ceasefire"
        case .technology: return "AI OR Nvidia OR OpenAI OR technology"
        case .business: return "market OR startup OR company OR business"
        case .sports: return "IPL OR cricket OR football OR sports"
        }
    }

    private func todayDateString(now: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now)
    }
}

private struct GuardianEnvelope: Decodable {
    let response: GuardianResponse
}

private struct GuardianResponse: Decodable {
    let currentPage: Int
    let pages: Int
    let results: [GuardianArticleDTO]

    enum CodingKeys: String, CodingKey {
        case currentPage = "currentPage"
        case pages
        case results
    }
}

private struct GuardianArticleDTO: Decodable {
    let id: String
    let webTitle: String?
    let webUrl: String?
    let webPublicationDate: String?
    let fields: GuardianFields?
    let sectionName: String?

    func toArticle(defaultCategory: NewsCategory) -> Article? {
        let title = fields?.headline ?? webTitle
        guard let title, !title.isEmpty else { return nil }
        let cleanTitle = HeadlineFormatter.simplify(title)
        let description = fields?.trailText ?? ""
        let body = fields?.bodyText ?? description
        let cards = SummaryBuilder.makeCards(from: cleanTitle, source: "The Guardian", text: body)
        return Article(
            id: id,
            headline: cleanTitle,
            source: "The Guardian",
            imageURL: fields?.thumbnail.flatMap(URL.init(string:)),
            originalURL: webUrl.flatMap(URL.init(string:)),
            publishedAt: webPublicationDate.flatMap(DateParser.newsDate(from:)),
            summaryCards: cards,
            plainSummary: cards.joined(separator: " "),
            rawDescription: description,
            rawContent: body,
            category: NewsCategory(providerValue: sectionName?.lowercased() ?? "")?.displayName ?? defaultCategory.displayName,
            categories: [NewsCategory(providerValue: sectionName?.lowercased() ?? "") ?? defaultCategory],
            keywords: []
        )
    }
}

private struct GuardianFields: Decodable {
    let headline: String?
    let trailText: String?
    let thumbnail: String?
    let bodyText: String?
}
