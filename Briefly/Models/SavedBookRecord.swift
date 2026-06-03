import Foundation

struct SavedBookRecord: Codable {
    let id: UUID?
    let userID: UUID
    let bookID: String
    let title: String
    let authors: [String]
    let genre: String
    let description: String
    let coverURL: String?
    let rating: Double?
    let pageCount: Int?
    let publishedYear: String
    let publisher: String
    let source: String
    let availability: String
    let previewURL: String?
    let downloadURL: String?
    let isSaved: Bool
    let isDownloaded: Bool
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case bookID = "book_id"
        case title
        case authors
        case genre
        case description
        case coverURL = "cover_url"
        case rating
        case pageCount = "page_count"
        case publishedYear = "published_year"
        case publisher
        case source
        case availability
        case previewURL = "preview_url"
        case downloadURL = "download_url"
        case isSaved = "is_saved"
        case isDownloaded = "is_downloaded"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(book: BookItem, userID: UUID, isSaved: Bool, isDownloaded: Bool) {
        id = nil
        self.userID = userID
        bookID = book.id
        title = book.title
        authors = book.authors
        genre = book.genre
        description = book.description
        coverURL = book.coverURL?.absoluteString
        rating = book.rating
        pageCount = book.pageCount
        publishedYear = book.publishedYear
        publisher = book.publisher
        source = book.source
        availability = book.availability.rawValue
        previewURL = book.previewURL?.absoluteString
        downloadURL = book.downloadURL?.absoluteString
        self.isSaved = isSaved
        self.isDownloaded = isDownloaded
        createdAt = nil
        updatedAt = nil
    }

    func book() -> BookItem {
        BookItem(
            id: bookID,
            title: title,
            authors: authors,
            genre: genre,
            description: description,
            coverURL: coverURL.flatMap(URL.init(string:)),
            rating: rating,
            pageCount: pageCount,
            publishedYear: publishedYear,
            publisher: publisher,
            source: source,
            availability: BookItem.Availability(rawValue: availability) ?? .reference,
            previewURL: previewURL.flatMap(URL.init(string:)),
            downloadURL: downloadURL.flatMap(URL.init(string:))
        )
    }
}

struct ReadingMinutesRecord: Codable {
    let id: UUID?
    let userID: UUID
    let readingDate: String
    let minutes: Int
    let seconds: Int
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case readingDate = "reading_date"
        case minutes
        case seconds
        case updatedAt = "updated_at"
    }

    init(userID: UUID, readingDate: String, seconds: Int) {
        id = nil
        self.userID = userID
        self.readingDate = readingDate
        self.seconds = seconds
        minutes = Int(ceil(Double(seconds) / 60))
        updatedAt = nil
    }
}

struct ReadingSummary: Equatable {
    var todaySeconds: Int = 0
    var weekSeconds: Int = 0
    var monthSeconds: Int = 0
    var overallSeconds: Int = 0
    var dailyGoalMinutes: Int = 30
    var hasCustomGoal: Bool = false

    var todayMinutes: Int { minutes(todaySeconds) }
    var weekMinutes: Int { minutes(weekSeconds) }
    var monthMinutes: Int { minutes(monthSeconds) }
    var overallMinutes: Int { minutes(overallSeconds) }
    var dailyGoalSeconds: Int { dailyGoalMinutes * 60 }

    var progress: Double {
        guard dailyGoalSeconds > 0 else { return 0 }
        return min(Double(todaySeconds) / Double(dailyGoalSeconds), 1)
    }

    private func minutes(_ seconds: Int) -> Int {
        Int(ceil(Double(max(seconds, 0)) / 60))
    }
}

struct ReadingGoalRecord: Codable {
    let id: UUID?
    let userID: UUID
    let dailyGoalMinutes: Int
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case dailyGoalMinutes = "daily_goal_minutes"
        case updatedAt = "updated_at"
    }

    init(userID: UUID, dailyGoalMinutes: Int) {
        id = nil
        self.userID = userID
        self.dailyGoalMinutes = dailyGoalMinutes
        updatedAt = nil
    }
}
