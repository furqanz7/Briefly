const corsHeaders = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
}

type SportConfig = {
  id: string
  name: string
  icon: string
  providerPath: string
}

type LiveMatch = {
  id: string
  providerID: string | null
  detailID: string | null
  sportID: string
  sportName: string
  competitionID: string
  competitionName: string
  country: string | null
  status: string
  statusDetail: string | null
  clock: string | null
  period: string | null
  startsAt: string | null
  homeName: string
  awayName: string
  homeScore: string | null
  awayScore: string | null
  scoreSummary: string | null
  homeLogoURL: string | null
  awayLogoURL: string | null
  venue: string | null
  note: string | null
  scoreboardSections: ScoreboardSection[] | null
}

type ScoreboardSection = {
  id: string
  title: string
  subtitle: string | null
  columns: string[]
  rows: ScoreboardRow[]
}

type ScoreboardRow = {
  id: string
  cells: string[]
  note: string | null
}

type LiveCompetition = {
  id: string
  name: string
  country: string | null
  matches: LiveMatch[]
}

type LiveSportSection = {
  id: string
  name: string
  icon: string
  competitions: LiveCompetition[]
}

type LiveScoresResponse = {
  generatedAt: string
  cacheHit: boolean
  providerConfigured: boolean
  message: string | null
  sports: LiveSportSection[]
  upcomingSports: LiveSportSection[]
  recentSports: LiveSportSection[]
}

type LiveMatchDetailResponse = {
  generatedAt: string
  match: LiveMatch
  scoreboardSections: ScoreboardSection[]
}

type CacheEntry = {
  expiresAt: number
  payload: LiveScoresResponse
}

type ProviderBackoffEntry = {
  until: number
  message: string
}

type ProviderSource = {
  id: string
  name: string
  sportID: string
  scope: string
  run: () => Promise<LiveSportSection>
}

type ProviderBudgetPeriod = "hour" | "day" | "month"

type ProviderBudgetConfig = {
  period: ProviderBudgetPeriod
  autoLimit: number
  minRefreshMS: number
  detailMinRefreshMS: number
  quotaBackoffMS: number
  snapshotTTLMS: number
}

type ProviderUsageRecord = {
  provider_id: string
  period: ProviderBudgetPeriod
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

const sports: SportConfig[] = [
  { id: "cricket", name: "Cricket", icon: "figure.cricket", providerPath: "cricket" },
  { id: "soccer", name: "Soccer", icon: "soccerball", providerPath: "football" },
  { id: "baseball", name: "Baseball", icon: "baseball.fill", providerPath: "baseball" },
  { id: "basketball", name: "Basketball", icon: "basketball.fill", providerPath: "basketball" },
  { id: "tennis", name: "Tennis", icon: "tennisball.fill", providerPath: "tennis" },
  { id: "formula1", name: "Formula 1", icon: "flag.checkered", providerPath: "formula-1" },
]

const cache = new Map<string, CacheEntry>()
const providerBackoff = new Map<string, ProviderBackoffEntry>()

const dayMS = 24 * 60 * 60 * 1000
const hourMS = 60 * 60 * 1000

const defaultProviderBudget: ProviderBudgetConfig = {
  period: "day",
  autoLimit: 10,
  minRefreshMS: 60 * 60 * 1000,
  detailMinRefreshMS: 30 * 1000,
  quotaBackoffMS: 6 * 60 * 60 * 1000,
  snapshotTTLMS: dayMS,
}

const providerBudgets: Record<string, ProviderBudgetConfig> = {
  "cricketdata": {
    period: "day",
    autoLimit: 60,
    minRefreshMS: 20 * 60 * 1000,
    detailMinRefreshMS: 30 * 1000,
    quotaBackoffMS: 6 * 60 * 60 * 1000,
    snapshotTTLMS: dayMS,
  },
  "cricbuzz": {
    period: "day",
    autoLimit: 5,
    minRefreshMS: 20 * 60 * 1000,
    detailMinRefreshMS: 30 * 1000,
    quotaBackoffMS: 12 * 60 * 60 * 1000,
    snapshotTTLMS: 2 * dayMS,
  },
  "cricket-live-line": {
    period: "day",
    autoLimit: 60,
    minRefreshMS: 10 * 60 * 1000,
    detailMinRefreshMS: 20 * 1000,
    quotaBackoffMS: 6 * 60 * 60 * 1000,
    snapshotTTLMS: dayMS,
  },
  "cricket-live-data": {
    period: "month",
    autoLimit: 30,
    minRefreshMS: 6 * 60 * 60 * 1000,
    detailMinRefreshMS: 30 * 60 * 1000,
    quotaBackoffMS: 12 * 60 * 60 * 1000,
    snapshotTTLMS: 7 * dayMS,
  },
  "cricbuzz-official": {
    period: "day",
    autoLimit: 60,
    minRefreshMS: 10 * 60 * 1000,
    detailMinRefreshMS: 20 * 1000,
    quotaBackoffMS: 6 * 60 * 60 * 1000,
    snapshotTTLMS: dayMS,
  },
  "espncricinfo": {
    period: "day",
    autoLimit: 0,
    minRefreshMS: dayMS,
    detailMinRefreshMS: 5 * 60 * 1000,
    quotaBackoffMS: dayMS,
    snapshotTTLMS: 7 * dayMS,
  },
  "sportapi-football": {
    period: "day",
    autoLimit: 1,
    minRefreshMS: 12 * 60 * 60 * 1000,
    detailMinRefreshMS: 5 * 60 * 1000,
    quotaBackoffMS: dayMS,
    snapshotTTLMS: 3 * dayMS,
  },
  "livescore-soccer": {
    period: "day",
    autoLimit: 12,
    minRefreshMS: 30 * 60 * 1000,
    detailMinRefreshMS: 45 * 1000,
    quotaBackoffMS: 12 * 60 * 60 * 1000,
    snapshotTTLMS: 2 * dayMS,
  },
  "free-football": {
    period: "day",
    autoLimit: 2,
    minRefreshMS: 6 * 60 * 60 * 1000,
    detailMinRefreshMS: 5 * 60 * 1000,
    quotaBackoffMS: dayMS,
    snapshotTTLMS: 7 * dayMS,
  },
  "os-sports-perform-v2": {
    period: "month",
    autoLimit: 120,
    minRefreshMS: 30 * 60 * 1000,
    detailMinRefreshMS: 5 * 60 * 1000,
    quotaBackoffMS: 12 * 60 * 60 * 1000,
    snapshotTTLMS: 3 * dayMS,
  },
  "rundown-v1": {
    period: "day",
    autoLimit: 36,
    minRefreshMS: 2 * 60 * 60 * 1000,
    detailMinRefreshMS: 5 * 60 * 1000,
    quotaBackoffMS: 12 * 60 * 60 * 1000,
    snapshotTTLMS: 3 * dayMS,
  },
  "sportscore-tennis-rankings": {
    period: "month",
    autoLimit: 40,
    minRefreshMS: 12 * 60 * 60 * 1000,
    detailMinRefreshMS: 30 * 60 * 1000,
    quotaBackoffMS: 12 * 60 * 60 * 1000,
    snapshotTTLMS: 7 * dayMS,
  },
  "tennis-atp-wta-itf": {
    period: "month",
    autoLimit: 40,
    minRefreshMS: 12 * 60 * 60 * 1000,
    detailMinRefreshMS: 30 * 60 * 1000,
    quotaBackoffMS: 12 * 60 * 60 * 1000,
    snapshotTTLMS: 7 * dayMS,
  },
  "tennisapi": {
    period: "day",
    autoLimit: 30,
    minRefreshMS: 20 * 60 * 1000,
    detailMinRefreshMS: 45 * 1000,
    quotaBackoffMS: 6 * 60 * 60 * 1000,
    snapshotTTLMS: dayMS,
  },
  "hyprace": {
    period: "day",
    autoLimit: 8,
    minRefreshMS: 3 * 60 * 60 * 1000,
    detailMinRefreshMS: 5 * 60 * 1000,
    quotaBackoffMS: 12 * 60 * 60 * 1000,
    snapshotTTLMS: 7 * dayMS,
  },
  "tank01-mlb": {
    period: "month",
    autoLimit: 180,
    minRefreshMS: 20 * 60 * 1000,
    detailMinRefreshMS: 60 * 1000,
    quotaBackoffMS: 12 * 60 * 60 * 1000,
    snapshotTTLMS: dayMS,
  },
  "baseball4": {
    period: "month",
    autoLimit: 120,
    minRefreshMS: 2 * 60 * 60 * 1000,
    detailMinRefreshMS: 15 * 60 * 1000,
    quotaBackoffMS: 12 * 60 * 60 * 1000,
    snapshotTTLMS: 3 * dayMS,
  },
  "baseballapi": {
    period: "day",
    autoLimit: 8,
    minRefreshMS: 12 * 60 * 60 * 1000,
    detailMinRefreshMS: 60 * 60 * 1000,
    quotaBackoffMS: 12 * 60 * 60 * 1000,
    snapshotTTLMS: 7 * dayMS,
  },
  "basketapi-madness-v3": {
    period: "day",
    autoLimit: 12,
    minRefreshMS: 6 * 60 * 60 * 1000,
    detailMinRefreshMS: 5 * 60 * 1000,
    quotaBackoffMS: 12 * 60 * 60 * 1000,
    snapshotTTLMS: 3 * dayMS,
  },
}

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders,
  })
}

function parseIntOr(value: string | null, fallback: number) {
  if (!value) return fallback
  const parsed = Number.parseInt(value, 10)
  return Number.isFinite(parsed) ? parsed : fallback
}

function clamp(n: number, min: number, max: number) {
  return Math.max(min, Math.min(max, n))
}

function asString(value: unknown): string | null {
  if (value === null || value === undefined) return null
  if (typeof value === "object") return null
  const text = String(value).replace(/\s+/g, " ").trim()
  return text.length > 0 ? text : null
}

function firstString(record: Record<string, unknown>, keys: string[]): string | null {
  for (const key of keys) {
    const value = asString(record[key])
    if (value) return value
  }
  return null
}

function stableID(seed: string) {
  let hash = 5381
  for (let i = 0; i < seed.length; i += 1) {
    hash = ((hash << 5) + hash) + seed.charCodeAt(i)
    hash = hash & hash
  }
  return Math.abs(hash).toString(36)
}

function isoWithoutMilliseconds(date: Date) {
  return date.toISOString().replace(/\.\d{3}Z$/, "Z")
}

function providerErrorMessage(error: unknown) {
  return error instanceof Error ? error.message : "Provider failed"
}

function providerBackoffMS(message: string) {
  const lower = message.toLowerCase()
  if (lower.includes("daily quota") || lower.includes("monthly quota")) return 6 * 60 * 60 * 1000
  if (lower.includes("http 429") || lower.includes("quota")) return 15 * 60 * 1000
  return 0
}

function providerBackoffMessage(entry: ProviderBackoffEntry) {
  const until = isoWithoutMilliseconds(new Date(entry.until))
  return `${entry.message} (paused until ${until})`
}

function providerBudget(providerID: string) {
  return providerBudgets[providerID] ?? defaultProviderBudget
}

function scopeMinRefreshMS(config: ProviderBudgetConfig, scope: string) {
  return scope.startsWith("detail:") ? config.detailMinRefreshMS : config.minRefreshMS
}

function periodWindow(period: ProviderBudgetPeriod, timestamp: number) {
  const date = new Date(timestamp)
  let startedAt: Date
  let endsAt: Date

  if (period === "hour") {
    startedAt = new Date(Date.UTC(
      date.getUTCFullYear(),
      date.getUTCMonth(),
      date.getUTCDate(),
      date.getUTCHours()
    ))
    endsAt = new Date(startedAt.getTime() + hourMS)
  } else if (period === "month") {
    startedAt = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1))
    endsAt = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 1))
  } else {
    startedAt = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()))
    endsAt = new Date(startedAt.getTime() + dayMS)
  }

  return {
    startedAt: isoWithoutMilliseconds(startedAt),
    endsAt: isoWithoutMilliseconds(endsAt),
  }
}

function supabaseRESTCredentials() {
  const url = Deno.env.get("SUPABASE_URL")
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SERVICE_KEY")
  if (!url || !key) return null
  return {
    baseURL: `${url.replace(/\/+$/, "")}/rest/v1`,
    key,
  }
}

async function supabaseREST<T>(path: string, init: RequestInit = {}): Promise<T> {
  const credentials = supabaseRESTCredentials()
  if (!credentials) {
    throw new Error("Supabase service role secret is not configured for provider budgeting.")
  }

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
    throw new Error(`Supabase budget store: HTTP ${response.status} ${body.slice(0, 160)}`)
  }

  if (response.status === 204) return undefined as T
  const text = await response.text()
  return (text ? JSON.parse(text) : undefined) as T
}

function usageRecord(
  providerID: string,
  config: ProviderBudgetConfig,
  now: number
): ProviderUsageRecord {
  const window = periodWindow(config.period, now)
  return {
    provider_id: providerID,
    period: config.period,
    window_started_at: window.startedAt,
    window_ends_at: window.endsAt,
    auto_limit: config.autoLimit,
    used_count: 0,
    blocked_until: null,
    last_attempt_at: null,
    last_success_at: null,
    last_error_at: null,
    last_error: null,
    updated_at: isoWithoutMilliseconds(new Date(now)),
  }
}

function normalizeUsage(
  providerID: string,
  config: ProviderBudgetConfig,
  record: ProviderUsageRecord | null,
  now: number
) {
  const current = usageRecord(providerID, config, now)
  if (!record) return current
  if (record.period !== config.period || Date.parse(record.window_ends_at) <= now) return current
  return {
    ...record,
    auto_limit: config.autoLimit,
  }
}

async function readProviderUsage(providerID: string) {
  if (!supabaseRESTCredentials()) return null
  const records = await supabaseREST<ProviderUsageRecord[]>(
    `sports_provider_usage?provider_id=eq.${encodeURIComponent(providerID)}&select=*`
  )
  return records[0] ?? null
}

async function writeProviderUsage(record: ProviderUsageRecord) {
  if (!supabaseRESTCredentials()) return
  await supabaseREST<void>("sports_provider_usage?on_conflict=provider_id", {
    method: "POST",
    headers: {
      "Prefer": "resolution=merge-duplicates,return=minimal",
    },
    body: JSON.stringify(record),
  })
}

async function readProviderSnapshotRecord<T>(providerID: string, scope: string) {
  if (!supabaseRESTCredentials()) return null
  const records = await supabaseREST<ProviderSnapshotRecord<T>[]>(
    `sports_provider_snapshots?provider_id=eq.${encodeURIComponent(providerID)}&scope=eq.${encodeURIComponent(scope)}&select=*`
  )
  return records[0] ?? null
}

async function readProviderSnapshot<T>(providerID: string, scope: string) {
  const record = await readProviderSnapshotRecord<T>(providerID, scope)
  return record?.payload ?? null
}

async function writeProviderSnapshot<T>(
  providerID: string,
  scope: string,
  payload: T,
  ttlMS: number
) {
  if (!supabaseRESTCredentials()) return
  const now = Date.now()
  await supabaseREST<void>("sports_provider_snapshots?on_conflict=provider_id%2Cscope", {
    method: "POST",
    headers: {
      "Prefer": "resolution=merge-duplicates,return=minimal",
    },
    body: JSON.stringify({
      provider_id: providerID,
      scope,
      payload,
      generated_at: isoWithoutMilliseconds(new Date(now)),
      expires_at: isoWithoutMilliseconds(new Date(now + ttlMS)),
      updated_at: isoWithoutMilliseconds(new Date(now)),
    }),
  })
}

async function withProviderBackoff<T>(providerID: string, run: () => Promise<T>): Promise<T> {
  const existing = providerBackoff.get(providerID)
  if (existing && existing.until > Date.now()) {
    throw new Error(providerBackoffMessage(existing))
  }

  providerBackoff.delete(providerID)

  try {
    const value = await run()
    providerBackoff.delete(providerID)
    return value
  } catch (error) {
    const message = providerErrorMessage(error)
    const backoffMS = providerBackoffMS(message)
    if (backoffMS > 0) {
      providerBackoff.set(providerID, {
        until: Date.now() + backoffMS,
        message,
      })
    }
    throw new Error(message)
  }
}

async function snapshotOrThrow<T>(providerID: string, scope: string, message: string): Promise<T> {
  try {
    const snapshot = await readProviderSnapshot<T>(providerID, scope)
    if (snapshot) return snapshot
  } catch (error) {
    console.warn(`${providerID}: quota snapshot read failed`, providerErrorMessage(error))
  }
  throw new Error(message)
}

async function runProviderTask<T>(
  providerID: string,
  scope: string,
  run: () => Promise<T>
): Promise<T> {
  const config = providerBudget(providerID)
  const persistentBudgetEnabled = Boolean(supabaseRESTCredentials())

  if (!persistentBudgetEnabled) {
    return await withProviderBackoff(providerID, run)
  }

  const now = Date.now()
  let usage: ProviderUsageRecord
  let snapshot: ProviderSnapshotRecord<T> | null = null

  try {
    usage = normalizeUsage(providerID, config, await readProviderUsage(providerID), now)
    snapshot = await readProviderSnapshotRecord<T>(providerID, scope)
  } catch (error) {
    console.warn(`${providerID}: quota store unavailable`, providerErrorMessage(error))
    return await withProviderBackoff(providerID, run)
  }

  const nowISO = isoWithoutMilliseconds(new Date(now))
  const minRefreshMS = scopeMinRefreshMS(config, scope)
  const snapshotGeneratedAt = snapshot ? Date.parse(snapshot.generated_at) : 0
  if (snapshot && snapshotGeneratedAt > 0 && now - snapshotGeneratedAt < minRefreshMS) {
    return snapshot.payload
  }

  if (config.autoLimit <= 0) {
    if (snapshot) return snapshot.payload
    return await snapshotOrThrow<T>(
      providerID,
      scope,
      `${providerID}: automatic provider calls are disabled to protect quota.`
    )
  }

  const blockedUntil = usage.blocked_until ? Date.parse(usage.blocked_until) : 0
  if (blockedUntil > now) {
    if (snapshot) return snapshot.payload
    return await snapshotOrThrow<T>(
      providerID,
      scope,
      `${providerID}: paused until ${isoWithoutMilliseconds(new Date(blockedUntil))}.`
    )
  }

  if (usage.used_count >= usage.auto_limit) {
    if (snapshot) return snapshot.payload
    return await snapshotOrThrow<T>(
      providerID,
      scope,
      `${providerID}: automatic ${usage.period} quota is exhausted.`
    )
  }

  usage = {
    ...usage,
    last_attempt_at: nowISO,
    updated_at: nowISO,
  }

  try {
    await writeProviderUsage(usage)
  } catch (error) {
    console.warn(`${providerID}: quota attempt write failed`, providerErrorMessage(error))
    return await withProviderBackoff(providerID, run)
  }

  try {
    const value = await withProviderBackoff(providerID, run)
    try {
      await writeProviderSnapshot(providerID, scope, value, config.snapshotTTLMS)
      await writeProviderUsage({
        ...usage,
        used_count: usage.used_count + 1,
        blocked_until: null,
        last_success_at: nowISO,
        last_error_at: null,
        last_error: null,
        updated_at: nowISO,
      })
    } catch (error) {
      console.warn(`${providerID}: quota success write failed`, providerErrorMessage(error))
    }
    return value
  } catch (error) {
    const message = providerErrorMessage(error)
    const backoffMS = providerBackoffMS(message) || config.quotaBackoffMS
    try {
      await writeProviderUsage({
        ...usage,
        used_count: usage.used_count + 1,
        blocked_until: backoffMS > 0 ? isoWithoutMilliseconds(new Date(now + backoffMS)) : null,
        last_error_at: nowISO,
        last_error: message.slice(0, 500),
        updated_at: nowISO,
      })
    } catch (writeError) {
      console.warn(`${providerID}: quota error write failed`, providerErrorMessage(writeError))
    }

    if (snapshot) return snapshot.payload
    return await snapshotOrThrow<T>(providerID, scope, message)
  }
}

async function runProviderSource(source: ProviderSource): Promise<LiveSportSection> {
  return await runProviderTask(source.id, source.scope, source.run)
}

function isoFromLooseDate(value: string | null): string | null {
  if (!value) return null
  const parsed = new Date(value.includes("T") ? value : value.replace(" ", "T"))
  return Number.isNaN(parsed.getTime()) ? null : isoWithoutMilliseconds(parsed)
}

function splitScore(value: string | null): [string | null, string | null] {
  if (!value) return [null, null]
  const normalized = value.replace(/\s+/g, " ").trim()
  const separator = normalized.includes(" - ") ? " - " : normalized.includes("-") ? "-" : null
  if (!separator) return [null, null]
  const parts = normalized.split(separator).map((part) => part.trim()).filter(Boolean)
  if (parts.length < 2) return [null, null]
  return [parts[0], parts.slice(1).join(separator).trim()]
}

function isLive(record: Record<string, unknown>) {
  const status = firstString(record, [
    "event_status",
    "event_live",
    "event_status_info",
    "status",
    "match_status",
  ])?.toLowerCase() ?? ""

  if (!status) return true
  const ended = ["finished", "after pen", "after et", "cancelled", "postponed", "not started", "ft"]
  return !ended.some((token) => status.includes(token))
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : []
}

function numberString(value: unknown): string | null {
  if (value === null || value === undefined) return null
  if (typeof value === "number" && Number.isFinite(value)) return String(value)
  return asString(value)
}

function cricketInningsScore(value: unknown): string | null {
  const innings = asRecord(value)
  if (!innings) return null

  const runs = numberString(innings.runs)
  if (!runs) return null

  const wickets = numberString(innings.wickets)
  const overs = numberString(innings.overs)
  const wicketPart = wickets ? `/${wickets}` : ""
  const overPart = overs ? ` (${overs})` : ""
  return `${runs}${wicketPart}${overPart}`
}

function cricketTeamScore(value: unknown): string | null {
  const score = asRecord(value)
  if (!score) return null

  const innings = [
    cricketInningsScore(score.inngs2),
    cricketInningsScore(score.inngs1),
  ].filter((item): item is string => Boolean(item))

  return innings[0] ?? null
}

