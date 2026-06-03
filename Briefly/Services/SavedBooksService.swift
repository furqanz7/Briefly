import Foundation

struct SavedBooksService {
    private let config = AppConfig.shared
    private let localStore = LocalSavedBooksStore()

    func fetchLibrary(session: UserSession) async throws -> (saved: [BookItem], downloadedIDs: Set<String>, readingSummary: ReadingSummary) {
        guard let baseURL = config.supabaseURL else {
            return (
                localStore.savedBooks(userID: session.userID),
                localStore.downloadedIDs(userID: session.userID),
                localReadingSummary(session: session)
            )
        }

        let records = try await fetchBookRecords(baseURL: baseURL, session: session)
        async let readingSummary = fetchReadingSummary(baseURL: baseURL, session: session)
        async let goal = fetchReadingGoal(baseURL: baseURL, session: session)
        var summary = try await readingSummary
        if let goal = try await goal {
            summary.dailyGoalMinutes = goal
            summary.hasCustomGoal = true
            localStore.setReadingGoalMinutes(goal, userID: session.userID)
        } else {
            summary.dailyGoalMinutes = 30
            summary.hasCustomGoal = false
        }
        localStore.setReadingSeconds(summary.todaySeconds, userID: session.userID)
        return (
            records.filter(\.isSaved).map { $0.book() },
            Set(records.filter(\.isDownloaded).map(\.bookID)),
            summary
        )
    }

    func save(book: BookItem, downloadedIDs: Set<String>, session: UserSession) async throws {
        try await upsert(book: book, isSaved: true, isDownloaded: downloadedIDs.contains(book.id), session: session)
        localStore.save(book, userID: session.userID)
    }

    func removeSaved(book: BookItem, downloadedIDs: Set<String>, session: UserSession) async throws {
        if downloadedIDs.contains(book.id) {
            try await upsert(book: book, isSaved: false, isDownloaded: true, session: session)
        } else {
            try await deleteBook(book: book, session: session)
        }
        localStore.remove(book, userID: session.userID)
    }

    func markDownloaded(book: BookItem, isSaved: Bool, session: UserSession) async throws {
        try await upsert(book: book, isSaved: isSaved, isDownloaded: true, session: session)
        localStore.markDownloaded(book, userID: session.userID)
    }

    func setReadingSeconds(_ seconds: Int, session: UserSession, date: Date = Date()) async throws {
        localStore.setReadingSeconds(seconds, userID: session.userID, date: date)
        guard let baseURL = config.supabaseURL else { return }

        var components = URLComponents(url: baseURL.appending(path: "/rest/v1/book_reading_minutes"), resolvingAgainstBaseURL: false)
        components?.queryItems = [.init(name: "on_conflict", value: "user_id,reading_date")]
        guard let url = components?.url else { return }

        var request = authedRequest(url: url, session: session)
        request.httpMethod = "POST"
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder.supabase.encode([
            ReadingMinutesRecord(userID: session.userID, readingDate: readingDateString(for: date), seconds: seconds)
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) || isMissingTable(data: data, statusCode: http.statusCode) else {
            throw APIError.server("Could not update reading time.")
        }
    }

    func setReadingGoalMinutes(_ minutes: Int, session: UserSession) async throws {
        let clamped = min(max(minutes, 1), 1440)
        localStore.setReadingGoalMinutes(clamped, userID: session.userID)
        guard let baseURL = config.supabaseURL else { return }

        var components = URLComponents(url: baseURL.appending(path: "/rest/v1/user_reading_goals"), resolvingAgainstBaseURL: false)
        components?.queryItems = [.init(name: "on_conflict", value: "user_id")]
        guard let url = components?.url else { return }

        var request = authedRequest(url: url, session: session)
        request.httpMethod = "POST"
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder.supabase.encode([
            ReadingGoalRecord(userID: session.userID, dailyGoalMinutes: clamped)
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) || isMissingTable(data: data, statusCode: http.statusCode) else {
            throw APIError.server("Could not update reading goal.")
        }
    }

    private func fetchBookRecords(baseURL: URL, session: UserSession) async throws -> [SavedBookRecord] {
        var components = URLComponents(url: baseURL.appending(path: "/rest/v1/saved_books"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "select", value: "*"),
            .init(name: "user_id", value: "eq.\(session.userID.uuidString.lowercased())"),
            .init(name: "or", value: "(is_saved.eq.true,is_downloaded.eq.true)"),
            .init(name: "order", value: "updated_at.desc")
        ]

        guard let url = components?.url else { return [] }
        var request = authedRequest(url: url, session: session)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return [] }
        guard (200...299).contains(http.statusCode) else {
            if isMissingTable(data: data, statusCode: http.statusCode) { return [] }
            throw APIError.server("Could not load books.")
        }

        return try JSONDecoder.supabase.decode([SavedBookRecord].self, from: data)
    }

    private func fetchReadingSummary(baseURL: URL, session: UserSession, date: Date = Date()) async throws -> ReadingSummary {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let startOfWeek = Calendar.current.dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay
        let startOfMonth = Calendar.current.dateInterval(of: .month, for: date)?.start ?? startOfDay

        var components = URLComponents(url: baseURL.appending(path: "/rest/v1/book_reading_minutes"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "select", value: "reading_date,minutes,seconds"),
            .init(name: "user_id", value: "eq.\(session.userID.uuidString.lowercased())"),
            .init(name: "order", value: "reading_date.desc")
        ]

        guard let url = components?.url else { return localReadingSummary(session: session) }
        var request = authedRequest(url: url, session: session)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return localReadingSummary(session: session) }
        guard (200...299).contains(http.statusCode) else {
            if isMissingTable(data: data, statusCode: http.statusCode) {
                return localReadingSummary(session: session)
            }
            throw APIError.server("Could not load reading time.")
        }

        let records = try JSONDecoder.supabase.decode([ReadingMinutesResponse].self, from: data)
        var summary = ReadingSummary()
        for record in records {
            let seconds = record.seconds ?? (record.minutes * 60)
            guard let recordDate = readingDate(from: record.readingDate) else { continue }
            summary.overallSeconds += seconds
            if Calendar.current.isDate(recordDate, inSameDayAs: date) {
                summary.todaySeconds += seconds
            }
            if recordDate >= startOfWeek {
                summary.weekSeconds += seconds
            }
            if recordDate >= startOfMonth {
                summary.monthSeconds += seconds
            }
        }
        return summary
    }

