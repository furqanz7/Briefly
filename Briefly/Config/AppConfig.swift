import Foundation

struct AppConfig {
    let supabaseURL: URL?
    let supabaseAnonKey: String
    let newsDataAPIKey: String
    let mediastackAPIKey: String
    let newsAPIOrgKey: String
    let gnewsAPIKey: String
    let guardianAPIKey: String
    let worldNewsAPIKey: String
    let newYorkTimesAPIKey: String
    let newYorkTimesAPISecret: String
    let massiveRESTAPIKey: String
    let massiveAccessKeyID: String
    let massiveSecretAccessKey: String
    let massiveEndpoint: URL?
    let massiveBucket: String
    let aiAPIKey: String
    let aiBaseURL: URL?
    let aiModel: String
    let aiProvider: AIProvider
    let admobNativeHomeAdUnitID: String
    let admobNativeCategoryAdUnitID: String
    let admobNativeArticleAdUnitID: String
    let admobNativeSportsAdUnitID: String
    let admobNativeJobsAdUnitID: String
    let admobNativeBooksAdUnitID: String

    static let shared = AppConfig.load()
    static let admobNativeTestAdUnitID = "ca-app-pub-3940256099942544/3986624511"

    static func load() -> AppConfig {
        let bundle = Bundle.main
        let dictionary = bundle.url(forResource: "Secrets", withExtension: "plist")
            .flatMap { NSDictionary(contentsOf: $0) as? [String: Any] } ?? [:]

        func string(_ key: String, fallback: String = "") -> String {
            dictionary[key] as? String ?? fallback
        }

        #if DEBUG
        let nativeAdFallback = Self.admobNativeTestAdUnitID
        #else
        let nativeAdFallback = ""
        #endif

        let nativeHomeAdUnitID = string("ADMOB_NATIVE_HOME_AD_UNIT_ID", fallback: nativeAdFallback)
        let nativeCategoryAdUnitID = string("ADMOB_NATIVE_CATEGORY_AD_UNIT_ID", fallback: nativeHomeAdUnitID)
        let nativeArticleAdUnitID = string("ADMOB_NATIVE_ARTICLE_AD_UNIT_ID", fallback: nativeHomeAdUnitID)
        let nativeSportsAdUnitID = string("ADMOB_NATIVE_SPORTS_AD_UNIT_ID", fallback: nativeHomeAdUnitID)
        let nativeJobsAdUnitID = string("ADMOB_NATIVE_JOBS_AD_UNIT_ID", fallback: nativeHomeAdUnitID)
        let nativeBooksAdUnitID = string("ADMOB_NATIVE_BOOKS_AD_UNIT_ID", fallback: nativeHomeAdUnitID)

        return AppConfig(
            supabaseURL: normalizedSupabaseURL(string("SUPABASE_URL")),
            supabaseAnonKey: string("SUPABASE_ANON_KEY"),
            newsDataAPIKey: string("NEWSDATA_API_KEY"),
            mediastackAPIKey: string("MEDIASTACK_API_KEY"),
            newsAPIOrgKey: string("NEWSAPI_API_KEY"),
            gnewsAPIKey: string("GNEWS_API_KEY"),
            guardianAPIKey: string("GUARDIAN_API_KEY"),
            worldNewsAPIKey: string("WORLDNEWS_API_KEY"),
            newYorkTimesAPIKey: string("NYT_API_KEY"),
            newYorkTimesAPISecret: string("NYT_API_SECRET"),
            massiveRESTAPIKey: string("MASSIVE_REST_API_KEY"),
            massiveAccessKeyID: string("MASSIVE_ACCESS_KEY_ID"),
            massiveSecretAccessKey: string("MASSIVE_SECRET_ACCESS_KEY"),
            massiveEndpoint: URL(string: string("MASSIVE_S3_ENDPOINT")),
            massiveBucket: string("MASSIVE_BUCKET"),
            aiAPIKey: string("AI_API_KEY"),
            aiBaseURL: URL(string: string("AI_BASE_URL", fallback: "https://api.groq.com/openai/v1")),
            aiModel: string("AI_MODEL", fallback: "llama-3.3-70b-versatile"),
            aiProvider: AIProvider(rawValue: string("AI_PROVIDER", fallback: "openai_compatible")) ?? .openAICompatible,
            admobNativeHomeAdUnitID: nativeHomeAdUnitID,
            admobNativeCategoryAdUnitID: nativeCategoryAdUnitID,
            admobNativeArticleAdUnitID: nativeArticleAdUnitID,
            admobNativeSportsAdUnitID: nativeSportsAdUnitID,
            admobNativeJobsAdUnitID: nativeJobsAdUnitID,
            admobNativeBooksAdUnitID: nativeBooksAdUnitID
        )
    }

