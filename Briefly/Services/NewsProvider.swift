import Foundation

protocol NewsProvider {
    func fetch(
        category: NewsCategory,
        pageToken: String?,
        pageSize: Int,
        forceRefresh: Bool
    ) async throws -> NewsProviderBatch

    func search(
        query: String,
        category: NewsCategory,
        pageSize: Int,
        forceRefresh: Bool
    ) async throws -> [Article]
}

struct NewsProviderBatch {
    let articles: [Article]
    let nextPageToken: String?
}

extension NewsProvider {
    var diagnosticsName: String {
        String(describing: type(of: self))
    }

    func search(
        query: String,
        category: NewsCategory,
        pageSize: Int,
        forceRefresh: Bool
    ) async throws -> [Article] {
        []
    }
}
