import Foundation

struct SportsService {
    private static var cachedResponse: LiveScoresResponse?
    private static var cacheTimestamp: Date?
    private static let cacheTTL: TimeInterval = 60

    private let config = AppConfig.shared

    func fetchLiveScores(forceRefresh: Bool = false) async throws -> LiveScoresResponse {
        if !forceRefresh,
           let cached = Self.cachedResponse,
           let cacheTimestamp = Self.cacheTimestamp,
           Date().timeIntervalSince(cacheTimestamp) < Self.cacheTTL {
            return cached
        }

        guard let url = config.liveScoresFunctionURL, config.hasSupabase else {
            let response = LiveScoresResponse(
                generatedAt: Date(),
                cacheHit: false,
                providerConfigured: false,
                message: "Live scores need the Supabase live-scores function.",
                sports: []
            )
            Self.store(response)
            return response
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.append(URLQueryItem(name: "ttl", value: forceRefresh ? "30" : "60"))

        let locale = Locale.autoupdatingCurrent
        queryItems.append(URLQueryItem(name: "timezone", value: TimeZone.autoupdatingCurrent.identifier))
        if let region = locale.region?.identifier {
            queryItems.append(URLQueryItem(name: "region", value: region))
        }

        components?.queryItems = queryItems
        guard let finalURL = components?.url else {
            throw APIError.server("The live scores URL could not be built.")
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = forceRefresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy

        let (data, http) = try await HTTPClient.data(for: request)
        let payload = try HTTPClient.requireSuccess(data, http)
        let response = try JSONDecoder.supabase.decode(LiveScoresResponse.self, from: payload)
        Self.store(response)
        return response
    }

    func fetchMatchDetail(for match: LiveMatch) async throws -> LiveMatchDetailResponse {
        guard let url = config.liveScoresFunctionURL, config.hasSupabase else {
            return LiveMatchDetailResponse(
                generatedAt: Date(),
                match: match,
                scoreboardSections: match.scoreboardSections ?? []
            )
        }

        guard let providerID = match.providerID, let detailID = match.detailID else {
            return LiveMatchDetailResponse(
                generatedAt: Date(),
                match: match,
                scoreboardSections: match.scoreboardSections ?? []
            )
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "detailProvider", value: providerID),
            URLQueryItem(name: "detailID", value: detailID)
        ]

        guard let finalURL = components?.url else {
            throw APIError.server("The live match detail URL could not be built.")
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, http) = try await HTTPClient.data(for: request)
        let payload = try HTTPClient.requireSuccess(data, http)
        return try JSONDecoder.supabase.decode(LiveMatchDetailResponse.self, from: payload)
    }

    private static func store(_ response: LiveScoresResponse) {
        cachedResponse = response
        cacheTimestamp = Date()
    }
}
