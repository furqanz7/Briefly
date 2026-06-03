import Foundation

@MainActor
final class JobsViewModel: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "For you"
        case remote = "Remote"
        case saved = "Saved"

        var id: String { rawValue }
    }

    enum Country: String, CaseIterable, Identifiable {
        case us = "US"
        case remote = "Remote"
        case uk = "UK"
        case canada = "Canada"
        case india = "India"

        var id: String { rawValue }

        var providerCode: String {
            switch self {
            case .us, .remote:
                return "us"
            case .uk:
                return "gb"
            case .canada:
                return "ca"
            case .india:
                return "in"
            }
        }

        var querySuffix: String {
            switch self {
            case .remote:
                return " remote"
            default:
                return ""
            }
        }
    }

    @Published private(set) var jobs: [JobListing] = []
    @Published private(set) var savedJobs: [JobListing] = []
    @Published private(set) var appliedJobs: [JobListing] = []
    @Published private(set) var passedJobs: [JobListing] = []
    @Published var selectedFilter: Filter = .all
    @Published var selectedCountry: Country = .us
    @Published var searchText = ""
    @Published var selectedJob: JobListing?
    @Published var isLoading = false
    @Published var isLoadingDetail = false
    @Published var errorMessage: String?
    @Published var providerMessage: String?

    private let service: JobsProviding
    private let savedStore: LocalSavedJobsStore
    private let savedService: SavedJobsService
    private let defaultQuery = "ios developer remote"
    let quickSearches = ["iOS", "Backend", "Product", "Design", "Remote"]

    init(
        service: JobsProviding = JobsService(),
        savedStore: LocalSavedJobsStore = LocalSavedJobsStore(),
        savedService: SavedJobsService = SavedJobsService()
    ) {
        self.service = service
        self.savedStore = savedStore
        self.savedService = savedService
    }

    var deckJobs: [JobListing] {
        let activeIDs = Set(savedJobs.map(\.id)).union(passedJobs.map(\.id))
        return filteredJobs.filter { !activeIDs.contains($0.id) }
    }

    var visibleJobs: [JobListing] {
        switch selectedFilter {
        case .saved:
            return filtered(savedJobs)
        case .all, .remote:
            return deckJobs
        }
    }

    var currentJob: JobListing? {
        visibleJobs.first
    }

    var savedCountText: String {
        "\(savedJobs.count) saved"
    }

    var activeQuery: String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = query.isEmpty ? defaultQuery : query
        return "\(base)\(selectedCountry.querySuffix)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func load(session: UserSession?) async {
        guard jobs.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        providerMessage = nil
        await loadAccountBackedJobs(session: session)
        do {
            jobs = try await service.fetchJobs(query: activeQuery, country: selectedCountry.providerCode)
        } catch {
            errorMessage = "Jobs are unavailable right now."
        }
        isLoading = false
    }

    func refresh(session: UserSession?) async {
        jobs = []
        passedJobs = []
        await load(session: session)
    }

    func search(session: UserSession?) async {
        isLoading = true
        errorMessage = nil
        providerMessage = nil
        passedJobs = []
        await loadAccountBackedJobs(session: session)
        do {
            jobs = try await service.fetchJobs(query: activeQuery, country: selectedCountry.providerCode)
        } catch {
            errorMessage = "No jobs matched that search yet."
        }
        isLoading = false
    }

    func chooseQuickSearch(_ query: String) {
        searchText = query
        if selectedFilter == .saved {
            selectedFilter = .all
        }
    }

    func saveCurrent(session: UserSession?) {
        guard let job = currentJob else { return }
        Task { await save(job, session: session) }
    }

    func save(_ job: JobListing, session: UserSession?) async {
        guard let session else {
            providerMessage = "Sign in before saving roles."
            return
        }
        savedJobs.removeAll { $0.id == job.id }
        savedJobs.insert(job, at: 0)
        savedStore.save(job, userID: session.userID)
        do {
            try await savedService.save(job: job, session: session)
        } catch {
            providerMessage = "Could not sync this saved job yet."
        }
    }

    func passCurrent() {
        guard let job = currentJob else { return }
        if !passedJobs.contains(job) {
            passedJobs.append(job)
        }
    }

    func restoreDeck() {
        passedJobs = []
        if selectedFilter != .saved {
            selectedFilter = .all
        }
    }

    func removeSaved(_ job: JobListing, session: UserSession?) async {
        guard let session else {
            providerMessage = "Sign in before editing saved roles."
            return
        }
        savedJobs.removeAll { $0.id == job.id }
        savedStore.delete(job, userID: session.userID)
        do {
            try await savedService.deleteSaved(job: job, session: session)
        } catch {
            providerMessage = "Could not sync this saved job yet."
        }
    }

    func markApplied(_ job: JobListing, session: UserSession?) async {
        guard let session else {
            providerMessage = "Sign in before marking jobs as applied."
            return
        }
        appliedJobs.removeAll { $0.id == job.id }
        appliedJobs.insert(job, at: 0)
        savedStore.markApplied(job, userID: session.userID)
        do {
            try await savedService.markApplied(job: job, session: session)
        } catch {
            providerMessage = "Could not sync this applied job yet."
        }
        NotificationCenter.default.post(name: AppNotifications.appliedJobsDidChange, object: nil)
    }

    func hasApplied(_ job: JobListing) -> Bool {
        appliedJobs.contains { $0.id == job.id }
    }

    func open(_ job: JobListing) {
        selectedJob = job
        Task {
            await loadDetail(for: job)
        }
    }

    func loadDetail(for job: JobListing) async {
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        do {
            let detail = try await service.fetchDetail(for: job, country: selectedCountry.providerCode)
            replace(job: detail)
            if selectedJob?.id == detail.id {
                selectedJob = detail
            }
        } catch {
            providerMessage = "Detailed job data is unavailable right now."
        }
    }

    private func replace(job: JobListing) {
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        }
        if let index = savedJobs.firstIndex(where: { $0.id == job.id }) {
            savedJobs[index] = job
        }
        if let index = appliedJobs.firstIndex(where: { $0.id == job.id }) {
            appliedJobs[index] = job
        }
    }

    private func loadAccountBackedJobs(session: UserSession?) async {
        guard let session else {
            savedJobs = []
            appliedJobs = []
            return
        }

        do {
            async let saved = savedService.fetchSavedJobs(session: session)
            async let applied = savedService.fetchAppliedJobs(session: session)
            savedJobs = try await saved
            appliedJobs = try await applied
            NotificationCenter.default.post(name: AppNotifications.appliedJobsDidChange, object: nil)
        } catch {
            savedJobs = savedStore.fetch(userID: session.userID)
            appliedJobs = savedStore.fetchApplied(userID: session.userID)
        }
    }

    private var filteredJobs: [JobListing] {
        var result = jobs

        if selectedFilter == .remote {
            result = result.filter { $0.workMode == .remote }
        }

        return result
    }

    private func filtered(_ source: [JobListing]) -> [JobListing] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return source }
        return source.filter { job in
            job.title.localizedCaseInsensitiveContains(query)
                || job.company.localizedCaseInsensitiveContains(query)
                || job.location.localizedCaseInsensitiveContains(query)
                || job.skills.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }
}
