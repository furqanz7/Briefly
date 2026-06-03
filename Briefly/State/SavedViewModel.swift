import Foundation

@MainActor
final class SavedViewModel: ObservableObject {
    @Published var articles: [Article] = []
    @Published var searchText = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let savedService = SavedArticlesService()
    private var lastLoadedAt: Date?
    private let reloadInterval: TimeInterval = 120

    var filteredArticles: [Article] {
        guard !searchText.isEmpty else { return articles }
        return articles.filter {
            $0.headline.localizedCaseInsensitiveContains(searchText) ||
            $0.source.localizedCaseInsensitiveContains(searchText)
        }
    }

    func load(session: UserSession?, force: Bool = false) async {
        guard let session else {
            articles = []
            errorMessage = nil
            return
        }

        if !force,
           let lastLoadedAt,
           !articles.isEmpty,
           Date().timeIntervalSince(lastLoadedAt) < reloadInterval {
            return
        }

        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            articles = try await savedService.fetchSavedArticles(session: session)
            lastLoadedAt = .now
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func remove(article: Article, session: UserSession?) async {
        guard let session else { return }
        do {
            try await savedService.delete(article: article, session: session)
            articles.removeAll { $0.id == article.id }
            NotificationCenter.default.post(name: AppNotifications.savedArticlesDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
