const corsHeaders = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
}

type BudgetPeriod = "hour" | "day" | "month"
type JobsSource = "live" | "cached" | "stale" | "fixture"
type ProviderID = "jsearch" | "googlejobs" | "linkedin" | "indeed" | "yc" | "startupjobs" | "glassdoor" | "freelancer"

type JobListing = {
  id: string
  title: string
  company: string
  location: string
  workMode: "Remote" | "Hybrid" | "On-site"
  salary: string
  matchScore: number
  postedAt: string
  companySummary: string
  roleSummary: string
  skills: string[]
  perks: string[]
  requirements: string[]
  applyURL: string | null
}

type JobsResponse = {
  generatedAt: string
  source: JobsSource
  provider: string | null
  cacheHit: boolean
  stale: boolean
  updatedAt: string | null
  expiresAt: string | null
  message: string | null
  jobs: JobListing[]
}

type ProviderBudgetConfig = {
  period: BudgetPeriod
  autoLimit: number
  minRefreshMS: number
  quotaBackoffMS: number
  snapshotTTLMS: number
}

type ProviderUsageRecord = {
  provider_id: string
  period: BudgetPeriod
  window_started_at: string
  window_ends_at: string
  auto_limit: number
  used_count: number
  blocked_until: string | null
  last_attempt_at: string | null
  last_success_at: string | null
  last_error_at: string | null
  last_error: string | null
  updated_at: string | null
}

type ProviderSnapshotRecord<T> = {
  provider_id: string
  scope: string
  payload: T
  generated_at: string
  expires_at: string
  updated_at: string
}

const minuteMS = 60 * 1000
const dayMS = 24 * 60 * 60 * 1000

const providerBudgets: Record<ProviderID, ProviderBudgetConfig> = {
  jsearch: {
    period: "day",
    autoLimit: 80,
    minRefreshMS: 30 * minuteMS,
    quotaBackoffMS: 6 * 60 * minuteMS,
    snapshotTTLMS: 2 * dayMS,
  },
  googlejobs: {
    period: "day",
    autoLimit: 60,
    minRefreshMS: 45 * minuteMS,
    quotaBackoffMS: 6 * 60 * minuteMS,
    snapshotTTLMS: 2 * dayMS,
  },
  linkedin: {
    period: "day",
    autoLimit: 50,
    minRefreshMS: 60 * minuteMS,
    quotaBackoffMS: 6 * 60 * minuteMS,
    snapshotTTLMS: 2 * dayMS,
  },
  indeed: {
    period: "day",
    autoLimit: 50,
    minRefreshMS: 60 * minuteMS,
    quotaBackoffMS: 6 * 60 * minuteMS,
    snapshotTTLMS: 2 * dayMS,
  },
  yc: {
    period: "day",
    autoLimit: 8,
    minRefreshMS: 6 * 60 * minuteMS,
    quotaBackoffMS: 12 * 60 * minuteMS,
    snapshotTTLMS: 3 * dayMS,
  },
  startupjobs: {
    period: "day",
    autoLimit: 20,
    minRefreshMS: 3 * 60 * minuteMS,
    quotaBackoffMS: 12 * 60 * minuteMS,
    snapshotTTLMS: 3 * dayMS,
  },
  glassdoor: {
    period: "day",
    autoLimit: 30,
    minRefreshMS: 2 * 60 * minuteMS,
    quotaBackoffMS: 8 * 60 * minuteMS,
    snapshotTTLMS: 2 * dayMS,
  },
  freelancer: {
    period: "day",
    autoLimit: 40,
    minRefreshMS: 2 * 60 * minuteMS,
    quotaBackoffMS: 8 * 60 * minuteMS,
    snapshotTTLMS: 2 * dayMS,
  },
}

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders })
}

function iso(date = new Date()) {
  return date.toISOString().replace(/\.\d{3}Z$/, "Z")
}

function env(name: string) {
  return Deno.env.get(name)?.trim() ?? ""
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error)
}

function periodWindow(period: BudgetPeriod, now: number) {
  const date = new Date(now)
  let startedAt: Date
  let endsAt: Date

  if (period === "hour") {
    startedAt = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate(), date.getUTCHours()))
    endsAt = new Date(startedAt.getTime() + 60 * minuteMS)
  } else if (period === "month") {
    startedAt = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1))
    endsAt = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 1))
  } else {
    startedAt = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()))
    endsAt = new Date(startedAt.getTime() + dayMS)
  }

  return { startedAt: iso(startedAt), endsAt: iso(endsAt) }
}

function supabaseRESTCredentials() {
  const url = env("SUPABASE_URL")
  const key = env("SUPABASE_SERVICE_ROLE_KEY") || env("SUPABASE_SERVICE_KEY")
  if (!url || !key) return null
  return { baseURL: `${url.replace(/\/+$/, "")}/rest/v1`, key }
}

async function supabaseREST<T>(path: string, init: RequestInit = {}): Promise<T> {
  const credentials = supabaseRESTCredentials()
  if (!credentials) throw new Error("Supabase service role secret is not configured for jobs provider budgeting.")

  const response = await fetch(`${credentials.baseURL}/${path}`, {
    ...init,
    headers: {
      "apikey": credentials.key,
      "authorization": `Bearer ${credentials.key}`,
      "content-type": "application/json",
      ...(init.headers ?? {}),
    },
  })

  if (!response.ok) {
    const body = await response.text().catch(() => "")
    throw new Error(`Supabase jobs store: HTTP ${response.status} ${body.slice(0, 160)}`)
  }

  if (response.status === 204) return undefined as T
  const text = await response.text()
  return (text ? JSON.parse(text) : undefined) as T
}

function usageRecord(providerID: ProviderID, now: number): ProviderUsageRecord {
  const budget = providerBudgets[providerID]
  const window = periodWindow(budget.period, now)
  return {
    provider_id: providerID,
    period: budget.period,
    window_started_at: window.startedAt,
    window_ends_at: window.endsAt,
    auto_limit: budget.autoLimit,
    used_count: 0,
    blocked_until: null,
    last_attempt_at: null,
    last_success_at: null,
    last_error_at: null,
    last_error: null,
    updated_at: iso(new Date(now)),
  }
}

function normalizeUsage(providerID: ProviderID, record: ProviderUsageRecord | null, now: number) {
  const budget = providerBudgets[providerID]
  const current = usageRecord(providerID, now)
  if (!record) return current
  if (record.period !== budget.period || Date.parse(record.window_ends_at) <= now) return current
  return { ...record, auto_limit: budget.autoLimit }
}

async function readUsage(providerID: ProviderID) {
  if (!supabaseRESTCredentials()) return null
  const records = await supabaseREST<ProviderUsageRecord[]>(
    `jobs_provider_usage?provider_id=eq.${encodeURIComponent(providerID)}&select=*`
  )
  return records[0] ?? null
}

