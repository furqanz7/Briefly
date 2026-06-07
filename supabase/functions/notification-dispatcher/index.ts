const corsHeaders = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
}

type PushDevice = {
  id: string
  user_id: string
  device_token: string
  environment: "production" | "sandbox"
}

type NotificationPreferences = {
  user_id: string
  daily_brief_enabled: boolean
  breaking_news_enabled: boolean
  jobs_enabled: boolean
  sports_enabled: boolean
  reading_goal_enabled: boolean
  daily_brief_time: string
  timezone: string | null
}

type JobActivity = {
  event_type: string
  role_query: string | null
  job_title: string | null
  company: string | null
  market: string | null
  deck: string | null
  keywords: string[] | null
  created_at: string
}

type JobListing = {
  id: string
  title: string
  company: string
  location: string
  matchScore?: number
  applyURL?: string | null
}

type FeedSnapshot = {
  payload: FeedResponse
  generated_at: string
}

type FeedResponse = {
  generatedAt?: string
  articles?: ArticlePayload[]
}

type ArticlePayload = {
  id: string
  headline: string
  source: string
  imageURL?: string | null
  originalURL?: string | null
  publishedAt?: string | null
  summaryCards?: string[]
  plainSummary?: string
  rawDescription?: string
  rawContent?: string
  category?: string
  categories?: string[]
  keywords?: string[]
}

type LiveScoresResponse = {
  sports?: LiveSportSection[]
}

type LiveSportSection = {
  id: string
  name: string
  competitions: LiveCompetition[]
}

type LiveCompetition = {
  id: string
  name: string
  country?: string | null
  matches: LiveMatch[]
}

type LiveMatch = {
  id: string
  sportID: string
  sportName: string
  competitionName: string
  country?: string | null
  status: string
  statusDetail?: string | null
  clock?: string | null
  period?: string | null
  homeName: string
  awayName: string
  homeScore?: string | null
  awayScore?: string | null
  scoreSummary?: string | null
  note?: string | null
}

type FollowedSportsTeam = {
  sport_id: string
  team_name: string
  team_key: string
}

type ReadingGoal = {
  daily_goal_minutes: number
}

type ReadingMinutes = {
  minutes: number
  seconds: number | null
}

type DispatchResult = {
  userID: string
  lane: string
  status: string
  reason?: string
  title?: string
  detail?: string
}

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders })
}

function env(name: string) {
  return Deno.env.get(name)?.trim() ?? ""
}

function supabaseCredentials() {
  const url = env("SUPABASE_URL").replace(/\/+$/, "")
  const key = env("SUPABASE_SERVICE_ROLE_KEY") || env("SUPABASE_SERVICE_KEY")
  if (!url || !key) throw new Error("Supabase service role credentials are not configured.")
  return { url, key }
}

async function supabaseREST<T>(path: string, init: RequestInit = {}): Promise<T> {
  const { url, key } = supabaseCredentials()
  const response = await fetch(`${url}/rest/v1/${path}`, {
    ...init,
    headers: {
      "apikey": key,
      "authorization": `Bearer ${key}`,
      "content-type": "application/json",
      ...(init.headers ?? {}),
    },
  })

  if (!response.ok) {
    const body = await response.text().catch(() => "")
    throw new Error(`Supabase REST ${response.status}: ${body.slice(0, 300)}`)
  }

  if (response.status === 204) return undefined as T
  const text = await response.text()
  return (text ? JSON.parse(text) : undefined) as T
}

async function callFunction<T>(name: string, params?: URLSearchParams): Promise<T | null> {
  const { url, key } = supabaseCredentials()
  const endpoint = new URL(`${url}/functions/v1/${name}`)
  if (params) endpoint.search = params.toString()

  const response = await fetch(endpoint, {
    headers: {
      "apikey": key,
      "authorization": `Bearer ${key}`,
      "content-type": "application/json",
    },
  })

  if (!response.ok) return null
  return await response.json().catch(() => null) as T | null
}

function countryCode(market: string | null | undefined) {
  switch ((market ?? "").toLowerCase()) {
    case "uk":
      return "gb"
    case "canada":
      return "ca"
    case "india":
      return "in"
    case "remote":
    case "us":
    default:
      return "us"
  }
}

