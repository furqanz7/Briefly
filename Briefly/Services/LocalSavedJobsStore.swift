import Foundation

struct LocalSavedJobsStore {
    private let savedStorageKey = "local_saved_jobs_v1"
    private let appliedStorageKey = "local_applied_jobs_v1"

    func fetch() -> [JobListing] {
        fetch(key: savedStorageKey)
    }

    func fetchApplied() -> [JobListing] {
        fetch(key: appliedStorageKey)
    }

    func save(_ job: JobListing) {
        var jobs = fetch()
        jobs.removeAll { $0.id == job.id }
        jobs.insert(job, at: 0)
        persist(jobs, key: savedStorageKey)
    }

    func markApplied(_ job: JobListing) {
        var jobs = fetchApplied()
        jobs.removeAll { $0.id == job.id }
        jobs.insert(job, at: 0)
        persist(jobs, key: appliedStorageKey)
    }

    func update(_ job: JobListing) {
        var jobs = fetch()
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        jobs[index] = job
        persist(jobs, key: savedStorageKey)
    }

    func updateApplied(_ job: JobListing) {
        var jobs = fetchApplied()
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        jobs[index] = job
        persist(jobs, key: appliedStorageKey)
    }

    func delete(_ job: JobListing) {
        var jobs = fetch()
        jobs.removeAll { $0.id == job.id }
        persist(jobs, key: savedStorageKey)
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
}