async function writeUsage(record: ProviderUsageRecord) {
  if (!supabaseRESTCredentials()) return
  await supabaseREST<void>("jobs_provider_usage?on_conflict=provider_id", {
    method: "POST",
    headers: { "Prefer": "resolution=merge-duplicates,return=minimal" },
    body: JSON.stringify(record),
  })
}

async function readSnapshot(providerID: ProviderID, scope: string) {
  if (!supabaseRESTCredentials()) return null
  const records = await supabaseREST<ProviderSnapshotRecord<JobListing[]>[]>(
    `jobs_provider_snapshots?provider_id=eq.${encodeURIComponent(providerID)}&scope=eq.${encodeURIComponent(scope)}&select=*`
  )
  return records[0] ?? null
}

async function writeSnapshot(providerID: ProviderID, scope: string, payload: JobListing[]) {
  if (!supabaseRESTCredentials()) return
  const now = Date.now()
  const budget = providerBudgets[providerID]
  await supabaseREST<void>("jobs_provider_snapshots?on_conflict=provider_id%2Cscope", {
    method: "POST",
    headers: { "Prefer": "resolution=merge-duplicates,return=minimal" },
    body: JSON.stringify({
      provider_id: providerID,
      scope,
      payload,
      generated_at: iso(new Date(now)),
      expires_at: iso(new Date(now + budget.snapshotTTLMS)),
      updated_at: iso(new Date(now)),
    }),
  })
}

function responseFromSnapshot(providerID: ProviderID, snapshot: ProviderSnapshotRecord<JobListing[]>, message: string | null = null): JobsResponse {
  const expires = Date.parse(snapshot.expires_at)
  return {
    generatedAt: iso(),
    source: expires > Date.now() ? "cached" : "stale",
    provider: providerID,
    cacheHit: true,
    stale: expires <= Date.now(),
    updatedAt: snapshot.generated_at,
    expiresAt: snapshot.expires_at,
    message,
    jobs: snapshot.payload,
  }
}

async function runWithBudget(providerID: ProviderID, scope: string, run: () => Promise<JobListing[]>): Promise<JobsResponse> {
  const persistentBudgetEnabled = Boolean(supabaseRESTCredentials())
  const budget = providerBudgets[providerID]
  const snapshot = await readSnapshot(providerID, scope)

  if (!persistentBudgetEnabled) {
    const jobs = await run()
    return liveResponse(providerID, jobs, null, null)
  }

  const now = Date.now()
  let usage = normalizeUsage(providerID, await readUsage(providerID), now)
  const generatedAt = snapshot ? Date.parse(snapshot.generated_at) : 0

  if (snapshot && generatedAt > 0 && now - generatedAt < budget.minRefreshMS) {
    return responseFromSnapshot(providerID, snapshot)
  }

  const blockedUntil = usage.blocked_until ? Date.parse(usage.blocked_until) : 0
  if (blockedUntil > now) {
    if (snapshot) return responseFromSnapshot(providerID, snapshot, `Showing cached jobs because ${providerLabel(providerID)} quota is paused.`)
    throw new Error(`${providerLabel(providerID)} is paused until ${iso(new Date(blockedUntil))}.`)
  }

  if (usage.used_count >= usage.auto_limit) {
    if (snapshot) return responseFromSnapshot(providerID, snapshot, `Showing cached jobs because ${providerLabel(providerID)} quota is exhausted.`)
    throw new Error(`${providerLabel(providerID)} automatic ${usage.period} quota is exhausted.`)
  }

  const nowISO = iso(new Date(now))
  usage = { ...usage, last_attempt_at: nowISO, updated_at: nowISO }
  await writeUsage(usage)

  try {
    const jobs = await run()
    await writeSnapshot(providerID, scope, jobs)
    await writeUsage({
      ...usage,
      used_count: usage.used_count + 1,
      blocked_until: null,
      last_success_at: nowISO,
      last_error_at: null,
      last_error: null,
      updated_at: nowISO,
    })
    return liveResponse(providerID, jobs, nowISO, iso(new Date(now + budget.snapshotTTLMS)))
  } catch (error) {
    const message = errorMessage(error)
    await writeUsage({
      ...usage,
      used_count: usage.used_count + 1,
      blocked_until: iso(new Date(now + budget.quotaBackoffMS)),
      last_error_at: nowISO,
      last_error: message.slice(0, 500),
      updated_at: nowISO,
    })
    if (snapshot) return responseFromSnapshot(providerID, snapshot, `Showing cached jobs because ${providerLabel(providerID)} failed.`)
    throw error
  }
}

function liveResponse(providerID: ProviderID, jobs: JobListing[], updatedAt: string | null, expiresAt: string | null): JobsResponse {
  return {
    generatedAt: iso(),
    source: "live",
    provider: providerID,
    cacheHit: false,
    stale: false,
    updatedAt,
    expiresAt,
    message: null,
    jobs,
  }
}

function combinedResponse(responses: JobsResponse[]): JobsResponse {
  const jobs = dedupeJobs(interleaveJobs(responses.map((response) => response.jobs))).slice(0, 40)
  const provider = responses
    .map((response) => response.provider)
    .filter(Boolean)
    .join(",")
  return {
    generatedAt: iso(),
    source: responses.some((response) => response.source === "live") ? "live" : responses[0]?.source ?? "cached",
    provider: provider || null,
    cacheHit: responses.every((response) => response.cacheHit),
    stale: responses.every((response) => response.stale),
    updatedAt: responses.map((response) => response.updatedAt).filter(Boolean).sort().at(-1) ?? null,
    expiresAt: responses.map((response) => response.expiresAt).filter(Boolean).sort()[0] ?? null,
    message: responses.map((response) => response.message).filter(Boolean).join(" ") || null,
    jobs,
  }
}

function interleaveJobs(groups: JobListing[][]) {
  const jobs: JobListing[] = []
  const max = Math.max(...groups.map((group) => group.length), 0)
  for (let index = 0; index < max; index += 1) {
    for (const group of groups) {
      const job = group[index]
      if (job) jobs.push(job)
    }
  }
  return jobs
}

function providerLabel(providerID: ProviderID) {
  if (providerID === "googlejobs") return "Google Jobs"
  if (providerID === "linkedin") return "LinkedIn Jobs"
  if (providerID === "indeed") return "Indeed"
  if (providerID === "yc") return "Y Combinator Jobs"
  if (providerID === "startupjobs") return "Startup Jobs"
  if (providerID === "glassdoor") return "Glassdoor"
  if (providerID === "freelancer") return "Freelancer"
  return "JSearch"
}

function dedupeJobs(jobs: JobListing[]) {
  const seen = new Set<string>()
  return jobs.filter((job) => {
    const key = `${job.title}|${job.company}|${job.location}`.toLowerCase().replace(/\s+/g, " ").trim()
    if (seen.has(key)) return false
    seen.add(key)
    return true
  })
}

function rapidAPIKey() {
  const apiKey = env("JSEARCH_RAPIDAPI_KEY") || env("RAPIDAPI_KEY")
  if (!apiKey) throw new Error("JSearch RapidAPI key is not configured.")
  return apiKey
}