function safeCells(values: unknown[]) {
  return values.map((value) => {
    if (typeof value === "boolean") return value ? "Yes" : "No"
    return asString(value) ?? ""
  })
}

function isPlaceholderTeamName(value: string | null) {
  if (!value) return true
  const normalized = value.trim().toLowerCase()
  return normalized === "home" || normalized === "away" || normalized === "true" || normalized === "false"
}

function scoreboardSection(
  id: string,
  title: string,
  columns: string[],
  rows: ScoreboardRow[],
  subtitle: string | null = null
): ScoreboardSection {
  return { id, title, subtitle, columns, rows }
}

function genericSummarySections(match: LiveMatch): ScoreboardSection[] {
  const score = match.homeScore && match.awayScore
    ? `${match.homeScore} - ${match.awayScore}`
    : match.scoreSummary ?? null
  const rows: ScoreboardRow[] = []

  if (score && score.toLowerCase() !== "live") {
    rows.push({
      id: "score",
      cells: ["Score", score],
      note: null,
    })
  }

  const statusText = match.statusDetail ?? match.status
  if (statusText && statusText.toLowerCase() !== "true") {
    rows.push({
      id: "status",
      cells: ["Status", statusText],
      note: null,
    })
  }

  if (!isPlaceholderTeamName(match.homeName) || !isPlaceholderTeamName(match.awayName)) {
    rows.push({
      id: "teams",
      cells: ["Teams", `${match.homeName} vs ${match.awayName}`],
      note: null,
    })
  }

  if (match.venue) {
    rows.push({ id: "venue", cells: ["Venue", match.venue], note: null })
  }

  if (rows.length === 0) {
    rows.push({
      id: "waiting",
      cells: ["Update", "Detailed scorecard is not available yet."],
      note: null,
    })
  }

  return [
    scoreboardSection("summary", "Scoreboard", [], rows),
  ]
}

function rowID(seed: string, index: number) {
  return `${stableID(seed)}-${index}`
}

type MatchFeed = "live" | "upcoming" | "recent"

function isCricbuzzLive(matchInfo: Record<string, unknown>) {
  const state = asString(matchInfo.state)?.toLowerCase() ?? ""
  const status = asString(matchInfo.status)?.toLowerCase() ?? ""
  const terminalTokens = ["complete", "won by", "abandon", "stumps", "no result", "match tied"]

  if (!state && !status) return true
  if (state.includes("progress") || state.includes("innings") || state.includes("delay")) return true
  return !terminalTokens.some((token) => state.includes(token) || status.includes(token))
}

function normalizeCricbuzzMatch(item: Record<string, unknown>, feed: MatchFeed = "live"): LiveMatch | null {
  const matchInfo = asRecord(item.matchInfo)
  if (!matchInfo) return null
  if (feed === "live" && !isCricbuzzLive(matchInfo)) return null

  const team1 = asRecord(matchInfo.team1)
  const team2 = asRecord(matchInfo.team2)
  const team1Name = firstString(team1 ?? {}, ["teamSName", "teamName", "name"])
  const team2Name = firstString(team2 ?? {}, ["teamSName", "teamName", "name"])
  if (!team1Name || !team2Name) return null

  const matchScore = asRecord(item.matchScore)
  const team1Score = cricketTeamScore(matchScore?.team1Score)
  const team2Score = cricketTeamScore(matchScore?.team2Score)
  const matchID = firstString(matchInfo, ["matchId", "id"]) ??
    stableID(`${team1Name}|${team2Name}|${firstString(matchInfo, ["seriesName"]) ?? "cricket"}`)
  const seriesID = firstString(matchInfo, ["seriesId"]) ??
    stableID(firstString(matchInfo, ["seriesName"]) ?? "cricket")
  const venue = asRecord(matchInfo.venueInfo)
  const startDate = numberString(matchInfo.startDate)
  const startsAt = startDate ? isoWithoutMilliseconds(new Date(Number(startDate))) : null
  const status = firstString(matchInfo, ["state", "status"]) ?? "Live"
  const matchFormat = firstString(matchInfo, ["matchFormat"])
  const matchDesc = firstString(matchInfo, ["matchDesc"])
  const match: LiveMatch = {
    id: `cricket-${feed}-${matchID}`,
    providerID: "cricbuzz",
    detailID: matchID,
    sportID: "cricket",
    sportName: "Cricket",
    competitionID: `cricket-${seriesID}`,
    competitionName: firstString(matchInfo, ["seriesName"]) ?? "Cricket",
    country: firstString(venue ?? {}, ["country", "city"]),
    status,
    statusDetail: firstString(matchInfo, ["status"]),
    clock: null,
    period: matchFormat,
    startsAt,
    homeName: team1Name,
    awayName: team2Name,
    homeScore: team1Score,
    awayScore: team2Score,
    scoreSummary: [team1Score, team2Score].filter(Boolean).join(" | ") || null,
    homeLogoURL: null,
    awayLogoURL: null,
    venue: [firstString(venue ?? {}, ["ground"]), firstString(venue ?? {}, ["city"])]
      .filter(Boolean)
      .join(", ") || null,
    note: [matchDesc, firstString(matchInfo, ["status"])]
      .filter(Boolean)
      .join(" · ") || null,
    scoreboardSections: null,
  }
  match.scoreboardSections = genericSummarySections(match)
  return match
}

async function fetchCricbuzzCricketMatches(apiKey: string, feed: MatchFeed): Promise<LiveSportSection> {
  const response = await fetch(`https://cricbuzz-cricket.p.rapidapi.com/matches/v1/${feed}`, {
    headers: {
      "x-rapidapi-key": apiKey,
      "x-rapidapi-host": "cricbuzz-cricket.p.rapidapi.com",
      "content-type": "application/json",
    },
  })
  if (!response.ok) {
    const body = await response.text().catch(() => "")
    throw new Error(`Cricbuzz: HTTP ${response.status} ${body.slice(0, 160)}`)
  }

  const payload = await response.json()
  const matches: LiveMatch[] = []

  for (const typeMatch of asArray(payload?.typeMatches)) {
    const typeRecord = asRecord(typeMatch)
    for (const seriesMatch of asArray(typeRecord?.seriesMatches)) {
      const wrapper = asRecord(asRecord(seriesMatch)?.seriesAdWrapper)
      for (const rawMatch of asArray(wrapper?.matches)) {
        const match = normalizeCricbuzzMatch(asRecord(rawMatch) ?? {}, feed)
        if (match) matches.push(match)
      }
    }
  }

  const competitionsByID = new Map<string, LiveCompetition>()
  for (const match of matches) {
    const existing = competitionsByID.get(match.competitionID)
    if (existing) {
      existing.matches.push(match)
    } else {
      competitionsByID.set(match.competitionID, {
        id: match.competitionID,
        name: match.competitionName,
        country: match.country,
        matches: [match],
      })
    }
  }

  return {
    id: "cricket",
    name: "Cricket",
    icon: "figure.cricket",
    competitions: Array.from(competitionsByID.values()).sort((a, b) => a.name.localeCompare(b.name)),
  }
}

async function fetchCricbuzzLiveCricket(apiKey: string): Promise<LiveSportSection> {
  return await fetchCricbuzzCricketMatches(apiKey, "live")
}

function normalizeProviderMatch(sport: SportConfig, item: Record<string, unknown>): LiveMatch | null {
  if (!isLive(item)) return null

  const homeName = firstString(item, [
    "event_home_team",
    "event_home_team_name",
    "home_team",
    "event_first_player",
    "event_first_player_name",
  ])
  const awayName = firstString(item, [
    "event_away_team",
    "event_away_team_name",
    "away_team",
    "event_second_player",
    "event_second_player_name",
  ])
  if (!homeName || !awayName) return null

  const scoreSummary = firstString(item, [
    "event_final_result",
    "event_result",
    "event_score",
    "event_game_result",
    "event_home_final_result",
  ])
  const [parsedHomeScore, parsedAwayScore] = splitScore(scoreSummary)

  const homeScore = firstString(item, [
    "event_home_score",
    "home_score",
    "score_home",
    "event_home_final_result",
  ]) ?? parsedHomeScore
  const awayScore = firstString(item, [
    "event_away_score",
    "away_score",
    "score_away",
    "event_away_final_result",
  ]) ?? parsedAwayScore

  const competitionID = firstString(item, ["league_key", "league_id", "event_league_key"]) ??
    stableID(firstString(item, ["league_name", "event_league", "event_league_name"]) ?? "competition")
  const competitionName = firstString(item, ["league_name", "event_league", "event_league_name"]) ?? "Live matches"
  const country = firstString(item, ["country_name", "event_country", "league_country"])
  const status = firstString(item, ["event_status", "status", "match_status", "event_live"]) ?? "Live"
  const clock = firstString(item, ["event_live", "event_time_status", "event_minute", "event_timer"])
  const period = firstString(item, ["event_status_info", "event_round_info", "event_period"])
  const date = firstString(item, ["event_date", "date"])
  const time = firstString(item, ["event_time", "time"])
  const startsAt = date ? isoWithoutMilliseconds(new Date(`${date}T${time ?? "00:00"}:00Z`)) : null

  const id = firstString(item, ["event_key", "event_id", "match_id", "id"]) ??
    stableID(`${sport.id}|${competitionName}|${homeName}|${awayName}|${date ?? ""}|${time ?? ""}`)

  return {
    id: `${sport.id}-${id}`,
    providerID: null,
    detailID: null,
    sportID: sport.id,
    sportName: sport.name,
    competitionID: `${sport.id}-${competitionID}`,
    competitionName,
    country,
    status,
    statusDetail: firstString(item, ["event_status_info", "event_info", "event_stage"]),
    clock,
    period,
    startsAt,
    homeName,
    awayName,
    homeScore,
    awayScore,
    scoreSummary,
    homeLogoURL: firstString(item, [
      "home_team_logo",
      "event_home_team_logo",
      "event_first_player_logo",
    ]),
    awayLogoURL: firstString(item, [
      "away_team_logo",
      "event_away_team_logo",
      "event_second_player_logo",
    ]),
    venue: firstString(item, ["event_stadium", "event_venue", "venue"]),
    note: firstString(item, ["event_status_info", "event_info", "event_commentary"]),
    scoreboardSections: null,
  }
}

async function fetchSport(apiKey: string, sport: SportConfig, timezone: string): Promise<LiveSportSection> {
  const params = new URLSearchParams({
    met: "Livescore",
    APIkey: apiKey,
    timezone,
  })
  const url = `https://apiv2.allsportsapi.com/${sport.providerPath}/?${params.toString()}`
  const response = await fetch(url)
  if (!response.ok) {
    const body = await response.text().catch(() => "")
    throw new Error(`${sport.name}: HTTP ${response.status} ${body.slice(0, 160)}`)
  }

  const payload = await response.json()
  const rawItems = Array.isArray(payload?.result) ? payload.result : []
  const matches = rawItems
    .map((item: unknown) => normalizeProviderMatch(sport, item as Record<string, unknown>))
    .filter((match: LiveMatch | null): match is LiveMatch => match !== null)

  const competitionsByID = new Map<string, LiveCompetition>()
  for (const match of matches) {
    const existing = competitionsByID.get(match.competitionID)
    if (existing) {
      existing.matches.push(match)
    } else {
      competitionsByID.set(match.competitionID, {
        id: match.competitionID,
        name: match.competitionName,
        country: match.country,
        matches: [match],
      })
    }
  }

  return {
    id: sport.id,
    name: sport.name,
    icon: sport.icon,
    competitions: Array.from(competitionsByID.values()).sort((a, b) => a.name.localeCompare(b.name)),
  }
}

function rapidAPIHeaders(apiKey: string, host: string) {
  return {
    "x-rapidapi-key": apiKey,
    "x-rapidapi-host": host,
    "content-type": "application/json",
  }
}

async function fetchRapidJSON(apiKey: string, host: string, path: string): Promise<unknown> {
  const response = await fetch(`https://${host}${path}`, {
    headers: rapidAPIHeaders(apiKey, host),
  })
  if (!response.ok) {
    const body = await response.text().catch(() => "")
    throw new Error(`${host}: HTTP ${response.status} ${body.slice(0, 160)}`)
  }
  return await response.json()
}

async function fetchCricketDataJSON(apiKey: string | null, proxyURL: string | null): Promise<unknown> {
  const params = new URLSearchParams({ offset: "0" })
  if (!proxyURL && apiKey) {
    params.set("apikey", apiKey)
  }
  const url = proxyURL
    ? `${proxyURL}${proxyURL.includes("?") ? "&" : "?"}${params.toString()}`
    : `https://api.cricapi.com/v1/currentMatches?${params.toString()}`
  let lastError: unknown

  for (let attempt = 0; attempt < 3; attempt += 1) {
    try {
      const response = await fetch(url, {
        headers: {
          "accept": "application/json",
          "user-agent": "Briefly/1.0 live-scores",
        },
      })
      if (!response.ok) {
        const body = await response.text().catch(() => "")
        throw new Error(`HTTP ${response.status} ${body.slice(0, 160)}`)
      }
      return await response.json()
    } catch (error) {
      lastError = error
    }
  }

  const message = lastError instanceof Error && apiKey
    ? lastError.message.replace(apiKey, "[redacted]")
    : lastError instanceof Error
      ? lastError.message
      : "provider request failed"
  throw new Error(`CricketData: ${message}`)
}

function groupMatches(
  sportID: string,
  sportName: string,
  icon: string,
  matches: LiveMatch[]
): LiveSportSection {
  const competitionsByID = new Map<string, LiveCompetition>()
  for (const match of matches) {
    const existing = competitionsByID.get(match.competitionID)
    if (existing) {
      existing.matches.push(match)
    } else {
      competitionsByID.set(match.competitionID, {
        id: match.competitionID,
        name: match.competitionName,
        country: match.country,
        matches: [match],
      })
    }
  }

  return {
    id: sportID,
    name: sportName,
    icon,
    competitions: Array.from(competitionsByID.values()).sort((a, b) => a.name.localeCompare(b.name)),
  }
}

function nestedRecord(record: Record<string, unknown>, keys: string[]): Record<string, unknown> | null {
  for (const key of keys) {
    const nested = asRecord(record[key])
    if (nested) return nested
  }
  return null
}

function teamName(record: Record<string, unknown>, side: "home" | "away"): string | null {
  const direct = side === "home"
    ? firstString(record, ["homeName", "home_name", "home_team", "event_home_team", "team_home", "localteam_name"])
    : firstString(record, ["awayName", "away_name", "away_team", "event_away_team", "team_away", "visitorteam_name"])
  if (direct) return direct

  const nested = side === "home"
    ? nestedRecord(record, ["homeTeam", "home", "home_team", "localteam", "team1"])
    : nestedRecord(record, ["awayTeam", "away", "away_team", "visitorteam", "team2"])
  return nested ? firstString(nested, ["name", "shortName", "slug", "displayName", "teamName"]) : null
}

function teamScore(record: Record<string, unknown>, side: "home" | "away"): string | null {
  const direct = side === "home"
    ? firstString(record, ["homeScore", "home_score", "event_home_score", "score_home", "localteam_score"])
    : firstString(record, ["awayScore", "away_score", "event_away_score", "score_away", "visitorteam_score"])
  if (direct) return direct

  const score = side === "home"
    ? nestedRecord(record, ["homeScore", "home_score", "scoreHome"])
    : nestedRecord(record, ["awayScore", "away_score", "scoreAway"])
  return score ? firstString(score, ["display", "current", "total", "score", "normaltime", "period1"]) : null
}

function teamLogo(record: Record<string, unknown>, side: "home" | "away"): string | null {
  const nested = side === "home"
    ? nestedRecord(record, ["homeTeam", "home", "home_team", "localteam", "team1"])
    : nestedRecord(record, ["awayTeam", "away", "away_team", "visitorteam", "team2"])
  return nested ? firstString(nested, ["logo", "image", "imageUrl", "logoUrl", "crest"]) : null
}

function competitionName(record: Record<string, unknown>): string {
  const direct = firstString(record, ["league_name", "leagueName", "competition", "competition_name", "event_league", "tournament_name"])
  if (direct) return direct
  const tournament = nestedRecord(record, ["tournament", "league", "competition"])
  return firstString(tournament ?? {}, ["name", "uniqueTournamentName", "slug"]) ?? "Live matches"
}

function competitionCountry(record: Record<string, unknown>): string | null {
  const direct = firstString(record, ["country", "country_name", "event_country", "league_country"])
  if (direct) return direct
  const category = nestedRecord(record, ["category", "country"])
  return firstString(category ?? {}, ["name", "country", "alpha2"])
}

function normalizeRapidMatch(
  providerID: string,
  sportID: string,
  sportName: string,
  icon: string,
  item: Record<string, unknown>
): LiveMatch | null {
  if (!isLive(item)) return null

  const homeName = teamName(item, "home")
  const awayName = teamName(item, "away")
  if (!homeName || !awayName) return null

  const competition = competitionName(item)
  const country = competitionCountry(item)
  const id = firstString(item, ["id", "event_id", "event_key", "match_id", "matchId", "eid"]) ??
    stableID(`${providerID}|${sportID}|${competition}|${homeName}|${awayName}`)
  const scoreSummary = firstString(item, ["score", "scoreSummary", "event_score", "event_final_result", "result"])
  const [parsedHomeScore, parsedAwayScore] = splitScore(scoreSummary)
  const homeScore = teamScore(item, "home") ?? parsedHomeScore
  const awayScore = teamScore(item, "away") ?? parsedAwayScore
  const status = firstString(item, ["status", "event_status", "statusDescription", "description", "match_status"]) ?? "Live"
  const statusRecord = asRecord(item.status)
  const timeRecord = asRecord(item.time) ?? asRecord(item.statusTime)
  const roundRecord = asRecord(item.roundInfo)
  const statusText = firstString(statusRecord ?? {}, ["description", "type"])
  const statusDetail = firstString(item, ["statusDetail", "status_detail", "event_status_info", "statusDescription", "shortStatus"]) ??
    statusText
  const clock = firstString(item, ["time", "clock", "event_live", "minute", "currentMinute", "event_minute"]) ??
    firstString(timeRecord ?? {}, ["minute", "current", "display", "prefix"])
  const period = firstString(item, ["period", "round", "event_period", "stage", "statusType"]) ??
    firstString(roundRecord ?? {}, ["name", "round", "slug"])
  const venueRecord = nestedRecord(item, ["venue"])
  const venue = firstString(item, ["venue", "stadium", "event_stadium"]) ??
    firstString(venueRecord ?? {}, ["name", "cityName"])
  const startTimestamp = numberString(item.startTimestamp)
  const startsAt = startTimestamp ? isoWithoutMilliseconds(new Date(Number(startTimestamp) * 1000)) : null

  const match: LiveMatch = {
    id: `${providerID}-${sportID}-${id}`,
    providerID: null,
    detailID: null,
    sportID,
    sportName,
    competitionID: `${sportID}-${stableID(competition)}`,
    competitionName: competition,
    country,
    status: statusText ?? status,
    statusDetail,
    clock,
    period,
    startsAt,
    homeName,
    awayName,
    homeScore,
    awayScore,
    scoreSummary,
    homeLogoURL: teamLogo(item, "home"),
    awayLogoURL: teamLogo(item, "away"),
    venue,
    note: statusDetail,
    scoreboardSections: null,
  }
  match.scoreboardSections = genericSummarySections(match)
  return match
}

function payloadRecords(payload: unknown, keys: string[]): Record<string, unknown>[] {
  const direct = asRecord(payload)
  const candidates: unknown[] = []
  if (Array.isArray(payload)) candidates.push(payload)

  for (const key of keys) {
    const value = direct?.[key]
    if (Array.isArray(value)) candidates.push(value)
  }

  for (const event of asArray(direct?.events)) candidates.push(event)
  for (const stage of asArray(direct?.Stages)) {
    const stageRecord = asRecord(stage)
    if (Array.isArray(stageRecord?.Events)) candidates.push(stageRecord.Events)
    if (Array.isArray(stageRecord?.events)) candidates.push(stageRecord.events)
  }
  for (const stage of asArray(direct?.stages)) {
    const stageRecord = asRecord(stage)
    if (Array.isArray(stageRecord?.Events)) candidates.push(stageRecord.Events)
    if (Array.isArray(stageRecord?.events)) candidates.push(stageRecord.events)
  }

  return candidates.flatMap((candidate) => asArray(candidate))
    .map((item) => asRecord(item))
    .filter((item): item is Record<string, unknown> => Boolean(item))
}

async function fetchSportAPIFootball(apiKey: string): Promise<LiveSportSection> {
  const payload = await fetchRapidJSON(apiKey, "sportapi7.p.rapidapi.com", "/api/v1/sport/football/events/live")
  const matches = payloadRecords(payload, ["events", "data", "result"])
    .map((item) => normalizeRapidMatch("sportapi", "soccer", "Soccer", "soccerball", item))
    .filter((match): match is LiveMatch => Boolean(match))
  return groupMatches("soccer", "Soccer", "soccerball", matches)
}

async function fetchTennisAPI(apiKey: string): Promise<LiveSportSection> {
  const payload = await fetchRapidJSON(apiKey, "tennisapi1.p.rapidapi.com", "/api/tennis/events/live")
  const matches = payloadRecords(payload, ["events", "data", "result"])
    .map((item) => normalizeRapidMatch("tennisapi", "tennis", "Tennis", "tennisball.fill", item))
    .filter((match): match is LiveMatch => Boolean(match))
  return groupMatches("tennis", "Tennis", "tennisball.fill", matches)
}

const tennisAtpWtaItfHost = "tennis-api-atp-wta-itf.p.rapidapi.com"

type TennisAtpWtaRankingKind = "atp-singles" | "wta-singles" | "atp-doubles" | "wta-doubles"

function tennisAtpWtaRankingPath(kind: TennisAtpWtaRankingKind): string {
  const [tour, table] = kind.split("-")
  return `/tennis/v2/${tour}/ranking/${table}/`
}

function tennisAtpWtaRecords(payload: unknown): Record<string, unknown>[] {
  const direct = payloadRecords(payload, [
    "data",
    "rankings",
    "ranking",
    "results",
    "players",
    "items",
    "rows",
  ])
  const deep = sportscoreDeepRecords(payload)
  const seen = new Set<Record<string, unknown>>()
  return [...direct, ...deep].filter((record) => {
    if (seen.has(record)) return false
    seen.add(record)
    return true
  })
}

