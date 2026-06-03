import Foundation

struct LocalSavedArticlesStore {
    func fetch(userID: UUID) -> [Article] {
        guard let data = UserDefaults.standard.data(forKey: key(for: userID)),
              let articles = try? JSONDecoder.supabase.decode([Article].self, from: data) else {
            return []
        }
        return articles
    }

    func save(_ article: Article, userID: UUID) {
        var articles = fetch(userID: userID)
        articles.removeAll { $0.id == article.id }
        articles.insert(article, at: 0)
        persist(articles, userID: userID)
    }

    func delete(_ article: Article, userID: UUID) {
        var articles = fetch(userID: userID)
        articles.removeAll { $0.id == article.id }
        persist(articles, userID: userID)
    }

    private func persist(_ articles: [Article], userID: UUID) {
        guard let data = try? JSONEncoder.supabase.encode(articles) else { return }
        UserDefaults.standard.set(data, forKey: key(for: userID))
    }

    private func key(for userID: UUID) -> String {
        "local_saved_articles_\(userID.uuidString.lowercased())"
    }
}
