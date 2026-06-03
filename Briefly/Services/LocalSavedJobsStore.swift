import Foundation

struct LocalSavedJobsStore {
    private let savedStorageKey = "local_saved_jobs_v1"
    private let appliedStorageKey = "local_applied_jobs_v1"

    func fetch(userID: UUID) -> [JobListing] {
        fetch(key: key(savedStorageKey, userID: userID))
    }

    func fetchApplied(userID: UUID) -> [JobListing] {
        fetch(key: key(appliedStorageKey, userID: userID))
    }

    func save(_ job: JobListing, userID: UUID) {
        var jobs = fetch(userID: userID)
        jobs.removeAll { $0.id == job.id }
        jobs.insert(job, at: 0)
        persist(jobs, key: key(savedStorageKey, userID: userID))
    }

    func markApplied(_ job: JobListing, userID: UUID) {
        var jobs = fetchApplied(userID: userID)
        jobs.removeAll { $0.id == job.id }
        jobs.insert(job, at: 0)
        persist(jobs, key: key(appliedStorageKey, userID: userID))
    }

    func update(_ job: JobListing, userID: UUID) {
        var jobs = fetch(userID: userID)
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        jobs[index] = job
        persist(jobs, key: key(savedStorageKey, userID: userID))
    }

    func updateApplied(_ job: JobListing, userID: UUID) {
        var jobs = fetchApplied(userID: userID)
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        jobs[index] = job
        persist(jobs, key: key(appliedStorageKey, userID: userID))
    }

    func delete(_ job: JobListing, userID: UUID) {
        var jobs = fetch(userID: userID)
        jobs.removeAll { $0.id == job.id }
        persist(jobs, key: key(savedStorageKey, userID: userID))
    }

    private func fetch(key: String) -> [JobListing] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let jobs = try? JSONDecoder.supabase.decode([JobListing].self, from: data) else {
            return []
        }
        return jobs
    }

    private func persist(_ jobs: [JobListing], key: String) {
        guard let data = try? JSONEncoder.supabase.encode(jobs) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func key(_ base: String, userID: UUID) -> String {
        "\(base)_\(userID.uuidString.lowercased())"
    }
}