    private static func normalizedSupabaseURL(_ rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed) else { return nil }
        let lowerPath = components.path.lowercased()

        if lowerPath.hasSuffix("/rest/v1") {
            components.path = String(components.path.dropLast("/rest/v1".count))
        } else if lowerPath.hasSuffix("/rest/v1/") {
            components.path = String(components.path.dropLast("/rest/v1/".count))
        }

        if components.path == "/" {
            components.path = ""
        }

        return components.url
    }

    var hasSupabase: Bool {
        supabaseURL != nil && !supabaseAnonKey.isEmpty
    }

    var hasNewsAPI: Bool {
        hasNewsDataAPI || hasMediastackAPI || hasNewsAPIOrg || hasGNewsAPI || hasGuardianAPI || hasWorldNewsAPI || hasNewYorkTimesAPI
    }

    var hasNewsDataAPI: Bool {
        !newsDataAPIKey.isEmpty
    }

    var hasMediastackAPI: Bool {
        !mediastackAPIKey.isEmpty
    }

    var hasNewsAPIOrg: Bool {
        !newsAPIOrgKey.isEmpty
    }

    var hasGNewsAPI: Bool {
        !gnewsAPIKey.isEmpty
    }

    var hasGuardianAPI: Bool {
        !guardianAPIKey.isEmpty
    }

    var hasWorldNewsAPI: Bool {
        !worldNewsAPIKey.isEmpty
    }

    var hasNewYorkTimesAPI: Bool {
        !newYorkTimesAPIKey.isEmpty
    }

    var hasMassiveRESTAPI: Bool {
        !massiveRESTAPIKey.isEmpty
    }

    var hasMassiveConfig: Bool {
        !massiveAccessKeyID.isEmpty &&
        !massiveSecretAccessKey.isEmpty &&
        massiveEndpoint != nil &&
        !massiveBucket.isEmpty
    }

    var hasAI: Bool {
        aiBaseURL != nil && !aiAPIKey.isEmpty
    }

    var deleteAccountFunctionURL: URL? {
        supabaseURL?.appending(path: "/functions/v1/delete-account")
    }

    var dailyFeedFunctionURL: URL? {
        supabaseURL?.appending(path: "/functions/v1/daily-feed")
    }

    var liveScoresFunctionURL: URL? {
        supabaseURL?.appending(path: "/functions/v1/live-scores")
    }

    var marketDataFunctionURL: URL? {
        supabaseURL?.appending(path: "/functions/v1/market-data")
    }

    var jobsDataFunctionURL: URL? {
        supabaseURL?.appending(path: "/functions/v1/jobs-data")
    }

    var booksDataFunctionURL: URL? {
        supabaseURL?.appending(path: "/functions/v1/books-data")
    }

    var passwordRecoveryRedirectURL: URL? {
        URL(string: "briefly://auth/reset-password")
    }

    func nativeAdUnitID(for placement: NativeAdPlacement) -> String {
        #if DEBUG
        return Self.admobNativeTestAdUnitID
        #else
        switch placement {
        case .home:
            return admobNativeHomeAdUnitID
        case .category:
            return admobNativeCategoryAdUnitID
        case .articleDetail:
            return admobNativeArticleAdUnitID
        case .sports:
            return admobNativeSportsAdUnitID
        case .jobs:
            return admobNativeJobsAdUnitID
        case .books:
            return admobNativeBooksAdUnitID
        }
        #endif
    }

    var aiProviderDisplayName: String {
        switch aiProvider {
        case .openAICompatible:
            if let host = aiBaseURL?.host, host.contains("groq") {
                return "Groq"
            }
            return "an OpenAI-compatible AI provider"
        case .gemini:
            return "Google Gemini"
        }
    }
}

enum AIProvider: String {
    case openAICompatible = "openai_compatible"
    case gemini
}