function googleJobsAPIKey() {
  const apiKey = env("GOOGLE_JOBS_RAPIDAPI_KEY") || env("RAPIDAPI_KEY")
  if (!apiKey) throw new Error("Google Jobs RapidAPI key is not configured.")
  return apiKey
}

function linkedInJobsAPIKey() {
  const apiKey = env("LINKEDIN_JOBS_RAPIDAPI_KEY") || env("RAPIDAPI_KEY")
  if (!apiKey) throw new Error("LinkedIn Jobs RapidAPI key is not configured.")
  return apiKey
}

function indeedAPIKey() {
  const apiKey = env("INDEED_RAPIDAPI_KEY") || env("RAPIDAPI_KEY")
  if (!apiKey) throw new Error("Indeed RapidAPI key is not configured.")
  return apiKey
}

function ycJobsAPIKey() {
  const apiKey = env("YC_JOBS_RAPIDAPI_KEY") || env("RAPIDAPI_KEY")
  if (!apiKey) throw new Error("Y Combinator Jobs RapidAPI key is not configured.")
  return apiKey
}

function startupJobsAPIKey() {
  const apiKey = env("STARTUP_JOBS_RAPIDAPI_KEY") || env("RAPIDAPI_KEY")
  if (!apiKey) throw new Error("Startup Jobs RapidAPI key is not configured.")
  return apiKey
}

function glassdoorAPIKey() {
  const apiKey = env("GLASSDOOR_RAPIDAPI_KEY") || env("RAPIDAPI_KEY")
  if (!apiKey) throw new Error("Glassdoor RapidAPI key is not configured.")
  return apiKey
}

function freelancerAPIKey() {
  const apiKey = env("FREELANCER_RAPIDAPI_KEY") || env("RAPIDAPI_KEY")
  if (!apiKey) throw new Error("Freelancer RapidAPI key is not configured.")
  return apiKey
}

async function fetchJSearchJobs(query: string, country: string) {
  const apiKey = rapidAPIKey()
  const payload = await fetchJSearchPayload("/search-v2", query, country, apiKey)
    .catch(() => fetchJSearchPayload("/search", query, country, apiKey))

  const records = jobRecordsFromPayload(payload)
  const jobs = records.flatMap((value, index) => {
    if (!value || typeof value !== "object" || Array.isArray(value)) return []
    const job = jsearchRecordToJob(value as Record<string, unknown>, index)
    return job ? [job] : []
  })

  if (!jobs.length) throw new Error("JSearch: no usable jobs returned.")
  return jobs
}

async function fetchJSearchJobDetail(jobID: string, country: string, title: string | null, location: string | null) {
  const apiKey = rapidAPIKey()
  const url = new URL("https://jsearch.p.rapidapi.com/job-details")
  url.searchParams.set("job_id", jobID)
  url.searchParams.set("country", country)

  const payload = await fetchJSearchURL(url, apiKey, "JSearch details")
  const records = jobRecordsFromPayload(payload)
  const first = records.find((value) => value && typeof value === "object" && !Array.isArray(value))
  if (!first) throw new Error("JSearch details: no usable job returned.")

  const job = jsearchRecordToJob(first as Record<string, unknown>, 0)
  if (!job) throw new Error("JSearch details: missing title or company.")

  if (job.salary !== "Salary not listed") return [job]

  const salary = await fetchEstimatedSalary(title ?? job.title, location ?? job.location, country, apiKey)
    .catch(() => null)

  return [{
    ...job,
    salary: salary ?? job.salary,
  }]
}

async function fetchEstimatedSalary(title: string, location: string, country: string, apiKey: string) {
  const url = new URL("https://jsearch.p.rapidapi.com/estimated-salary")
  url.searchParams.set("job_title", title)
  url.searchParams.set("location", location)
  url.searchParams.set("country", country)
  url.searchParams.set("radius", "100")

  const payload = await fetchJSearchURL(url, apiKey, "JSearch salary")
  const records = salaryRecordsFromPayload(payload)
  const numbers = records.flatMap((value) => {
    if (!value || typeof value !== "object" || Array.isArray(value)) return []
    const record = value as Record<string, unknown>
    const min = numberFrom(record.min_salary ?? record.salary_min ?? record.publisher_min_salary)
    const max = numberFrom(record.max_salary ?? record.salary_max ?? record.publisher_max_salary)
    const median = numberFrom(record.median_salary ?? record.salary_median ?? record.salary)
    const currency = stringFrom(record.salary_currency) ?? stringFrom(record.currency) ?? "USD"
    const period = stringFrom(record.salary_period) ?? stringFrom(record.period) ?? "year"
    const text = salaryText(min ?? median, max ?? median, currency, period)
    return text === "Salary not listed" ? [] : [text]
  })
  return numbers[0] ?? null
}

async function fetchJSearchPayload(path: string, query: string, country: string, apiKey: string) {
  const url = new URL(`https://jsearch.p.rapidapi.com${path}`)
  url.searchParams.set("query", query)
  url.searchParams.set("page", "1")
  url.searchParams.set("num_pages", "1")
  url.searchParams.set("country", country)
  url.searchParams.set("date_posted", "all")

  return await fetchJSearchURL(url, apiKey, `JSearch ${path}`)
}

async function fetchJSearchURL(url: URL, apiKey: string, providerName: string) {
  const response = await fetch(url, {
    headers: {
      "x-rapidapi-key": apiKey,
      "x-rapidapi-host": "jsearch.p.rapidapi.com",
      "content-type": "application/json",
    },
  })
  const text = await response.text()
  if (!response.ok) throw new Error(`${providerName}: HTTP ${response.status} ${text.slice(0, 160)}`)

  try {
    return JSON.parse(text) as Record<string, unknown>
  } catch {
    throw new Error(`${providerName}: invalid JSON response`)
  }
}

function jobRecordsFromPayload(payload: Record<string, unknown>): unknown[] {
  if (Array.isArray(payload)) return payload
  if (Array.isArray(payload.data)) return payload.data
  if (Array.isArray(payload.jobs)) return payload.jobs
  if (Array.isArray(payload.items)) return payload.items
  if (Array.isArray(payload.records)) return payload.records
  if (Array.isArray(payload.jobResults)) return payload.jobResults
  if (Array.isArray(payload.job_results)) return payload.job_results
  if (Array.isArray(payload.posts)) return payload.posts
  if (Array.isArray(payload.hits)) return payload.hits
  if (Array.isArray(payload.results)) return payload.results
  if (Array.isArray(payload.jobListings)) return payload.jobListings
  if (payload.data && typeof payload.data === "object" && !Array.isArray(payload.data)) {
    const data = payload.data as Record<string, unknown>
    if (Array.isArray(data.jobs)) return data.jobs
    if (Array.isArray(data.results)) return data.results
    if (Array.isArray(data.jobListings)) return data.jobListings
    if (Array.isArray(data.data)) return data.data
    if (Array.isArray(data.items)) return data.items
    if (Array.isArray(data.records)) return data.records
    if (Array.isArray(data.jobResults)) return data.jobResults
    if (Array.isArray(data.job_results)) return data.job_results
    if (Array.isArray(data.posts)) return data.posts
    if (Array.isArray(data.hits)) return data.hits
  }
  for (const value of Object.values(payload)) {
    if (!value || typeof value !== "object" || Array.isArray(value)) continue
    const nested = value as Record<string, unknown>
    for (const key of ["jobs", "results", "items", "records", "data", "jobResults", "job_results", "jobListings", "posts", "hits"]) {
      if (Array.isArray(nested[key])) return nested[key]
    }
  }
  return []
}