    private func fetchReadingGoal(baseURL: URL, session: UserSession) async throws -> Int? {
        var components = URLComponents(url: baseURL.appending(path: "/rest/v1/user_reading_goals"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "select", value: "daily_goal_minutes"),
            .init(name: "user_id", value: "eq.\(session.userID.uuidString.lowercased())"),
            .init(name: "limit", value: "1")
        ]

        guard let url = components?.url else { return localReadingGoal(session: session) }
        var request = authedRequest(url: url, session: session)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            return localReadingGoal(session: session)
        }
        guard (200...299).contains(http.statusCode) else {
            if isMissingTable(data: data, statusCode: http.statusCode) {
                return localReadingGoal(session: session)
            }
            throw APIError.server("Could not load reading goal.")
        }

        return try JSONDecoder.supabase.decode([ReadingGoalResponse].self, from: data).first?.dailyGoalMinutes
    }

    private func upsert(book: BookItem, isSaved: Bool, isDownloaded: Bool, session: UserSession) async throws {
        guard let baseURL = config.supabaseURL else { return }

        var components = URLComponents(url: baseURL.appending(path: "/rest/v1/saved_books"), resolvingAgainstBaseURL: false)
        components?.queryItems = [.init(name: "on_conflict", value: "user_id,book_id")]
        guard let url = components?.url else { return }

        var request = authedRequest(url: url, session: session)
        request.httpMethod = "POST"
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder.supabase.encode([
            SavedBookRecord(book: book, userID: session.userID, isSaved: isSaved, isDownloaded: isDownloaded)
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            if isMissingTable(data: data, statusCode: http.statusCode) { return }
            throw APIError.server("Could not save this book.")
        }
    }

    private func deleteBook(book: BookItem, session: UserSession) async throws {
        guard let baseURL = config.supabaseURL else { return }

        var components = URLComponents(url: baseURL.appending(path: "/rest/v1/saved_books"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "user_id", value: "eq.\(session.userID.uuidString.lowercased())"),
            .init(name: "book_id", value: "eq.\(book.id)")
        ]

        guard let url = components?.url else { return }
        var request = authedRequest(url: url, session: session)
        request.httpMethod = "DELETE"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) || isMissingTable(data: data, statusCode: http.statusCode) else {
            throw APIError.server("Could not remove this book.")
        }
    }

    private func authedRequest(url: URL, session: UserSession) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func readingDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func readingDate(from string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }

    private func localReadingSummary(session: UserSession) -> ReadingSummary {
        ReadingSummary(
            todaySeconds: localStore.readingSeconds(userID: session.userID),
            weekSeconds: localStore.readingSeconds(userID: session.userID),
            monthSeconds: localStore.readingSeconds(userID: session.userID),
            overallSeconds: localStore.readingSeconds(userID: session.userID),
            dailyGoalMinutes: localStore.readingGoalMinutes(userID: session.userID),
            hasCustomGoal: localStore.hasReadingGoal(userID: session.userID)
        )
    }

    private func localReadingGoal(session: UserSession) -> Int? {
        guard localStore.hasReadingGoal(userID: session.userID) else { return nil }
        return localStore.readingGoalMinutes(userID: session.userID)
    }

    private func isMissingTable(data: Data, statusCode: Int) -> Bool {
        guard statusCode == 404,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["code"] as? String else {
            return false
        }
        return code == "PGRST205"
    }
}

private struct ReadingMinutesResponse: Decodable {
    let readingDate: String
    let minutes: Int
    let seconds: Int?

    enum CodingKeys: String, CodingKey {
        case readingDate = "reading_date"
        case minutes
        case seconds
    }
}

private struct ReadingGoalResponse: Decodable {
    let dailyGoalMinutes: Int

    enum CodingKeys: String, CodingKey {
        case dailyGoalMinutes = "daily_goal_minutes"
    }
}
