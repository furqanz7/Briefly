import Foundation

struct LocalSavedBooksStore {
    private let savedKey = "local_saved_books_v1"
    private let downloadedKey = "local_downloaded_books_v1"
    private let readingPrefix = "local_books_reading_minutes_"
    private let readingSecondsPrefix = "local_books_reading_seconds_"
    private let readingGoalKey = "local_books_reading_goal_v1"

    func savedBooks(userID: UUID) -> [BookItem] {
        savedBooks(key: key(savedKey, userID: userID))
    }

    func save(_ book: BookItem, userID: UUID) {
        var books = savedBooks(userID: userID)
        books.removeAll { $0.id == book.id }
        books.insert(book, at: 0)
        persistSaved(books, key: key(savedKey, userID: userID))
    }

    func remove(_ book: BookItem, userID: UUID) {
        var books = savedBooks(userID: userID)
        books.removeAll { $0.id == book.id }
        persistSaved(books, key: key(savedKey, userID: userID))
    }

    func downloadedIDs(userID: UUID) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key(downloadedKey, userID: userID)) ?? [])
    }

    func markDownloaded(_ book: BookItem, userID: UUID) {
        var ids = downloadedIDs(userID: userID)
        ids.insert(book.id)
        UserDefaults.standard.set(Array(ids), forKey: key(downloadedKey, userID: userID))
    }

    func readingMinutes(userID: UUID, for date: Date = Date()) -> Int {
        Int(ceil(Double(readingSeconds(userID: userID, for: date)) / 60))
    }

    func readingSeconds(userID: UUID, for date: Date = Date()) -> Int {
        let seconds = UserDefaults.standard.integer(forKey: readingSecondsKey(userID: userID, for: date))
        if seconds > 0 { return seconds }
        return UserDefaults.standard.integer(forKey: readingKey(userID: userID, for: date)) * 60
    }

    func addReadingMinutes(_ minutes: Int, userID: UUID, date: Date = Date()) {
        addReadingSeconds(minutes * 60, userID: userID, date: date)
    }

    func setReadingSeconds(_ seconds: Int, userID: UUID, date: Date = Date()) {
        UserDefaults.standard.set(max(seconds, 0), forKey: readingSecondsKey(userID: userID, for: date))
    }

    func addReadingSeconds(_ seconds: Int, userID: UUID, date: Date = Date()) {
        let key = readingSecondsKey(userID: userID, for: date)
        UserDefaults.standard.set(readingSeconds(userID: userID, for: date) + max(seconds, 0), forKey: key)
    }

    func resetReadingMinutes(userID: UUID, for date: Date = Date()) {
        UserDefaults.standard.removeObject(forKey: readingKey(userID: userID, for: date))
        UserDefaults.standard.removeObject(forKey: readingSecondsKey(userID: userID, for: date))
    }

    func readingGoalMinutes(userID: UUID) -> Int {
        let value = UserDefaults.standard.integer(forKey: key(readingGoalKey, userID: userID))
        return value > 0 ? value : 30
    }

    func setReadingGoalMinutes(_ minutes: Int, userID: UUID) {
        UserDefaults.standard.set(max(minutes, 1), forKey: key(readingGoalKey, userID: userID))
    }

    private func savedBooks(key: String) -> [BookItem] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let books = try? JSONDecoder.supabase.decode([BookItem].self, from: data) else {
            return []
        }
        return books
    }

    private func persistSaved(_ books: [BookItem], key: String) {
        guard let data = try? JSONEncoder.supabase.encode(books) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func readingKey(userID: UUID, for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(readingPrefix)\(userID.uuidString.lowercased())_\(formatter.string(from: date))"
    }

    private func readingSecondsKey(userID: UUID, for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(readingSecondsPrefix)\(userID.uuidString.lowercased())_\(formatter.string(from: date))"
    }

    private func key(_ base: String, userID: UUID) -> String {
        "\(base)_\(userID.uuidString.lowercased())"
    }
}