function salaryRecordsFromPayload(payload: Record<string, unknown>): unknown[] {
  if (Array.isArray(payload.data)) return payload.data
  if (Array.isArray(payload.salaries)) return payload.salaries
  if (payload.data && typeof payload.data === "object" && !Array.isArray(payload.data)) {
    const data = payload.data as Record<string, unknown>
    if (Array.isArray(data.salaries)) return data.salaries
    if (Array.isArray(data.results)) return data.results
    return [data]
  }
  return []
}

function jsearchRecordToJob(record: Record<string, unknown>, index: number): JobListing | null {
  const id = stringFrom(record.job_id) ?? stringFrom(record.id) ?? `jsearch-${index}`
  const title = stringFrom(record.job_title) ?? stringFrom(record.title)
  const company = stringFrom(record.employer_name) ?? stringFrom(record.company_name)
  if (!title || !company) return null

  const city = stringFrom(record.job_city)
  const state = stringFrom(record.job_state)
  const country = stringFrom(record.job_country)
  const location = [city, state, country].filter(Boolean).join(", ") || stringFrom(record.job_location) || "Location flexible"
  const isRemote = Boolean(record.job_is_remote)
  const description = stringFrom(record.job_description) ?? "This role is listed through JSearch. Open the application link for the full description."
  const salaryMin = numberFrom(record.job_min_salary)
  const salaryMax = numberFrom(record.job_max_salary)
  const salaryCurrency = stringFrom(record.job_salary_currency) ?? "USD"
  const salaryPeriod = stringFrom(record.job_salary_period)
  const applyURL = stringFrom(record.job_apply_link) ?? stringFrom(record.job_google_link)

  return {
    id,
    title,
    company,
    location,
    workMode: isRemote ? "Remote" : "On-site",
    salary: salaryText(salaryMin, salaryMax, salaryCurrency, salaryPeriod),
    matchScore: Math.max(72, 96 - index * 3),
    postedAt: postedText(record),
    companySummary: stringFrom(record.employer_company_type)
      ? `${company} is hiring in ${stringFrom(record.employer_company_type)}.`
      : `${company} is hiring for this role through JSearch.`,
    roleSummary: truncate(description.replace(/\s+/g, " "), 260),
    skills: skillsFromText(description),
    perks: perksFromText(description),
    requirements: requirementsFromText(description),
    applyURL,
  }
}

async function fetchGoogleJobs(query: string) {
  const apiKey = googleJobsAPIKey()
  const payload = await fetchGoogleJobsPayload("/google-jobs/title", { title: query }, apiKey)
    .catch(() => fetchGoogleJobsPayload("/google-jobs/company", { company: firstSearchToken(query) }, apiKey))

  const records = jobRecordsFromPayload(payload)
  const jobs = records.flatMap((value, index) => {
    if (!value || typeof value !== "object" || Array.isArray(value)) return []
    const job = googleJobsRecordToJob(value as Record<string, unknown>, index)
    return job ? [job] : []
  })

  if (!jobs.length) throw new Error("Google Jobs: no usable jobs returned.")
  return jobs
}

async function fetchLinkedInJobs(query: string, country: string) {
  const apiKey = linkedInJobsAPIKey()
  const params = {
    offset: "0",
    title_filter: query,
    location_filter: linkedInLocationFilter(country),
    description_type: "text",
  }
  const payload = await fetchRapidPayload(
    "https://linkedin-job-search-api.p.rapidapi.com/active-jb-7d",
    params,
    apiKey,
    "linkedin-job-search-api.p.rapidapi.com",
    "LinkedIn Jobs"
  ).catch(() => fetchRapidPayload(
    "https://linkedin-job-search-api.p.rapidapi.com/active-jb-1h",
    params,
    apiKey,
    "linkedin-job-search-api.p.rapidapi.com",
    "LinkedIn Jobs"
  ))

  const jobs = jobsFromGenericPayload(payload, "linkedin", "LinkedIn Jobs", query)
  if (!jobs.length) throw new Error("LinkedIn Jobs: no usable jobs returned.")
  return jobs
}

async function fetchIndeedJobs(query: string, country: string) {
  const apiKey = indeedAPIKey()
  const payload = await fetchRapidPayload(
    "https://indeed12.p.rapidapi.com/jobs/search",
    {
      query,
      location: indeedLocation(country),
      page_id: "1",
      locality: indeedLocality(country),
      fromage: "14",
      radius: "50",
      sort: "date",
      job_type: "",
      start: "1",
    },
    apiKey,
    "indeed12.p.rapidapi.com",
    "Indeed"
  )

  const jobs = jobsFromGenericPayload(payload, "indeed", "Indeed", query)
  if (!jobs.length) throw new Error(`Indeed: no usable jobs returned from ${payloadShape(payload)}.`)
  return jobs
}

async function fetchYCJobs(query: string) {
  const apiKey = ycJobsAPIKey()
  const payload = await fetchRapidPayload(
    "https://free-y-combinator-jobs-api.p.rapidapi.com/active-jb-7d",
    {},
    apiKey,
    "free-y-combinator-jobs-api.p.rapidapi.com",
    "Y Combinator Jobs"
  )

  const jobs = jobsFromGenericPayload(payload, "yc", "Y Combinator Jobs", query)
  if (!jobs.length) throw new Error("Y Combinator Jobs: no usable jobs returned.")
  return jobs
}

async function fetchStartupJobs(query: string) {
  const apiKey = startupJobsAPIKey()
  const payload = await fetchRapidPayload(
    "https://startup-jobs-api.p.rapidapi.com/active-ats-7d",
    {},
    apiKey,
    "startup-jobs-api.p.rapidapi.com",
    "Startup Jobs"
  ).catch(() => fetchRapidPayload(
    "https://startup-jobs-api.p.rapidapi.com/active-jb-7d",
    {},
    apiKey,
    "startup-jobs-api.p.rapidapi.com",
    "Startup Jobs"
  ))

  const jobs = jobsFromGenericPayload(payload, "startupjobs", "Startup Jobs", query)
  if (!jobs.length) throw new Error("Startup Jobs: no usable jobs returned.")
  return jobs
}