function tennisAtpWtaPlayerName(record: Record<string, unknown>): string | null {
  const direct = firstString(record, [
    "name",
    "fullName",
    "full_name",
    "playerName",
    "player_name",
    "competitorName",
    "competitor_name",
    "teamName",
    "team_name",
    "slug",
  ])
  if (direct) return direct
  const player = nestedRecord(record, ["player", "competitor", "team", "athlete"])
  return firstString(player ?? {}, ["name", "fullName", "full_name", "display_name", "slug"]) ??
    deepFirstString(record, ["playerName", "player_name", "fullName", "full_name", "display_name", "name"])
}

function tennisAtpWtaCountry(record: Record<string, unknown>): string | null {
  const direct = firstString(record, ["country", "countryName", "country_name", "nationality", "countryCode", "country_code"])
  if (direct) return direct
  const country = nestedRecord(record, ["country", "nationality"])
  return firstString(country ?? {}, ["name", "code", "alpha2"]) ??
    deepFirstString(record, ["countryName", "country_name", "countryCode", "country_code", "nationality"])
}

function tennisAtpWtaRows(payload: unknown, prefix: string): ScoreboardRow[] {
  return tennisAtpWtaRecords(payload)
    .slice(0, 50)
    .map((record, index) => {
      const playerName = tennisAtpWtaPlayerName(record)
      if (!playerName) return null
      const rank = firstString(record, ["rank", "ranking", "position", "place"]) ??
        deepFirstString(record, ["rank", "ranking", "position", "place"]) ??
        String(index + 1)
      const points = firstString(record, ["points", "point", "score", "rating", "value"]) ??
        deepFirstString(record, ["points", "point", "score", "rating", "value"]) ??
        "-"
      return {
        id: rowID(`${prefix}-${rank}-${playerName}`, index),
        cells: safeCells([rank, playerName, points]),
        note: tennisAtpWtaCountry(record),
      }
    })
    .filter((row): row is ScoreboardRow => Boolean(row))
}

function tennisAtpWtaTopPlayer(payload: unknown): string | null {
  const top = tennisAtpWtaRecords(payload)
    .map((record) => tennisAtpWtaPlayerName(record))
    .find((name): name is string => Boolean(name))
  return top ? `No. 1 ${top}` : null
}

function tennisAtpWtaRankingMatch(kind: TennisAtpWtaRankingKind, payload: unknown): LiveMatch {
  const [tour, table] = kind.split("-")
  const title = `${tour.toUpperCase()} ${table} rankings`
  const rows = tennisAtpWtaRows(payload, `tennis-atp-wta-itf-${kind}`)
  const match: LiveMatch = {
    id: `tennis-atp-wta-itf-${kind}`,
    providerID: "tennis-atp-wta-itf",
    detailID: kind,
    sportID: "tennis",
    sportName: "Tennis",
    competitionID: "tennis-atp-wta-itf-rankings",
    competitionName: "Tennis API ATP/WTA/ITF Rankings",
    country: null,
    status: "Current",
    statusDetail: title,
    clock: null,
    period: null,
    startsAt: null,
    homeName: title,
    awayName: "Top players",
    homeScore: null,
    awayScore: null,
    scoreSummary: tennisAtpWtaTopPlayer(payload),
    homeLogoURL: null,
    awayLogoURL: null,
    venue: null,
    note: "Tennis API ATP/WTA/ITF rankings, low-refresh to protect monthly quota",
    scoreboardSections: null,
  }
  match.scoreboardSections = rows.length > 0
    ? [scoreboardSection(kind, title, ["Rank", "Player", "Points"], rows)]
    : genericSummarySections(match)
  return match
}

async function fetchTennisAtpWtaItfRankings(apiKey: string): Promise<LiveSportSection> {
  const kinds: TennisAtpWtaRankingKind[] = ["atp-singles", "wta-singles", "atp-doubles", "wta-doubles"]
  const results = await Promise.allSettled(
    kinds.map((kind) => fetchRapidJSON(apiKey, tennisAtpWtaItfHost, tennisAtpWtaRankingPath(kind)))
  )
  const matches = results
    .map((result, index) => result.status === "fulfilled"
      ? tennisAtpWtaRankingMatch(kinds[index], result.value)
      : null)
    .filter((match): match is LiveMatch => Boolean(match))
  if (matches.length === 0) {
    const failed = results.find((result) => result.status === "rejected")
    throw failed?.status === "rejected" ? failed.reason : new Error("Tennis API rankings unavailable")
  }
  return groupMatches("tennis", "Tennis", "tennisball.fill", matches)
}

async function fetchTennisAtpWtaItfRankingDetail(apiKey: string, detailID: string): Promise<LiveMatchDetailResponse> {
  const kind = detailID.toLowerCase() as TennisAtpWtaRankingKind
  if (!["atp-singles", "wta-singles", "atp-doubles", "wta-doubles"].includes(kind)) {
    throw new Error("Tennis API ranking detail must be atp-singles, wta-singles, atp-doubles, or wta-doubles")
  }
  const payload = await fetchRapidJSON(apiKey, tennisAtpWtaItfHost, tennisAtpWtaRankingPath(kind))
  const match = tennisAtpWtaRankingMatch(kind, payload)
  return {
    generatedAt: isoWithoutMilliseconds(new Date()),
    match,
    scoreboardSections: match.scoreboardSections ?? genericSummarySections(match),
  }
}

const sportscoreHost = "sportscore1.p.rapidapi.com"

function sportscoreRecords(payload: unknown): Record<string, unknown>[] {
  const direct = payloadRecords(payload, ["data", "rankings", "results", "players", "items"])
  const root = asRecord(payload)
  const nestedData = asRecord(root?.data)
  const nested: Record<string, unknown>[] = []
  for (const source of [nestedData, root]) {
    if (!source) continue
    for (const key of ["data", "rankings", "results", "players", "items"]) {
      const value = source[key]
      if (Array.isArray(value)) {
        nested.push(...value.map((item) => asRecord(item)).filter((item): item is Record<string, unknown> => Boolean(item)))
      } else {
        const record = asRecord(value)
        if (record) {
          nested.push(...Object.values(record).map((item) => asRecord(item)).filter((item): item is Record<string, unknown> => Boolean(item)))
        }
      }
    }
  }
  return [...direct, ...nested]
}

function sportscoreDeepRecords(value: unknown, depth = 0): Record<string, unknown>[] {
  if (depth > 5) return []
  if (Array.isArray(value)) {
    return value.flatMap((item) => sportscoreDeepRecords(item, depth + 1))
  }
  const record = asRecord(value)
  if (!record) return []
  const children = Object.values(record).flatMap((item) => sportscoreDeepRecords(item, depth + 1))
  const hasRankingShape = [
    "rank",
    "ranking",
    "position",
    "place",
    "points",
    "player",
    "competitor",
    "athlete",
    "player_name",
  ].some((key) => key in record)
  return hasRankingShape ? [record, ...children] : children
}

function sportscoreRankingRecords(payload: unknown): Record<string, unknown>[] {
  const seen = new Set<Record<string, unknown>>()
  return [...sportscoreRecords(payload), ...sportscoreDeepRecords(payload)]
    .filter((record) => {
      if (seen.has(record)) return false
      seen.add(record)
      return true
    })
}

function deepFirstString(value: unknown, keys: string[], depth = 0): string | null {
  if (depth > 4) return null
  const record = asRecord(value)
  if (!record) return null
  const direct = firstString(record, keys)
  if (direct) return direct
  for (const child of Object.values(record)) {
    const found = deepFirstString(child, keys, depth + 1)
    if (found) return found
  }
  return null
}

function sportscorePlayerName(record: Record<string, unknown>): string | null {
  const direct = firstString(record, ["name", "player_name", "full_name", "slug", "title"])
  if (direct) return direct
  const player = nestedRecord(record, ["player", "competitor", "athlete"])
  return firstString(player ?? {}, ["name", "full_name", "display_name", "slug"]) ??
    deepFirstString(record, ["player_name", "full_name", "display_name", "name"])
}

function sportscoreCountry(record: Record<string, unknown>): string | null {
  const direct = firstString(record, ["country", "country_name", "nationality", "country_code"])
  if (direct) return direct
  const country = nestedRecord(record, ["country", "nationality"])
  return firstString(country ?? {}, ["name", "code", "alpha2"]) ??
    deepFirstString(record, ["country_name", "country_code", "nationality"])
}

function sportscoreRankingRows(payload: unknown, prefix: string): ScoreboardRow[] {
  return sportscoreRankingRecords(payload)
    .slice(0, 30)
    .map((record, index) => {
      const playerName = sportscorePlayerName(record)
      if (!playerName) return null
      const rank = firstString(record, ["rank", "ranking", "position", "place"]) ??
        deepFirstString(record, ["rank", "ranking", "position", "place"]) ??
        String(index + 1)
      const points = firstString(record, ["points", "score", "rating", "value"]) ??
        deepFirstString(record, ["points", "score", "rating", "value"]) ??
        "-"
      return {
        id: rowID(`${prefix}-${rank}-${playerName}`, index),
        cells: safeCells([rank, playerName, points]),
        note: sportscoreCountry(record),
      }
    })
    .filter((row): row is ScoreboardRow => Boolean(row))
}

function sportscoreTopPlayer(payload: unknown): string | null {
  const top = sportscoreRankingRecords(payload)
    .map((record) => sportscorePlayerName(record))
    .find((name): name is string => Boolean(name))
  return top ? `No. 1 ${top}` : null
}

function sportscoreRankingMatch(kind: "atp" | "wta", payload: unknown): LiveMatch {
  const title = `${kind.toUpperCase()} rankings`
  const rows = sportscoreRankingRows(payload, `sportscore-${kind}`)
  const match: LiveMatch = {
    id: `sportscore-tennis-${kind}`,
    providerID: "sportscore-tennis-rankings",
    detailID: kind,
    sportID: "tennis",
    sportName: "Tennis",
    competitionID: "tennis-sportscore-rankings",
    competitionName: "SportScore Tennis Rankings",
    country: null,
    status: "Current",
    statusDetail: title,
    clock: null,
    period: null,
    startsAt: null,
    homeName: title,
    awayName: "Top players",
    homeScore: null,
    awayScore: null,
    scoreSummary: sportscoreTopPlayer(payload),
    homeLogoURL: null,
    awayLogoURL: null,
    venue: null,
    note: "SportScore rankings, low-refresh to protect monthly quota",
    scoreboardSections: null,
  }
  match.scoreboardSections = rows.length > 0
    ? [scoreboardSection(`${kind}-rankings`, title, ["Rank", "Player", "Points"], rows)]
    : genericSummarySections(match)
  return match
}

async function fetchSportscoreTennisRankings(apiKey: string): Promise<LiveSportSection> {
  const results = await Promise.allSettled([
    fetchRapidJSON(apiKey, sportscoreHost, "/tennis-rankings/atp?page=1"),
    fetchRapidJSON(apiKey, sportscoreHost, "/tennis-rankings/wta?page=1"),
  ])
  const matches = results
    .map((result, index) => result.status === "fulfilled"
      ? sportscoreRankingMatch(index === 0 ? "atp" : "wta", result.value)
      : null)
    .filter((match): match is LiveMatch => Boolean(match))
  if (matches.length === 0) {
    const failed = results.find((result) => result.status === "rejected")
    throw failed?.status === "rejected" ? failed.reason : new Error("SportScore rankings unavailable")
  }
  return groupMatches("tennis", "Tennis", "tennisball.fill", matches)
}

async function fetchSportscoreTennisRankingDetail(apiKey: string, detailID: string): Promise<LiveMatchDetailResponse> {
  const rankingID = detailID.toLowerCase()
  if (rankingID !== "atp" && rankingID !== "wta") {
    throw new Error("SportScore ranking detail must be atp or wta")
  }
  const payload = await fetchRapidJSON(apiKey, sportscoreHost, `/tennis-rankings/${rankingID}?page=1`)
  const match = sportscoreRankingMatch(rankingID, payload)
  return {
    generatedAt: isoWithoutMilliseconds(new Date()),
    match,
    scoreboardSections: match.scoreboardSections ?? genericSummarySections(match),
  }
}

async function fetchLiveScoreSoccer(apiKey: string, timezone: string): Promise<LiveSportSection> {
  const offset = timezone === "Asia/Kolkata" ? "5.5" : "0"
  const path = `/matches/v2/list-live?Category=soccer&Timezone=${encodeURIComponent(offset)}`
  const payload = await fetchRapidJSON(apiKey, "livescore6.p.rapidapi.com", path)
  const matches = payloadRecords(payload, ["Events", "events", "matches", "data"])
    .map((item) => normalizeLiveScoreSoccerMatch(item))
    .filter((match): match is LiveMatch => Boolean(match))
  return groupMatches("soccer", "Soccer", "soccerball", matches)
}

function normalizeLiveScoreSoccerMatch(item: Record<string, unknown>): LiveMatch | null {
  const match = normalizeRapidMatch("livescore", "soccer", "Soccer", "soccerball", item)
  if (!match) return null

  const eventID = firstString(item, ["Eid", "eid", "id", "event_id", "event_key", "match_id", "matchId"])
  return {
    ...match,
    providerID: eventID ? "livescore-soccer" : match.providerID,
    detailID: eventID,
  }
}

function liveScoreDetailRows(payload: unknown): ScoreboardRow[] {
  const records = payloadRecords(payload, [
    "Scoreboard",
    "scoreboard",
    "Stats",
    "stats",
    "Incidents",
    "incidents",
    "Events",
    "events",
    "data",
  ])

  return records
    .map((record, index) => {
      const label = firstString(record, [
        "name",
        "title",
        "type",
        "eventType",
        "period",
        "minute",
        "Min",
      ]) ?? `Item ${index + 1}`
      const home = firstString(record, ["home", "homeValue", "home_score", "homeScore", "S1", "score1", "value1"])
      const away = firstString(record, ["away", "awayValue", "away_score", "awayScore", "S2", "score2", "value2"])
      const detail = firstString(record, ["text", "description", "comment", "value", "score", "result"])
      if (!home && !away && !detail && label.startsWith("Item ")) return null

      return {
        id: rowID(`livescore-detail-${label}`, index),
        cells: safeCells([label, home ?? detail, away]),
        note: detail && (home || away) ? detail : null,
      }
    })
    .filter((row): row is ScoreboardRow => Boolean(row))
}

async function fetchLiveScoreSoccerMatchDetail(apiKey: string, detailID: string): Promise<LiveMatchDetailResponse> {
  const params = new URLSearchParams({
    Category: "soccer",
    Eid: detailID,
  })
  const payload = await fetchRapidJSON(
    apiKey,
    "livescore6.p.rapidapi.com",
    `/matches/v2/get-scoreboard?${params.toString()}`
  )
  const record = payloadRecords(payload, ["Events", "events", "matches", "data"])[0] ?? asRecord(payload) ?? {}
  const fallbackMatch = normalizeLiveScoreSoccerMatch(record)
  const match = fallbackMatch ?? {
    id: `livescore-soccer-detail-${detailID}`,
    providerID: "livescore-soccer",
    detailID,
    sportID: "soccer",
    sportName: "Soccer",
    competitionID: "livescore-soccer-detail",
    competitionName: competitionName(record),
    country: competitionCountry(record),
    status: firstString(record, ["status", "statusDescription", "description"]) ?? "Live",
    statusDetail: firstString(record, ["statusDetail", "statusDescription", "description"]),
    clock: firstString(record, ["time", "clock", "minute", "currentMinute"]),
    period: firstString(record, ["period", "round", "stage"]),
    startsAt: null,
    homeName: teamName(record, "home") ?? "Home",
    awayName: teamName(record, "away") ?? "Away",
    homeScore: teamScore(record, "home"),
    awayScore: teamScore(record, "away"),
    scoreSummary: firstString(record, ["score", "scoreSummary", "result"]),
    homeLogoURL: teamLogo(record, "home"),
    awayLogoURL: teamLogo(record, "away"),
    venue: firstString(record, ["venue", "stadium"]),
    note: firstString(record, ["statusDetail", "statusDescription", "description"]),
    scoreboardSections: null,
  }
  const rows = liveScoreDetailRows(payload)
  match.scoreboardSections = rows.length > 0
    ? [scoreboardSection("scoreboard", "Scoreboard", ["Stat", "Home", "Away"], rows)]
    : genericSummarySections(match)

  return {
    generatedAt: isoWithoutMilliseconds(new Date()),
    match,
    scoreboardSections: match.scoreboardSections,
  }
}

const hypraceHost = "hyprace-api.p.rapidapi.com"
const hypraceSeasonID = "3d24e122-216e-4328-abcf-0af0c5f3fb9e"
const hypraceSeasonYear = "2026"

type HypraceDetailID = {
  kind: "drivers-standings" | "constructors-standings" | "grand-prix" | "race-results" | "qualifying-results"
  seasonId?: string
  grandPrixId?: string
  raceId?: string
  qualifyingId?: string
}

function hypracePath(path: string) {
  return path.startsWith("/") ? path : `/${path}`
}

async function fetchHypraceJSON(apiKey: string, path: string): Promise<unknown> {
  return await fetchRapidJSON(apiKey, hypraceHost, hypracePath(path))
}

function recursiveRecords(value: unknown, keys: string[], depth = 0): Record<string, unknown>[] {
  if (depth > 4) return []
  if (Array.isArray(value)) {
    return value
      .flatMap((item) => recursiveRecords(item, keys, depth + 1))
      .concat(value.map((item) => asRecord(item)).filter((item): item is Record<string, unknown> => Boolean(item)))
  }

  const record = asRecord(value)
  if (!record) return []

  const records: Record<string, unknown>[] = []
  for (const key of keys) {
    const child = record[key]
    if (Array.isArray(child)) {
      records.push(...child.map((item) => asRecord(item)).filter((item): item is Record<string, unknown> => Boolean(item)))
    } else if (asRecord(child)) {
      records.push(...recursiveRecords(child, keys, depth + 1))
    }
  }
  return records
}

function hypraceRecords(payload: unknown): Record<string, unknown>[] {
  const keys = [
    "data",
    "items",
    "result",
    "results",
    "response",
    "standings",
    "drivers",
    "constructors",
    "grandsPrix",
    "grandPrix",
    "races",
    "qualifying",
    "qualifyings",
  ]
  const direct = payloadRecords(payload, keys)
  if (direct.length > 0) return direct

  const recursive = recursiveRecords(payload, keys)
  if (recursive.length > 0) return recursive

  const root = asRecord(payload)
  return root ? [root] : []
}

function hypraceRecordName(record: Record<string, unknown>, fallback: string): string {
  const nestedDriver = nestedRecord(record, ["driver", "pilot", "athlete"])
  const nestedTeam = nestedRecord(record, ["constructor", "team", "entrant"])
  const firstName = firstString(record, ["firstName"])
  const lastName = firstString(record, ["lastName"])
  const combinedName = [firstName, lastName].filter(Boolean).join(" ")
  if (combinedName) return combinedName

  const directName = firstString(record, [
    "fullName",
    "driverName",
    "constructorName",
    "teamName",
    "grandPrixName",
    "raceName",
    "qualifyingName",
    "eventName",
    "name",
    "title",
    "displayName",
  ])
  if (directName) return directName

  const nestedDriverName = firstString(nestedDriver ?? {}, ["fullName", "name", "displayName"]) ??
    [firstString(nestedDriver ?? {}, ["firstName"]), firstString(nestedDriver ?? {}, ["lastName"])]
      .filter(Boolean)
      .join(" ")
  if (nestedDriverName) return nestedDriverName

  const nestedTeamName = firstString(nestedTeam ?? {}, ["name", "displayName"])
  if (nestedTeamName) return nestedTeamName

  const driverID = firstString(record, ["driverId"])
  if (driverID) return `Driver ${driverID.slice(0, 8)}`
  const constructorID = firstString(record, ["constructorId", "teamId", "chassisManufacturerId"])
  if (constructorID) return `Constructor ${constructorID.slice(0, 8)}`

  return fallback
}

function hypraceRecordID(record: Record<string, unknown>, seed: string): string {
  return firstString(record, [
    "id",
    "driverId",
    "constructorId",
    "teamId",
    "grandPrixId",
    "raceId",
    "qualifyingId",
  ]) ?? stableID(seed)
}

function hypraceStandingRows(payload: unknown): ScoreboardRow[] {
  return hypraceStandingRecords(payload)
    .slice(0, 30)
    .map((record, index) => {
      const name = hypraceRecordName(record, `Entry ${index + 1}`)
      const position = firstString(record, ["position", "rank", "standingPosition", "place", "order"]) ?? String(index + 1)
      const points = firstString(record, ["points", "pts", "totalPoints", "score", "seasonPoints"])
      const wins = firstString(record, ["wins", "victories", "raceWins"])
      return {
        id: rowID(`hyprace-standing-${name}`, index),
        cells: safeCells([position, name, points ?? "", wins ?? ""]),
        note: firstString(record, ["teamName", "constructorName", "country", "nationality"]),
      }
    })
    .filter((row) => row.cells.some((cell) => cell.length > 0))
}

function hypraceStandingRecords(payload: unknown): Record<string, unknown>[] {
  const wrappers = payloadRecords(payload, ["items", "data", "result", "results", "response"])
  const standings = wrappers.flatMap((wrapper) => {
    const rows = asArray(wrapper.standings)
    return rows.map((row) => asRecord(row)).filter((row): row is Record<string, unknown> => Boolean(row))
  })
  if (standings.length > 0) return standings

  const directStandings = payloadRecords(payload, ["standings"])
  if (directStandings.length > 0) return directStandings

  return wrappers.filter((wrapper) => firstString(wrapper, ["position", "points", "driverId", "constructorId"]))
}

