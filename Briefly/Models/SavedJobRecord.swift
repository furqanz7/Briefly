import Foundation

struct SavedJobRecord: Codable {
    let id: UUID?
    let userID: UUID
    let jobID: String
    let title: String
    let company: String
    let location: String
    let workMode: String
    let salary: String
    let matchScore: Int
    let postedAt: String
    let companySummary: String
    let roleSummary: String
    let skills: [String]
    let perks: [String]
    let requirements: [String]
    let applyURL: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case jobID = "job_id"
        case title
        case company
        case location
        case workMode = "work_mode"
        case salary
        case matchScore = "match_score"
        case postedAt = "posted_at"
        case companySummary = "company_summary"
        case roleSummary = "role_summary"
        case skills
        case perks
        case requirements
        case applyURL = "apply_url"
        case createdAt = "created_at"
    }

    init(job: JobListing, userID: UUID) {
        id = nil
        self.userID = userID
        jobID = job.id
        title = job.title
        company = job.company
        location = job.location
        workMode = job.workMode.rawValue
        salary = job.salary
        matchScore = job.matchScore
        postedAt = job.postedAt
        companySummary = job.companySummary
        roleSummary = job.roleSummary
        skills = job.skills
        perks = job.perks
        requirements = job.requirements
        applyURL = job.applyURL?.absoluteString
        createdAt = nil
    }

    func job() -> JobListing {
        JobListing(
            id: jobID,
            title: title,
            company: company,
            location: location,
            workMode: JobListing.WorkMode(rawValue: workMode) ?? .remote,
            salary: salary,
            matchScore: matchScore,
            postedAt: postedAt,
            companySummary: companySummary,
            roleSummary: roleSummary,
            skills: skills,
            perks: perks,
            requirements: requirements,
            applyURL: applyURL.flatMap(URL.init(string:))
        )
    }
}
