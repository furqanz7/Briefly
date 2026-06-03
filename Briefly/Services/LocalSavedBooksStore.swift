import Foundation

struct LocalSavedBooksStore {
    private let savedKey = "local_saved_books_v1"
    private let downloadedKey = "local_downloaded_books_v1"
    private let readingPrefix = "local_books_reading_minutes_"

    func savedBooks() -> [BookItem] {
        guard let data = UserDefaults.standard.data(forKey: savedKey),
              let books = try? JSONDecoder.supabase.decode([BookItem].self, from: data) else {
            return []
        }
        return books
    }

    func save(_ book: BookItem) {
        var books = savedBooks()
        books.removeAll { $0.id == book.id }
        books.insert(book, at: 0)
        persistSaved(books)
    }

    func remove(_ book: BookItem) {
        var books = savedBooks()
        books.removeAll { $0.id == book.id }
        persistSaved(books)
    }

    func downloadedIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: downloadedKey) ?? [])
    }

    func markDownloaded(_ book: BookItem) {
        var ids = downloadedIDs()
        ids.insert(book.id)
        UserDefaults.standard.set(Array(ids), forKey: downloadedKey)
    }

    func readingMinutes(for date: Date = Date()) -> Int {
        UserDefaults.standard.integer(forKey: readingKey(for: date))
    }

    func addReadingMinutes(_ minutes: Int, date: Date = Date()) {
        let key = readingKey(for: date)
        UserDefaults.standard.set(readingMinutes(for: date) + minutes, forKey: key)
    }

    func resetReadingMinutes(for date: Date = Date()) {
        UserDefaults.standard.removeObject(forKey: readingKey(for: date))
    }

    private func persistSaved(_ books: [BookItem]) {
        guard let data = try? JSONEncoder.supabase.encode(books) else { return }
        UserDefaults.standard.set(data, forKey: savedKey)
    }

    private func readingKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return readingPrefix + formatter.string(from: date)
    }
}