function hypraceEventRows(payload: unknown): ScoreboardRow[] {
  const grandPrixRows = payloadRecords(payload, ["items", "data", "result", "results", "response"])
  const scheduleRows = grandPrixRows.flatMap((record) => {
    const schedule = asArray(record.schedule)
    return schedule.map((item) => asRecord(item)).filter((item): item is Record<string, unknown> => Boolean(item))
  })
  const records = scheduleRows.length > 0 ? scheduleRows : hypraceRecords(payload)

  return records
    .slice(0, 30)
    .map((record, index) => {
      const name = hypraceRecordName(record, `Event ${index + 1}`)
      const status = firstString(record, ["status", "state", "type", "sessionType", "raceType"]) ?? ""
      const date = isoFromLooseDate(firstString(record, ["startDate", "date", "startsAt", "scheduledAt"]))
      return {
        id: rowID(`hyprace-event-${name}`, index),
        cells: safeCells([name, status, date ?? ""]),
        note: firstString(record, ["circuitName", "venue", "location", "country"]),
      }
    })
    .filter((row) => row.cells.some((cell) => cell.length > 0))
}

function hypraceStandingMatch(kind: HypraceDetailID["kind"], payload: unknown): LiveMatch | null {
  if (kind !== "drivers-standings" && kind !== "constructors-standings") return null
  const rows = hypraceStandingRows(payload)
  if (rows.length === 0) return null

  const title = kind === "drivers-standings" ? "Drivers standings" : "Constructors standings"
  const leader = rows[0]?.cells[1] || null
  const points = rows[0]?.cells[2] || null
  const detail: HypraceDetailID = { kind }
  const match: LiveMatch = {
    id: `hyprace-${kind}`,
    providerID: "hyprace",
    detailID: JSON.stringify(detail),
    sportID: "formula1",
    sportName: "Formula 1",
    competitionID: "formula1-hyprace-standings",
    competitionName: "Formula 1 standings",
    country: null,
    status: "Current",
    statusDetail: `${hypraceSeasonYear} season`,
    clock: null,
    period: hypraceSeasonYear,
    startsAt: null,
    homeName: title,
    awayName: leader ?? "Championship",
    homeScore: rows.length.toString(),
    awayScore: points,
    scoreSummary: leader ? `${leader}${points ? `, ${points} pts` : ""}` : `${rows.length} entries`,
    homeLogoURL: null,
    awayLogoURL: null,
    venue: null,
    note: "Hyprace",
    scoreboardSections: null,
  }
  match.scoreboardSections = [
    scoreboardSection(kind, title, ["Pos", "Name", "Pts", "Wins"], rows, `${hypraceSeasonYear} season`),
  ]
  return match
}

function hypraceGrandPrixMatch(payload: unknown): LiveMatch | null {
  const record = hypraceRecords(payload)[0]
  if (!record) return null
  const grandPrixID = hypraceRecordID(record, "current-grand-prix")
  const name = hypraceRecordName(record, "Current Grand Prix")
  const detail: HypraceDetailID = { kind: "grand-prix", grandPrixId: grandPrixID }
  const startDate = isoFromLooseDate(firstString(record, ["startDate", "date", "startsAt", "scheduledAt"]))
  const match: LiveMatch = {
    id: `hyprace-grand-prix-${grandPrixID}`,
    providerID: "hyprace",
    detailID: JSON.stringify(detail),
    sportID: "formula1",
    sportName: "Formula 1",
    competitionID: "formula1-hyprace-current",
    competitionName: "Current Grand Prix",
    country: firstString(record, ["country", "location"]),
    status: firstString(record, ["status", "state"]) ?? "Current",
    statusDetail: firstString(record, ["round", "raceType", "eventType"]) ?? `${hypraceSeasonYear} season`,
    clock: null,
    period: firstString(record, ["round", "seasonRound"]),
    startsAt: startDate,
    homeName: name,
    awayName: "Race weekend",
    homeScore: null,
    awayScore: null,
    scoreSummary: firstString(record, ["status", "state", "round"]) ?? "Current",
    homeLogoURL: null,
    awayLogoURL: null,
    venue: firstString(record, ["circuitName", "venue", "trackName"]),
    note: "Hyprace",
    scoreboardSections: null,
  }
  match.scoreboardSections = hypraceEventRows(payload).length > 0
    ? [scoreboardSection("grand-prix", name, ["Event", "Status", "Date"], hypraceEventRows(payload))]
    : genericSummarySections(match)
  return match
}

async function fetchHypraceFormula1(apiKey: string): Promise<LiveSportSection> {
  const [drivers, constructors, grandPrix] = await Promise.allSettled([
    fetchHypraceJSON(apiKey, "/v2/drivers-standings?isLastStanding=true&pageSize=10&pageNumber=1"),
    fetchHypraceJSON(apiKey, "/v2/constructors-standings?isLastStanding=true&pageSize=10&pageNumber=1"),
    fetchHypraceJSON(apiKey, "/v2/grands-prix?isCurrent=true&pageNumber=1&pageSize=10"),
  ])

  const matches: LiveMatch[] = []
  if (drivers.status === "fulfilled") {
    const match = hypraceStandingMatch("drivers-standings", drivers.value)
    if (match) matches.push(match)
  }
  if (constructors.status === "fulfilled") {
    const match = hypraceStandingMatch("constructors-standings", constructors.value)
    if (match) matches.push(match)
  }
  if (grandPrix.status === "fulfilled") {
    const match = hypraceGrandPrixMatch(grandPrix.value)
    if (match) matches.push(match)
  }

  if (matches.length === 0) {
    const errors = [drivers, constructors, grandPrix]
      .filter((result): result is PromiseRejectedResult => result.status === "rejected")
      .map((result) => result.reason instanceof Error ? result.reason.message : "Hyprace provider failed")
    if (errors.length > 0) throw new Error(errors[0])
  }

  return groupMatches("formula1", "Formula 1", "flag.checkered", matches)
}

function parseHypraceDetailID(detailID: string): HypraceDetailID | null {
  try {
    const parsed = JSON.parse(detailID)
    const record = asRecord(parsed)
    const kind = firstString(record ?? {}, ["kind"])
    if (
      kind === "drivers-standings" ||
      kind === "constructors-standings" ||
      kind === "grand-prix" ||
      kind === "race-results" ||
      kind === "qualifying-results"
    ) {
      return {
        kind,
        seasonId: firstString(record ?? {}, ["seasonId"]) ?? undefined,
        grandPrixId: firstString(record ?? {}, ["grandPrixId"]) ?? undefined,
        raceId: firstString(record ?? {}, ["raceId"]) ?? undefined,
        qualifyingId: firstString(record ?? {}, ["qualifyingId"]) ?? undefined,
      }
    }
  } catch (_) {
    return null
  }
  return null
}

async function fetchHypraceMatchDetail(apiKey: string, detailID: string): Promise<LiveMatchDetailResponse> {
  const detail = parseHypraceDetailID(detailID)
  if (!detail) throw new Error("Invalid Hyprace detail ID")

  if (detail.kind === "drivers-standings" || detail.kind === "constructors-standings") {
    const seasonId = detail.seasonId ?? hypraceSeasonID
    const seasonParam = detail.seasonId ? `seasonId=${seasonId}&` : ""
    const path = detail.kind === "drivers-standings"
      ? `/v2/drivers-standings?${seasonParam}isLastStanding=true&pageSize=30&pageNumber=1`
      : `/v2/constructors-standings?${seasonParam}isLastStanding=true&pageSize=30&pageNumber=1`
    const payload = await fetchHypraceJSON(apiKey, path)
    const match = hypraceStandingMatch(detail.kind, payload)
    if (!match) throw new Error("Hyprace standings returned no rows")
    return {
      generatedAt: isoWithoutMilliseconds(new Date()),
      match,
      scoreboardSections: match.scoreboardSections ?? genericSummarySections(match),
    }
  }

  if (detail.kind === "grand-prix" && detail.grandPrixId) {
    const [races, qualifying] = await Promise.allSettled([
      fetchHypraceJSON(apiKey, `/v2/grands-prix/${detail.grandPrixId}/races?pageNumber=1&type=MainRace&pageSize=10`),
      fetchHypraceJSON(apiKey, `/v2/grands-prix/${detail.grandPrixId}/qualifying?pageNumber=1&type=Standard&pageSize=10`),
    ])
    const raceRows = races.status === "fulfilled" ? hypraceEventRows(races.value) : []
    const qualifyingRows = qualifying.status === "fulfilled" ? hypraceEventRows(qualifying.value) : []
    const match = hypraceGrandPrixMatch({ data: [{ id: detail.grandPrixId, name: "Current Grand Prix" }] })
    if (!match) throw new Error("Hyprace Grand Prix detail returned no rows")
    const sections = [
      raceRows.length > 0 ? scoreboardSection("races", "Races", ["Event", "Status", "Date"], raceRows) : null,
      qualifyingRows.length > 0 ? scoreboardSection("qualifying", "Qualifying", ["Event", "Status", "Date"], qualifyingRows) : null,
    ].filter((section): section is ScoreboardSection => Boolean(section))
    match.scoreboardSections = sections.length > 0 ? sections : genericSummarySections(match)
    return {
      generatedAt: isoWithoutMilliseconds(new Date()),
      match,
      scoreboardSections: match.scoreboardSections,
    }
  }

  throw new Error("Hyprace detail type is not wired yet")
}

async function fetchFreeFootball(apiKey: string): Promise<LiveSportSection> {
  const payload = await fetchRapidJSON(apiKey, "free-api-live-football-data.p.rapidapi.com", "/football-current-live")
  const matches = payloadRecords(payload, ["events", "matches", "response", "data", "result"])
    .map((item) => normalizeRapidMatch("freefootball", "soccer", "Soccer", "soccerball", item))
    .filter((match): match is LiveMatch => Boolean(match))
  return groupMatches("soccer", "Soccer", "soccerball", matches)
}

const osSportsHost = "os-sports-perform.p.rapidapi.com"

function normalizeOSSportsPerformMatch(item: Record<string, unknown>): LiveMatch | null {
  const match = normalizeRapidMatch("os-sports-perform", "soccer", "Soccer", "soccerball", item)
  if (!match) return null

  const eventID = firstString(item, ["event_id", "eventId", "id", "match_id", "matchId"])
  return {
    ...match,
    id: `os-sports-perform-soccer-${eventID ?? stableID(`${match.homeName}|${match.awayName}|${match.startsAt ?? ""}`)}`,
    providerID: eventID ? "os-sports-perform" : match.providerID,
    detailID: eventID,
  }
}

async function fetchOSSportsPerformSoccer(apiKey: string): Promise<LiveSportSection> {
  const payload = await fetchRapidJSON(apiKey, osSportsHost, "/v1/events/schedule/live?sport_id=1")
  const matches = payloadRecords(payload, ["data", "events", "matches", "result"])
    .map((item) => normalizeOSSportsPerformMatch(item))
    .filter((match): match is LiveMatch => Boolean(match))
  return groupMatches("soccer", "Soccer", "soccerball", matches)
}

function osSportsDetailRows(payload: unknown, prefix: string): ScoreboardRow[] {
  return payloadRecords(payload, ["data", "events", "incidents", "statistics", "stats", "odds", "form", "items", "result"])
    .slice(0, 12)
    .map((record, index): ScoreboardRow | null => {
      const label = firstString(record, ["name", "title", "type", "incident_type", "market", "period", "team_name"]) ??
        `Item ${index + 1}`
      const value = firstString(record, ["value", "text", "description", "score", "odd", "odds", "result", "minute"])
      const side = firstString(record, ["team", "side", "home_away", "participant"])
      if (!value && !side && label.startsWith("Item ")) return null
      return {
        id: rowID(`${prefix}-${label}`, index),
        cells: safeCells([label, value, side]),
        note: null,
      }
    })
    .filter((row): row is ScoreboardRow => Boolean(row))
}

async function fetchOSSportsPerformMatchDetail(apiKey: string, detailID: string): Promise<LiveMatchDetailResponse> {
  const [eventData, statistics, incidents, odds, graphPoints] = await Promise.allSettled([
    fetchRapidJSON(apiKey, osSportsHost, `/v1/events/data?event_id=${encodeURIComponent(detailID)}`),
    fetchRapidJSON(apiKey, osSportsHost, `/v1/events/statistics?event_id=${encodeURIComponent(detailID)}`),
    fetchRapidJSON(apiKey, osSportsHost, `/v1/events/incidents?event_id=${encodeURIComponent(detailID)}`),
    fetchRapidJSON(apiKey, osSportsHost, `/v1/events/odds/all?odds_format=decimal&event_id=${encodeURIComponent(detailID)}&provider_id=1`),
    fetchRapidJSON(apiKey, osSportsHost, `/v1/events/graph-points?event_id=${encodeURIComponent(detailID)}`),
  ])

  const eventPayload = eventData.status === "fulfilled" ? eventData.value : {}
  const eventDirect = asRecord(eventPayload)
  const record = payloadRecords(eventPayload, ["data", "events", "matches", "result"])[0] ??
    asRecord(eventDirect?.data) ??
    eventDirect ??
    {}
  let fallbackMatch = normalizeOSSportsPerformMatch(record)
  if (!fallbackMatch) {
    try {
      const liveSection = await fetchOSSportsPerformSoccer(apiKey)
      fallbackMatch = liveSection.competitions
        .flatMap((competition) => competition.matches)
        .find((candidate) => candidate.detailID === detailID) ?? null
    } catch (_) {
      fallbackMatch = null
    }
  }
  const match: LiveMatch = fallbackMatch ?? {
    id: `os-sports-perform-soccer-${detailID}`,
    providerID: "os-sports-perform",
    detailID,
    sportID: "soccer",
    sportName: "Soccer",
    competitionID: "soccer-os-sports-perform",
    competitionName: competitionName(record),
    country: competitionCountry(record),
    status: firstString(record, ["status", "event_status", "statusDescription", "description"]) ?? "Live",
    statusDetail: firstString(record, ["statusDetail", "statusDescription", "description"]),
    clock: firstString(record, ["time", "clock", "minute", "currentMinute"]),
    period: firstString(record, ["period", "round", "stage"]),
    startsAt: isoFromLooseDate(firstString(record, ["startTime", "date", "start_at"])),
    homeName: teamName(record, "home") ?? "Home",
    awayName: teamName(record, "away") ?? "Away",
    homeScore: teamScore(record, "home"),
    awayScore: teamScore(record, "away"),
    scoreSummary: firstString(record, ["score", "scoreSummary", "result"]),
    homeLogoURL: teamLogo(record, "home"),
    awayLogoURL: teamLogo(record, "away"),
    venue: firstString(record, ["venue", "stadium"]),
    note: firstString(record, ["statusDetail", "statusDescription", "description"]),
    scoreboardSections: null,
  }

  const sections = [
    statistics.status === "fulfilled"
      ? scoreboardSection("statistics", "Statistics", ["Metric", "Value", "Team"], osSportsDetailRows(statistics.value, "os-stat"))
      : null,
    incidents.status === "fulfilled"
      ? scoreboardSection("incidents", "Incidents", ["Event", "Minute", "Team"], osSportsDetailRows(incidents.value, "os-incident"))
      : null,
    odds.status === "fulfilled"
      ? scoreboardSection("odds", "Odds", ["Market", "Value", "Side"], osSportsDetailRows(odds.value, "os-odds"))
      : null,
    graphPoints.status === "fulfilled"
      ? scoreboardSection("graph", "Graph Points", ["Point", "Value", "Side"], osSportsDetailRows(graphPoints.value, "os-graph"))
      : null,
  ].filter((section): section is ScoreboardSection => Boolean(section && section.rows.length > 0))

  match.scoreboardSections = sections.length > 0 ? sections : genericSummarySections(match)
  return {
    generatedAt: isoWithoutMilliseconds(new Date()),
    match,
    scoreboardSections: match.scoreboardSections,
  }
}

const rundownHost = "therundown-therundown-v1.p.rapidapi.com"
const rundownSoccerSportID = "2"

function rundownTeamName(record: Record<string, unknown>, side: "home" | "away"): string | null {
  const direct = teamName(record, side)
  if (direct) return direct

  const teams = [
    ...asArray(record.teams),
    ...asArray(record.teams_normalized),
    ...asArray(record.participants),
  ].map((item) => asRecord(item)).filter((item): item is Record<string, unknown> => Boolean(item))
  const sideKeys = side === "home"
    ? ["is_home", "home", "isHome", "home_team"]
    : ["is_away", "away", "isAway", "away_team"]
  const candidate = teams.find((team) => sideKeys.some((key) => team[key] === true || team[key] === 1 || team[key] === "true"))
  return firstString(candidate ?? {}, ["name", "team_name", "display_name", "full_name", "school", "mascot"])
}

function rundownCompetition(record: Record<string, unknown>) {
  return firstString(record, ["league_name", "league", "conference", "division", "sport_name"]) ?? "Rundown soccer schedule"
}

function rundownStartsAt(record: Record<string, unknown>) {
  const direct = firstString(record, ["event_date", "event_date_utc", "start_time", "starts_at", "date_event", "scheduled"])
  if (direct) return isoFromLooseDate(direct)
  const schedule = nestedRecord(record, ["schedule"])
  return schedule ? isoFromLooseDate(firstString(schedule, ["date", "datetime", "start_time", "event_date"])) : null
}

function normalizeRundownMatch(item: Record<string, unknown>): LiveMatch | null {
  const homeName = rundownTeamName(item, "home")
  const awayName = rundownTeamName(item, "away")
  if (!homeName || !awayName) return null

  const detailID = firstString(item, ["event_id", "eventId", "id"])
  const competition = rundownCompetition(item)
  const scoreSummary = firstString(item, ["score", "scoreSummary", "event_final_result", "result"])
  const [parsedHomeScore, parsedAwayScore] = splitScore(scoreSummary)
  const status = firstString(item, ["status", "event_status", "status_detail"]) ?? "Scheduled"
  const startsAt = rundownStartsAt(item)
  const match: LiveMatch = {
    id: `rundown-soccer-${detailID ?? stableID(`${competition}|${homeName}|${awayName}|${startsAt ?? ""}`)}`,
    providerID: detailID ? "rundown" : null,
    detailID,
    sportID: "soccer",
    sportName: "Soccer",
    competitionID: `soccer-rundown-${stableID(competition)}`,
    competitionName: competition,
    country: competitionCountry(item),
    status,
    statusDetail: firstString(item, ["status_detail", "statusDetail", "broadcast", "broadcast_network"]),
    clock: firstString(item, ["clock", "time", "event_clock"]),
    period: firstString(item, ["period", "season_type", "season"]),
    startsAt,
    homeName,
    awayName,
    homeScore: teamScore(item, "home") ?? parsedHomeScore,
    awayScore: teamScore(item, "away") ?? parsedAwayScore,
    scoreSummary,
    homeLogoURL: teamLogo(item, "home"),
    awayLogoURL: teamLogo(item, "away"),
    venue: firstString(item, ["venue", "venue_name", "stadium"]),
    note: "Rundown schedule, odds and stats",
    scoreboardSections: null,
  }
  match.scoreboardSections = genericSummarySections(match)
  return match
}

function rundownRecords(payload: unknown): Record<string, unknown>[] {
  const directRecords = payloadRecords(payload, ["events", "data", "schedule", "schedules", "results", "games"])
  const root = asRecord(payload)
  const nested: Record<string, unknown>[] = []
  for (const key of ["events", "data", "schedule", "schedules", "results", "games"]) {
    const value = root?.[key]
    const record = asRecord(value)
    if (record) {
      nested.push(...Object.values(record).map((item) => asRecord(item)).filter((item): item is Record<string, unknown> => Boolean(item)))
    }
  }
  for (const record of directRecords) {
    const event = asRecord(record.event) ?? asRecord(record.game)
    if (event) nested.push(event)
  }
  return [...directRecords, ...nested]
}

async function fetchRundownSoccerSchedule(apiKey: string): Promise<LiveSportSection> {
  const today = new Date()
  const tomorrow = new Date(today.getTime() + dayMS)
  const eventPath = (date: Date) =>
    `/sports/${rundownSoccerSportID}/events/${date.toISOString().slice(0, 10)}?include=scores&affiliate_ids=1%2C2%2C3&offset=0`
  const results = await Promise.allSettled([
    fetchRapidJSON(apiKey, rundownHost, eventPath(today)),
    fetchRapidJSON(apiKey, rundownHost, eventPath(tomorrow)),
    fetchRapidJSON(apiKey, rundownHost, `/sports/${rundownSoccerSportID}/schedule?limit=100`),
  ])
  const records = results.flatMap((result) => result.status === "fulfilled" ? rundownRecords(result.value) : [])
  const matches = records
    .map((item) => normalizeRundownMatch(item))
    .filter((match): match is LiveMatch => Boolean(match))
    .slice(0, 24)
  return groupMatches("soccer", "Soccer", "soccerball", matches)
}

function rundownValue(record: Record<string, unknown>) {
  return firstString(record, [
    "value",
    "line",
    "price",
    "odds",
    "american",
    "decimal",
    "total",
    "spread",
    "score",
    "stat",
  ])
}

function rundownRows(payload: unknown, prefix: string): ScoreboardRow[] {
  return payloadRecords(payload, [
    "events",
    "data",
    "lines",
    "markets",
    "participants",
    "stats",
    "teams",
    "players",
    "scores",
    "results",
  ])
    .slice(0, 18)
    .map((record, index): ScoreboardRow | null => {
      const label = firstString(record, [
        "name",
        "market_name",
        "participant_name",
        "team_name",
        "player_name",
        "affiliate_name",
        "sportsbook",
        "type",
      ]) ?? `Item ${index + 1}`
      const value = rundownValue(record)
      const note = firstString(record, ["period", "side", "updated_at", "status", "description"])
      if (!value && !note && label.startsWith("Item ")) return null
      return {
        id: rowID(`${prefix}-${label}`, index),
        cells: safeCells([label, value, note]),
        note: null,
      }
    })
    .filter((row): row is ScoreboardRow => Boolean(row))
}

