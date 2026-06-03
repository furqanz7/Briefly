import Foundation

@MainActor
final class BooksViewModel: ObservableObject {
    enum Genre: String, CaseIterable, Identifiable {
        case all = "All"
        case fiction = "Fiction"
        case business = "Business"
        case biography = "Biography"
        case fantasy = "Fantasy"
        case history = "History"
        case science = "Science"
        case technology = "Technology"
        case romance = "Romance"
        case classics = "Classics"

        var id: String { rawValue }
    }

    @Published private(set) var books: [BookItem] = []
    @Published private(set) var savedBooks: [BookItem] = []
    @Published private(set) var downloadedIDs: Set<String> = []
    @Published var selectedGenre: Genre = .all
    @Published var searchText = ""
    @Published var selectedBook: BookItem?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var readingMinutesToday = 0

    private let service: BooksProviding
    private let store: LocalSavedBooksStore
    private let defaultQuery = "bestsellers"
    let readingGoalMinutes = 30

    init(service: BooksProviding = BooksService(), store: LocalSavedBooksStore = LocalSavedBooksStore()) {
        self.service = service
        self.store = store
        savedBooks = store.savedBooks()
        downloadedIDs = store.downloadedIDs()
        readingMinutesToday = store.readingMinutes()
    }

    var featuredBook: BookItem? {
        books.first
    }

    var visibleBooks: [BookItem] {
        books.filter { book in
            selectedGenre == .all || book.genre.localizedCaseInsensitiveContains(selectedGenre.rawValue)
        }
    }

    var readingProgress: Double {
        min(Double(readingMinutesToday) / Double(readingGoalMinutes), 1)
    }

    var activeQuery: String {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultQuery : trimmed
    }

    func load() async {
        guard books.isEmpty else { return }
        await search()
    }

    func search() async {
        isLoading = true
        errorMessage = nil
        do {
            books = try await service.fetchBooks(query: activeQuery, genre: selectedGenre.rawValue)
        } catch {
            errorMessage = "Books are unavailable right now."
        }
        isLoading = false
    }

    func choose(_ genre: Genre) {
        selectedGenre = genre
    }

    func toggleSave(_ book: BookItem) {
        if savedBooks.contains(book) {
            savedBooks.removeAll { $0.id == book.id }
            store.remove(book)
        } else {
            savedBooks.insert(book, at: 0)
            store.save(book)
        }
    }

    func markDownloaded(_ book: BookItem) {
        store.markDownloaded(book)
        downloadedIDs = store.downloadedIDs()
    }

    func addReadingMinutes(_ minutes: Int) {
        store.addReadingMinutes(minutes)
        readingMinutesToday = store.readingMinutes()
    }

    func resetReadingMinutes() {
        store.resetReadingMinutes()
        readingMinutesToday = 0
    }
}
