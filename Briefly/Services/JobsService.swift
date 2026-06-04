import Foundation

enum JobsServiceError: LocalizedError {
    case missingSupabase
    case invalidResponse
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingSupabase:
            return "Jobs need the Supabase jobs-data function."
        case .invalidResponse:
            return "Jobs returned an invalid response."
        case .unavailable(let message):
            return message
        }
    }
}

protocol JobsProviding {
    func fetchJobs(query: String, country: String) async throws -> JobsDataResponse
    func fetchDetail(for job: JobListing, country: String) async throws -> JobsDataResponse
}

struct JobsDataResponse: Decodable {
    let generatedAt: Date
    let source: String
    let provider: String?
    let cacheHit: Bool
    let stale: Bool
    let updatedAt: Date?
    let expiresAt: Date?
    let message: String?
    let jobs: [JobListing]

    var providerStatusMessage: String? {
        if source == "fixture" {
            return "Showing sample roles while jobs refresh."
        }

        if stale || cacheHit {
            return "Showing saved job matches while refreshing."
        }

        return nil
    }

    static func fixture(message: String? = nil) -> JobsDataResponse {
        JobsDataResponse(
            generatedAt: .now,
            source: "fixture",
            provider: nil,
            cacheHit: false,
            stale: true,
            updatedAt: nil,
            expiresAt: nil,
            message: message ?? "Jobs providers are not configured yet.",
            jobs: JobListing.fixtures
        )
    }

    func withProviderMessage(_ message: String) -> JobsDataResponse {
        JobsDataResponse(
            generatedAt: .now,
            source: cacheHit ? source : "cached",
            provider: provider,
            cacheHit: true,
            stale: true,
            updatedAt: updatedAt ?? generatedAt,
            expiresAt: expiresAt,
            message: message,
            jobs: jobs
        )
    }
}

struct JobsService: JobsProviding {
    private struct CachedResponse {
        let response: JobsDataResponse
        let storedAt: Date
    }

    private static var cachedResponses: [String: CachedResponse] = [:]
    private static let cacheTTL: TimeInterval = 180

    private let config = AppConfig.shared

    func fetchJobs(query: String = "ios developer remote", country: String = "us") async throws -> JobsDataResponse {
        let key = cacheKey(query: query, country: country)
        if let cached = validCachedResponse(for: key) {
            return cached
        }

        guard let url = config.jobsDataFunctionURL, config.hasSupabase else {
            let response = JobsDataResponse.fixture()
            Self.store(response, for: key)
            return response
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "country", value: country)
        ]

        guard let finalURL = components?.url else {
            throw JobsServiceError.invalidResponse
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, http) = try await HTTPClient.data(for: request)
            let payload = try HTTPClient.requireSuccess(data, http)
            let response = try JSONDecoder.supabase.decode(JobsDataResponse.self, from: payload)

            guard !response.jobs.isEmpty else {
                throw JobsServiceError.unavailable(response.message ?? "No jobs are available yet.")
            }

            Self.store(response, for: key)
            return response
        } catch {
            if let cached = Self.cachedResponses[key]?.response, !cached.jobs.isEmpty {
                return cached.withProviderMessage("Showing cached job matches because live providers are unavailable.")
            }
            throw error
        }
    }

    func fetchDetail(for job: JobListing, country: String = "us") async throws -> JobsDataResponse {
        guard let url = config.jobsDataFunctionURL, config.hasSupabase else {
            return JobsDataResponse(
                generatedAt: .now,
                source: "fixture",
                provider: nil,
                cacheHit: false,
                stale: true,
                updatedAt: nil,
                expiresAt: nil,
                message: "Job detail providers are not configured yet.",
                jobs: [job]
            )
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "job_id", value: job.id),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "title", value: job.title),
            URLQueryItem(name: "location", value: job.location)
        ]

        guard let finalURL = components?.url else {
            throw JobsServiceError.invalidResponse
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, http) = try await HTTPClient.data(for: request)
            let payload = try HTTPClient.requireSuccess(data, http)
            let response = try JSONDecoder.supabase.decode(JobsDataResponse.self, from: payload)

            guard !response.jobs.isEmpty else {
                throw JobsServiceError.unavailable(response.message ?? "No job detail is available yet.")
            }

            return response
        } catch {
            return JobsDataResponse(
                generatedAt: .now,
                source: "cached",
                provider: nil,
                cacheHit: true,
                stale: true,
                updatedAt: nil,
                expiresAt: nil,
                message: "Detailed provider data is unavailable right now.",
                jobs: [job]
            )
        }
    }

    private func validCachedResponse(for key: String) -> JobsDataResponse? {
        guard let cached = Self.cachedResponses[key],
              Date().timeIntervalSince(cached.storedAt) < Self.cacheTTL,
              !cached.response.jobs.isEmpty else {
            return nil
        }
        return cached.response
    }

    private static func store(_ response: JobsDataResponse, for key: String) {
        guard !response.jobs.isEmpty else { return }
        cachedResponses[key] = CachedResponse(response: response, storedAt: .now)
    }

    private func cacheKey(query: String, country: String) -> String {
        let queryKey = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(country.lowercased())|\(queryKey)"
    }
}