async function fetchRundownMatchDetail(apiKey: string, detailID: string): Promise<LiveMatchDetailResponse> {
  const [event, stats, markets, moneyline, spread, totals] = await Promise.allSettled([
    fetchRapidJSON(apiKey, rundownHost, `/events/${encodeURIComponent(detailID)}?include=scores`),
    fetchRapidJSON(apiKey, rundownHost, `/v2/events/${encodeURIComponent(detailID)}/stats`),
    fetchRapidJSON(apiKey, rundownHost, `/v2/events/${encodeURIComponent(detailID)}/markets`),
    fetchRapidJSON(apiKey, rundownHost, `/lines/${encodeURIComponent(detailID)}/moneyline?include=all_periods`),
    fetchRapidJSON(apiKey, rundownHost, `/lines/${encodeURIComponent(detailID)}/spread?include=all_periods`),
    fetchRapidJSON(apiKey, rundownHost, `/lines/${encodeURIComponent(detailID)}/totals?include=all_periods`),
  ])

  const eventPayload = event.status === "fulfilled" ? event.value : {}
  const record = payloadRecords(eventPayload, ["events", "data", "results"])[0] ??
    asRecord(asRecord(eventPayload)?.event) ??
    asRecord(eventPayload) ??
    {}
  const fallback = normalizeRundownMatch(record)
  const match: LiveMatch = fallback ?? {
    id: `rundown-soccer-${detailID}`,
    providerID: "rundown",
    detailID,
    sportID: "soccer",
    sportName: "Soccer",
    competitionID: "soccer-rundown",
    competitionName: rundownCompetition(record),
    country: competitionCountry(record),
    status: firstString(record, ["status", "event_status"]) ?? "Scheduled",
    statusDetail: firstString(record, ["status_detail", "statusDetail"]),
    clock: firstString(record, ["clock", "time"]),
    period: firstString(record, ["period", "season_type", "season"]),
    startsAt: rundownStartsAt(record),
    homeName: rundownTeamName(record, "home") ?? "Home",
    awayName: rundownTeamName(record, "away") ?? "Away",
    homeScore: teamScore(record, "home"),
    awayScore: teamScore(record, "away"),
    scoreSummary: firstString(record, ["score", "scoreSummary", "result"]),
    homeLogoURL: teamLogo(record, "home"),
    awayLogoURL: teamLogo(record, "away"),
    venue: firstString(record, ["venue", "venue_name", "stadium"]),
    note: "Rundown",
    scoreboardSections: null,
  }

  const sections = [
    event.status === "fulfilled"
      ? scoreboardSection("event", "Event", ["Field", "Value", "Info"], rundownRows(event.value, "rundown-event"))
      : null,
    stats.status === "fulfilled"
      ? scoreboardSection("stats", "Stats", ["Metric", "Value", "Info"], rundownRows(stats.value, "rundown-stats"))
      : null,
    markets.status === "fulfilled"
      ? scoreboardSection("markets", "Markets", ["Market", "Value", "Info"], rundownRows(markets.value, "rundown-markets"))
      : null,
    moneyline.status === "fulfilled"
      ? scoreboardSection("moneyline", "Moneyline", ["Book", "Odds", "Info"], rundownRows(moneyline.value, "rundown-moneyline"))
      : null,
    spread.status === "fulfilled"
      ? scoreboardSection("spread", "Spread", ["Book", "Line", "Info"], rundownRows(spread.value, "rundown-spread"))
      : null,
    totals.status === "fulfilled"
      ? scoreboardSection("totals", "Totals", ["Book", "Total", "Info"], rundownRows(totals.value, "rundown-totals"))
      : null,
  ].filter((section): section is ScoreboardSection => Boolean(section && section.rows.length > 0))

  match.scoreboardSections = sections.length > 0 ? sections : genericSummarySections(match)
  return {
    generatedAt: isoWithoutMilliseconds(new Date()),
    match,
    scoreboardSections: match.scoreboardSections,
  }
}

function cricketDataTeamInfo(item: Record<string, unknown>, teamName: string | null): Record<string, unknown> | null {
  if (!teamName) return null
  return asArray(item.teamInfo)
    .map((team) => asRecord(team))
    .find((team) => firstString(team ?? {}, ["name", "shortname"]) === teamName) ?? null
}

function cricketDataScoreRows(scores: unknown[]): ScoreboardRow[] {
  return asArray(scores)
    .map((rawScore, index) => {
      const score = asRecord(rawScore) ?? {}
      const inning = firstString(score, ["inning"]) ?? `Innings ${index + 1}`
      const runs = numberString(score.r)
      const wickets = numberString(score.w)
      const overs = numberString(score.o)
      return {
        id: rowID(`cricketdata-score-${inning}`, index),
        cells: safeCells([
          inning,
          runs,
          wickets,
          overs,
        ]),
        note: null,
      }
    })
    .filter((row) => row.cells.some((cell) => cell.length > 0))
}

function cricketDataScoreForTeam(scores: unknown[], teamName: string | null): string | null {
  if (!teamName) return null
  const teamPrefix = teamName.toLowerCase()
  for (const rawScore of asArray(scores)) {
    const score = asRecord(rawScore) ?? {}
    const inning = firstString(score, ["inning"])?.toLowerCase()
    if (!inning?.startsWith(teamPrefix)) continue

    const runs = numberString(score.r)
    if (!runs) return null

    const wickets = numberString(score.w)
    const overs = numberString(score.o)
    return `${runs}${wickets ? `/${wickets}` : ""}${overs ? ` (${overs})` : ""}`
  }
  return null
}

function normalizeCricketDataMatch(item: Record<string, unknown>): LiveMatch | null {
  const status = firstString(item, ["status"]) ?? "Live"
  const lowerStatus = status.toLowerCase()
  const matchStarted = item.matchStarted === true || lowerStatus.includes("live")
  const matchEnded = item.matchEnded === true ||
    ["won by", "draw", "abandon", "cancel", "no result", "complete"].some((token) => lowerStatus.includes(token))
  if (!matchStarted || matchEnded) return null

  const teams = asArray(item.teams).map((team) => asString(team)).filter((team): team is string => Boolean(team))
  const homeName = teams[0] ?? firstString(item, ["team1", "homeTeam"])
  const awayName = teams[1] ?? firstString(item, ["team2", "awayTeam"])
  if (!homeName || !awayName) return null

  const scores = asArray(item.score)
  const homeInfo = cricketDataTeamInfo(item, homeName)
  const awayInfo = cricketDataTeamInfo(item, awayName)
  const matchID = firstString(item, ["id"]) ?? stableID(`cricketdata|${homeName}|${awayName}|${firstString(item, ["dateTimeGMT", "date"]) ?? ""}`)
  const competitionName = firstString(item, ["series", "name"]) ?? "Cricket"
  const competitionID = stableID(competitionName)
  const startsAtText = firstString(item, ["dateTimeGMT", "dateTime", "date"])
  const startsAt = startsAtText ? isoWithoutMilliseconds(new Date(startsAtText.replace(" ", "T") + "Z")) : null
  const scoreRows = cricketDataScoreRows(scores)

  const match: LiveMatch = {
    id: `cricketdata-${matchID}`,
    providerID: null,
    detailID: null,
    sportID: "cricket",
    sportName: "Cricket",
    competitionID: `cricket-cricketdata-${competitionID}`,
    competitionName,
    country: null,
    status,
    statusDetail: status,
    clock: null,
    period: firstString(item, ["matchType"]),
    startsAt,
    homeName,
    awayName,
    homeScore: cricketDataScoreForTeam(scores, homeName),
    awayScore: cricketDataScoreForTeam(scores, awayName),
    scoreSummary: scoreRows.map((row) => `${row.cells[0]} ${row.cells[1]}/${row.cells[2]} (${row.cells[3]})`).join(" | ") || null,
    homeLogoURL: firstString(homeInfo ?? {}, ["img"]),
    awayLogoURL: firstString(awayInfo ?? {}, ["img"]),
    venue: firstString(item, ["venue"]),
    note: status,
    scoreboardSections: null,
  }
  match.scoreboardSections = scoreRows.length > 0
    ? [scoreboardSection("score", "Scorecard", ["Innings", "R", "W", "O"], scoreRows)]
    : genericSummarySections(match)
  return match
}

function cricketLiveLineTeamName(item: Record<string, unknown>, side: "home" | "away"): string | null {
  const direct = side === "home"
    ? firstString(item, ["team_a", "teamA", "team_a_name", "teamAName", "team1", "team_1", "localteam", "home_team", "homeTeam"])
    : firstString(item, ["team_b", "teamB", "team_b_name", "teamBName", "team2", "team_2", "visitorteam", "away_team", "awayTeam"])
  if (direct) return direct

  const nested = side === "home"
    ? nestedRecord(item, ["team_a", "teamA", "team1", "localteam", "homeTeam"])
    : nestedRecord(item, ["team_b", "teamB", "team2", "visitorteam", "awayTeam"])
  return nested ? firstString(nested, ["name", "shortName", "short_name", "teamName"]) : null
}

function cricketLiveLineScore(item: Record<string, unknown>, side: "home" | "away"): string | null {
  const score = side === "home"
    ? firstString(item, ["team_a_scores", "teamAScores", "team_a_score", "team1_score", "localteam_score", "home_score"])
    : firstString(item, ["team_b_scores", "teamBScores", "team_b_score", "team2_score", "visitorteam_score", "away_score"])
  const overs = side === "home"
    ? firstString(item, ["team_a_over", "team_a_scores_over", "teamAOver", "team1_over", "localteam_overs", "home_overs"])
    : firstString(item, ["team_b_over", "team_b_scores_over", "teamBOver", "team2_over", "visitorteam_overs", "away_overs"])

  if (!score) return null
  return overs ? `${score} (${overs})` : score
}

function cricketLiveLineDate(item: Record<string, unknown>): string | null {
  const raw = firstString(item, ["dateTimeGMT", "date_time", "match_time", "datetime", "date_wise", "date"])
  if (!raw) return null
  const normalized = raw.includes("T") ? raw : raw.replace(" ", "T")
  const parsed = new Date(normalized.endsWith("Z") ? normalized : `${normalized}Z`)
  return Number.isNaN(parsed.getTime()) ? null : isoWithoutMilliseconds(parsed)
}

function cricketLiveLineRows(item: Record<string, unknown>, homeName: string, awayName: string): ScoreboardRow[] {
  return [
    {
      id: "home-score",
      cells: safeCells([homeName, cricketLiveLineScore(item, "home") ?? "-"]),
      note: null,
    },
    {
      id: "away-score",
      cells: safeCells([awayName, cricketLiveLineScore(item, "away") ?? "-"]),
      note: null,
    },
  ].filter((row) => row.cells.some((cell) => cell && cell !== "-"))
}

function normalizeCricketLiveLineMatch(item: Record<string, unknown>, feed: MatchFeed): LiveMatch | null {
  if (feed === "live" && !isLive(item)) return null

  const homeName = cricketLiveLineTeamName(item, "home")
  const awayName = cricketLiveLineTeamName(item, "away")
  if (!homeName || !awayName) return null

  const matchID = firstString(item, ["match_id", "matchId", "id", "match_key"]) ??
    stableID(`cricket-live-line|${homeName}|${awayName}|${firstString(item, ["date_wise", "match_time", "date"]) ?? ""}`)
  const competitionName = firstString(item, ["series", "series_name", "seriesName", "league", "competition", "matchs"]) ?? "Cricket"
  const competitionID = firstString(item, ["series_id", "seriesId", "league_id"]) ?? stableID(competitionName)
  const status = firstString(item, ["match_status", "status", "status_note", "result", "match_result"]) ??
    (feed === "upcoming" ? "Upcoming" : feed === "recent" ? "Result" : "Live")
  const homeScore = cricketLiveLineScore(item, "home")
  const awayScore = cricketLiveLineScore(item, "away")

  const match: LiveMatch = {
    id: `cricket-live-line-${feed}-${matchID}`,
    providerID: "cricket-live-line",
    detailID: matchID,
    sportID: "cricket",
    sportName: "Cricket",
    competitionID: `cricket-live-line-${competitionID}`,
    competitionName,
    country: firstString(item, ["country", "venue_country"]),
    status,
    statusDetail: firstString(item, ["status_note", "result", "match_result", "toss"]) ?? status,
    clock: firstString(item, ["current_inning", "session", "live", "match_status"]),
    period: firstString(item, ["match_type", "matchType", "matchs"]),
    startsAt: cricketLiveLineDate(item),
    homeName,
    awayName,
    homeScore,
    awayScore,
    scoreSummary: [homeScore, awayScore].filter(Boolean).join(" | ") || firstString(item, ["score", "scorecard"]),
    homeLogoURL: firstString(item, ["team_a_img", "teamAImg", "team1_img", "home_team_logo"]),
    awayLogoURL: firstString(item, ["team_b_img", "teamBImg", "team2_img", "away_team_logo"]),
    venue: firstString(item, ["venue", "venue_name", "place"]),
    note: firstString(item, ["status_note", "result", "match_result", "toss"]),
    scoreboardSections: null,
  }

  const rows = cricketLiveLineRows(item, homeName, awayName)
  match.scoreboardSections = rows.length > 0
    ? [scoreboardSection("score", "Scorecard", ["Team", "Score"], rows)]
    : genericSummarySections(match)
  return match
}

async function fetchCricketLiveLineMatches(apiKey: string, feed: MatchFeed): Promise<LiveSportSection> {
  const pathByFeed: Record<MatchFeed, string> = {
    live: "/liveMatches",
    upcoming: "/upcomingMatches",
    recent: "/recentMatches",
  }
  const payload = await fetchRapidJSON(apiKey, "cricket-live-line1.p.rapidapi.com", pathByFeed[feed])
  const matches = payloadRecords(payload, ["data", "matches", "result", "response"])
    .map((item) => normalizeCricketLiveLineMatch(item, feed))
    .filter((match): match is LiveMatch => Boolean(match))
  return groupMatches("cricket", "Cricket", "figure.cricket", matches)
}

function cricketLiveLineScorecardSections(payload: unknown): ScoreboardSection[] {
  const records = payloadRecords(payload, [
    "data",
    "scorecard",
    "scoreCard",
    "score_card",
    "innings",
    "batting",
    "bowling",
    "result",
  ])

  const rows: ScoreboardRow[] = []
  for (const [index, record] of records.entries()) {
    const title = firstString(record, ["name", "player", "batsman", "bowler", "team", "inning", "title"]) ??
      `Row ${index + 1}`
    const runs = firstString(record, ["runs", "run", "r"])
    const balls = firstString(record, ["balls", "ball", "b"])
    const fours = firstString(record, ["fours", "4s", "four"])
    const sixes = firstString(record, ["sixes", "6s", "six"])
    const strikeRate = firstString(record, ["strike_rate", "strikeRate", "sr"])
    const overs = firstString(record, ["overs", "over", "o"])
    const wickets = firstString(record, ["wickets", "wicket", "w"])
    const economy = firstString(record, ["economy", "econ", "er"])
    const values = [runs, balls, fours, sixes, strikeRate, overs, wickets, economy].filter(Boolean)
    if (values.length === 0 && title.startsWith("Row ")) continue

    rows.push({
      id: rowID(`cricket-live-line-scorecard-${title}`, index),
      cells: safeCells([title, ...values.slice(0, 5)]),
      note: firstString(record, ["out_by", "dismissal", "how_out", "status", "comment"]),
    })
  }

  return rows.length > 0
    ? [scoreboardSection("scorecard", "Scorecard", ["Player", "1", "2", "3", "4", "5"], rows)]
    : []
}

async function fetchCricketLiveLineMatchDetail(apiKey: string, detailID: string): Promise<LiveMatchDetailResponse> {
  const payload = await fetchRapidJSON(apiKey, "cricket-live-line1.p.rapidapi.com", `/match/${detailID}/scorecard`)
  const root = asRecord(payload) ?? {}
  const record = payloadRecords(payload, ["data", "match", "result", "response"])[0] ?? root
  const homeName = cricketLiveLineTeamName(record, "home") ?? "Home"
  const awayName = cricketLiveLineTeamName(record, "away") ?? "Away"
  const status = firstString(record, ["match_status", "status", "status_note", "result", "match_result"]) ?? "Live"

  const match: LiveMatch = {
    id: `cricket-live-line-detail-${detailID}`,
    providerID: "cricket-live-line",
    detailID,
    sportID: "cricket",
    sportName: "Cricket",
    competitionID: `cricket-live-line-${firstString(record, ["series_id", "seriesId"]) ?? "detail"}`,
    competitionName: firstString(record, ["series", "series_name", "seriesName", "league", "competition"]) ?? "Cricket",
    country: firstString(record, ["country", "venue_country"]),
    status,
    statusDetail: firstString(record, ["status_note", "result", "match_result", "toss"]) ?? status,
    clock: firstString(record, ["current_inning", "session", "live", "match_status"]),
    period: firstString(record, ["match_type", "matchType", "matchs"]),
    startsAt: cricketLiveLineDate(record),
    homeName,
    awayName,
    homeScore: cricketLiveLineScore(record, "home"),
    awayScore: cricketLiveLineScore(record, "away"),
    scoreSummary: firstString(record, ["score", "scorecard"]),
    homeLogoURL: firstString(record, ["team_a_img", "teamAImg", "team1_img", "home_team_logo"]),
    awayLogoURL: firstString(record, ["team_b_img", "teamBImg", "team2_img", "away_team_logo"]),
    venue: firstString(record, ["venue", "venue_name", "place"]),
    note: firstString(record, ["status_note", "result", "match_result", "toss"]),
    scoreboardSections: null,
  }

  const sections = cricketLiveLineScorecardSections(payload)
  match.scoreboardSections = sections.length > 0 ? sections : genericSummarySections(match)
  return {
    generatedAt: isoWithoutMilliseconds(new Date()),
    match,
    scoreboardSections: match.scoreboardSections,
  }
}

const cricketLiveDataHost = "cricket-live-data.p.rapidapi.com"

function datePathInTimezone(timezone: string, offsetDays = 0) {
  const base = new Date(Date.now() + offsetDays * dayMS)
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(base)
  const get = (type: string) => parts.find((part) => part.type === type)?.value ?? ""
  return `${get("year")}-${get("month")}-${get("day")}`
}

function cricketLiveDataRecords(payload: unknown): Record<string, unknown>[] {
  return payloadRecords(payload, [
    "data",
    "matches",
    "fixtures",
    "results",
    "match",
    "response",
    "result",
  ])
}

function cricketLiveDataTeamName(item: Record<string, unknown>, side: "home" | "away"): string | null {
  const direct = side === "home"
    ? firstString(item, ["home", "home_name", "homeName", "homeTeam", "home_team", "team1", "team_1", "teamA", "team_a", "localteam"])
    : firstString(item, ["away", "away_name", "awayName", "awayTeam", "away_team", "team2", "team_2", "teamB", "team_b", "visitorteam"])
  if (direct) return direct

  const nested = side === "home"
    ? nestedRecord(item, ["home", "homeTeam", "home_team", "team1", "teamA", "localteam"])
    : nestedRecord(item, ["away", "awayTeam", "away_team", "team2", "teamB", "visitorteam"])
  return nested ? firstString(nested, ["name", "teamName", "shortName", "short_name", "title"]) : null
}

function cricketLiveDataScore(item: Record<string, unknown>, side: "home" | "away"): string | null {
  const direct = side === "home"
    ? firstString(item, ["home_score", "homeScore", "team1_score", "team1Score", "team_a_score", "teamAScore", "localteam_score"])
    : firstString(item, ["away_score", "awayScore", "team2_score", "team2Score", "team_b_score", "teamBScore", "visitorteam_score"])
  if (direct) return direct

  const nested = side === "home"
    ? nestedRecord(item, ["home", "homeTeam", "home_score", "team1", "teamA", "localteam"])
    : nestedRecord(item, ["away", "awayTeam", "away_score", "team2", "teamB", "visitorteam"])
  return nested ? firstString(nested, ["score", "runs", "innings", "display", "current"]) : null
}

function cricketLiveDataStartsAt(item: Record<string, unknown>): string | null {
  return isoFromLooseDate(firstString(item, [
    "dateTimeGMT",
    "date_time",
    "datetime",
    "startTime",
    "start_time",
    "startDate",
    "start_date",
    "match_date",
    "date",
  ]))
}

function normalizeCricketLiveDataMatch(item: Record<string, unknown>, feed: MatchFeed): LiveMatch | null {
  const homeName = cricketLiveDataTeamName(item, "home")
  const awayName = cricketLiveDataTeamName(item, "away")
  if (!homeName || !awayName) return null

  const matchID = firstString(item, ["id", "match_id", "matchId", "fixture_id", "fixtureId", "key"]) ??
    stableID(`cricket-live-data|${homeName}|${awayName}|${firstString(item, ["date", "startTime", "match_date"]) ?? ""}`)
  const competition = firstString(item, ["series", "series_name", "seriesName", "competition", "league", "tournament", "name"]) ?? "Cricket"
  const status = firstString(item, ["status", "match_status", "status_note", "result", "match_result", "state"]) ??
    (feed === "recent" ? "Result" : feed === "upcoming" ? "Scheduled" : "Live")
  const statusDetail = firstString(item, ["status_note", "statusDetail", "result", "match_result", "description", "toss"]) ?? status
  const homeScore = cricketLiveDataScore(item, "home")
  const awayScore = cricketLiveDataScore(item, "away")

  const match: LiveMatch = {
    id: `cricket-live-data-${feed}-${matchID}`,
    providerID: "cricket-live-data",
    detailID: matchID,
    sportID: "cricket",
    sportName: "Cricket",
    competitionID: `cricket-live-data-${stableID(competition)}`,
    competitionName: competition,
    country: firstString(item, ["country", "venue_country"]),
    status,
    statusDetail,
    clock: firstString(item, ["current_inning", "innings", "session", "day"]),
    period: firstString(item, ["match_type", "matchType", "format", "round"]),
    startsAt: cricketLiveDataStartsAt(item),
    homeName,
    awayName,
    homeScore,
    awayScore,
    scoreSummary: [homeScore, awayScore].filter(Boolean).join(" | ") || firstString(item, ["score", "scorecard"]),
    homeLogoURL: firstString(item, ["home_logo", "homeLogo", "team1Logo", "team_a_img"]),
    awayLogoURL: firstString(item, ["away_logo", "awayLogo", "team2Logo", "team_b_img"]),
    venue: firstString(item, ["venue", "venue_name", "ground", "stadium"]),
    note: statusDetail,
    scoreboardSections: null,
  }
  match.scoreboardSections = genericSummarySections(match)
  return match
}

async function fetchCricketLiveDataMatches(apiKey: string, timezone: string, feed: MatchFeed): Promise<LiveSportSection> {
  const path = feed === "recent"
    ? `/results-by-date/${datePathInTimezone(timezone, -1)}`
    : `/fixtures-by-date/${datePathInTimezone(timezone, feed === "upcoming" ? 1 : 0)}`
  const payload = await fetchRapidJSON(apiKey, cricketLiveDataHost, path)
  const matches = cricketLiveDataRecords(payload)
    .map((item) => normalizeCricketLiveDataMatch(item, feed))
    .filter((match): match is LiveMatch => Boolean(match))
  return groupMatches("cricket", "Cricket", "figure.cricket", matches)
}