async function fetchGlassdoorJobs(query: string, country: string) {
  const apiKey = glassdoorAPIKey()
  const locationPayload = await fetchRapidPayload(
    "https://glassdoor-real-time.p.rapidapi.com/jobs/search",
    {
      query,
      location: indeedLocation(country),
    },
    apiKey,
    "glassdoor-real-time.p.rapidapi.com",
    "Glassdoor"
  ).catch(() => fetchRapidPayload(
    "https://glassdoor-real-time.p.rapidapi.com/jobs/search",
    { query },
    apiKey,
    "glassdoor-real-time.p.rapidapi.com",
    "Glassdoor"
  ))

  const locationJobs = jobsFromGlassdoorPayload(locationPayload, query)
  if (locationJobs.length) return locationJobs

  const queryOnlyPayload = await fetchRapidPayload(
    "https://glassdoor-real-time.p.rapidapi.com/jobs/search",
    { query },
    apiKey,
    "glassdoor-real-time.p.rapidapi.com",
    "Glassdoor"
  )
  const jobs = jobsFromGlassdoorPayload(queryOnlyPayload, query)
  if (!jobs.length) throw new Error(`Glassdoor: no usable jobs returned from ${payloadShape(queryOnlyPayload)}.`)
  return jobs
}

function jobsFromGlassdoorPayload(payload: Record<string, unknown>, query: string) {
  return jobRecordsFromPayload(payload).flatMap((value, index) => {
    if (!value || typeof value !== "object" || Array.isArray(value)) return []
    const job = glassdoorRecordToJob(value as Record<string, unknown>, index)
    if (!job || !queryMatchesJob(job, query, "glassdoor")) return []
    return [job]
  })
}

async function fetchFreelancerJobs(query: string) {
  const apiKey = freelancerAPIKey()
  const payload = await fetchRapidPayload(
    "https://freelancer-api.p.rapidapi.com/api/find-job",
    {},
    apiKey,
    "freelancer-api.p.rapidapi.com",
    "Freelancer"
  ).catch(() => fetchRapidPayload(
    "https://freelancer-api.p.rapidapi.com/api/find-job/100",
    {},
    apiKey,
    "freelancer-api.p.rapidapi.com",
    "Freelancer"
  ))

  const jobs = jobsFromFreelancerPayload(payload, query)
  if (!jobs.length) throw new Error(`Freelancer: no usable jobs returned from ${payloadShape(payload)}.`)
  return jobs
}

async function fetchRapidPayload(baseURL: string, params: Record<string, string>, apiKey: string, host: string, providerName: string) {
  const url = new URL(baseURL)
  for (const [key, value] of Object.entries(params)) {
    if (value) url.searchParams.set(key, value)
  }

  const response = await fetch(url, {
    headers: {
      "x-rapidapi-key": apiKey,
      "x-rapidapi-host": host,
      "content-type": "application/json",
    },
  })
  const text = await response.text()
  if (!response.ok) throw new Error(`${providerName}: HTTP ${response.status} ${text.slice(0, 160)}`)

  try {
    return JSON.parse(text) as Record<string, unknown>
  } catch {
    throw new Error(`${providerName}: invalid JSON response`)
  }
}

function jobsFromGenericPayload(payload: Record<string, unknown>, providerID: ProviderID, label: string, query: string) {
  return jobRecordsFromPayload(payload).flatMap((value, index) => {
    if (!value || typeof value !== "object" || Array.isArray(value)) return []
    const job = genericJobRecordToJob(value as Record<string, unknown>, index, providerID, label)
    if (!job || !queryMatchesJob(job, query, providerID)) return []
    return [job]
  })
}

function jobsFromFreelancerPayload(payload: Record<string, unknown>, query: string) {
  const jobs = jobRecordsFromPayload(payload).flatMap((value, index) => {
    if (!value || typeof value !== "object" || Array.isArray(value)) return []
    const job = freelancerRecordToJob(value as Record<string, unknown>, index)
    if (!job || !queryMatchesJob(job, query, "freelancer")) return []
    return [job]
  })
  if (jobs.length) return jobs

  return jobRecordsFromPayload(payload).flatMap((value, index) => {
    if (!value || typeof value !== "object" || Array.isArray(value)) return []
    const job = freelancerRecordToJob(value as Record<string, unknown>, index)
    return job ? [job] : []
  })
}

function glassdoorRecordToJob(record: Record<string, unknown>, index: number): JobListing | null {
  const jobview = objectFrom(record.jobview) ?? record
  const header = objectFrom(jobview.header) ?? {}
  const jobRecord = objectFrom(jobview.job) ?? {}
  const employer = objectFrom(header.employer) ?? {}
  const title = firstString(jobRecord, ["jobTitleText", "title", "job_title"])
    ?? firstString(header, ["normalizedJobTitle"])
  const company = firstString(employer, ["name"])
    ?? firstString(header, ["employerNameFromSearch", "employerName", "companyName"])
  if (!title || !company) return null

  const rawID = firstString(jobRecord, ["listingId", "jobListingId", "id"])
    ?? firstString(header, ["jobResultTrackingKey", "adOrderId"])
    ?? [title, company, String(index)].join("-")
  const location = firstString(header, ["locationName", "location", "formattedLocation"])
    ?? "Location flexible"
  const attributes = glassdoorAttributes(header)
  const description = attributes.length
    ? `${title}. ${attributes.join(". ")}.`
    : `This role is listed through Glassdoor. Open the application link for the full posting.`
  const relativeURL = firstString(header, ["jobViewUrl"])
  const applyURL = relativeURL?.startsWith("http")
    ? relativeURL
    : relativeURL
      ? `https://www.glassdoor.com${relativeURL}`
      : null
  const salary = glassdoorSalaryText(header)
  const ageInDays = numberFrom(header.ageInDays)
  const postedAt = ageInDays === null ? "Recently" : ageInDays <= 0 ? "Today" : `${ageInDays} day${ageInDays === 1 ? "" : "s"} ago`
  const lower = `${location} ${attributes.join(" ")}`.toLowerCase()

  return {
    id: `glassdoor-${slug(rawID)}`,
    title,
    company,
    location,
    workMode: lower.includes("remote") ? "Remote" : lower.includes("hybrid") ? "Hybrid" : "On-site",
    salary,
    matchScore: Math.max(68, 90 - index * 2),
    postedAt,
    companySummary: `${company} is hiring for this role through Glassdoor.`,
    roleSummary: truncate(description.replace(/\s+/g, " "), 260),
    skills: attributes.slice(0, 5).length ? attributes.slice(0, 5) : skillsFromText(description),
    perks: perksFromText(description),
    requirements: requirementsFromText(description),
    applyURL,
  }
}

function glassdoorAttributes(header: Record<string, unknown>) {
  const indeedJobAttribute = objectFrom(header.indeedJobAttribute)
  const extracted = Array.isArray(indeedJobAttribute?.extractedJobAttributes)
    ? indeedJobAttribute.extractedJobAttributes
    : []
  return extracted.flatMap((value) => {
    if (!value || typeof value !== "object" || Array.isArray(value)) return []
    const text = stringFrom((value as Record<string, unknown>).value)
    return text ? [text] : []
  })
}

