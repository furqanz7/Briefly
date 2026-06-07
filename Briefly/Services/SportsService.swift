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
        request.timeoutInterval = 10
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = forceRefresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy

        do {
            let (data, http) = try await HTTPClient.data(for: request)
            let payload = try HTTPClient.requireSuccess(data, http)
            let response = try JSONDecoder.supabase.decode(LiveScoresResponse.self, from: payload)
            Self.store(response)
            return response
        } catch {
            if let cached = Self.cachedResponse, cached.sports.contains(where: { $0.matchCount > 0 }) {
                return cached.withProviderMessage("Showing cached scores because live providers are unavailable.")
            }
            throw error
        }
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
        request.timeoutInterval = 8
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

struct FollowedSportsService {
    private let config = AppConfig.shared

    func followTeams(from match: LiveMatch, session: UserSession) async throws {
        guard let baseURL = config.supabaseURL else { return }

        let teams = [match.homeName, match.awayName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter {
                !$0.isEmpty
                    && $0.caseInsensitiveCompare("home") != .orderedSame
                    && $0.caseInsensitiveCompare("away") != .orderedSame
            }
            .map {
                FollowedSportsTeamPayload(
                    userID: session.userID.uuidString.lowercased(),
                    sportID: match.sportID,
                    sportName: match.sportName,
                    teamName: $0,
                    teamKey: Self.teamKey($0),
                    source: "match_detail"
                )
            }
            .filter { !$0.teamKey.isEmpty }

        guard !teams.isEmpty else { return }

        var components = URLComponents(url: baseURL.appending(path: "/rest/v1/sports_followed_teams"), resolvingAgainstBaseURL: false)
        components?.queryItems = [.init(name: "on_conflict", value: "user_id,sport_id,team_key")]
        guard let url = components?.url else { return }

        var request = authedRequest(url: url, session: session)
        request.httpMethod = "POST"
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder.supabase.encode(teams)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            if isMissingTable(data: data, statusCode: http.statusCode) { return }
            throw APIError.server("Could not follow these teams yet.")
        }
    }

    private func authedRequest(url: URL, session: UserSession) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
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

    private static func teamKey(_ name: String) -> String {
        name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

private struct FollowedSportsTeamPayload: Encodable {
    let userID: String
    let sportID: String
    let sportName: String
    let teamName: String
    let teamKey: String
    let source: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case sportID = "sport_id"
        case sportName = "sport_name"
        case teamName = "team_name"
        case teamKey = "team_key"
        case source
    }
}