function cricketLiveDataScorecardSections(payload: unknown): ScoreboardSection[] {
  const records = payloadRecords(payload, [
    "scorecard",
    "scoreCard",
    "score_card",
    "innings",
    "batting",
    "bowling",
    "players",
    "data",
    "match",
    "result",
  ])

  const rows = records
    .map((record, index) => {
      const name = firstString(record, ["name", "player", "batsman", "bowler", "team", "title", "inning"]) ??
        `Row ${index + 1}`
      const values = [
        firstString(record, ["runs", "run", "r", "score"]),
        firstString(record, ["balls", "ball", "b"]),
        firstString(record, ["fours", "4s", "four"]),
        firstString(record, ["sixes", "6s", "six"]),
        firstString(record, ["strike_rate", "strikeRate", "sr"]),
        firstString(record, ["overs", "over", "o"]),
        firstString(record, ["wickets", "wicket", "w"]),
        firstString(record, ["economy", "econ", "er"]),
      ].filter(Boolean)

      if (values.length === 0 && name.startsWith("Row ")) return null
      return {
        id: rowID(`cricket-live-data-scorecard-${name}`, index),
        cells: safeCells([name, ...values.slice(0, 5)]),
        note: firstString(record, ["dismissal", "out_by", "how_out", "status", "comment", "description"]),
      }
    })
    .filter((row): row is ScoreboardRow => Boolean(row))

  return rows.length > 0
    ? [scoreboardSection("scorecard", "Scorecard", ["Player", "1", "2", "3", "4", "5"], rows)]
    : []
}

async function fetchCricketLiveDataMatchDetail(apiKey: string, detailID: string): Promise<LiveMatchDetailResponse> {
  const payload = await fetchRapidJSON(apiKey, cricketLiveDataHost, `/match/${encodeURIComponent(detailID)}`)
  const record = cricketLiveDataRecords(payload)[0] ?? asRecord(payload) ?? {}
  const fallbackMatch = normalizeCricketLiveDataMatch(record, "live")
  const match = fallbackMatch ?? {
    id: `cricket-live-data-detail-${detailID}`,
    providerID: "cricket-live-data",
    detailID,
    sportID: "cricket",
    sportName: "Cricket",
    competitionID: "cricket-live-data-detail",
    competitionName: firstString(record, ["series", "series_name", "seriesName", "competition", "league"]) ?? "Cricket",
    country: firstString(record, ["country", "venue_country"]),
    status: firstString(record, ["status", "match_status", "status_note", "result"]) ?? "Cricket",
    statusDetail: firstString(record, ["status_note", "result", "match_result", "description"]),
    clock: firstString(record, ["current_inning", "innings", "session", "day"]),
    period: firstString(record, ["match_type", "matchType", "format", "round"]),
    startsAt: cricketLiveDataStartsAt(record),
    homeName: cricketLiveDataTeamName(record, "home") ?? "Team 1",
    awayName: cricketLiveDataTeamName(record, "away") ?? "Team 2",
    homeScore: cricketLiveDataScore(record, "home"),
    awayScore: cricketLiveDataScore(record, "away"),
    scoreSummary: firstString(record, ["score", "scorecard"]),
    homeLogoURL: firstString(record, ["home_logo", "homeLogo", "team1Logo", "team_a_img"]),
    awayLogoURL: firstString(record, ["away_logo", "awayLogo", "team2Logo", "team_b_img"]),
    venue: firstString(record, ["venue", "venue_name", "ground", "stadium"]),
    note: firstString(record, ["status_note", "result", "match_result", "description"]),
    scoreboardSections: null,
  } satisfies LiveMatch

  const sections = cricketLiveDataScorecardSections(payload)
  match.scoreboardSections = sections.length > 0 ? sections : genericSummarySections(match)
  return {
    generatedAt: isoWithoutMilliseconds(new Date()),
    match,
    scoreboardSections: match.scoreboardSections,
  }
}

function espnCricinfoMatchID(item: Record<string, unknown>): string | null {
  return firstString(item, ["match_id", "matchId", "id", "objectId", "gameId"])
}

function espnCricinfoTeamName(item: Record<string, unknown>, side: "home" | "away"): string | null {
  const direct = side === "home"
    ? firstString(item, ["team1", "team_1", "teamA", "team_a", "homeTeam", "home_team", "team1Name"])
    : firstString(item, ["team2", "team_2", "teamB", "team_b", "awayTeam", "away_team", "team2Name"])
  if (direct) return direct

  const nested = side === "home"
    ? nestedRecord(item, ["team1", "teamA", "homeTeam", "home"])
    : nestedRecord(item, ["team2", "teamB", "awayTeam", "away"])
  return nested ? firstString(nested, ["name", "longName", "shortName", "displayName"]) : null
}

function espnCricinfoScore(item: Record<string, unknown>, side: "home" | "away"): string | null {
  const direct = side === "home"
    ? firstString(item, ["team1Score", "team_1_score", "teamAScore", "team_a_score", "homeScore", "home_score"])
    : firstString(item, ["team2Score", "team_2_score", "teamBScore", "team_b_score", "awayScore", "away_score"])
  if (direct) return direct

  const nested = side === "home"
    ? nestedRecord(item, ["team1", "teamA", "homeTeam", "home"])
    : nestedRecord(item, ["team2", "teamB", "awayTeam", "away"])
  return nested ? firstString(nested, ["score", "scoreText", "runs", "innings"]) : null
}

function espnCricinfoDetailID(item: Record<string, unknown>, matchID: string): string {
  const payload = {
    match_id: matchID,
    series_slug: firstString(item, ["series_slug", "seriesSlug"]),
    match_slug: firstString(item, ["match_slug", "matchSlug"]),
  }
  return JSON.stringify(payload)
}

function parseEspnCricinfoDetailID(detailID: string): { match_id: string, series_slug?: string, match_slug?: string } {
  try {
    const parsed = JSON.parse(detailID)
    if (parsed && typeof parsed === "object" && typeof parsed.match_id === "string") {
      return {
        match_id: parsed.match_id,
        series_slug: typeof parsed.series_slug === "string" ? parsed.series_slug : undefined,
        match_slug: typeof parsed.match_slug === "string" ? parsed.match_slug : undefined,
      }
    }
  } catch {
    // Older clients may send just the match id.
  }
  return { match_id: detailID }
}

function normalizeEspnCricinfoMatch(item: Record<string, unknown>): LiveMatch | null {
  if (!isLive(item)) return null

  const homeName = espnCricinfoTeamName(item, "home")
  const awayName = espnCricinfoTeamName(item, "away")
  if (!homeName || !awayName) return null

  const matchID = espnCricinfoMatchID(item) ??
    stableID(`espncricinfo|${homeName}|${awayName}|${firstString(item, ["date", "startTime", "startDate"]) ?? ""}`)
  const competitionName = firstString(item, ["series", "seriesName", "series_name", "competition", "league"]) ?? "Cricket"
  const homeScore = espnCricinfoScore(item, "home")
  const awayScore = espnCricinfoScore(item, "away")
  const status = firstString(item, ["status", "statusText", "status_note", "description", "match_status"]) ?? "Live"
  const startTime = firstString(item, ["startTime", "startDate", "dateTimeGMT", "date"])
  const startsAt = isoFromLooseDate(startTime)

  const match: LiveMatch = {
    id: `espncricinfo-live-${matchID}`,
    providerID: "espncricinfo",
    detailID: espnCricinfoDetailID(item, matchID),
    sportID: "cricket",
    sportName: "Cricket",
    competitionID: `espncricinfo-${stableID(competitionName)}`,
    competitionName,
    country: firstString(item, ["country", "groundCountry"]),
    status,
    statusDetail: firstString(item, ["statusText", "status_note", "description", "summary"]) ?? status,
    clock: firstString(item, ["currentInning", "innings", "day", "session"]),
    period: firstString(item, ["matchType", "format", "match_class"]),
    startsAt,
    homeName,
    awayName,
    homeScore,
    awayScore,
    scoreSummary: [homeScore, awayScore].filter(Boolean).join(" | ") || firstString(item, ["score", "scoreText"]),
    homeLogoURL: firstString(item, ["team1Logo", "team_a_img", "homeLogo"]),
    awayLogoURL: firstString(item, ["team2Logo", "team_b_img", "awayLogo"]),
    venue: firstString(item, ["venue", "ground", "groundName"]),
    note: firstString(item, ["statusText", "status_note", "description", "summary"]),
    scoreboardSections: null,
  }
  match.scoreboardSections = genericSummarySections(match)
  return match
}

async function fetchEspnCricinfoLiveCricket(apiKey: string): Promise<LiveSportSection> {
  const primaryPayload = await fetchRapidJSON(
    apiKey,
    "espncricinfo-api.p.rapidapi.com",
    "/api/v1/cricketinfo/live-scores"
  )

  let records = payloadRecords(primaryPayload, ["data", "matches", "result", "response", "items"])
  if (records.length === 0) {
    const rssPayload = await fetchRapidJSON(
      apiKey,
      "espncricinfo-api.p.rapidapi.com",
      "/api/v1/cricketinfo/rss/live-scores"
    )
    records = payloadRecords(rssPayload, ["data", "matches", "result", "response", "items"])
  }

  const matches = records
    .map((item) => normalizeEspnCricinfoMatch(item))
    .filter((match): match is LiveMatch => Boolean(match))

  return groupMatches("cricket", "Cricket", "figure.cricket", matches)
}

function espnCricinfoScorecardSections(payload: unknown): ScoreboardSection[] {
  const records = payloadRecords(payload, [
    "data",
    "scorecard",
    "scoreCard",
    "fullScorecard",
    "innings",
    "batting",
    "bowling",
    "players",
  ])

  const rows = records
    .map((record, index) => {
      const name = firstString(record, ["name", "player", "batsman", "bowler", "team", "title", "inning"]) ??
        `Row ${index + 1}`
      const values = [
        firstString(record, ["runs", "run", "r"]),
        firstString(record, ["balls", "ball", "b"]),
        firstString(record, ["fours", "4s", "four"]),
        firstString(record, ["sixes", "6s", "six"]),
        firstString(record, ["strikeRate", "strike_rate", "sr"]),
        firstString(record, ["overs", "over", "o"]),
        firstString(record, ["wickets", "wicket", "w"]),
        firstString(record, ["economy", "econ", "er"]),
      ].filter(Boolean)

      if (values.length === 0 && name.startsWith("Row ")) return null
      return {
        id: rowID(`espncricinfo-scorecard-${name}`, index),
        cells: safeCells([name, ...values.slice(0, 5)]),
        note: firstString(record, ["dismissal", "out", "howOut", "comment", "status"]),
      }
    })
    .filter((row): row is ScoreboardRow => Boolean(row))

  return rows.length > 0
    ? [scoreboardSection("scorecard", "Full scorecard", ["Player", "1", "2", "3", "4", "5"], rows)]
    : []
}

async function fetchEspnCricinfoMatchDetail(apiKey: string, detailID: string): Promise<LiveMatchDetailResponse> {
  const detail = parseEspnCricinfoDetailID(detailID)
  const params = new URLSearchParams({ match_id: detail.match_id })
  if (detail.series_slug) params.set("series_slug", detail.series_slug)
  if (detail.match_slug) params.set("match_slug", detail.match_slug)

  const payload = await fetchRapidJSON(
    apiKey,
    "espncricinfo-api.p.rapidapi.com",
    `/api/v1/cricketinfo/match-details?${params.toString()}`
  )
  const record = payloadRecords(payload, ["data", "match", "result", "response"])[0] ?? asRecord(payload) ?? {}
  const fallbackMatch = normalizeEspnCricinfoMatch(record)
  const match = fallbackMatch ?? {
    id: `espncricinfo-detail-${detail.match_id}`,
    providerID: "espncricinfo",
    detailID,
    sportID: "cricket",
    sportName: "Cricket",
    competitionID: "espncricinfo-detail",
    competitionName: firstString(record, ["series", "seriesName", "series_name"]) ?? "Cricket",
    country: firstString(record, ["country", "groundCountry"]),
    status: firstString(record, ["status", "statusText", "description"]) ?? "Live",
    statusDetail: firstString(record, ["statusText", "description", "summary"]),
    clock: firstString(record, ["currentInning", "innings", "day", "session"]),
    period: firstString(record, ["matchType", "format"]),
    startsAt: null,
    homeName: espnCricinfoTeamName(record, "home") ?? "Home",
    awayName: espnCricinfoTeamName(record, "away") ?? "Away",
    homeScore: espnCricinfoScore(record, "home"),
    awayScore: espnCricinfoScore(record, "away"),
    scoreSummary: firstString(record, ["score", "scoreText"]),
    homeLogoURL: firstString(record, ["team1Logo", "team_a_img", "homeLogo"]),
    awayLogoURL: firstString(record, ["team2Logo", "team_b_img", "awayLogo"]),
    venue: firstString(record, ["venue", "ground", "groundName"]),
    note: firstString(record, ["statusText", "description", "summary"]),
    scoreboardSections: null,
  }
  const sections = espnCricinfoScorecardSections(payload)
  match.scoreboardSections = sections.length > 0 ? sections : genericSummarySections(match)
  return {
    generatedAt: isoWithoutMilliseconds(new Date()),
    match,
    scoreboardSections: match.scoreboardSections,
  }
}

async function fetchCricketDataLiveCricket(apiKey: string | null, proxyURL: string | null): Promise<LiveSportSection> {
  const payload = await fetchCricketDataJSON(apiKey, proxyURL)
  const matches = payloadRecords(payload, ["data"])
    .map((item) => normalizeCricketDataMatch(item))
    .filter((match): match is LiveMatch => Boolean(match))
  return groupMatches("cricket", "Cricket", "figure.cricket", matches)
}

function dateKeyInTimezone(timezone: string, offsetDays = 0) {
  const base = new Date(Date.now() + offsetDays * dayMS)
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(base)
  const get = (type: string) => parts.find((part) => part.type === type)?.value ?? ""
  return `${get("year")}${get("month")}${get("day")}`
}

function tank01MLBRecords(payload: unknown): Record<string, unknown>[] {
  const direct = asRecord(payload)
  const body = direct ? direct.body : payload
  const bodyRecord = asRecord(body)
  const candidates: unknown[] = [payload, body]

  for (const key of ["games", "gameList", "schedule", "data", "result", "events"]) {
    if (bodyRecord?.[key]) candidates.push(bodyRecord[key])
    if (direct?.[key]) candidates.push(direct[key])
  }

  if (bodyRecord) {
    for (const value of Object.values(bodyRecord)) {
      if (Array.isArray(value)) candidates.push(value)
    }
  }

  return candidates
    .flatMap((candidate) => asArray(candidate))
    .map((item) => asRecord(item))
    .filter((item): item is Record<string, unknown> => Boolean(item))
}

function tank01TeamName(record: Record<string, unknown>, side: "home" | "away") {
  const direct = side === "home"
    ? firstString(record, ["home", "homeAbv", "teamAbvHome", "homeTeam", "homeTeamAbv", "teamIDHome", "homeName"])
    : firstString(record, ["away", "awayAbv", "teamAbvAway", "awayTeam", "awayTeamAbv", "teamIDAway", "awayName"])
  if (direct) return direct

  const nested = side === "home"
    ? nestedRecord(record, ["homeTeam", "home", "teamHome"])
    : nestedRecord(record, ["awayTeam", "away", "teamAway"])
  return nested ? firstString(nested, ["teamAbv", "abv", "name", "teamName", "city", "shortName"]) : null
}

function tank01Score(record: Record<string, unknown>, side: "home" | "away") {
  return side === "home"
    ? firstString(record, ["homePts", "homeRuns", "homeScore", "homeTeamScore", "teamScoreHome", "scoreHome"])
    : firstString(record, ["awayPts", "awayRuns", "awayScore", "awayTeamScore", "teamScoreAway", "scoreAway"])
}

function tank01StatusBucket(record: Record<string, unknown>): MatchFeed {
  const status = firstString(record, ["gameStatus", "gameStatusCode", "status", "statusCode", "gameState"])?.toLowerCase() ?? ""
  const hasScore = Boolean(tank01Score(record, "home") || tank01Score(record, "away"))
  if (!status && !hasScore) return "upcoming"
  if (!hasScore && /^\d{1,2}:\d{2}\s*[ap]?$/.test(status.replace(/\./g, ""))) return "upcoming"
  if (["final", "completed", "complete", "postponed", "cancelled", "canceled"].some((token) => status.includes(token))) {
    return "recent"
  }
  if (["scheduled", "pre-game", "pregame", "not started", "preview"].some((token) => status.includes(token))) {
    return "upcoming"
  }
  return "live"
}

function tank01StartsAt(record: Record<string, unknown>) {
  const epoch = firstString(record, ["gameTime_epoch", "gameTimeEpoch", "gameTime_epoch_ms", "epoch"])
  if (epoch) {
    const numeric = Number(epoch)
    if (Number.isFinite(numeric) && numeric > 0) {
      return isoWithoutMilliseconds(new Date(numeric > 9_999_999_999 ? numeric : numeric * 1000))
    }
  }
  return isoFromLooseDate(firstString(record, ["gameTime", "startTime", "gameDateTime", "dateTime"]))
}

function normalizeTank01MLBMatch(item: Record<string, unknown>, feed: MatchFeed): LiveMatch | null {
  const bucket = tank01StatusBucket(item)
  if (feed !== bucket) return null

  const homeName = tank01TeamName(item, "home")
  const awayName = tank01TeamName(item, "away")
  if (!homeName || !awayName) return null

  const gameID = firstString(item, ["gameID", "gameId", "id"]) ??
    stableID(`${homeName}|${awayName}|${firstString(item, ["gameDate", "gameTime"]) ?? ""}`)
  const status = firstString(item, ["gameStatus", "status", "gameStatusCode", "statusCode"]) ??
    (feed === "upcoming" ? "Scheduled" : feed === "recent" ? "Final" : "Live")
  const inning = firstString(item, ["inning", "currentInning", "inningState", "period"])
  const gameClock = firstString(item, ["gameClock", "clock", "gameTime", "startTime"])
  const homeScore = tank01Score(item, "home")
  const awayScore = tank01Score(item, "away")
  const scoreSummary = homeScore && awayScore ? `${awayScore} - ${homeScore}` : null
  const venue = firstString(item, ["venue", "stadium", "gameVenue", "ballpark"])
  const note = firstString(item, ["gameStatus", "status", "gameStatusCode", "statusCode", "gameTime"])

  const match: LiveMatch = {
    id: `tank01-mlb-${gameID}`,
    providerID: "tank01-mlb",
    detailID: gameID,
    sportID: "baseball",
    sportName: "Baseball",
    competitionID: "baseball-mlb",
    competitionName: "MLB",
    country: "United States",
    status,
    statusDetail: note,
    clock: gameClock,
    period: inning,
    startsAt: tank01StartsAt(item),
    homeName,
    awayName,
    homeScore,
    awayScore,
    scoreSummary,
    homeLogoURL: firstString(item, ["homeLogo", "homeLogoURL", "teamLogoHome"]),
    awayLogoURL: firstString(item, ["awayLogo", "awayLogoURL", "teamLogoAway"]),
    venue,
    note,
    scoreboardSections: null,
  }
  match.scoreboardSections = genericSummarySections(match)
  return match
}

async function fetchTank01MLBGames(apiKey: string, timezone: string, feed: MatchFeed): Promise<LiveSportSection> {
  const offsets = feed === "upcoming" ? [0, 1] : feed === "recent" ? [-1] : [0]
  const payloads = await Promise.all(offsets.map((offsetDays) => {
    const gameDate = dateKeyInTimezone(timezone, offsetDays)
    return fetchRapidJSON(
      apiKey,
      "tank01-mlb-live-in-game-real-time-statistics.p.rapidapi.com",
      `/getMLBGamesForDate?gameDate=${encodeURIComponent(gameDate)}`
    )
  }))
  const matches = payloads
    .flatMap((payload) => tank01MLBRecords(payload))
    .map((item) => normalizeTank01MLBMatch(item, feed))
    .filter((match): match is LiveMatch => Boolean(match))
  return groupMatches("baseball", "Baseball", "baseball.fill", matches)
}

async function fetchTank01MLBMatchDetail(apiKey: string, detailID: string, timezone: string): Promise<LiveMatchDetailResponse> {
  const feeds: MatchFeed[] = ["live", "upcoming", "recent"]
  for (const feed of feeds) {
    const section = await fetchTank01MLBGames(apiKey, timezone, feed)
    const match = section.competitions
      .flatMap((competition) => competition.matches)
      .find((candidate) => candidate.detailID === detailID || candidate.id.endsWith(detailID))
    if (match) {
      const scoreboardSections = match.scoreboardSections ?? genericSummarySections(match)
      return {
        generatedAt: isoWithoutMilliseconds(new Date()),
        match: { ...match, scoreboardSections },
        scoreboardSections,
      }
    }
  }
  throw new Error("Tank01 MLB: game detail is not available in the cached daily scoreboard.")
}

const baseball4Host = "baseball4.p.rapidapi.com"

function baseball4Records(payload: unknown): Record<string, unknown>[] {
  const direct = asRecord(payload)
  const candidates: unknown[] = [payload]
  for (const key of ["body", "data", "games", "dates", "schedule", "result", "response"]) {
    const value = direct?.[key]
    if (value) candidates.push(value)
  }

  const records: Record<string, unknown>[] = []
  const visit = (value: unknown) => {
    if (Array.isArray(value)) {
      for (const item of value) visit(item)
      return
    }
    const record = asRecord(value)
    if (!record) return
    const hasGameID = firstString(record, ["gamePk", "gameID", "gameId", "id"])
    const hasTeams = Boolean(record.teams || record.home || record.away || record.homeTeam || record.awayTeam)
    if (hasGameID || hasTeams) records.push(record)
    for (const key of ["games", "gameList", "dates", "schedule", "items", "events", "data"]) {
      if (record[key]) visit(record[key])
    }
  }

  for (const candidate of candidates) visit(candidate)
  return records
}