function glassdoorSalaryText(header: Record<string, unknown>) {
  const currency = stringFrom(header.payCurrency) ?? "USD"
  const period = stringFrom(header.payPeriod)
  const adjusted = objectFrom(header.payPeriodAdjustedPay)
  const min = numberFrom(adjusted?.min)
  const max = numberFrom(adjusted?.max)
  return salaryText(min, max, currency, period)
}

function objectFrom(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null
}

function payloadShape(value: unknown, depth = 0): string {
  if (Array.isArray(value)) return `array(${value.length})`
  if (!value || typeof value !== "object") return typeof value
  const record = value as Record<string, unknown>
  const keys = Object.keys(record).slice(0, 10)
  if (depth >= 1) return `object(${keys.join(",")})`
  return `object(${keys.map((key) => `${key}:${payloadShape(record[key], depth + 1)}`).join(";")})`
}

function genericJobRecordToJob(record: Record<string, unknown>, index: number, providerID: ProviderID, label: string): JobListing | null {
  const title = firstString(record, ["title", "job_title", "position", "role", "name", "jobTitle", "jobName", "job_title_text", "jobTitleText"])
  const company = firstString(record, ["company", "company_name", "companyName", "organization", "org", "employer_name", "employerName", "employer", "hiring_company"])
  if (!title || !company) return null

  const location = firstString(record, ["location", "job_location", "locations", "city", "country", "formatted_location", "location_name", "workplace"])
    ?? "Location flexible"
  const description = firstString(record, ["description", "job_description", "summary", "snippet", "body", "text", "description_text", "plain_text_description", "descriptionPlainText"])
    ?? `This role is listed through ${label}. Open the application link for the full posting.`
  const salary = firstString(record, ["salary", "salary_text", "compensation", "pay", "base_salary"])
    ?? "Salary not listed"
  const applyURL = firstString(record, ["url", "link", "job_url", "jobUrl", "apply_url", "applyUrl", "application_url", "job_apply_link", "linkedin_url", "external_url"])
  const rawID = firstString(record, ["id", "job_id", "jobId", "listingId", "jobListingId", "linkedin_job_id", "indeed_id", "posting_id", "jobPostingId", "ats_job_id"])
    ?? [title, company, location, String(index)].join("-")
  const postedAt = firstString(record, ["posted_at", "date_posted", "created_at", "indexed_at", "published_at", "postedDate", "posted_time"])
    ?? "Recently"
  const lower = `${location} ${description}`.toLowerCase()

  return {
    id: `${providerID}-${slug(rawID)}`,
    title,
    company,
    location,
    workMode: lower.includes("remote") ? "Remote" : lower.includes("hybrid") ? "Hybrid" : "On-site",
    salary,
    matchScore: Math.max(68, 91 - index * 2),
    postedAt,
    companySummary: `${company} is hiring for this role through ${label}.`,
    roleSummary: truncate(description.replace(/\s+/g, " "), 260),
    skills: skillsFromText(description),
    perks: perksFromText(description),
    requirements: requirementsFromText(description),
    applyURL,
  }
}

function freelancerRecordToJob(record: Record<string, unknown>, index: number): JobListing | null {
  const title = firstString(record, ["title", "name", "project_title", "project-title", "projectName", "job_title", "position"])
  if (!title) return null

  const company = firstString(record, ["client", "client_name", "employer", "employer_name", "owner", "username", "buyer", "company"])
    ?? "Freelancer client"
  const location = firstString(record, ["location", "country", "city"])
    ?? "Remote freelance"
  const description = firstString(record, ["description", "project-description", "summary", "snippet", "body", "text", "content", "excerpt"])
    ?? "This freelance opportunity is listed through Freelancer. Open the application link for the full brief."
  const rawID = firstString(record, ["id", "job_id", "project_id", "projectId", "seo_url", "project-link", "guid"])
    ?? [title, company, location, String(index)].join("-")
  const applyURL = firstString(record, ["url", "link", "project-link", "job_url", "project_url", "seo_url", "apply_url", "guid"])
  const salary = freelancerBudgetText(record)
  const postedAt = firstString(record, ["posted_at", "created_at", "date_posted", "time_submitted", "submitdate"])
    ?? "Recently"

  return {
    id: `freelancer-${slug(rawID)}`,
    title,
    company,
    location,
    workMode: "Remote",
    salary,
    matchScore: Math.max(66, 88 - index * 2),
    postedAt,
    companySummary: `${company} is sourcing this project through Freelancer.`,
    roleSummary: truncate(description.replace(/\s+/g, " "), 260),
    skills: skillsFromText(description),
    perks: perksFromText(description),
    requirements: requirementsFromText(description),
    applyURL,
  }
}

function freelancerBudgetText(record: Record<string, unknown>) {
  const direct = firstString(record, ["budget", "budget_text", "salary", "price", "project-price", "compensation"])
  if (direct) return direct

  const currency = firstString(record, ["currency", "currency_code"]) ?? "USD"
  const min = numberFrom(record.min_budget) ?? numberFrom(record.budget_min) ?? numberFrom(record.minimum_budget)
  const max = numberFrom(record.max_budget) ?? numberFrom(record.budget_max) ?? numberFrom(record.maximum_budget)
  if (min || max) return salaryText(min, max, currency, "project")
  return "Budget not listed"
}

function firstString(record: Record<string, unknown>, keys: string[]) {
  for (const key of keys) {
    const direct = stringFrom(record[key])
    if (direct) return direct
    if (Array.isArray(record[key])) {
      const values = record[key].flatMap((value) => {
        const text = stringFrom(value)
        return text ? [text] : []
      })
      if (values.length) return values.join(", ")
    }
    if (record[key] && typeof record[key] === "object") {
      const nested = record[key] as Record<string, unknown>
      const nestedText = stringFrom(nested.name)
        ?? stringFrom(nested.title)
        ?? stringFrom(nested.value)
        ?? stringFrom(nested.text)
        ?? stringFrom(nested.rendered)
        ?? stringFrom(nested.href)
      if (nestedText) return nestedText
    }
  }
  return null
}

