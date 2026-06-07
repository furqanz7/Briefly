import Foundation

struct NewYorkTimesProvider: NewsProvider {
    private let config = AppConfig.shared

    func fetch(category: NewsCategory, pageToken: String?, pageSize: Int, forceRefresh: Bool) async throws -> NewsProviderBatch {
        let page = max(0, Int(pageToken ?? "0") ?? 0)
        guard let url = requestURL(for: category, page: page) else {
            return NewsProviderBatch(articles: [], nextPageToken: nil)
        }

        var request = URLRequest(url: url)
        request.cachePolicy = forceRefresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        request.timeoutInterval = 12

        let (data, http) = try await HTTPClient.data(for: request)
        let okData = try HTTPClient.requireSuccess(data, http)

        let payload = try JSONDecoder.supabase.decode(NewYorkTimesResponse.self, from: okData)
        let articles = payload.response.docs.compactMap { $0.toArticle(defaultCategory: category) }
        let nextPage = articles.count >= min(pageSize, 10) ? "\(page + 1)" : nil
        return NewsProviderBatch(articles: Array(articles.prefix(pageSize)), nextPageToken: nextPage)
    }

    private func requestURL(for category: NewsCategory, page: Int) -> URL? {
        guard let apiURL = URL(string: "https://api.nytimes.com/svc/search/v2/articlesearch.json") else { return nil }
        var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "api-key", value: config.newYorkTimesAPIKey),
            .init(name: "page", value: "\(page)"),
            .init(name: "sort", value: "newest"),
            .init(name: "begin_date", value: compactTodayDate()),
            .init(name: "q", value: query(for: category))
        ]
        return components?.url
    }

    private func query(for category: NewsCategory) -> String {
        switch category {
        case .world: return "Pakistan OR Middle East OR Iran OR Israel OR world"
        case .politics: return "election OR government OR politics OR parliament"
        case .conflict: return "war OR conflict OR attack OR strike OR ceasefire"
        case .technology: return "AI OR Nvidia OR OpenAI OR technology"
        case .business: return "market OR startup OR company OR earnings"
        case .sports: return "IPL OR cricket OR football OR sports"
        }
    }

    private func compactTodayDate(now: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: now)
    }
}

private struct NewYorkTimesResponse: Decodable {
    let response: NewYorkTimesDocsEnvelope
}

private struct NewYorkTimesDocsEnvelope: Decodable {
    let docs: [NewYorkTimesArticleDTO]

    enum CodingKeys: String, CodingKey {
        case docs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        docs = try container.decodeIfPresent([NewYorkTimesArticleDTO].self, forKey: .docs) ?? []
    }
}

private struct NewYorkTimesArticleDTO: Decodable {
    let webURL: String?
    let snippet: String?
    let leadParagraph: String?
    let abstract: String?
    let pubDate: String?
    let headline: NewYorkTimesHeadlineDTO?
    let multimedia: [NewYorkTimesMediaDTO]
    let source: String?

    enum CodingKeys: String, CodingKey {
        case webURL = "web_url"
        case snippet
        case leadParagraph = "lead_paragraph"
        case abstract
        case pubDate = "pub_date"
        case headline
        case multimedia
        case source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        webURL = try container.decodeIfPresent(String.self, forKey: .webURL)
        snippet = try container.decodeIfPresent(String.self, forKey: .snippet)
        leadParagraph = try container.decodeIfPresent(String.self, forKey: .leadParagraph)
        abstract = try container.decodeIfPresent(String.self, forKey: .abstract)
        pubDate = try container.decodeIfPresent(String.self, forKey: .pubDate)
        headline = try container.decodeIfPresent(NewYorkTimesHeadlineDTO.self, forKey: .headline)
        source = try container.decodeIfPresent(String.self, forKey: .source)

        // NYT returns `multimedia` as either an array, a dictionary, or null depending on fields and API behavior.
        if let items = try container.decodeIfPresent([NewYorkTimesMediaDTO].self, forKey: .multimedia) {
            multimedia = items
        } else if let single = try container.decodeIfPresent(NewYorkTimesMediaDTO.self, forKey: .multimedia) {
            multimedia = [single]
        } else {
            multimedia = []
        }
    }

    func toArticle(defaultCategory: NewsCategory) -> Article? {
        guard let title = headline?.main, !title.isEmpty else { return nil }
        let cleanTitle = HeadlineFormatter.simplify(title)
        let body = [abstract, snippet, leadParagraph].compactMap { $0 }.joined(separator: " ")
        let cards = SummaryBuilder.makeCards(from: cleanTitle, source: source ?? "The New York Times", text: body)
        let imageURL = multimedia.first(where: { ($0.url ?? "").contains("images") })?.fullURL

        return Article(
            id: webURL ?? cleanTitle,
            headline: cleanTitle,
            source: source ?? "The New York Times",
            imageURL: imageURL,
            originalURL: webURL.flatMap(URL.init(string:)),
            publishedAt: pubDate.flatMap(DateParser.newsDate(from:)),
            summaryCards: cards,
            plainSummary: cards.joined(separator: " "),
            rawDescription: abstract ?? snippet ?? "",
            rawContent: leadParagraph ?? body,
            category: defaultCategory.displayName,
            categories: [defaultCategory],
            keywords: []
        )
    }
}

private struct NewYorkTimesHeadlineDTO: Decodable {
    let main: String?
}

private struct NewYorkTimesMediaDTO: Decodable {
    let url: String?

    var fullURL: URL? {
        guard let url else { return nil }
        if url.hasPrefix("http") {
            return URL(string: url)
        }
        return URL(string: "https://www.nytimes.com/\(url)")
    }
}