function baseball4TeamName(record: Record<string, unknown>, side: "home" | "away"): string | null {
  const direct = side === "home"
    ? firstString(record, ["home", "homeName", "homeTeam", "teamNameHome", "home_team"])
    : firstString(record, ["away", "awayName", "awayTeam", "teamNameAway", "away_team"])
  if (direct) return direct

  const teams = nestedRecord(record, ["teams"])
  const sideRecord = side === "home"
    ? nestedRecord(record, ["home", "homeTeam", "teamHome"]) ?? nestedRecord(teams ?? {}, ["home"])
    : nestedRecord(record, ["away", "awayTeam", "teamAway"]) ?? nestedRecord(teams ?? {}, ["away"])
  const team = nestedRecord(sideRecord ?? {}, ["team"]) ?? sideRecord
  return team ? firstString(team, ["name", "teamName", "clubName", "shortName", "abbreviation"]) : null
}

function baseball4Score(record: Record<string, unknown>, side: "home" | "away"): string | null {
  const direct = side === "home"
    ? firstString(record, ["homeScore", "home_score", "homeRuns", "runsHome", "scoreHome"])
    : firstString(record, ["awayScore", "away_score", "awayRuns", "runsAway", "scoreAway"])
  if (direct) return direct

  const teams = nestedRecord(record, ["teams"])
  const sideRecord = side === "home"
    ? nestedRecord(record, ["home", "homeTeam", "teamHome"]) ?? nestedRecord(teams ?? {}, ["home"])
    : nestedRecord(record, ["away", "awayTeam", "teamAway"]) ?? nestedRecord(teams ?? {}, ["away"])
  return sideRecord ? firstString(sideRecord, ["score", "runs", "total", "current"]) : null
}

function baseball4StartsAt(record: Record<string, unknown>): string | null {
  return isoFromLooseDate(firstString(record, [
    "gameDate",
    "officialDate",
    "dateTime",
    "startTime",
    "start_date",
    "date",
  ]))
}

function baseball4Status(record: Record<string, unknown>, feed: MatchFeed): string {
  const statusRecord = nestedRecord(record, ["status", "gameStatus"])
  return firstString(record, ["status", "gameStatus", "gameState", "detailedState", "abstractGameState"]) ??
    firstString(statusRecord ?? {}, ["detailedState", "abstractGameState", "statusCode", "codedGameState"]) ??
    (feed === "recent" ? "Final" : feed === "upcoming" ? "Scheduled" : "Live")
}

function normalizeBaseball4Match(item: Record<string, unknown>, feed: MatchFeed): LiveMatch | null {
  const homeName = baseball4TeamName(item, "home")
  const awayName = baseball4TeamName(item, "away")
  if (!homeName || !awayName) return null

  const gamePk = firstString(item, ["gamePk", "gameID", "gameId", "id"]) ??
    stableID(`baseball4|${homeName}|${awayName}|${firstString(item, ["gameDate", "officialDate"]) ?? ""}`)
  const status = baseball4Status(item, feed)
  const statusDetail = firstString(item, ["detailedState", "abstractGameState", "reason"]) ??
    firstString(nestedRecord(item, ["status"]) ?? {}, ["detailedState", "abstractGameState"]) ??
    status
  const homeScore = baseball4Score(item, "home")
  const awayScore = baseball4Score(item, "away")
  const venueRecord = nestedRecord(item, ["venue"])
  const leagueRecord = nestedRecord(item, ["league"])

  const match: LiveMatch = {
    id: `baseball4-${gamePk}`,
    providerID: "baseball4",
    detailID: gamePk,
    sportID: "baseball",
    sportName: "Baseball",
    competitionID: "baseball-mlb",
    competitionName: firstString(item, ["league", "competition"]) ?? firstString(leagueRecord ?? {}, ["name"]) ?? "MLB",
    country: "United States",
    status,
    statusDetail,
    clock: firstString(item, ["gameInning", "inning", "currentInning", "gameTime"]),
    period: firstString(item, ["seriesDescription", "gameType", "gameNumber"]),
    startsAt: baseball4StartsAt(item),
    homeName,
    awayName,
    homeScore,
    awayScore,
    scoreSummary: homeScore && awayScore ? `${awayScore} - ${homeScore}` : null,
    homeLogoURL: firstString(item, ["homeLogo", "teamLogoHome"]),
    awayLogoURL: firstString(item, ["awayLogo", "teamLogoAway"]),
    venue: firstString(item, ["venue", "venueName"]) ?? firstString(venueRecord ?? {}, ["name"]),
    note: statusDetail,
    scoreboardSections: null,
  }
  match.scoreboardSections = genericSummarySections(match)
  return match
}

async function fetchBaseball4MLBSchedule(apiKey: string, timezone: string, feed: MatchFeed): Promise<LiveSportSection> {
  const date = datePathInTimezone(timezone, feed === "upcoming" ? 1 : feed === "recent" ? -1 : 0)
  const payload = await fetchRapidJSON(apiKey, baseball4Host, `/v1/mlb/schedule?date=${encodeURIComponent(date)}`)
  const matches = baseball4Records(payload)
    .map((item) => normalizeBaseball4Match(item, feed))
    .filter((match): match is LiveMatch => Boolean(match))
  return groupMatches("baseball", "Baseball", "baseball.fill", matches)
}

function baseball4Rows(payload: unknown, prefix: string): ScoreboardRow[] {
  return payloadRecords(payload, ["data", "body", "teams", "players", "stats", "game", "boxscore", "plays", "allPlays", "probabilities", "matrix"])
    .slice(0, 80)
    .map((record, index): ScoreboardRow | null => {
      const label = firstString(record, ["name", "fullName", "playerName", "teamName", "event", "description", "result", "title"]) ??
        firstString(nestedRecord(record, ["player"]) ?? {}, ["fullName", "name"]) ??
        firstString(nestedRecord(record, ["team"]) ?? {}, ["name", "teamName"]) ??
        `Row ${index + 1}`
      const value = firstString(record, ["value", "score", "runs", "rbi", "avg", "era", "probability", "inning", "count"]) ??
        firstString(nestedRecord(record, ["result"]) ?? {}, ["description", "event", "eventType"])
      const note = firstString(record, ["note", "status", "summary", "details", "description"]) ??
        firstString(nestedRecord(record, ["about"]) ?? {}, ["halfInning", "inning"])
      if (!value && !note && label.startsWith("Row ")) return null
      return {
        id: rowID(`${prefix}-${label}`, index),
        cells: safeCells([label, value ?? "", note ?? ""]),
        note: null,
      }
    })
    .filter((row): row is ScoreboardRow => Boolean(row))
}

async function fetchBaseball4MatchDetail(apiKey: string, detailID: string): Promise<LiveMatchDetailResponse> {
  const [game, boxscore, playByPlay, probability, matrix] = await Promise.allSettled([
    fetchRapidJSON(apiKey, baseball4Host, `/v1/mlb/games?gamePk=${encodeURIComponent(detailID)}`),
    fetchRapidJSON(apiKey, baseball4Host, `/v1/mlb/games-boxscore?gamePk=${encodeURIComponent(detailID)}`),
    fetchRapidJSON(apiKey, baseball4Host, `/v1/mlb/games-playbyplay?gamePk=${encodeURIComponent(detailID)}`),
    fetchRapidJSON(apiKey, baseball4Host, `/v1/mlb/games-probability?gamePk=${encodeURIComponent(detailID)}`),
    fetchRapidJSON(apiKey, baseball4Host, `/v1/mlb/games-matrix?gamePk=${encodeURIComponent(detailID)}`),
  ])
  const gamePayload = game.status === "fulfilled" ? game.value : null
  const gameRecord = baseball4Records(gamePayload)[0] ?? asRecord(gamePayload) ?? {}
  const fallbackMatch = normalizeBaseball4Match(gameRecord, "live")
  const match = fallbackMatch ?? {
    id: `baseball4-detail-${detailID}`,
    providerID: "baseball4",
    detailID,
    sportID: "baseball",
    sportName: "Baseball",
    competitionID: "baseball-mlb",
    competitionName: "MLB",
    country: "United States",
    status: baseball4Status(gameRecord, "live"),
    statusDetail: firstString(gameRecord, ["detailedState", "abstractGameState"]),
    clock: firstString(gameRecord, ["gameInning", "inning", "currentInning"]),
    period: firstString(gameRecord, ["seriesDescription", "gameType", "gameNumber"]),
    startsAt: baseball4StartsAt(gameRecord),
    homeName: baseball4TeamName(gameRecord, "home") ?? "Home",
    awayName: baseball4TeamName(gameRecord, "away") ?? "Away",
    homeScore: baseball4Score(gameRecord, "home"),
    awayScore: baseball4Score(gameRecord, "away"),
    scoreSummary: null,
    homeLogoURL: null,
    awayLogoURL: null,
    venue: firstString(gameRecord, ["venue", "venueName"]) ?? firstString(nestedRecord(gameRecord, ["venue"]) ?? {}, ["name"]),
    note: firstString(gameRecord, ["detailedState", "abstractGameState"]),
    scoreboardSections: null,
  } satisfies LiveMatch

  const sections: ScoreboardSection[] = []
  if (boxscore.status === "fulfilled") {
    const rows = baseball4Rows(boxscore.value, "baseball4-boxscore")
    if (rows.length > 0) sections.push(scoreboardSection("boxscore", "Box score", ["Name", "Value", "Info"], rows))
  }
  if (playByPlay.status === "fulfilled") {
    const rows = baseball4Rows(playByPlay.value, "baseball4-play")
    if (rows.length > 0) sections.push(scoreboardSection("play-by-play", "Play by play", ["Play", "Value", "Info"], rows))
  }
  if (probability.status === "fulfilled") {
    const rows = baseball4Rows(probability.value, "baseball4-probability")
    if (rows.length > 0) sections.push(scoreboardSection("probability", "Win probability", ["Metric", "Value", "Info"], rows))
  }
  if (matrix.status === "fulfilled") {
    const rows = baseball4Rows(matrix.value, "baseball4-matrix")
    if (rows.length > 0) sections.push(scoreboardSection("game-matrix", "Game matrix", ["Metric", "Value", "Info"], rows))
  }

  match.scoreboardSections = sections.length > 0 ? sections : genericSummarySections(match)
  return {
    generatedAt: isoWithoutMilliseconds(new Date()),
    match,
    scoreboardSections: match.scoreboardSections,
  }
}

const baseballAPIHost = "baseballapi.p.rapidapi.com"
const baseballAPITournamentID = "11205"
const baseballAPIFallbackSeasonID = "49349"

function baseballAPIRecords(payload: unknown): Record<string, unknown>[] {
  const direct = payloadRecords(payload, [
    "data",
    "standings",
    "rows",
    "table",
    "groups",
    "teams",
    "results",
    "items",
  ])
  const deep = sportscoreDeepRecords(payload)
  const seen = new Set<Record<string, unknown>>()
  return [...direct, ...deep].filter((record) => {
    if (seen.has(record)) return false
    seen.add(record)
    return true
  })
}

function baseballAPITeamName(record: Record<string, unknown>): string | null {
  const direct = firstString(record, ["teamName", "team_name", "name", "shortName", "short_name", "displayName", "display_name"])
  if (direct) return direct
  const team = nestedRecord(record, ["team", "participant", "competitor"])
  return firstString(team ?? {}, ["name", "shortName", "short_name", "displayName", "display_name", "slug"]) ??
    deepFirstString(record, ["teamName", "team_name", "displayName", "display_name", "name"])
}

function baseballAPIStandingValue(record: Record<string, unknown>, keys: string[]): string | null {
  return firstString(record, keys) ?? deepFirstString(record, keys)
}

function baseballAPIStandingRows(payload: unknown): ScoreboardRow[] {
  return baseballAPIRecords(payload)
    .map((record, index) => {
      const team = baseballAPITeamName(record)
      if (!team) return null
      const position = baseballAPIStandingValue(record, ["position", "rank", "place"]) ?? String(index + 1)
      const played = baseballAPIStandingValue(record, ["matches", "played", "games", "total"]) ?? "-"
      const wins = baseballAPIStandingValue(record, ["wins", "win", "won", "W"]) ?? "-"
      const losses = baseballAPIStandingValue(record, ["losses", "loss", "lost", "L"]) ?? "-"
      const pct = baseballAPIStandingValue(record, ["percentage", "pct", "winPercentage", "win_percentage"]) ?? "-"
      if (played === "-" && wins === "-" && losses === "-" && pct === "-") return null
      return {
        id: rowID(`baseballapi-standing-${position}-${team}`, index),
        cells: safeCells([position, team, played, wins, losses, pct]),
        note: baseballAPIStandingValue(record, ["groupName", "group_name", "division", "conference"]),
      }
    })
    .filter((row): row is ScoreboardRow => Boolean(row))
    .slice(0, 60)
}

function baseballAPIStandingsMatch(payload: unknown): LiveMatch {
  const rows = baseballAPIStandingRows(payload)
  const topTeam = rows[0]?.cells[1] ?? null
  const match: LiveMatch = {
    id: "baseballapi-mlb-standings",
    providerID: "baseballapi",
    detailID: "mlb-standings",
    sportID: "baseball",
    sportName: "Baseball",
    competitionID: "baseballapi-mlb-standings",
    competitionName: "BaseballAPI MLB Standings",
    country: "USA",
    status: "Current",
    statusDetail: "MLB standings",
    clock: null,
    period: null,
    startsAt: null,
    homeName: "MLB standings",
    awayName: "League table",
    homeScore: null,
    awayScore: null,
    scoreSummary: topTeam ? `Leader ${topTeam}` : null,
    homeLogoURL: null,
    awayLogoURL: null,
    venue: null,
    note: "BaseballAPI standings, low-refresh to protect 50/day quota",
    scoreboardSections: null,
  }
  match.scoreboardSections = rows.length > 0
    ? [scoreboardSection("mlb-standings", "MLB standings", ["#", "Team", "GP", "W", "L", "PCT"], rows)]
    : genericSummarySections(match)
  return match
}

function baseballAPISeasonID(payload: unknown): string | null {
  const records = payloadRecords(payload, ["data", "seasons", "results", "items"])
  const candidates = records
    .map((record) => {
      const id = firstString(record, ["id", "seasonId", "season_id"])
      if (!id) return null
      const yearText = firstString(record, ["year", "name", "season", "displayName", "display_name"]) ?? ""
      const years = yearText.match(/\d{4}/g)?.map((item) => Number.parseInt(item, 10)) ?? []
      return { id, year: years.length > 0 ? Math.max(...years) : 0 }
    })
    .filter((candidate): candidate is { id: string, year: number } => Boolean(candidate))
    .sort((a, b) => b.year - a.year)
  return candidates[0]?.id ?? null
}

async function fetchBaseballAPIStandingsPayload(apiKey: string): Promise<unknown> {
  const seasonsPayload = await fetchRapidJSON(
    apiKey,
    baseballAPIHost,
    `/api/baseball/tournament/${baseballAPITournamentID}/seasons`
  )
  const seasonID = baseballAPISeasonID(seasonsPayload) ?? baseballAPIFallbackSeasonID
  return await fetchRapidJSON(
    apiKey,
    baseballAPIHost,
    `/api/baseball/tournament/${baseballAPITournamentID}/season/${seasonID}/standings/total`
  )
}

async function fetchBaseballAPIStandings(apiKey: string): Promise<LiveSportSection> {
  const payload = await fetchBaseballAPIStandingsPayload(apiKey)
  return groupMatches("baseball", "Baseball", "baseball.fill", [baseballAPIStandingsMatch(payload)])
}

async function fetchBaseballAPIStandingsDetail(apiKey: string): Promise<LiveMatchDetailResponse> {
  const payload = await fetchBaseballAPIStandingsPayload(apiKey)
  const match = baseballAPIStandingsMatch(payload)
  return {
    generatedAt: isoWithoutMilliseconds(new Date()),
    match,
    scoreboardSections: match.scoreboardSections ?? genericSummarySections(match),
  }
}

function nestedScore(record: Record<string, unknown>, side: "home" | "away") {
  const direct = teamScore(record, side)
  if (direct) return direct
  const score = side === "home"
    ? nestedRecord(record, ["homeScore", "home_score", "scoreHome"])
    : nestedRecord(record, ["awayScore", "away_score", "scoreAway"])
  return score ? firstString(score, ["current", "display", "total", "period1", "normaltime", "score"]) : null
}

function normalizeBasketAPIMatch(item: Record<string, unknown>, feed: MatchFeed): LiveMatch | null {
  const homeName = teamName(item, "home")
  const awayName = teamName(item, "away")
  if (!homeName || !awayName) return null

  const eventID = firstString(item, ["id", "event_id", "eventId", "matchId"]) ??
    stableID(`${homeName}|${awayName}|${firstString(item, ["startTimestamp", "slug"]) ?? ""}`)
  const tournament = nestedRecord(item, ["tournament", "league", "competition"])
  const tournamentName = firstString(tournament ?? {}, ["name", "uniqueTournamentName", "slug"]) ??
    competitionName(item)
  const statusRecord = asRecord(item.status)
  const status = firstString(item, ["status", "event_status", "statusDescription"]) ??
    firstString(statusRecord ?? {}, ["description", "type"]) ??
    (feed === "recent" ? "Final" : "Scheduled")
  const statusDetail = firstString(statusRecord ?? {}, ["description", "type"]) ??
    firstString(item, ["statusDetail", "statusDescription", "shortStatus"])
  const startTimestamp = numberString(item.startTimestamp)
  const startsAt = startTimestamp ? isoWithoutMilliseconds(new Date(Number(startTimestamp) * 1000)) :
    isoFromLooseDate(firstString(item, ["startTime", "date", "event_date"]))
  const homeScore = nestedScore(item, "home")
  const awayScore = nestedScore(item, "away")
  const scoreSummary = homeScore && awayScore ? `${awayScore} - ${homeScore}` : null
  const venueRecord = nestedRecord(item, ["venue"])
  const venue = firstString(item, ["venue", "stadium"]) ?? firstString(venueRecord ?? {}, ["name", "cityName"])

  const match: LiveMatch = {
    id: `basketapi-${eventID}`,
    providerID: "basketapi",
    detailID: eventID,
    sportID: "basketball",
    sportName: "Basketball",
    competitionID: `basketball-${stableID(tournamentName)}`,
    competitionName: tournamentName,
    country: competitionCountry(item),
    status,
    statusDetail,
    clock: null,
    period: firstString(item, ["round", "roundInfo", "stage"]),
    startsAt,
    homeName,
    awayName,
    homeScore,
    awayScore,
    scoreSummary,
    homeLogoURL: teamLogo(item, "home"),
    awayLogoURL: teamLogo(item, "away"),
    venue,
    note: statusDetail ?? status,
    scoreboardSections: null,
  }
  match.scoreboardSections = genericSummarySections(match)
  return match
}

async function fetchBasketAPI(apiKey: string, feed: MatchFeed): Promise<LiveSportSection> {
  const date = new Date()
  const day = String(date.getUTCDate()).padStart(2, "0")
  const month = String(date.getUTCMonth() + 1).padStart(2, "0")
  const year = date.getUTCFullYear()
  const path = `/api/basketball/tournament/132/schedules/${day}/${month}/${year}`
  const payload = await fetchRapidJSON(apiKey, "basketapi1.p.rapidapi.com", path)
  const matches = payloadRecords(payload, ["events", "matches", "data", "result"])
    .map((item) => normalizeBasketAPIMatch(item, feed))
    .filter((match): match is LiveMatch => Boolean(match))
    .filter((match) => {
      const status = `${match.status} ${match.statusDetail ?? ""}`.toLowerCase()
      const isEnded = /ended|final|finished|after/.test(status)
      if (feed === "recent") return isEnded
      return !isEnded
    })
  return groupMatches("basketball", "Basketball", "basketball.fill", matches)
}

async function fetchBasketAPIMatchDetail(apiKey: string, detailID: string): Promise<LiveMatchDetailResponse> {
  for (const feed of ["upcoming", "recent"] as MatchFeed[]) {
    const section = await fetchBasketAPI(apiKey, feed)
    const match = section.competitions
      .flatMap((competition) => competition.matches)
      .find((candidate) => candidate.detailID === detailID || candidate.id.endsWith(detailID))
    if (match) {
      const scoreboardSections = match.scoreboardSections ?? genericSummarySections(match)
      return {
        generatedAt: isoWithoutMilliseconds(new Date()),
        match: { ...match, scoreboardSections },
        scoreboardSections,
      }
    }
  }
  throw new Error("BasketAPI: match detail is not available in the cached tournament schedule.")
}

function cricbuzzPlayerRows(players: unknown[], columns: string[], kind: "bat" | "bowl"): ScoreboardRow[] {
  return asArray(players)
    .map((player, index) => {
      const record = asRecord(player) ?? {}
      if (kind === "bat") {
        return {
          id: rowID(`bat-${firstString(record, ["id", "name"]) ?? index}`, index),
          cells: safeCells([
            firstString(record, ["name", "nickname"]),
            record.runs,
            record.balls,
            record.fours,
            record.sixes,
            record.strkrate,
          ]),
          note: firstString(record, ["outdec"]),
        }
      }

      return {
        id: rowID(`bowl-${firstString(record, ["id", "name"]) ?? index}`, index),
        cells: safeCells([
          firstString(record, ["name", "nickname"]),
          record.overs,
          record.maidens,
          record.runs,
          record.wickets,
          record.economy,
        ]),
        note: null,
      }
    })
    .filter((row) => row.cells.some((cell) => cell.length > 0))
}

function cricbuzzScorecardSections(payload: Record<string, unknown>): ScoreboardSection[] {
  const sections: ScoreboardSection[] = []
  for (const innings of asArray(payload.scorecard)) {
    const record = asRecord(innings) ?? {}
    const teamName = firstString(record, ["batteamname", "batteamsname"]) ?? "Innings"
    const score = [
      numberString(record.score),
      numberString(record.wickets) ? `/${numberString(record.wickets)}` : "",
      numberString(record.overs) ? ` (${numberString(record.overs)} ov)` : "",
    ].join("")

    const batsmanRows = cricbuzzPlayerRows(record.batsman as unknown[], ["Batter", "R", "B", "4s", "6s", "SR"], "bat")
    if (batsmanRows.length > 0) {
      sections.push(scoreboardSection(
        `batting-${firstString(record, ["inningsid"]) ?? stableID(teamName)}`,
        `${teamName} batting`,
        ["Batter", "R", "B", "4s", "6s", "SR"],
        batsmanRows,
        score || null
      ))
    }

    const bowlerRows = cricbuzzPlayerRows(record.bowler as unknown[], ["Bowler", "O", "M", "R", "W", "Econ"], "bowl")
    if (bowlerRows.length > 0) {
      sections.push(scoreboardSection(
        `bowling-${firstString(record, ["inningsid"]) ?? stableID(teamName)}`,
        `${teamName} bowling`,
        ["Bowler", "O", "M", "R", "W", "Econ"],
        bowlerRows
      ))
    }
  }
  return sections
}