function queryMatchesJob(job: JobListing, query: string, providerID: ProviderID) {
  if (providerID === "yc" || providerID === "startupjobs") return true
  const tokens = query
    .toLowerCase()
    .split(/[^a-z0-9+#.]+/)
    .filter((token) => token.length > 2 && !["job", "jobs", "remote", "senior"].includes(token))
  if (!tokens.length) return true
  const haystack = `${job.title} ${job.company} ${job.location} ${job.roleSummary} ${job.skills.join(" ")}`.toLowerCase()
  return tokens.some((token) => haystack.includes(token))
}

function linkedInLocationFilter(country: string) {
  const normalized = country.toLowerCase()
  if (normalized === "us" || normalized === "usa") return "United States"
  if (normalized === "gb" || normalized === "uk") return "United Kingdom"
  if (normalized === "ca") return "Canada"
  if (normalized === "au") return "Australia"
  if (normalized === "in") return "India"
  return country
}

function indeedLocality(country: string) {
  const normalized = country.toLowerCase()
  if (normalized === "usa") return "us"
  if (normalized === "uk") return "gb"
  return normalized || "us"
}

function indeedLocation(country: string) {
  const normalized = country.toLowerCase()
  if (normalized === "us" || normalized === "usa") return "united states"
  if (normalized === "gb" || normalized === "uk") return "united kingdom"
  if (normalized === "ca") return "canada"
  if (normalized === "au") return "australia"
  if (normalized === "in") return "india"
  return country
}

async function fetchGoogleJobsPayload(path: string, params: Record<string, string>, apiKey: string) {
  const url = new URL(`https://google-jobs-api.p.rapidapi.com${path}`)
  for (const [key, value] of Object.entries(params)) {
    url.searchParams.set(key, value)
  }

  const response = await fetch(url, {
    headers: {
      "x-rapidapi-key": apiKey,
      "x-rapidapi-host": "google-jobs-api.p.rapidapi.com",
      "content-type": "application/json",
    },
  })
  const text = await response.text()
  if (!response.ok) throw new Error(`Google Jobs ${path}: HTTP ${response.status} ${text.slice(0, 160)}`)

  try {
    return JSON.parse(text) as Record<string, unknown>
  } catch {
    throw new Error(`Google Jobs ${path}: invalid JSON response`)
  }
}

function googleJobsRecordToJob(record: Record<string, unknown>, index: number): JobListing | null {
  const title = stringFrom(record.title) ?? stringFrom(record.job_title) ?? stringFrom(record.position)
  const company = googleCompanyFromRecord(record, title)
  if (!title || !company || company.toLowerCase() === "unknown") return null

  const id = `googlejobs-${slug([title, company, stringFrom(record.location) ?? stringFrom(record.job_location) ?? String(index)].join("-"))}`
  const location = stringFrom(record.location) ?? stringFrom(record.job_location) ?? stringFrom(record.place) ?? "Location flexible"
  const description = stringFrom(record.description)
    ?? stringFrom(record.job_description)
    ?? stringFrom(record.snippet)
    ?? stringFrom(record.summary)
    ?? "This role is listed through Google Jobs. Open the application link for the full posting."
  const salary = stringFrom(record.salary)
    ?? stringFrom(record.salary_text)
    ?? stringFrom(record.compensation)
    ?? "Salary not listed"
  const applyURL = stringFrom(record.apply_link)
    ?? stringFrom(record.applyURL)
    ?? stringFrom(record.url)
    ?? stringFrom(record.link)
    ?? stringFrom(record.share_link)
  if (isWeakGoogleJobsResult(title, company, applyURL)) return null
  const lower = `${location} ${description}`.toLowerCase()

  return {
    id,
    title,
    company,
    location,
    workMode: lower.includes("remote") ? "Remote" : "On-site",
    salary,
    matchScore: Math.max(70, 92 - index * 3),
    postedAt: stringFrom(record.posted_at) ?? stringFrom(record.date_posted) ?? stringFrom(record.detected_extensions) ?? "Recently",
    companySummary: `${company} is hiring for this role through Google Jobs.`,
    roleSummary: truncate(description.replace(/\s+/g, " "), 260),
    skills: skillsFromText(description),
    perks: perksFromText(description),
    requirements: requirementsFromText(description),
    applyURL,
  }
}

function isWeakGoogleJobsResult(title: string, company: string, applyURL: string | null) {
  const lowerTitle = title.toLowerCase()
  const lowerCompany = company.toLowerCase()
  const lowerURL = applyURL?.toLowerCase() ?? ""
  if (lowerTitle.includes("best ") && lowerTitle.includes(" jobs in ")) return true
  if (lowerTitle.match(/^[\d,]+\+? .* jobs in /)) return true
  if (lowerCompany.includes(" jobs")) return true
  if (normalizeJobText(lowerCompany) === normalizeJobText(lowerTitle)) return true
  if (["linkedin", "ziprecruiter", "indeed", "jobleads", "jobijoba"].includes(lowerCompany)) return true
  return [
    "reddit.com",
    "quora.com",
    "finance.yahoo.com",
    "news.google.com",
    "indeed.com",
    "bebee.com",
    "linkedin.com/in/",
    "jobleads.com",
    "jobrapido.com",
    "jobijoba.",
  ].some((domain) => lowerURL.includes(domain))
}

function googleCompanyFromRecord(record: Record<string, unknown>, title: string | null) {
  const rawCompany = stringFrom(record.company) ?? stringFrom(record.company_name) ?? stringFrom(record.employer_name)
  if (!title) return rawCompany

  const parts = title.split(/\s+-\s+/).map((part) => part.trim()).filter(Boolean)
  const suffix = parts.length > 1 ? parts.at(-1) ?? null : null
  const atCompany = title.match(/\s@\s([^-|]+?)(?:\s+-\s+|$)/)?.[1]?.trim() ?? null
  if (!rawCompany) return cleanCompanyName(suffix)

  const normalizedCompany = normalizeJobText(rawCompany)
  const normalizedTitleLead = normalizeJobText(parts[0] ?? title)
  if (suffix && (normalizedCompany === normalizedTitleLead || normalizedCompany.includes("job"))) {
    return cleanCompanyName(atCompany) ?? cleanCompanyName(suffix) ?? rawCompany
  }

  return cleanCompanyName(rawCompany)
}

function cleanCompanyName(value: string | null) {
  if (!value) return null
  const cleaned = value
    .replace(/\bcareers\b/ig, "")
    .replace(/\bjobs\b/ig, "")
    .replace(/\s+/g, " ")
    .trim()
  return cleaned.length ? cleaned : null
}

function normalizeJobText(value: string) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim()
}

function firstSearchToken(query: string) {
  return query
    .split(/\s+/)
    .find((part) => part.length > 2)
    ?? query
}

function slug(value: string) {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 90)
}

function salaryText(min: number | null, max: number | null, currency: string, period: string | null) {
  if (min === null && max === null) return "Salary not listed"
  const formatter = new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: currency.length === 3 ? currency : "USD",
    maximumFractionDigits: 0,
  })
  const suffix = period ? ` / ${period.toLowerCase()}` : ""
  if (min !== null && max !== null) return `${formatter.format(min)} - ${formatter.format(max)}${suffix}`
  return `${formatter.format(min ?? max ?? 0)}${suffix}`
}

function postedText(record: Record<string, unknown>) {
  return stringFrom(record.job_posted_at) ?? stringFrom(record.job_posted_at_datetime_utc) ?? "Recently"
}

function skillsFromText(text: string) {
  const common = ["Swift", "SwiftUI", "iOS", "React", "TypeScript", "Python", "SQL", "Postgres", "AWS", "Design", "Product", "Data"]
  const hits = common.filter((skill) => text.toLowerCase().includes(skill.toLowerCase()))
  return hits.length ? hits.slice(0, 5) : ["Communication", "Ownership", "Execution"]
}