async function fetchJobMatches(query: string, country: string) {
  const params = new URLSearchParams({ q: query, country })
  const payload = await callFunction<{ jobs?: JobListing[] }>("jobs-data", params)
  return payload?.jobs ?? []
}

function deriveJobQuery(events: JobActivity[]) {
  const explicitQuery = events.find((event) => event.role_query?.trim())?.role_query?.trim()
  if (explicitQuery) return explicitQuery

  const openOrSaved = events.find((event) => event.job_title?.trim())
  if (openOrSaved?.job_title) return openOrSaved.job_title

  const keywords = events.flatMap((event) => event.keywords ?? []).filter(Boolean)
  if (keywords.length > 0) return keywords.slice(0, 4).join(" ")

  return null
}

function apnsConfig() {
  const keyID = env("APNS_KEY_ID")
  const teamID = env("APNS_TEAM_ID")
  const bundleID = env("APNS_BUNDLE_ID")
  const privateKey = env("APNS_AUTH_KEY").replaceAll("\\n", "\n")
  const environment = env("APNS_ENV") || "production"

  if (!keyID || !teamID || !bundleID || !privateKey) return null
  return { keyID, teamID, bundleID, privateKey, environment }
}

function base64URL(input: ArrayBuffer | Uint8Array | string) {
  const bytes = typeof input === "string"
    ? new TextEncoder().encode(input)
    : input instanceof Uint8Array
      ? input
      : new Uint8Array(input)

  let binary = ""
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "")
}

function pemToArrayBuffer(pem: string) {
  const base64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "")
  const binary = atob(base64)
  const bytes = new Uint8Array(binary.length)
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index)
  }
  return bytes.buffer
}

async function apnsJWT(config: NonNullable<ReturnType<typeof apnsConfig>>) {
  const header = base64URL(JSON.stringify({ alg: "ES256", kid: config.keyID }))
  const claims = base64URL(JSON.stringify({
    iss: config.teamID,
    iat: Math.floor(Date.now() / 1000),
  }))
  const signingInput = `${header}.${claims}`
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(config.privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  )
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  )
  return `${signingInput}.${base64URL(signature)}`
}

