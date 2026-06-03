import Foundation

struct SavedArticlesService {
    private let config = AppConfig.shared
    private let localStore = LocalSavedArticlesStore()

    func fetchSavedArticles(session: UserSession) async throws -> [Article] {
        guard let baseURL = config.supabaseURL else {
            return localStore.fetch(userID: session.userID)
        }

        var components = URLComponents(url: baseURL.appending(path: "/rest/v1/saved_articles"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "select", value: "*"),
            .init(name: "user_id", value: "eq.\(session.userID.uuidString.lowercased())"),
            .init(name: "order", value: "created_at.desc")
        ]

        guard let url = components?.url else { return [] }
        var request = authedRequest(url: url, session: session)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            return localStore.fetch(userID: session.userID)
        }

        guard (200...299).contains(http.statusCode) else {
            if isMissingTable(data: data, statusCode: http.statusCode) {
                return localStore.fetch(userID: session.userID)
            }
            throw APIError.server("Could not load saved articles.")
        }

        let records = try JSONDecoder.supabase.decode([SavedArticleRecord].self, from: data)
        return records.map { $0.article() }
    }

    func save(article: Article, session: UserSession) async throws {
        guard let baseURL = config.supabaseURL else {
            localStore.save(article, userID: session.userID)
            return
        }

        let url = baseURL.appending(path: "/rest/v1/saved_articles")
        var request = authedRequest(url: url, session: session)
        request.httpMethod = "POST"
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder.supabase.encode([SavedArticleRecord(article: article, userID: session.userID)])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            localStore.save(article, userID: session.userID)
            return
        }

        guard (200...299).contains(http.statusCode) else {
            if isMissingTable(data: data, statusCode: http.statusCode) {
                localStore.save(article, userID: session.userID)
                return
            }
            throw APIError.server("Could not save this article.")
        }

        localStore.save(article, userID: session.userID)
    }

    func delete(article: Article, session: UserSession) async throws {
        guard let baseURL = config.supabaseURL else {
            localStore.delete(article, userID: session.userID)
            return
        }

        var components = URLComponents(url: baseURL.appending(path: "/rest/v1/saved_articles"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "user_id", value: "eq.\(session.userID.uuidString.lowercased())"),
            .init(name: "article_id", value: "eq.\(article.id)")
        ]

        guard let url = components?.url else { return }
        var request = authedRequest(url: url, session: session)
        request.httpMethod = "DELETE"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            localStore.delete(article, userID: session.userID)
            return
        }

        guard (200...299).contains(http.statusCode) else {
            if isMissingTable(data: data, statusCode: http.statusCode) {
                localStore.delete(article, userID: session.userID)
                return
            }
            throw APIError.server("Could not remove this article.")
        }

        localStore.delete(article, userID: session.userID)
    }

    private func authedRequest(url: URL, session: UserSession) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
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