function perksFromText(text: string) {
  const lower = text.toLowerCase()
  const perks = [
    lower.includes("remote") ? "Remote flexibility" : null,
    lower.includes("equity") ? "Equity" : null,
    lower.includes("health") ? "Health benefits" : null,
    lower.includes("pto") || lower.includes("vacation") ? "Paid time off" : null,
  ].filter(Boolean) as string[]
  return perks.length ? perks : ["Competitive package", "Growth role"]
}

function requirementsFromText(text: string) {
  const sentences = text
    .split(/[.\n]/)
    .map((part) => part.trim())
    .filter((part) => part.length > 45 && part.length < 180)
  return sentences.slice(0, 3).length ? sentences.slice(0, 3) : [
    "Relevant experience for the role",
    "Strong communication and execution",
    "Ability to work with a fast-moving team",
  ]
}

function truncate(value: string, limit: number) {
  if (value.length <= limit) return value
  return `${value.slice(0, limit - 1).trim()}...`
}

function stringFrom(value: unknown) {
  if (typeof value === "string") {
    const trimmed = value
      .replace(/<[^>]*>/g, " ")
      .replace(/&nbsp;/g, " ")
      .replace(/&amp;/g, "&")
      .replace(/&quot;/g, "\"")
      .replace(/&#039;/g, "'")
      .replace(/\s+/g, " ")
      .trim()
    return trimmed.length === 0 ? null : trimmed
  }
  if (typeof value === "number" && Number.isFinite(value)) return String(value)
  return null
}

function numberFrom(value: unknown) {
  if (typeof value === "number" && Number.isFinite(value)) return value
  if (typeof value === "string") {
    const parsed = Number.parseFloat(value.replace(/,/g, ""))
    return Number.isFinite(parsed) ? parsed : null
  }
  return null
}

const fixtureJobs: JobListing[] = [
  {
    id: "fixture-ios",
    title: "Senior iOS Engineer",
    company: "Northstar Labs",
    location: "New York, NY",
    workMode: "Hybrid",
    salary: "$170K - $220K",
    matchScore: 94,
    postedAt: "2 hr ago",
    companySummary: "A product studio building fast consumer workflows for finance, news, and personal intelligence.",
    roleSummary: "Own SwiftUI surfaces from prototype to App Store release, polish interaction details, and wire production data into a premium mobile experience.",
    skills: ["SwiftUI", "iOS", "Async/Await", "Charts"],
    perks: ["Equity", "Flexible PTO", "Design-heavy team"],
    requirements: ["5+ years shipping iOS apps", "Strong SwiftUI layout and state management", "Comfortable with API-backed consumer products"],
    applyURL: "https://example.com/jobs/ios",
  },
]

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders })
  if (request.method !== "GET") return json(405, { error: "Method not allowed" })

  const url = new URL(request.url)
  const jobID = url.searchParams.get("job_id")?.trim()
  const query = url.searchParams.get("q")?.trim() || "ios developer remote"
  const country = url.searchParams.get("country")?.trim() || "us"
  const title = url.searchParams.get("title")?.trim() || null
  const location = url.searchParams.get("location")?.trim() || null
  const scope = jobID
    ? `detail:${country}:${jobID}`
    : `search:${country}:${query.toLowerCase()}`

  try {
    const response = jobID
      ? await fetchJobDetailWithProviders(jobID, country, title, location, scope)
      : await fetchSearchWithProviders(query, country, scope)
    return json(200, response)
  } catch (error) {
    return json(200, {
      generatedAt: iso(),
      source: "fixture",
      provider: null,
      cacheHit: false,
      stale: true,
      updatedAt: null,
      expiresAt: null,
      message: errorMessage(error),
      jobs: fixtureJobs,
    } satisfies JobsResponse)
  }
})

async function fetchSearchWithProviders(query: string, country: string, scope: string) {
  const responses: JobsResponse[] = []
  const errors: string[] = []

  for (const provider of [
    { id: "jsearch" as const, run: () => fetchJSearchJobs(query, country) },
    { id: "googlejobs" as const, run: () => fetchGoogleJobs(query) },
    { id: "linkedin" as const, run: () => fetchLinkedInJobs(query, country) },
    { id: "indeed" as const, run: () => fetchIndeedJobs(query, country) },
    { id: "glassdoor" as const, run: () => fetchGlassdoorJobs(query, country) },
    { id: "freelancer" as const, run: () => fetchFreelancerJobs(query) },
    { id: "yc" as const, run: () => fetchYCJobs(query) },
    { id: "startupjobs" as const, run: () => fetchStartupJobs(query) },
  ]) {
    try {
      const response = await runWithBudget(provider.id, scope, provider.run)
      if (response.jobs.length) responses.push(response)
    } catch (error) {
      errors.push(errorMessage(error))
    }
  }

  if (responses.length) return combinedResponse(responses)
  throw new Error(errors.join(" | ") || "No jobs are available yet.")
}

async function fetchJobDetailWithProviders(jobID: string, country: string, title: string | null, location: string | null, scope: string) {
  if (jobID.startsWith("googlejobs-")) {
    const response = await runWithBudget("googlejobs", scope, () => fetchGoogleJobs(title ?? location ?? jobID))
    return responseWithBestDetailMatch(response, jobID)
  }

  if (jobID.startsWith("linkedin-")) {
    const response = await runWithBudget("linkedin", scope, () => fetchLinkedInJobs(title ?? location ?? jobID, country))
    return responseWithBestDetailMatch(response, jobID)
  }

  if (jobID.startsWith("indeed-")) {
    const response = await runWithBudget("indeed", scope, () => fetchIndeedJobs(title ?? location ?? jobID, country))
    return responseWithBestDetailMatch(response, jobID)
  }

  if (jobID.startsWith("glassdoor-")) {
    const response = await runWithBudget("glassdoor", scope, () => fetchGlassdoorJobs(title ?? location ?? jobID, country))
    return responseWithBestDetailMatch(response, jobID)
  }

  if (jobID.startsWith("freelancer-")) {
    const response = await runWithBudget("freelancer", scope, () => fetchFreelancerJobs(title ?? location ?? jobID))
    return responseWithBestDetailMatch(response, jobID)
  }

  if (jobID.startsWith("yc-")) {
    const response = await runWithBudget("yc", scope, () => fetchYCJobs(title ?? location ?? jobID))
    return responseWithBestDetailMatch(response, jobID)
  }

  if (jobID.startsWith("startupjobs-")) {
    const response = await runWithBudget("startupjobs", scope, () => fetchStartupJobs(title ?? location ?? jobID))
    return responseWithBestDetailMatch(response, jobID)
  }

  return await runWithBudget(
    "jsearch",
    scope,
    () => fetchJSearchJobDetail(jobID, country, title, location)
  )
}

function responseWithBestDetailMatch(response: JobsResponse, jobID: string) {
  const exact = response.jobs.filter((job) => job.id === jobID).slice(0, 1)
  return {
    ...response,
    jobs: exact.length ? exact : response.jobs.slice(0, 1),
  }
}
