import Foundation
import UIKit
import UserNotifications

enum AppNotifications {
    static let savedArticlesDidChange = Notification.Name("savedArticlesDidChange")
    static let appliedJobsDidChange = Notification.Name("appliedJobsDidChange")
    static let remoteNotificationTokenDidChange = Notification.Name("remoteNotificationTokenDidChange")
}

enum JobActivityEventType: String {
    case search
    case open
    case save
    case pass
    case apply
}

struct NotificationPreferences: Codable, Equatable {
    var userID: UUID?
    var dailyBriefEnabled: Bool
    var breakingNewsEnabled: Bool
    var jobsEnabled: Bool
    var sportsEnabled: Bool
    var readingGoalEnabled: Bool
    var dailyBriefTime: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case dailyBriefEnabled = "daily_brief_enabled"
        case breakingNewsEnabled = "breaking_news_enabled"
        case jobsEnabled = "jobs_enabled"
        case sportsEnabled = "sports_enabled"
        case readingGoalEnabled = "reading_goal_enabled"
        case dailyBriefTime = "daily_brief_time"
    }

    static func defaults(userID: UUID? = nil) -> NotificationPreferences {
        NotificationPreferences(
            userID: userID,
            dailyBriefEnabled: true,
            breakingNewsEnabled: false,
            jobsEnabled: true,
            sportsEnabled: false,
            readingGoalEnabled: false,
            dailyBriefTime: "08:00:00"
        )
    }
}

final class NotificationService {
    static let shared = NotificationService()

    private let config = AppConfig.shared
    private let deviceTokenKey = "briefly.push.apnsToken.v1"

    private init() {}

    var cachedDeviceToken: String? {
        UserDefaults.standard.string(forKey: deviceTokenKey)
    }

