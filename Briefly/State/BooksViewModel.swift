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
    @Published var readingSummary = ReadingSummary()

    private let service: BooksProviding
    private let store: LocalSavedBooksStore
    private let savedService: SavedBooksService
    private let defaultQuery = "bestsellers"
    var readingMinutesToday: Int { readingSummary.todayMinutes }
    var readingGoalMinutes: Int { readingSummary.dailyGoalMinutes }

    init(
        service: BooksProviding = BooksService(),
        store: LocalSavedBooksStore = LocalSavedBooksStore(),
        savedService: SavedBooksService = SavedBooksService()
    ) {
        self.service = service
        self.store = store
        self.savedService = savedService
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
        readingSummary.progress
    }

    var activeQuery: String {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultQuery : trimmed
    }

    func load(session: UserSession?) async {
        guard books.isEmpty else { return }
        await loadAccountBackedLibrary(session: session)
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

    func toggleSave(_ book: BookItem, session: UserSession?) {
        guard let session else { return }
        if savedBooks.contains(book) {
            savedBooks.removeAll { $0.id == book.id }
            store.remove(book, userID: session.userID)
            Task {
                try? await savedService.removeSaved(book: book, downloadedIDs: downloadedIDs, session: session)
            }
        } else {
            savedBooks.insert(book, at: 0)
            store.save(book, userID: session.userID)
            Task {
                try? await savedService.save(book: book, downloadedIDs: downloadedIDs, session: session)
            }
        }
    }

    func markDownloaded(_ book: BookItem, session: UserSession?) {
        guard let session else { return }
        store.markDownloaded(book, userID: session.userID)
        downloadedIDs = store.downloadedIDs(userID: session.userID)
        Task {
            try? await savedService.markDownloaded(book: book, isSaved: savedBooks.contains(book), session: session)
        }
    }

    func addReadingMinutes(_ minutes: Int, session: UserSession?) {
        addReadingSeconds(minutes * 60, session: session)
    }

    func addReadingSeconds(_ seconds: Int, session: UserSession?) {
        guard let session else { return }
        let elapsed = max(seconds, 0)
        store.addReadingSeconds(elapsed, userID: session.userID)
        readingSummary.todaySeconds += elapsed
        readingSummary.weekSeconds += elapsed
        readingSummary.monthSeconds += elapsed
        readingSummary.overallSeconds += elapsed
        syncReadingMinutes(session: session)
    }

    func resetReadingMinutes(session: UserSession?) {
        guard let session else { return }
        store.resetReadingMinutes(userID: session.userID)
        let removed = readingSummary.todaySeconds
        readingSummary.todaySeconds = 0
        readingSummary.weekSeconds = max(0, readingSummary.weekSeconds - removed)
        readingSummary.monthSeconds = max(0, readingSummary.monthSeconds - removed)
        readingSummary.overallSeconds = max(0, readingSummary.overallSeconds - removed)
        syncReadingMinutes(session: session)
    }

    func updateReadingGoal(minutes: Int, session: UserSession?) {
        guard let session else { return }
        let clamped = min(max(minutes, 1), 1440)
        readingSummary.dailyGoalMinutes = clamped
        store.setReadingGoalMinutes(clamped, userID: session.userID)
        Task {
            try? await savedService.setReadingGoalMinutes(clamped, session: session)
        }
    }

    func loadAccountBackedLibrary(session: UserSession?) async {
        guard let session else {
            savedBooks = []
            downloadedIDs = []
            readingSummary = ReadingSummary()
            return
        }

        do {
            let library = try await savedService.fetchLibrary(session: session)
            savedBooks = library.saved
            downloadedIDs = library.downloadedIDs
            readingSummary = library.readingSummary
        } catch {
            savedBooks = store.savedBooks(userID: session.userID)
            downloadedIDs = store.downloadedIDs(userID: session.userID)
            readingSummary = ReadingSummary(
                todaySeconds: store.readingSeconds(userID: session.userID),
                weekSeconds: store.readingSeconds(userID: session.userID),
                monthSeconds: store.readingSeconds(userID: session.userID),
                overallSeconds: store.readingSeconds(userID: session.userID),
                dailyGoalMinutes: store.readingGoalMinutes(userID: session.userID)
            )
        }
    }

    private func syncReadingMinutes(session: UserSession?) {
        guard let session else { return }
        let seconds = readingSummary.todaySeconds
        Task {
            try? await savedService.setReadingSeconds(seconds, session: session)
        }
    }
}
