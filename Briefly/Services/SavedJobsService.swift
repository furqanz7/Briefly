import Foundation

struct SavedJobsService {
    private let config = AppConfig.shared
    private let localStore = LocalSavedJobsStore()

    func fetchSavedJobs(session: UserSession) async throws -> [JobListing] {
        try await fetchJobs(table: "saved_jobs", session: session, fallback: localStore.fetch(userID: session.userID))
    }

    func fetchAppliedJobs(session: UserSession) async throws -> [JobListing] {
        try await fetchJobs(table: "applied_jobs", session: session, fallback: localStore.fetchApplied(userID: session.userID))
    }

    func save(job: JobListing, session: UserSession) async throws {
        try await upsert(job: job, table: "saved_jobs", session: session)
        localStore.save(job, userID: session.userID)
    }

    func markApplied(job: JobListing, session: UserSession) async throws {
        try await upsert(job: job, table: "applied_jobs", session: session)
        localStore.markApplied(job, userID: session.userID)
    }

    func deleteSaved(job: JobListing, session: UserSession) async throws {
        try await delete(job: job, table: "saved_jobs", session: session)
        localStore.delete(job, userID: session.userID)
    }

    private func fetchJobs(table: String, session: UserSession, fallback: [JobListing]) async throws -> [JobListing] {
        guard let baseURL = config.supabaseURL else { return fallback }

        var components = URLComponents(url: baseURL.appending(path: "/rest/v1/\(table)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "select", value: "*"),
            .init(name: "user_id", value: "eq.\(session.userID.uuidString.lowercased())"),
            .init(name: "order", value: "created_at.desc")
        ]

        guard let url = components?.url else { return fallback }
        var request = authedRequest(url: url, session: session)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return fallback }
        guard (200...299).contains(http.statusCode) else {
            if isMissingTable(data: data, statusCode: http.statusCode) { return fallback }
            throw APIError.server("Could not load jobs.")
        }

        return try JSONDecoder.supabase.decode([SavedJobRecord].self, from: data).map { $0.job() }
    }

    private func upsert(job: JobListing, table: String, session: UserSession) async throws {
        guard let baseURL = config.supabaseURL else { return }

        var components = URLComponents(url: baseURL.appending(path: "/rest/v1/\(table)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [.init(name: "on_conflict", value: "user_id,job_id")]
        guard let url = components?.url else { return }

        var request = authedRequest(url: url, session: session)
        request.httpMethod = "POST"
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder.supabase.encode([SavedJobRecord(job: job, userID: session.userID)])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            if isMissingTable(data: data, statusCode: http.statusCode) { return }
            throw APIError.server("Could not save this job.")
        }
    }

    private func delete(job: JobListing, table: String, session: UserSession) async throws {
        guard let baseURL = config.supabaseURL else { return }

        var components = URLComponents(url: baseURL.appending(path: "/rest/v1/\(table)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "user_id", value: "eq.\(session.userID.uuidString.lowercased())"),
            .init(name: "job_id", value: "eq.\(job.id)")
        ]

        guard let url = components?.url else { return }
        var request = authedRequest(url: url, session: session)
        request.httpMethod = "DELETE"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            if isMissingTable(data: data, statusCode: http.statusCode) { return }
            throw APIError.server("Could not remove this job.")
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
}
