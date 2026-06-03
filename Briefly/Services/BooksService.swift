import Foundation

enum BooksServiceError: LocalizedError {
    case invalidResponse
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Books returned an invalid response."
        case .unavailable:
            return "Books are unavailable right now."
        }
    }
}

protocol BooksProviding {
    func fetchBooks(query: String, genre: String) async throws -> [BookItem]
}

struct BooksDataResponse: Decodable {
    let books: [BookItem]
}

struct BooksService: BooksProviding {
    private let config = AppConfig.shared

    func fetchBooks(query: String = "bestsellers", genre: String = "All") async throws -> [BookItem] {
        if let books = try? await fetchFromSupabase(query: query, genre: genre), !books.isEmpty {
            return books
        }

        let groups = await [
            (try? fetchGoogleBooks(query: query, genre: genre)) ?? [],
            (try? fetchOpenLibrary(query: query, genre: genre)) ?? [],
            (try? fetchGutendex(query: query, genre: genre)) ?? []
        ]
        let books = dedupe(groups.flatMap { $0 })
        if books.isEmpty { throw BooksServiceError.unavailable }
        return Array(books.prefix(96))
    }

    private func fetchFromSupabase(query: String, genre: String) async throws -> [BookItem] {
        guard let url = config.booksDataFunctionURL, config.hasSupabase else {
            throw BooksServiceError.unavailable
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "genre", value: genre)
        ]
        guard let finalURL = components?.url else { throw BooksServiceError.invalidResponse }

        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, http) = try await HTTPClient.data(for: request)
        let payload = try HTTPClient.requireSuccess(data, http)
        return try JSONDecoder.supabase.decode(BooksDataResponse.self, from: payload).books
    }

    private func fetchGoogleBooks(query: String, genre: String) async throws -> [BookItem] {
        var components = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")
        let subject = genre == "All" ? "" : "+subject:\(genre)"
        components?.queryItems = [
            URLQueryItem(name: "q", value: "\(query)\(subject)"),
            URLQueryItem(name: "maxResults", value: "40"),
            URLQueryItem(name: "printType", value: "books")
        ]
        guard let url = components?.url else { throw BooksServiceError.invalidResponse }
        let (data, http) = try await HTTPClient.data(for: URLRequest(url: url))
        let payload = try HTTPClient.requireSuccess(data, http)
        let response = try JSONDecoder().decode(GoogleBooksResponse.self, from: payload)
        return response.items?.compactMap(\.bookItem) ?? []
    }

    private func fetchOpenLibrary(query: String, genre: String) async throws -> [BookItem] {
        var components = URLComponents(string: "https://openlibrary.org/search.json")
        components?.queryItems = [
            URLQueryItem(name: "q", value: genre == "All" ? query : "\(query) \(genre)"),
            URLQueryItem(name: "limit", value: "50")
        ]
        guard let url = components?.url else { throw BooksServiceError.invalidResponse }
        let (data, http) = try await HTTPClient.data(for: URLRequest(url: url))
        let payload = try HTTPClient.requireSuccess(data, http)
        let response = try JSONDecoder().decode(OpenLibraryResponse.self, from: payload)
        return response.docs.compactMap(\.bookItem)
    }

    private func fetchGutendex(query: String, genre: String) async throws -> [BookItem] {
        var components = URLComponents(string: "https://gutendex.com/books")
        components?.queryItems = [
            URLQueryItem(name: "search", value: genre == "All" ? query : "\(query) \(genre)")
        ]
        guard let url = components?.url else { throw BooksServiceError.invalidResponse }
        let (data, http) = try await HTTPClient.data(for: URLRequest(url: url))
        let payload = try HTTPClient.requireSuccess(data, http)
        let response = try JSONDecoder().decode(GutendexResponse.self, from: payload)
        return response.results.compactMap(\.bookItem)
    }

    private func dedupe(_ books: [BookItem]) -> [BookItem] {
        var seen = Set<String>()
        return books.filter { book in
            let key = "\(book.title)|\(book.authorLine)".lowercased()
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }
}

private struct GoogleBooksResponse: Decodable {
    let items: [GoogleVolume]?
}

private struct GoogleVolume: Decodable {
    let id: String
    let volumeInfo: VolumeInfo
    let accessInfo: AccessInfo?

