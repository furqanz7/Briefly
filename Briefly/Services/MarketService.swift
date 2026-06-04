import Foundation

enum MarketServiceError: LocalizedError {
    case missingSupabase
    case invalidResponse
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingSupabase:
            return "Market snapshots need the Supabase market-data function."
        case .invalidResponse:
            return "Market data returned an invalid response."
        case .unavailable(let message):
            return message
        }
    }
}

struct MarketDataResponse: Decodable {
    let generatedAt: Date
    let source: MarketSnapshotSource
    let provider: String?
    let cacheHit: Bool
    let stale: Bool
    let updatedAt: Date?
    let expiresAt: Date?
    let message: String?
    let snapshots: [MarketSnapshot]

    var providerStatusMessage: String? {
        normalizedProviderMessage(
            cachedLabel: "market data",
            staleLabel: "Showing saved market data while live providers refresh."
        )
    }

    private func normalizedProviderMessage(cachedLabel: String, staleLabel: String) -> String? {
        if stale || source == .stale {
            return staleLabel
        }

        if cacheHit || source == .cached {
            return "Showing cached \(cachedLabel)."
        }

        return nil
    }
}

struct CryptoStatsResponse: Decodable {
    let generatedAt: Date
    let source: MarketSnapshotSource
    let provider: String
    let cacheHit: Bool
    let stale: Bool
    let updatedAt: Date?
    let expiresAt: Date?
    let message: String?
    let stats: CryptoStats

    var providerStatusMessage: String? {
        if stale || source == .stale {
            return "Showing saved crypto stats while live providers refresh."
        }
        if cacheHit || source == .cached {
            return "Showing cached crypto stats."
        }
        return nil
    }
}

struct CryptoStats: Equatable, Decodable {
    let totalMarketCap: Double?
    let totalVolume24h: Double?
    let btcDominance: Double?
    let totalCoins: Double?
    let totalMarkets: Double?
    let totalExchanges: Double?
}

struct CryptoMoversResponse: Decodable {
    let generatedAt: Date
    let source: MarketSnapshotSource
    let provider: String
    let cacheHit: Bool
    let stale: Bool
    let updatedAt: Date?
    let expiresAt: Date?
    let message: String?
    let gainers: [MarketSnapshot]
    let losers: [MarketSnapshot]

    var providerStatusMessage: String? {
        if stale || source == .stale {
            return "Showing saved crypto movers while live providers refresh."
        }
        if cacheHit || source == .cached {
            return "Showing cached crypto movers."
        }
        return nil
    }
}

enum MarketSnapshotSource: String, Decodable {
    case live
    case cached
    case stale
}

struct MarketService {
    private static var cachedResponse: MarketDataResponse?
    private static var cacheTimestamp: Date?
    private static let cacheTTL: TimeInterval = 60

    private let config = AppConfig.shared

    func fetchSnapshots(forceRefresh: Bool = false) async throws -> MarketDataResponse {
        if !forceRefresh,
           let cached = Self.cachedResponse,
           let cacheTimestamp = Self.cacheTimestamp,
           Date().timeIntervalSince(cacheTimestamp) < Self.cacheTTL {
            return cached
        }

        guard let url = config.marketDataFunctionURL, config.hasSupabase else {
            throw MarketServiceError.missingSupabase
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if forceRefresh {
            components?.queryItems = [URLQueryItem(name: "force", value: "1")]
        }

        guard let finalURL = components?.url else {
            throw MarketServiceError.invalidResponse
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = forceRefresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy

        let (data, http) = try await HTTPClient.data(for: request)
        let payload = try HTTPClient.requireSuccess(data, http)
        let response = try JSONDecoder.supabase.decode(MarketDataResponse.self, from: payload)

        guard !response.snapshots.isEmpty else {
            throw MarketServiceError.unavailable(response.message ?? "No market data is available yet.")
        }

        Self.store(response)
        return response
    }

    func fetchCryptoSnapshots() async throws -> MarketDataResponse {
        try await fetchMarketSnapshots(kind: "crypto", emptyMessage: "No crypto market data is available yet.")
    }

    func fetchTrendingCryptoSnapshots() async throws -> MarketDataResponse {
        try await fetchMarketSnapshots(kind: "crypto-trending", emptyMessage: "No trending crypto data is available yet.")
    }

    func searchCryptoSnapshots(query: String) async throws -> MarketDataResponse {
        try await fetchMarketSnapshots(
            kind: "crypto-search",
            extraQueryItems: [URLQueryItem(name: "q", value: query)],
            emptyMessage: "No matching crypto assets are available yet."
        )
    }

    func fetchCryptoStats() async throws -> CryptoStatsResponse {
        try await fetchCryptoPayload(kind: "crypto-stats", as: CryptoStatsResponse.self)
    }

    func fetchCryptoMovers() async throws -> CryptoMoversResponse {
        let response = try await fetchCryptoPayload(kind: "crypto-movers", as: CryptoMoversResponse.self)
        guard !response.gainers.isEmpty || !response.losers.isEmpty else {
            throw MarketServiceError.unavailable(response.message ?? "No crypto movers are available yet.")
        }
        return response
    }

    private func fetchCryptoPayload<T: Decodable>(kind: String, as type: T.Type) async throws -> T {
        guard let url = config.marketDataFunctionURL, config.hasSupabase else {
            throw MarketServiceError.missingSupabase
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "kind", value: kind)]

        guard let finalURL = components?.url else {
            throw MarketServiceError.invalidResponse
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, http) = try await HTTPClient.data(for: request)
        let payload = try HTTPClient.requireSuccess(data, http)
        return try JSONDecoder.supabase.decode(T.self, from: payload)
    }

    private func fetchMarketSnapshots(
        kind: String,
        extraQueryItems: [URLQueryItem] = [],
        emptyMessage: String
    ) async throws -> MarketDataResponse {
        guard let url = config.marketDataFunctionURL, config.hasSupabase else {
            throw MarketServiceError.missingSupabase
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "kind", value: kind)] + extraQueryItems

        guard let finalURL = components?.url else {
            throw MarketServiceError.invalidResponse
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, http) = try await HTTPClient.data(for: request)
        let payload = try HTTPClient.requireSuccess(data, http)
        let response = try JSONDecoder.supabase.decode(MarketDataResponse.self, from: payload)

        guard !response.snapshots.isEmpty else {
            throw MarketServiceError.unavailable(response.message ?? emptyMessage)
        }

        return response
    }

    func fetchDetail(for snapshot: MarketSnapshot) async throws -> MarketDetail {
        guard let url = config.marketDataFunctionURL, config.hasSupabase else {
            throw MarketServiceError.missingSupabase
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if snapshot.assetType == "crypto" {
            components?.queryItems = [URLQueryItem(name: "coin", value: snapshot.detailID ?? snapshot.id)]
        } else {
            components?.queryItems = [URLQueryItem(name: "symbol", value: snapshot.detailID ?? snapshot.id)]
        }

        guard let finalURL = components?.url else {
            throw MarketServiceError.invalidResponse
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, http) = try await HTTPClient.data(for: request)
        let payload = try HTTPClient.requireSuccess(data, http)
        let detail = try JSONDecoder.supabase.decode(MarketDetail.self, from: payload)

        guard detail.snapshot.price != nil || !detail.chart.isEmpty else {
            throw MarketServiceError.unavailable(detail.message ?? "No market detail is available yet.")
        }

        return detail
    }

    private static func store(_ response: MarketDataResponse) {
        cachedResponse = response
        cacheTimestamp = Date()
    }
}