async function fetchCricbuzzMatchDetail(apiKey: string, detailID: string): Promise<LiveMatchDetailResponse> {
  const payload = asRecord(await fetchRapidJSON(apiKey, "cricbuzz-cricket.p.rapidapi.com", `/mcenter/v1/${detailID}/hscard`)) ?? {}
  const innings = asArray(payload.scorecard).map((item) => asRecord(item) ?? {})
  const homeInnings = innings[0] ?? {}
  const awayInnings = innings[1] ?? {}
  const homeName = firstString(homeInnings, ["batteamsname", "batteamname"]) ?? "Team 1"
  const awayName = firstString(awayInnings, ["batteamsname", "batteamname"]) ?? "Team 2"
  const homeScore = numberString(homeInnings.score)
  const homeWickets = numberString(homeInnings.wickets)
  const awayScore = numberString(awayInnings.score)
  const awayWickets = numberString(awayInnings.wickets)
  const match: LiveMatch = {
    id: `cricket-${detailID}`,
    providerID: "cricbuzz",
    detailID,
    sportID: "cricket",
    sportName: "Cricket",
    competitionID: "cricket-detail",
    competitionName: "Cricket",
    country: null,
    status: firstString(payload, ["status"]) ?? "Live",
    statusDetail: firstString(payload, ["status"]),
    clock: null,
    period: null,
    startsAt: null,
    homeName,
    awayName,
    homeScore: homeScore ? `${homeScore}${homeWickets ? `/${homeWickets}` : ""}` : null,
    awayScore: awayScore ? `${awayScore}${awayWickets ? `/${awayWickets}` : ""}` : null,
    scoreSummary: firstString(payload, ["status"]),
    homeLogoURL: null,
    awayLogoURL: null,
    venue: null,
    note: firstString(payload, ["status"]),
    scoreboardSections: null,
  }
  const scoreboardSections = cricbuzzScorecardSections(payload)
  match.scoreboardSections = scoreboardSections
  return {
    generatedAt: isoWithoutMilliseconds(new Date()),
    match,
    scoreboardSections,
  }
}

function mergeSections(sections: LiveSportSection[]): LiveSportSection[] {
  const sportsByID = new Map<string, LiveSportSection>()
  for (const section of sections) {
    if (section.competitions.length === 0) continue
    const existing = sportsByID.get(section.id)
    if (!existing) {
      sportsByID.set(section.id, {
        ...section,
        competitions: mergeCompetitions(section.competitions),
      })
      continue
    }
    sportsByID.set(section.id, {
      ...existing,
      competitions: mergeCompetitions([...existing.competitions, ...section.competitions]),
    })
  }
  return Array.from(sportsByID.values())
}

function matchFingerprint(match: LiveMatch) {
  return [
    match.sportID,
    match.homeName.toLowerCase(),
    match.awayName.toLowerCase(),
    match.startsAt ?? "",
  ].join("|")
}

function mergeCompetitions(competitions: LiveCompetition[]): LiveCompetition[] {
  const byID = new Map<string, LiveCompetition>()
  const seenMatchIDs = new Set<string>()

  for (const competition of competitions) {
    const existing = byID.get(competition.id)
    const incomingMatches = competition.matches.filter((match) => {
      const fingerprint = matchFingerprint(match)
      if (seenMatchIDs.has(fingerprint)) return false
      seenMatchIDs.add(fingerprint)
      return true
    })

    if (incomingMatches.length === 0) continue

    if (existing) {
      byID.set(competition.id, {
        ...existing,
        matches: [...existing.matches, ...incomingMatches],
      })
    } else {
      byID.set(competition.id, {
        ...competition,
        matches: incomingMatches,
      })
    }
  }

  return Array.from(byID.values()).sort((a, b) => a.name.localeCompare(b.name))
}

function providerSources(
  rapidAPIKey: string | undefined,
  cricketDataAPIKey: string | undefined,
  cricketDataProxyURL: string | undefined,
  timezone: string
): ProviderSource[] {
  const sources: ProviderSource[] = []

  if (rapidAPIKey) {
    sources.push(
      {
        id: "cricbuzz",
        name: "Cricbuzz Cricket",
        sportID: "cricket",
        scope: `live:${timezone}`,
        run: () => fetchCricbuzzLiveCricket(rapidAPIKey),
      },
      {
        id: "cricket-live-line",
        name: "Cricket Live Line",
        sportID: "cricket",
        scope: `live:${timezone}`,
        run: () => fetchCricketLiveLineMatches(rapidAPIKey, "live"),
      },
      {
        id: "cricket-live-data",
        name: "Cricket Live Data",
        sportID: "cricket",
        scope: `fixtures:cricket-live-data:${datePathInTimezone(timezone, 0)}`,
        run: () => fetchCricketLiveDataMatches(rapidAPIKey, timezone, "live"),
      },
      {
        id: "espncricinfo",
        name: "ESPNcricinfo",
        sportID: "cricket",
        scope: `live:${timezone}`,
        run: () => fetchEspnCricinfoLiveCricket(rapidAPIKey),
      },
      {
        id: "sportapi-football",
        name: "SportAPI Football",
        sportID: "soccer",
        scope: `live:${timezone}`,
        run: () => fetchSportAPIFootball(rapidAPIKey),
      },
      {
        id: "tennisapi",
        name: "TennisAPI",
        sportID: "tennis",
        scope: `live:${timezone}`,
        run: () => fetchTennisAPI(rapidAPIKey),
      },
      {
        id: "sportscore-tennis-rankings",
        name: "SportScore Tennis Rankings",
        sportID: "tennis",
        scope: "rankings:tennis:atp-wta:v2",
        run: () => fetchSportscoreTennisRankings(rapidAPIKey),
      },
      {
        id: "tennis-atp-wta-itf",
        name: "Tennis API ATP/WTA/ITF",
        sportID: "tennis",
        scope: "rankings:tennis:atp-wta-itf:v1",
        run: () => fetchTennisAtpWtaItfRankings(rapidAPIKey),
      },
      {
        id: "livescore-soccer",
        name: "LiveScore Soccer",
        sportID: "soccer",
        scope: `live:${timezone}`,
        run: () => fetchLiveScoreSoccer(rapidAPIKey, timezone),
      },
      {
        id: "free-football",
        name: "Free Football",
        sportID: "soccer",
        scope: `live:${timezone}`,
        run: () => fetchFreeFootball(rapidAPIKey),
      },
      {
        id: "os-sports-perform-v2",
        name: "OS Sports Perform",
        sportID: "soccer",
        scope: `live:soccer:${timezone}`,
        run: () => fetchOSSportsPerformSoccer(rapidAPIKey),
      },
      {
        id: "hyprace",
        name: "Hyprace Formula 1",
        sportID: "formula1",
        scope: `live:${timezone}`,
        run: () => fetchHypraceFormula1(rapidAPIKey),
      },
      {
        id: "tank01-mlb",
        name: "Tank01 MLB",
        sportID: "baseball",
        scope: `live:baseball:v2:${timezone}`,
        run: () => fetchTank01MLBGames(rapidAPIKey, timezone, "live"),
      },
      {
        id: "baseball4",
        name: "Baseball",
        sportID: "baseball",
        scope: `schedule:baseball4:mlb:${datePathInTimezone(timezone, 0)}`,
        run: () => fetchBaseball4MLBSchedule(rapidAPIKey, timezone, "live"),
      },
      {
        id: "baseballapi",
        name: "BaseballAPI",
        sportID: "baseball",
        scope: "standings:baseballapi:mlb:v1",
        run: () => fetchBaseballAPIStandings(rapidAPIKey),
      },
    )
  }

  if (cricketDataAPIKey || cricketDataProxyURL) {
    sources.push({
      id: "cricketdata",
      name: "CricketData",
      sportID: "cricket",
      scope: `live:${timezone}`,
      run: () => fetchCricketDataLiveCricket(cricketDataAPIKey ?? null, cricketDataProxyURL ?? null),
    })
  }

  return sources
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  if (req.method !== "GET") {
    return json(405, { error: "Method not allowed" })
  }

  const rapidAPIKey = Deno.env.get("RAPIDAPI_KEY")
  const cricketDataAPIKey = Deno.env.get("CRICKETDATA_API_KEY")
  const cricketDataProxyURL = Deno.env.get("CRICKETDATA_PROXY_URL")
  const url = new URL(req.url)
  const ttl = clamp(parseIntOr(url.searchParams.get("ttl"), 1), 1, 120)
  const timezone = url.searchParams.get("timezone") || "Asia/Kolkata"
  const health = url.searchParams.get("health") === "1"
  const detailProvider = url.searchParams.get("detailProvider")
  const detailID = url.searchParams.get("detailID")
  const cacheKey = `live-scores:${timezone}:${ttl}:${Boolean(rapidAPIKey)}:${Boolean(cricketDataAPIKey || cricketDataProxyURL)}`
  const now = Date.now()
  const sources = providerSources(rapidAPIKey, cricketDataAPIKey, cricketDataProxyURL, timezone)

  if (detailProvider && detailID) {
    if (!rapidAPIKey) {
      return json(200, {
        generatedAt: isoWithoutMilliseconds(new Date()),
        match: {
          id: `${detailProvider}-${detailID}`,
          providerID: detailProvider,
          detailID,
          sportID: "sports",
          sportName: "Sports",
          competitionID: "sports",
          competitionName: "Live match",
          country: null,
          status: "Live",
          statusDetail: null,
          clock: null,
          period: null,
          startsAt: null,
          homeName: "Home",
          awayName: "Away",
          homeScore: null,
          awayScore: null,
          scoreSummary: "Live",
          homeLogoURL: null,
          awayLogoURL: null,
          venue: null,
          note: "Add RAPIDAPI_KEY as a Supabase Edge Function secret to enable match scoreboards.",
          scoreboardSections: [],
        },
        scoreboardSections: [],
      } satisfies LiveMatchDetailResponse)
    }

    if (detailProvider === "cricbuzz") {
      try {
        return json(200, await runProviderTask(
          "cricbuzz",
          `detail:${detailProvider}:${detailID}`,
          () => fetchCricbuzzMatchDetail(rapidAPIKey, detailID)
        ))
      } catch (error) {
        return json(502, {
          error: error instanceof Error ? error.message : "Scoreboard provider failed",
        })
      }
    }

    if (detailProvider === "cricket-live-line") {
      try {
        return json(200, await runProviderTask(
          "cricket-live-line",
          `detail:${detailProvider}:${detailID}`,
          () => fetchCricketLiveLineMatchDetail(rapidAPIKey, detailID)
        ))
      } catch (error) {
        return json(502, {
          error: error instanceof Error ? error.message : "Scoreboard provider failed",
        })
      }
    }

    if (detailProvider === "cricket-live-data") {
      try {
        return json(200, await runProviderTask(
          "cricket-live-data",
          `detail:${detailProvider}:${detailID}`,
          () => fetchCricketLiveDataMatchDetail(rapidAPIKey, detailID)
        ))
      } catch (error) {
        return json(502, {
          error: error instanceof Error ? error.message : "Scoreboard provider failed",
        })
      }
    }

    if (detailProvider === "espncricinfo") {
      try {
        return json(200, await runProviderTask(
          "espncricinfo",
          `detail:${detailProvider}:${detailID}`,
          () => fetchEspnCricinfoMatchDetail(rapidAPIKey, detailID)
        ))
      } catch (error) {
        return json(502, {
          error: error instanceof Error ? error.message : "Scoreboard provider failed",
        })
      }
    }

    if (detailProvider === "livescore-soccer") {
      try {
        return json(200, await runProviderTask(
          "livescore-soccer",
          `detail:${detailProvider}:${detailID}`,
          () => fetchLiveScoreSoccerMatchDetail(rapidAPIKey, detailID)
        ))
      } catch (error) {
        return json(502, {
          error: error instanceof Error ? error.message : "Scoreboard provider failed",
        })
      }
    }

    if (detailProvider === "os-sports-perform") {
      try {
        return json(200, await runProviderTask(
          "os-sports-perform-v2",
          `detail:${detailProvider}:v3:${detailID}`,
          () => fetchOSSportsPerformMatchDetail(rapidAPIKey, detailID)
        ))
      } catch (error) {
        return json(502, {
          error: error instanceof Error ? error.message : "Scoreboard provider failed",
        })
      }
    }

    if (detailProvider === "hyprace") {
      try {
        return json(200, await runProviderTask(
          "hyprace",
          `detail:${detailProvider}:${detailID}`,
          () => fetchHypraceMatchDetail(rapidAPIKey, detailID)
        ))
      } catch (error) {
        return json(502, {
          error: error instanceof Error ? error.message : "Scoreboard provider failed",
        })
      }
    }

    if (detailProvider === "tank01-mlb") {
      try {
        return json(200, await runProviderTask(
          "tank01-mlb",
          `detail:${detailProvider}:${detailID}:${timezone}`,
          () => fetchTank01MLBMatchDetail(rapidAPIKey, detailID, timezone)
        ))
      } catch (error) {
        return json(502, {
          error: error instanceof Error ? error.message : "Scoreboard provider failed",
        })
      }
    }

    if (detailProvider === "baseball4") {
      try {
        return json(200, await runProviderTask(
          "baseball4",
          `detail:${detailProvider}:${detailID}`,
          () => fetchBaseball4MatchDetail(rapidAPIKey, detailID)
        ))
      } catch (error) {
        return json(502, {
          error: error instanceof Error ? error.message : "Scoreboard provider failed",
        })
      }
    }

    if (detailProvider === "baseballapi") {
      try {
        return json(200, await runProviderTask(
          "baseballapi",
          `detail:${detailProvider}:${detailID}:v1`,
          () => fetchBaseballAPIStandingsDetail(rapidAPIKey)
        ))
      } catch (error) {
        return json(502, {
          error: error instanceof Error ? error.message : "Scoreboard provider failed",
        })
      }
    }

    if (detailProvider === "basketapi") {
      try {
        return json(200, await runProviderTask(
          "basketapi-madness-v3",
          `detail:${detailProvider}:${detailID}`,
          () => fetchBasketAPIMatchDetail(rapidAPIKey, detailID)
        ))
      } catch (error) {
        return json(502, {
          error: error instanceof Error ? error.message : "Scoreboard provider failed",
        })
      }
    }

    if (detailProvider === "rundown") {
      try {
        return json(200, await runProviderTask(
          "rundown-v1",
          `detail:${detailProvider}:${detailID}`,
          () => fetchRundownMatchDetail(rapidAPIKey, detailID)
        ))
      } catch (error) {
        return json(502, {
          error: error instanceof Error ? error.message : "Scoreboard provider failed",
        })
      }
    }

    if (detailProvider === "sportscore-tennis-rankings") {
      try {
        return json(200, await runProviderTask(
          "sportscore-tennis-rankings",
          `detail:${detailProvider}:${detailID}:v2`,
          () => fetchSportscoreTennisRankingDetail(rapidAPIKey, detailID)
        ))
      } catch (error) {
        return json(502, {
          error: error instanceof Error ? error.message : "Scoreboard provider failed",
        })
      }
    }

    if (detailProvider === "tennis-atp-wta-itf") {
      try {
        return json(200, await runProviderTask(
          "tennis-atp-wta-itf",
          `detail:${detailProvider}:${detailID}:v1`,
          () => fetchTennisAtpWtaItfRankingDetail(rapidAPIKey, detailID)
        ))
      } catch (error) {
        return json(502, {
          error: error instanceof Error ? error.message : "Scoreboard provider failed",
        })
      }
    }

    return json(404, {
      error: "This provider does not expose a separate scoreboard endpoint yet.",
    })
  }

  const cached = cache.get(cacheKey)
  if (cached && cached.expiresAt > now) {
    return json(200, { ...cached.payload, cacheHit: true })
  }

  if (!rapidAPIKey && !cricketDataAPIKey && !cricketDataProxyURL) {
    return json(200, {
      generatedAt: isoWithoutMilliseconds(new Date()),
      cacheHit: false,
      providerConfigured: false,
      message: "Add RAPIDAPI_KEY or CRICKETDATA_API_KEY as a Supabase Edge Function secret to enable live scores.",
      sports: [],
      upcomingSports: [],
      recentSports: [],
    } satisfies LiveScoresResponse)
  }

  if (health) {
    const healthSources = rapidAPIKey
      ? [
          ...sources,
          {
            id: "rundown-v1",
            name: "The Rundown",
            sportID: "soccer",
            scope: "health:upcoming:soccer:schedule:v1",
            run: () => fetchRundownSoccerSchedule(rapidAPIKey),
          },
        ]
      : sources
    const checks = await Promise.all(healthSources.map(async (source) => {
      const startedAt = Date.now()
      try {
        const section = await runProviderSource(source)
        const matchCount = section.competitions.reduce((total, competition) => total + competition.matches.length, 0)
        return {
          id: source.id,
          name: source.name,
          sportID: source.sportID,
          ok: true,
          competitionCount: section.competitions.length,
          matchCount,
          durationMS: Date.now() - startedAt,
          message: matchCount > 0 ? null : "Provider responded but has no live matches right now.",
        }
      } catch (error) {
        return {
          id: source.id,
          name: source.name,
          sportID: source.sportID,
          ok: false,
          competitionCount: 0,
          matchCount: 0,
          durationMS: Date.now() - startedAt,
          message: error instanceof Error ? error.message : "Provider failed",
        }
      }
    }))

    return json(200, {
      generatedAt: isoWithoutMilliseconds(new Date()),
      providerConfigured: sources.length > 0,
      providers: checks,
    })
  }

  const [results, upcomingResult, recentResult] = await Promise.all([
    Promise.allSettled(sources.map((source) => runProviderSource(source))),
    rapidAPIKey
      ? Promise.allSettled([
          runProviderTask("cricbuzz", "upcoming:cricket", () => fetchCricbuzzCricketMatches(rapidAPIKey, "upcoming")),
          runProviderTask("cricket-live-line", "upcoming:cricket", () => fetchCricketLiveLineMatches(rapidAPIKey, "upcoming")),
          runProviderTask("cricket-live-data", `upcoming:cricket-live-data:${datePathInTimezone(timezone, 1)}`, () => fetchCricketLiveDataMatches(rapidAPIKey, timezone, "upcoming")),
          runProviderTask("tank01-mlb", `upcoming:baseball:v2:${timezone}`, () => fetchTank01MLBGames(rapidAPIKey, timezone, "upcoming")),
          runProviderTask("baseball4", `upcoming:baseball4:mlb:${datePathInTimezone(timezone, 1)}`, () => fetchBaseball4MLBSchedule(rapidAPIKey, timezone, "upcoming")),
          runProviderTask("basketapi-madness-v3", "upcoming:basketball:march-madness:v2", () => fetchBasketAPI(rapidAPIKey, "upcoming")),
          runProviderTask("rundown-v1", "upcoming:soccer:schedule:v1", () => fetchRundownSoccerSchedule(rapidAPIKey)),
        ]).then((results) => results
          .filter((result): result is PromiseFulfilledResult<LiveSportSection> => result.status === "fulfilled")
          .map((result) => result.value))
      : Promise.resolve([] as LiveSportSection[]),
    rapidAPIKey
      ? Promise.allSettled([
          runProviderTask("cricbuzz", "recent:cricket", () => fetchCricbuzzCricketMatches(rapidAPIKey, "recent")),
          runProviderTask("cricket-live-line", "recent:cricket", () => fetchCricketLiveLineMatches(rapidAPIKey, "recent")),
          runProviderTask("cricket-live-data", `recent:cricket-live-data:${datePathInTimezone(timezone, -1)}`, () => fetchCricketLiveDataMatches(rapidAPIKey, timezone, "recent")),
          runProviderTask("tank01-mlb", `recent:baseball:v2:${timezone}`, () => fetchTank01MLBGames(rapidAPIKey, timezone, "recent")),
          runProviderTask("baseball4", `recent:baseball4:mlb:${datePathInTimezone(timezone, -1)}`, () => fetchBaseball4MLBSchedule(rapidAPIKey, timezone, "recent")),
          runProviderTask("basketapi-madness-v3", "recent:basketball:march-madness:v3", () => fetchBasketAPI(rapidAPIKey, "recent")),
        ]).then((results) => results
          .filter((result): result is PromiseFulfilledResult<LiveSportSection> => result.status === "fulfilled")
          .map((result) => result.value))
      : Promise.resolve([] as LiveSportSection[]),
  ].map((promise) => promise.catch((error) => error)))

  const sections: LiveSportSection[] = []
  const failures: string[] = []

  if (results instanceof Error) {
    failures.push(results.message)
  } else {
    for (const result of results) {
      if (result.status === "fulfilled") {
        sections.push(result.value)
      } else {
        failures.push(result.reason instanceof Error ? result.reason.message : "Provider failed")
      }
    }
  }

  const upcomingSports = upcomingResult instanceof Error ? [] : mergeSections(upcomingResult)
  const recentSports = recentResult instanceof Error ? [] : mergeSections(recentResult)

  for (const error of [upcomingResult, recentResult]) {
    if (error instanceof Error) {
      failures.push(error.message)
    }
  }

  const payload: LiveScoresResponse = {
    generatedAt: isoWithoutMilliseconds(new Date()),
    cacheHit: false,
    providerConfigured: true,
    message: failures.length > 0 && sections.every((section) => section.competitions.length === 0)
      ? "No live matches returned by the configured sports providers right now."
      : null,
    sports: mergeSections(sections),
    upcomingSports,
    recentSports,
  }
  cache.set(cacheKey, {
    expiresAt: now + ttl * 1000,
    payload,
  })
  return json(200, payload)
})