    var bookItem: BookItem? {
        guard !volumeInfo.title.isEmpty else { return nil }
        return BookItem(
            id: "google-\(id)",
            title: volumeInfo.title,
            authors: volumeInfo.authors ?? [],
            genre: volumeInfo.categories?.first ?? "General",
            description: volumeInfo.description?.strippingHTML ?? "No summary available yet.",
            coverURL: volumeInfo.imageLinks?.thumbnailURL,
            rating: volumeInfo.averageRating,
            pageCount: volumeInfo.pageCount,
            publishedYear: String((volumeInfo.publishedDate ?? "").prefix(4)),
            publisher: volumeInfo.publisher ?? "Unknown publisher",
            source: "Google Books",
            availability: accessInfo?.epub?.downloadLink == nil ? .preview : .readable,
            previewURL: volumeInfo.previewLink.flatMap(URL.init(string:)),
            downloadURL: accessInfo?.epub?.downloadLink.flatMap(URL.init(string:))
        )
    }
}

private struct VolumeInfo: Decodable {
    let title: String
    let authors: [String]?
    let publisher: String?
    let publishedDate: String?
    let description: String?
    let pageCount: Int?
    let categories: [String]?
    let averageRating: Double?
    let previewLink: String?
    let imageLinks: ImageLinks?
}

private struct ImageLinks: Decodable {
    let thumbnail: String?
    var thumbnailURL: URL? {
        guard let thumbnail else { return nil }
        return URL(string: thumbnail.replacingOccurrences(of: "http://", with: "https://"))
    }
}

private struct AccessInfo: Decodable {
    let epub: DownloadInfo?
}

private struct DownloadInfo: Decodable {
    let downloadLink: String?
}

private struct OpenLibraryResponse: Decodable {
    let docs: [OpenLibraryDoc]
}

private struct OpenLibraryDoc: Decodable {
    let key: String
    let title: String
    let author_name: [String]?
    let subject: [String]?
    let first_publish_year: Int?
    let publisher: [String]?
    let cover_i: Int?
    let number_of_pages_median: Int?
    let ratings_average: Double?

    var bookItem: BookItem? {
        guard !title.isEmpty else { return nil }
        return BookItem(
            id: "openlibrary-\(key.replacingOccurrences(of: "/", with: "-"))",
            title: title,
            authors: author_name ?? [],
            genre: subject?.first ?? "General",
            description: "Open Library reference with editions, metadata, and catalog details.",
            coverURL: cover_i.map { URL(string: "https://covers.openlibrary.org/b/id/\($0)-L.jpg") } ?? nil,
            rating: ratings_average,
            pageCount: number_of_pages_median,
            publishedYear: first_publish_year.map(String.init) ?? "",
            publisher: publisher?.first ?? "Open Library",
            source: "Open Library",
            availability: .reference,
            previewURL: URL(string: "https://openlibrary.org\(key)"),
            downloadURL: nil
        )
    }
}

private struct GutendexResponse: Decodable {
    let results: [GutendexBook]
}

private struct GutendexBook: Decodable {
    struct Person: Decodable { let name: String }
    let id: Int
    let title: String
    let authors: [Person]
    let subjects: [String]
    let download_count: Int?
    let formats: [String: String]

    var bookItem: BookItem? {
        guard !title.isEmpty else { return nil }
        let download = formats["application/epub+zip"] ?? formats["text/html"] ?? formats["text/plain; charset=utf-8"]
        let cover = formats["image/jpeg"]
        return BookItem(
            id: "gutendex-\(id)",
            title: title,
            authors: authors.map(\.name),
            genre: subjects.first ?? "Classic",
            description: "Public domain edition with readable and downloadable formats.",
            coverURL: cover.flatMap(URL.init(string:)),
            rating: nil,
            pageCount: nil,
            publishedYear: "Public domain",
            publisher: "Project Gutenberg",
            source: "Gutendex",
            availability: download == nil ? .reference : .readable,
            previewURL: formats["text/html"].flatMap(URL.init(string:)),
            downloadURL: download.flatMap(URL.init(string:))
        )
    }
}

private extension String {
    var strippingHTML: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}