struct FixtureJobsService: JobsProviding {
    func fetchJobs(query: String = "ios developer remote", country: String = "us") async throws -> JobsDataResponse {
        JobsDataResponse.fixture(message: "Showing fixture jobs for previews.")
    }

    func fetchDetail(for job: JobListing, country: String = "us") async throws -> JobsDataResponse {
        JobsDataResponse(
            generatedAt: .now,
            source: "fixture",
            provider: nil,
            cacheHit: false,
            stale: false,
            updatedAt: nil,
            expiresAt: nil,
            message: "Showing fixture job detail for previews.",
            jobs: [job]
        )
    }
}

extension JobListing {
    static let fixtures: [JobListing] = [
        JobListing(
            id: "job-briefly-ios",
            title: "Senior iOS Engineer",
            company: "Northstar Labs",
            location: "New York, NY",
            workMode: .hybrid,
            salary: "$170K - $220K",
            matchScore: 94,
            postedAt: "2 hr ago",
            companySummary: "A product studio building fast consumer workflows for finance, news, and personal intelligence.",
            roleSummary: "Own SwiftUI surfaces from prototype to App Store release, polish interaction details, and wire production data into a premium mobile experience.",
            skills: ["SwiftUI", "iOS", "Async/Await", "Charts"],
            perks: ["Equity", "Flexible PTO", "Design-heavy team"],
            requirements: [
                "5+ years shipping iOS apps",
                "Strong SwiftUI layout and state management",
                "Comfortable working with API-backed consumer products"
            ],
            applyURL: URL(string: "https://example.com/jobs/ios")
        ),
        JobListing(
            id: "job-market-data",
            title: "Market Data Engineer",
            company: "Signal Harbor",
            location: "Remote",
            workMode: .remote,
            salary: "$150K - $205K",
            matchScore: 91,
            postedAt: "Today",
            companySummary: "Infrastructure team normalizing financial feeds, sports data, and real-time provider fallbacks.",
            roleSummary: "Design cache-aware data pipelines, provider quota guards, and clean APIs that keep mobile clients fast without burning limits.",
            skills: ["Supabase", "Deno", "Postgres", "APIs"],
            perks: ["Remote first", "Home office", "Usage-based bonus"],
            requirements: [
                "Experience with third-party API integrations",
                "Strong Postgres and caching fundamentals",
                "Can design graceful stale-data fallbacks"
            ],
            applyURL: URL(string: "https://example.com/jobs/data")
        ),
        JobListing(
            id: "job-product-designer",
            title: "Product Designer, Mobile",
            company: "Arcday",
            location: "San Francisco, CA",
            workMode: .onsite,
            salary: "$135K - $180K",
            matchScore: 87,
            postedAt: "1 day ago",
            companySummary: "A mobile-first team building premium reading, discovery, and saved-content experiences.",
            roleSummary: "Shape high-density mobile interfaces, build interaction prototypes, and work closely with engineers on visual polish.",
            skills: ["Figma", "iOS", "Prototyping", "UX"],
            perks: ["Studio setup", "Founder access", "Launch bonus"],
            requirements: [
                "Portfolio with shipped mobile work",
                "Strong visual hierarchy and motion instincts",
                "Comfortable with product metrics and iteration"
            ],
            applyURL: URL(string: "https://example.com/jobs/design")
        ),
        JobListing(
            id: "job-ai-search",
            title: "AI Search Product Engineer",
            company: "Scoutline",
            location: "London, UK",
            workMode: .hybrid,
            salary: "GBP 115K - 155K",
            matchScore: 83,
            postedAt: "3 days ago",
            companySummary: "Search and ranking startup focused on summarizing high-signal content across jobs, markets, and news.",
            roleSummary: "Build ranking flows, personalization surfaces, and fast search experiences across mobile and web clients.",
            skills: ["Search", "Ranking", "TypeScript", "Swift"],
            perks: ["Relocation", "Learning budget", "Quarterly offsites"],
            requirements: [
                "Experience with search or recommendation systems",
                "Can tune product quality with limited data",
                "Strong product engineering taste"
            ],
            applyURL: URL(string: "https://example.com/jobs/search")
        )
    ]
}