    func storeDeviceToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: deviceTokenKey)
    }

    func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @MainActor
    func requestAuthorizationAndRegister(session: UserSession?) async throws -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus

        if status == .notDetermined {
            _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            status = await center.notificationSettings().authorizationStatus
        }

        if status.allowsRemoteNotifications {
            UIApplication.shared.registerForRemoteNotifications()
            if let session {
                Task { try? await self.syncDeviceToken(session: session) }
                Task { try? await self.ensurePreferences(session: session) }
            }
        }

        return status
    }

    func syncDeviceToken(session: UserSession) async throws {
        guard let token = cachedDeviceToken, !token.isEmpty else { return }
        guard let baseURL = config.supabaseURL else { return }

        var components = URLComponents(url: baseURL.appending(path: "/rest/v1/push_devices"), resolvingAgainstBaseURL: false)
        components?.queryItems = [.init(name: "on_conflict", value: "user_id,device_token")]
        guard let url = components?.url else { return }

        var request = authedRequest(url: url, session: session)
        request.httpMethod = "POST"
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder.supabase.encode([
            PushDevicePayload(
                userID: session.userID.uuidString.lowercased(),
                deviceToken: token,
                platform: "ios",
                bundleID: Bundle.main.bundleIdentifier,
                appVersion: appVersion,
                environment: pushEnvironment,
                enabled: true,
                lastSeenAt: ISO8601DateFormatter().string(from: Date())
            )
        ])

        try await runMinimalRequest(request, fallbackMessage: "Could not sync notification device.")
        try? await ensurePreferences(session: session)
    }

    func disableDevice(session: UserSession) async throws {
        guard let token = cachedDeviceToken, !token.isEmpty else { return }
        guard let baseURL = config.supabaseURL else { return }

        var components = URLComponents(url: baseURL.appending(path: "/rest/v1/push_devices"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "user_id", value: "eq.\(session.userID.uuidString.lowercased())"),
            .init(name: "device_token", value: "eq.\(token)")
        ]
        guard let url = components?.url else { return }

        var request = authedRequest(url: url, session: session)
        request.httpMethod = "PATCH"
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder.supabase.encode(["enabled": false])

        try await runMinimalRequest(request, fallbackMessage: "Could not disable notification device.")
    }

    func loadPreferences(session: UserSession) async throws -> NotificationPreferences {
        guard let baseURL = config.supabaseURL else {
            return .defaults(userID: session.userID)
        }

        var components = URLComponents(url: baseURL.appending(path: "/rest/v1/notification_preferences"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "select", value: "*"),
            .init(name: "user_id", value: "eq.\(session.userID.uuidString.lowercased())"),
            .init(name: "limit", value: "1")
        ]
        guard let url = components?.url else {
            return .defaults(userID: session.userID)
        }

        var request = authedRequest(url: url, session: session)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            if isMissingTable(data: data, statusCode: http.statusCode) {
                return .defaults(userID: session.userID)
            }
            throw APIError.server("Could not load notification preferences.")
        }

        let records = try JSONDecoder.supabase.decode([NotificationPreferences].self, from: data)
        return records.first ?? .defaults(userID: session.userID)
    }

    func savePreferences(_ preferences: NotificationPreferences, session: UserSession) async throws {
        guard let baseURL = config.supabaseURL else { return }

        var components = URLComponents(url: baseURL.appending(path: "/rest/v1/notification_preferences"), resolvingAgainstBaseURL: false)
        components?.queryItems = [.init(name: "on_conflict", value: "user_id")]
        guard let url = components?.url else { return }

        var payload = preferences
        payload.userID = session.userID

        var request = authedRequest(url: url, session: session)
        request.httpMethod = "POST"
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder.supabase.encode([payload])

        try await runMinimalRequest(request, fallbackMessage: "Could not save notification preferences.")
    }

    func ensurePreferences(session: UserSession) async throws {
        guard let baseURL = config.supabaseURL else { return }

        var components = URLComponents(url: baseURL.appending(path: "/rest/v1/notification_preferences"), resolvingAgainstBaseURL: false)
        components?.queryItems = [.init(name: "on_conflict", value: "user_id")]
        guard let url = components?.url else { return }

        var request = authedRequest(url: url, session: session)
        request.httpMethod = "POST"
        request.setValue("resolution=ignore-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder.supabase.encode([NotificationPreferences.defaults(userID: session.userID)])

        try await runMinimalRequest(request, fallbackMessage: "Could not prepare notification preferences.")
    }

    func recordJobActivity(
        _ eventType: JobActivityEventType,
        job: JobListing?,
        query: String,
        country: String,
        deck: String,
        session: UserSession?
    ) async {
        guard let session else { return }
        guard let baseURL = config.supabaseURL else { return }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if eventType == .search && trimmedQuery.isEmpty {
            return
        }

        var components = URLComponents(url: baseURL.appending(path: "/rest/v1/job_activity_events"), resolvingAgainstBaseURL: false)
        guard let url = components?.url else { return }

        var request = authedRequest(url: url, session: session)
        request.httpMethod = "POST"
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try? JSONEncoder.supabase.encode([
            JobActivityPayload(
                userID: session.userID.uuidString.lowercased(),
                eventType: eventType.rawValue,
                roleQuery: trimmedQuery.isEmpty ? nil : trimmedQuery,
                jobID: job?.id,
                jobTitle: job?.title,
                company: job?.company,
                market: country,
                deck: deck,
                location: job?.location,
                workMode: job?.workMode.rawValue,
                keywords: keywords(query: trimmedQuery, job: job),
                metadata: metadata(for: job)
            )
        ])

        try? await runMinimalRequest(request, fallbackMessage: "Could not record job activity.")
    }

    private func authedRequest(url: URL, session: UserSession) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func runMinimalRequest(_ request: URLRequest, fallbackMessage: String) async throws {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            if isMissingTable(data: data, statusCode: http.statusCode) { return }
            throw APIError.server(fallbackMessage)
        }
    }

    private func isMissingTable(data: Data, statusCode: Int) -> Bool {
        guard statusCode == 404,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["code"] as? String else {
            return false
        }
        return code == "PGRST205"
    }

    private var appVersion: String? {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        switch (version, build) {
        case let (.some(version), .some(build)):
            return "\(version) (\(build))"
        case let (.some(version), .none):
            return version
        default:
            return build
        }
    }

    private var pushEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    private func keywords(query: String, job: JobListing?) -> [String] {
        let queryTokens = query
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.count > 1 }

        let jobTokens = [
            job?.title,
            job?.company,
            job?.location,
            job?.workMode.rawValue
        ]
        .compactMap { $0 }
        .flatMap {
            $0.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        }
        .filter { $0.count > 1 }

        let skills = job?.skills.map { $0.lowercased() } ?? []
        return Array(NSOrderedSet(array: queryTokens + skills + jobTokens).compactMap { $0 as? String }).prefix(18).map { $0 }
    }

    private func metadata(for job: JobListing?) -> [String: String] {
        guard let job else { return [:] }
        var metadata: [String: String] = [
            "match_score": "\(job.matchScore)",
            "salary": job.salary,
            "posted_at": job.postedAt
        ]
        if let applyURL = job.applyURL?.absoluteString {
            metadata["apply_url"] = applyURL
        }
        return metadata
    }
}

private extension UNAuthorizationStatus {
    var allowsRemoteNotifications: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }
}

private struct PushDevicePayload: Encodable {
    let userID: String
    let deviceToken: String
    let platform: String
    let bundleID: String?
    let appVersion: String?
    let environment: String
    let enabled: Bool
    let lastSeenAt: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case deviceToken = "device_token"
        case platform
        case bundleID = "bundle_id"
        case appVersion = "app_version"
        case environment
        case enabled
        case lastSeenAt = "last_seen_at"
    }
}

private struct JobActivityPayload: Encodable {
    let userID: String
    let eventType: String
    let roleQuery: String?
    let jobID: String?
    let jobTitle: String?
    let company: String?
    let market: String
    let deck: String
    let location: String?
    let workMode: String?
    let keywords: [String]
    let metadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case eventType = "event_type"
        case roleQuery = "role_query"
        case jobID = "job_id"
        case jobTitle = "job_title"
        case company
        case market
        case deck
        case location
        case workMode = "work_mode"
        case keywords
        case metadata
    }
}