async function sendAPNs(deviceToken: string, payload: unknown) {
  const config = apnsConfig()
  if (!config) throw new Error("APNs credentials are not configured.")

  const host = config.environment === "sandbox"
    ? "https://api.sandbox.push.apple.com"
    : "https://api.push.apple.com"

  const response = await fetch(`${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      "authorization": `bearer ${await apnsJWT(config)}`,
      "apns-topic": config.bundleID,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  })

  if (!response.ok) {
    const body = await response.text().catch(() => "")
    throw new Error(`APNs ${response.status}: ${body.slice(0, 200)}`)
  }
}

async function fetchDevices(userID: string) {
  return await supabaseREST<PushDevice[]>(
    `push_devices?user_id=eq.${userID}&enabled=eq.true&select=id,user_id,device_token,environment`,
  )
}

async function alreadyDelivered(userID: string, notificationType: string, dedupeKey: string) {
  const rows = await supabaseREST<{ id: string }[]>(
    `notification_deliveries?user_id=eq.${userID}&notification_type=eq.${notificationType}&dedupe_key=eq.${encodeURIComponent(dedupeKey)}&status=eq.sent&select=id&limit=1`,
  )
  return rows.length > 0
}

async function recentDeliveryCount(userID: string, notificationType: string, hours: number) {
  const since = new Date(Date.now() - hours * 60 * 60 * 1000).toISOString()
  const rows = await supabaseREST<{ id: string }[]>(
    `notification_deliveries?user_id=eq.${userID}&notification_type=eq.${notificationType}&status=eq.sent&created_at=gte.${encodeURIComponent(since)}&select=id&limit=5`,
  )
  return rows.length
}

async function writeDelivery(
  userID: string,
  deviceID: string | null,
  notificationType: string,
  dedupeKey: string,
  title: string,
  body: string,
  status: "sent" | "failed" | "skipped",
  providerMessage: string | null,
  targetURL: string | null,
) {
  await supabaseREST<void>("notification_deliveries?on_conflict=user_id,device_id,notification_type,dedupe_key", {
    method: "POST",
    headers: { "Prefer": "resolution=merge-duplicates,return=minimal" },
    body: JSON.stringify({
      user_id: userID,
      device_id: deviceID,
      notification_type: notificationType,
      title,
      body,
      target_url: targetURL,
      dedupe_key: dedupeKey,
      status,
      provider_message: providerMessage,
      sent_at: status === "sent" ? new Date().toISOString() : null,
    }),
  })
}

async function dispatchNotification(args: {
  userID: string
  devices: PushDevice[]
  notificationType: string
  route: string
  dedupeKey: string
  title: string
  body: string
  targetURL: string | null
  data?: Record<string, unknown>
  dryRun: boolean
}): Promise<DispatchResult[]> {
  const { userID, devices, notificationType, route, dedupeKey, title, body, targetURL, data, dryRun } = args

  if (devices.length === 0) {
    return [{ userID, lane: notificationType, status: "skipped", reason: "no_enabled_devices" }]
  }

  if (await alreadyDelivered(userID, notificationType, dedupeKey)) {
    return [{ userID, lane: notificationType, status: "skipped", reason: "already_delivered", title }]
  }

  if (dryRun) {
    return [{ userID, lane: notificationType, status: "dry_run", title, detail: body }]
  }

  const payload = {
    aps: {
      alert: { title, body },
      sound: "default",
    },
    type: notificationType,
    route,
    ...(data ?? {}),
  }

  const results: DispatchResult[] = []
  for (const device of devices) {
    try {
      await sendAPNs(device.device_token, payload)
      await writeDelivery(userID, device.id, notificationType, dedupeKey, title, body, "sent", null, targetURL)
      results.push({ userID, lane: notificationType, status: "sent", title, detail: device.id })
    } catch (error) {
      const providerMessage = error instanceof Error ? error.message : "Unknown APNs error"
      await writeDelivery(userID, device.id, notificationType, dedupeKey, title, body, "failed", providerMessage, targetURL)
      results.push({ userID, lane: notificationType, status: "failed", title, reason: providerMessage })
    }
  }
  return results
}

function timezone(preferences: NotificationPreferences) {
  return preferences.timezone?.trim() || "UTC"
}

function localParts(timeZone: string, date = new Date()) {
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    hour12: false,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  })
  const parts = Object.fromEntries(formatter.formatToParts(date).map((part) => [part.type, part.value]))
  return {
    day: `${parts.year}-${parts.month}-${parts.day}`,
    minutes: Number(parts.hour) * 60 + Number(parts.minute),
  }
}

function timeToMinutes(value: string | null | undefined) {
  const [hour, minute] = (value ?? "08:00:00").split(":").map((part) => Number(part))
  return (Number.isFinite(hour) ? hour : 8) * 60 + (Number.isFinite(minute) ? minute : 0)
}

function truncate(value: string | null | undefined, maxLength: number) {
  const clean = (value ?? "").replace(/\s+/g, " ").trim()
  if (clean.length <= maxLength) return clean
  return `${clean.slice(0, Math.max(0, maxLength - 1)).trimEnd()}...`
}

function normalizeKey(value: string) {
  return value
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
}

async function latestFeedSnapshot() {
  const rows = await supabaseREST<FeedSnapshot[]>(
    "news_feed_snapshots?select=payload,generated_at&order=generated_at.desc&limit=1",
  )
  return rows[0] ?? null
}

function articleCategories(article: ArticlePayload) {
  const values = [
    article.category ?? "",
    ...(article.categories ?? []),
    ...(article.keywords ?? []),
    article.headline,
    article.plainSummary ?? "",
  ].join(" ").toLowerCase()

  const categories = new Set<string>()
  if (/\b(conflict|war|attack|strike|missile|troops|ceasefire|hostage|killed|crisis)\b/.test(values)) {
    categories.add("conflict")
  }
  if (/\b(politics|election|president|parliament|senate|government|minister|vote)\b/.test(values)) {
    categories.add("politics")
  }
  if (/\b(world|global|international|middle east|border|diplomat)\b/.test(values)) {
    categories.add("world")
  }
  return [...categories]
}

function breakingScore(article: ArticlePayload) {
  const text = [
    article.category ?? "",
    ...(article.categories ?? []),
    ...(article.keywords ?? []),
    article.headline,
    article.plainSummary ?? "",
  ].join(" ").toLowerCase()

  let score = 0
  if (/\b(conflict|war|attack|strike|missile|troops|ceasefire|hostage|killed|crisis)\b/.test(text)) score += 4
  if (/\b(politics|election|president|parliament|senate|government|minister|vote)\b/.test(text)) score += 2
  if (/\b(world|global|international|middle east|border|diplomat)\b/.test(text)) score += 2
  if (/\b(live|breaking|urgent|escalation|major|dead|injured|sanctions)\b/.test(text)) score += 2
  return score
}

function recentEnough(article: ArticlePayload) {
  if (!article.publishedAt) return true
  const publishedAt = Date.parse(article.publishedAt)
  if (!Number.isFinite(publishedAt)) return true
  return Date.now() - publishedAt < 12 * 60 * 60 * 1000
}

function articleNotificationData(article: ArticlePayload) {
  return {
    article_id: article.id,
    headline: truncate(article.headline, 170),
    source: truncate(article.source, 60),
    image_url: article.imageURL ?? "",
    original_url: article.originalURL ?? "",
    published_at: article.publishedAt ?? "",
    summary_cards: (article.summaryCards ?? []).slice(0, 1).map((card) => truncate(card, 300)),
    plain_summary: truncate(article.plainSummary, 320),
    raw_description: truncate(article.rawDescription, 320),
    raw_content: truncate(article.rawContent, 420),
    category: article.category ?? "World",
    categories: articleCategories(article),
    keywords: (article.keywords ?? []).slice(0, 8).map((keyword) => truncate(keyword, 40)),
  }
}

function matchText(match: LiveMatch) {
  return [
    match.sportName,
    match.competitionName,
    match.country ?? "",
    match.homeName,
    match.awayName,
    match.status,
    match.statusDetail ?? "",
    match.note ?? "",
  ].join(" ").toLowerCase()
}

function isMajorMatch(match: LiveMatch) {
  return /\b(world cup|champions league|premier league|nba finals|finals|wimbledon|grand slam|ipl|olympic|world test championship|ashes|super bowl|major final)\b/
    .test(matchText(match))
}

function matchStatusBody(match: LiveMatch) {
  const score = match.homeScore && match.awayScore
    ? `${match.homeScore}-${match.awayScore}`
    : match.scoreSummary
      ? match.scoreSummary
      : match.clock || match.period || match.status
  return truncate(`${score} · ${match.competitionName}`, 120)
}

async function dailyBriefLane(preferences: NotificationPreferences, devices: PushDevice[], dryRun: boolean) {
  if (!preferences.daily_brief_enabled) return []
  const local = localParts(timezone(preferences))
  if (local.minutes < timeToMinutes(preferences.daily_brief_time)) {
    return [{ userID: preferences.user_id, lane: "daily_brief", status: "skipped", reason: "before_daily_brief_time" }]
  }

  const snapshot = await latestFeedSnapshot()
  if (!snapshot || Date.now() - Date.parse(snapshot.generated_at) > 26 * 60 * 60 * 1000) {
    return [{ userID: preferences.user_id, lane: "daily_brief", status: "skipped", reason: "no_fresh_brief" }]
  }

  return await dispatchNotification({
    userID: preferences.user_id,
    devices,
    notificationType: "daily_brief",
    route: "home",
    dedupeKey: `${local.day}:daily_brief`,
    title: "Your daily brief is ready",
    body: "Today in 60 Seconds is refreshed.",
    targetURL: "briefly://home",
    dryRun,
  })
}

async function breakingEssentialsLane(preferences: NotificationPreferences, devices: PushDevice[], dryRun: boolean) {
  if (!preferences.breaking_news_enabled) return []
  if (await recentDeliveryCount(preferences.user_id, "breaking_essential", 24) >= 2) {
    return [{ userID: preferences.user_id, lane: "breaking_essential", status: "skipped", reason: "daily_cap_reached" }]
  }

  const snapshot = await latestFeedSnapshot()
  const articles = snapshot?.payload?.articles ?? []
  const candidate = articles
    .filter(recentEnough)
    .map((article) => ({ article, score: breakingScore(article) }))
    .filter((item) => item.score >= 4)
    .sort((a, b) => b.score - a.score)[0]?.article

  if (!candidate) {
    return [{ userID: preferences.user_id, lane: "breaking_essential", status: "skipped", reason: "no_high_priority_story" }]
  }

  const local = localParts(timezone(preferences))
  return await dispatchNotification({
    userID: preferences.user_id,
    devices,
    notificationType: "breaking_essential",
    route: "article",
    dedupeKey: `${local.day}:breaking:${candidate.id}`,
    title: "Breaking essential",
    body: truncate(candidate.headline, 150),
    targetURL: candidate.originalURL ?? "briefly://home",
    data: articleNotificationData(candidate),
    dryRun,
  })
}

async function jobsLane(preferences: NotificationPreferences, devices: PushDevice[], dryRun: boolean) {
  if (!preferences.jobs_enabled) return []
  const since = new Date(Date.now() - 14 * 24 * 60 * 60 * 1000).toISOString()
  const events = await supabaseREST<JobActivity[]>(
    `job_activity_events?user_id=eq.${preferences.user_id}&created_at=gte.${encodeURIComponent(since)}&select=event_type,role_query,job_title,company,market,deck,keywords,created_at&order=created_at.desc&limit=20`,
  )

  const query = deriveJobQuery(events)
  if (!query) {
    return [{ userID: preferences.user_id, lane: "job_match", status: "skipped", reason: "no_recent_activity" }]
  }

  const matches = await fetchJobMatches(query, countryCode(events[0]?.market))
  const local = localParts(timezone(preferences))
  const undelivered = []
  for (const job of matches) {
    const dedupeKey = `${local.day}:job:${job.id}`
    if (!(await alreadyDelivered(preferences.user_id, "job_match", dedupeKey))) {
      undelivered.push({ job, dedupeKey })
    }
    if (undelivered.length >= 3) break
  }

  const top = undelivered[0]
  if (!top) {
    return [{ userID: preferences.user_id, lane: "job_match", status: "skipped", reason: "no_new_job_match", detail: query }]
  }

  const count = undelivered.length
  const role = truncate(query, 24)
  const title = count === 1
    ? `New ${role} role matches your profile`
    : `${count} new ${role} roles match your profile`

  return await dispatchNotification({
    userID: preferences.user_id,
    devices,
    notificationType: "job_match",
    route: "jobs",
    dedupeKey: top.dedupeKey,
    title: truncate(title, 120),
    body: truncate(`${top.job.title} at ${top.job.company}`, 150),
    targetURL: top.job.applyURL ?? "briefly://jobs",
    data: {
      job_id: top.job.id,
      url: top.job.applyURL ?? "",
    },
    dryRun,
  })
}

async function sportsLane(preferences: NotificationPreferences, devices: PushDevice[], dryRun: boolean) {
  if (!preferences.sports_enabled) return []
  const followed = await supabaseREST<FollowedSportsTeam[]>(
    `sports_followed_teams?user_id=eq.${preferences.user_id}&select=sport_id,team_name,team_key&limit=100`,
  )
  const scores = await callFunction<LiveScoresResponse>("live-scores", new URLSearchParams({ ttl: "60" }))
  const matches = (scores?.sports ?? []).flatMap((sport) =>
    sport.competitions.flatMap((competition) =>
      competition.matches.map((match) => ({ ...match, sportName: match.sportName || sport.name }))
    )
  )

  if (matches.length === 0) {
    return [{ userID: preferences.user_id, lane: "sports_live", status: "skipped", reason: "no_live_matches" }]
  }

  const followedKeys = new Set(followed.map((team) => `${team.sport_id}:${team.team_key}`))
  let candidate = matches.find((match) => {
    const home = normalizeKey(match.homeName)
    const away = normalizeKey(match.awayName)
    return followedKeys.has(`${match.sportID}:${home}`) || followedKeys.has(`${match.sportID}:${away}`)
  })

  let reason = "followed_team"
  if (!candidate) {
    if (await recentDeliveryCount(preferences.user_id, "sports_live", 24) >= 1) {
      return [{ userID: preferences.user_id, lane: "sports_live", status: "skipped", reason: "major_match_cap_reached" }]
    }
    candidate = matches.find(isMajorMatch)
    reason = "major_match"
  }

  if (!candidate) {
    return [{ userID: preferences.user_id, lane: "sports_live", status: "skipped", reason: followed.length ? "no_followed_team_live" : "no_followed_teams" }]
  }

  const local = localParts(timezone(preferences))
  return await dispatchNotification({
    userID: preferences.user_id,
    devices,
    notificationType: "sports_live",
    route: "sports",
    dedupeKey: `${local.day}:sports:${candidate.id}`,
    title: truncate(`Live now: ${candidate.homeName} vs ${candidate.awayName}`, 120),
    body: matchStatusBody(candidate),
    targetURL: "briefly://sports",
    data: {
      match_id: candidate.id,
      sport_id: candidate.sportID,
      reason,
    },
    dryRun,
  })
}

async function readingGoalLane(preferences: NotificationPreferences, devices: PushDevice[], dryRun: boolean) {
  if (!preferences.reading_goal_enabled) return []
  const local = localParts(timezone(preferences))
  if (local.minutes < 18 * 60) {
    return [{ userID: preferences.user_id, lane: "reading_goal", status: "skipped", reason: "before_evening_reminder" }]
  }

  const goals = await supabaseREST<ReadingGoal[]>(
    `user_reading_goals?user_id=eq.${preferences.user_id}&select=daily_goal_minutes&limit=1`,
  )
  const goal = goals[0]?.daily_goal_minutes
  if (!goal || goal <= 0) {
    return [{ userID: preferences.user_id, lane: "reading_goal", status: "skipped", reason: "no_goal_set" }]
  }

  const rows = await supabaseREST<ReadingMinutes[]>(
    `book_reading_minutes?user_id=eq.${preferences.user_id}&reading_date=eq.${local.day}&select=minutes,seconds&limit=1`,
  )
  const secondsRead = rows.reduce((total, row) => total + (row.seconds ?? row.minutes * 60), 0)
  const remainingMinutes = Math.ceil(Math.max(0, goal * 60 - secondsRead) / 60)
  if (remainingMinutes <= 0) {
    return [{ userID: preferences.user_id, lane: "reading_goal", status: "skipped", reason: "goal_met" }]
  }

  return await dispatchNotification({
    userID: preferences.user_id,
    devices,
    notificationType: "reading_goal",
    route: "books",
    dedupeKey: `${local.day}:reading_goal`,
    title: `${remainingMinutes} min left for today's reading goal`,
    body: "Open Books to finish your daily reading streak.",
    targetURL: "briefly://books",
    data: {
      remaining_minutes: remainingMinutes,
      goal_minutes: goal,
    },
    dryRun,
  })
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { headers: corsHeaders })
  if (request.method !== "POST") return json(405, { error: "Use POST." })

  try {
    const url = new URL(request.url)
    const body = await request.json().catch(() => ({})) as { dryRun?: boolean; limit?: number; lanes?: string[] }
    const dryRun = body.dryRun ?? url.searchParams.get("dry_run") === "true"
    const limit = Math.max(1, Math.min(body.limit ?? 50, 200))
    const requestedLanes = new Set(body.lanes ?? ["daily_brief", "breaking_essential", "job_match", "sports_live", "reading_goal"])

    const preferences = await supabaseREST<NotificationPreferences[]>(
      `notification_preferences?select=*&limit=${limit}`,
    )

    const results: DispatchResult[] = []
    for (const preference of preferences) {
      const devices = await fetchDevices(preference.user_id)
      if (devices.length === 0) {
        results.push({ userID: preference.user_id, lane: "all", status: "skipped", reason: "no_enabled_devices" })
        continue
      }

      if (requestedLanes.has("daily_brief")) {
        results.push(...await dailyBriefLane(preference, devices, dryRun))
      }
      if (requestedLanes.has("breaking_essential")) {
        results.push(...await breakingEssentialsLane(preference, devices, dryRun))
      }
      if (requestedLanes.has("job_match")) {
        results.push(...await jobsLane(preference, devices, dryRun))
      }
      if (requestedLanes.has("sports_live")) {
        results.push(...await sportsLane(preference, devices, dryRun))
      }
      if (requestedLanes.has("reading_goal")) {
        results.push(...await readingGoalLane(preference, devices, dryRun))
      }
    }

    return json(200, { dryRun, results })
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown notification dispatcher error"
    return json(500, { error: message })
  }
})
