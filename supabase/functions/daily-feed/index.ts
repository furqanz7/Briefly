const corsHeaders = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
}

type NewsCategory =
  | "world"
  | "politics"
  | "conflict"
  | "technology"
  | "business"
  | "sports"

type Article = {
  id: string
  headline: string
  source: string
  imageURL: string | null
  originalURL: string | null
  publishedAt: string | null
  summaryCards: string[]
  plainSummary: string
  rawDescription: string
  rawContent: string
  category: string
  categories: NewsCategory[]
  keywords: string[]
}

type FeedResponse = {
  generatedAt: string
  cacheHit: boolean
  articles: Article[]
}

type CacheEntry = {
  expiresAt: number
  payload: FeedResponse
}

const feedCache = new Map<string, CacheEntry>()

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

function startOfDayISO(date: Date) {
  const d = new Date(date)
  d.setHours(0, 0, 0, 0)
  return d.toISOString().slice(0, 10)
}

function categoryDisplayName(category: NewsCategory): string {
  switch (category) {
    case "world":
      return "World"
    case "politics":
      return "Politics"
    case "conflict":
      return "War / Conflict"
    case "technology":
      return "Technology"
    case "business":
      return "Business"
    case "sports":
      return "Sports"
  }
}

function normalizeText(value: string) {
  return value
    .replace(/\s+/g, " ")
    .replace(/\u00a0/g, " ")
    .trim()
}

function toID(seed: string) {
  // Stable-enough ID for client dedupe and Saved articles.
  const data = new TextEncoder().encode(seed)
  return crypto.subtle.digest("SHA-256", data).then((hash) => {
    const bytes = new Uint8Array(hash)
    return Array.from(bytes)
      .slice(0, 16)
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("")
  })
}

async function poolMap<T, R>(
  items: T[],
  concurrency: number,
  fn: (item: T) => Promise<R>
): Promise<R[]> {
  const results: R[] = []
  let index = 0

  const workers = Array.from({ length: Math.max(1, concurrency) }, async () => {
    while (index < items.length) {
      const current = index++
      results[current] = await fn(items[current])
    }
  })

  await Promise.all(workers)
  return results
}

async function fetchJSON(url: string, init?: RequestInit) {
  const response = await fetch(url, init)
  if (!response.ok) {
    const body = await response.text().catch(() => "")
    throw new Error(`httpStatus(${response.status}, ${body.slice(0, 180)})`)
  }
  return await response.json()
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : []
}

function asString(value: unknown): string | null {
  if (value === null || value === undefined || typeof value === "object") return null
  const text = normalizeText(String(value))
  return text.length > 0 ? text : null
}

function firstString(record: Record<string, unknown>, keys: string[]): string | null {
  for (const key of keys) {
    const value = asString(record[key])
    if (value) return value
  }
  return null
}

function numberString(value: unknown): string | null {
  if (typeof value === "number" && Number.isFinite(value)) return String(value)
  return asString(value)
}

function isoFromTimestamp(value: unknown): string | null {
  const timestamp = numberString(value)
  if (!timestamp) return null
  const numeric = Number(timestamp)
  if (!Number.isFinite(numeric)) return null
  return new Date(numeric > 9999999999 ? numeric : numeric * 1000).toISOString()
}

function imageFromRecord(record: Record<string, unknown>): string | null {
  const direct = firstString(record, ["imageURL", "imageUrl", "img", "coverImage", "thumbnail", "thumbnailUrl"])
  if (direct) return direct

  for (const key of ["image", "cover", "storyImage", "thumbnail"]) {
    const nested = asRecord(record[key])
    const value = nested ? firstString(nested, ["url", "imageUrl", "source", "src"]) : null
    if (value) return value
  }

  return null
}

async function guardianFetch(
  apiKey: string,
  category: NewsCategory,
  pageSize: number,
  fromDate: string
): Promise<Article[]> {
  // Guardian does not have all categories; we query by keywords to keep it simple and cheap.
  const queryByCategory: Record<NewsCategory, string> = {
    world: "world OR international OR pakistan OR iran OR israel OR china OR russia",
    politics: "politics OR election OR government OR parliament OR polls",
    conflict: "war OR conflict OR strike OR attack OR ceasefire",
    technology: "technology OR AI OR Nvidia OR OpenAI OR Apple OR Google",
    business: "business OR market OR startup OR earnings OR funding",
    sports: "sports OR cricket OR IPL OR football OR match",
  }

  const params = new URLSearchParams({
    "api-key": apiKey,
    "page-size": String(pageSize),
    "order-by": "newest",
    "from-date": fromDate,
    "show-fields": "headline,trailText,thumbnail,bodyText",
    q: queryByCategory[category],
  })

  const url = `https://content.guardianapis.com/search?${params.toString()}`
  const payload = await fetchJSON(url)
  const results = payload?.response?.results ?? []

  const mapped: Article[] = []
  for (const item of results) {
    const headline = normalizeText(item?.fields?.headline ?? item?.webTitle ?? "")
    if (!headline) continue
    const originalURL = typeof item?.webUrl === "string" ? item.webUrl : null
    const publishedAt = typeof item?.webPublicationDate === "string" ? item.webPublicationDate : null
    const description = normalizeText(item?.fields?.trailText ?? "")
    const bodyText = normalizeText(item?.fields?.bodyText ?? "")
    const imageURL = typeof item?.fields?.thumbnail === "string" ? item.fields.thumbnail : null

    const id = await toID(`${originalURL ?? headline}|The Guardian`)
    mapped.push({
      id,
      headline,
      source: "The Guardian",
      imageURL,
      originalURL,
      publishedAt,
      summaryCards: description ? [description] : [],
      plainSummary: description || bodyText.slice(0, 240),
      rawDescription: description,
      rawContent: bodyText.slice(0, 2500),
      category: categoryDisplayName(category),
      categories: [category],
      keywords: [],
    })
  }
  return mapped
}

async function gnewsFetch(
  apiKey: string,
  category: NewsCategory,
  pageSize: number,
  lang: string,
  country: string
): Promise<Article[]> {
  // GNews supports a subset of categories; for the rest, use search.
  const supportsTopHeadlines =
    category === "business" || category === "technology" || category === "sports" || category === "world"

  const queryByCategory: Record<NewsCategory, string> = {
    world: "Pakistan OR Middle East OR Iran OR Israel OR China OR Russia",
    politics: "election OR government OR parliament OR polls",
    conflict: "war OR conflict OR attack OR strike OR ceasefire",
    technology: "AI OR Nvidia OR OpenAI OR Apple OR Google",
    business: "market OR startup OR earnings OR stock",
    sports: "IPL OR cricket OR football OR match",
  }

  const base = supportsTopHeadlines
    ? "https://gnews.io/api/v4/top-headlines"
    : "https://gnews.io/api/v4/search"

  const params = new URLSearchParams({
    apikey: apiKey,
    lang,
    max: String(pageSize),
    q: queryByCategory[category],
    page: "1",
  })

  if (supportsTopHeadlines) {
    params.set("category", category === "world" ? "world" : category)
    if (category === "sports") params.set("country", country)
    if (category === "business" || category === "technology") params.set("country", "us")
  }

  const url = `${base}?${params.toString()}`
  const payload = await fetchJSON(url)
  const results = payload?.articles ?? []

  const mapped: Article[] = []
  for (const item of results) {
    const headline = normalizeText(item?.title ?? "")
    if (!headline) continue
    const originalURL = typeof item?.url === "string" ? item.url : null
    const publishedAt = typeof item?.publishedAt === "string" ? item.publishedAt : null
    const description = normalizeText(item?.description ?? "")
    const content = normalizeText(item?.content ?? "")
    const imageURL = typeof item?.image === "string" ? item.image : null
    const sourceName = normalizeText(item?.source?.name ?? "GNews")

    const id = await toID(`${originalURL ?? headline}|${sourceName}`)
    mapped.push({
      id,
      headline,
      source: sourceName,
      imageURL,
      originalURL,
      publishedAt,
      summaryCards: description ? [description] : [],
      plainSummary: description || content.slice(0, 240),
      rawDescription: description,
      rawContent: content.slice(0, 2500),
      category: categoryDisplayName(category),
      categories: [category],
      keywords: [],
    })
  }
  return mapped
}

async function newsAPIOrgFetch(
  apiKey: string,
  category: NewsCategory,
  pageSize: number,
  country: string
): Promise<Article[]> {
  const queryByCategory: Record<NewsCategory, string> = {
    world: "Pakistan OR Iran OR Israel OR China OR Russia OR Middle East",
    politics: "election OR government OR parliament OR polls OR campaign",
    conflict: "war OR conflict OR attack OR strike OR ceasefire",
    technology: "AI OR Nvidia OR OpenAI OR Apple OR Google",
    business: "market OR startup OR earnings OR stock OR deal",
    sports: "IPL OR cricket OR football OR match",
  }

  // newsapi.org categories: business, entertainment, general, health, science, sports, technology
  const apiCategory =
    category === "sports" || category === "business" || category === "technology" ? category : "general"

  const params = new URLSearchParams({
    apiKey,
    pageSize: String(pageSize),
    page: "1",
    category: apiCategory,
    q: queryByCategory[category],
  })
  // If country is invalid, newsapi returns empty; keep it simple: IN for sports, US for others.
  params.set("country", category === "sports" ? country : "us")

  const url = `https://newsapi.org/v2/top-headlines?${params.toString()}`
  const payload = await fetchJSON(url)
  const results = payload?.articles ?? []

  const mapped: Article[] = []
  for (const item of results) {
    const headline = normalizeText(item?.title ?? "")
    if (!headline) continue
    const originalURL = typeof item?.url === "string" ? item.url : null
    const publishedAt = typeof item?.publishedAt === "string" ? item.publishedAt : null
    const description = normalizeText(item?.description ?? "")
    const content = normalizeText(item?.content ?? "")
    const imageURL = typeof item?.urlToImage === "string" ? item.urlToImage : null
    const sourceName = normalizeText(item?.source?.name ?? "NewsAPI")

    const id = await toID(`${originalURL ?? headline}|${sourceName}`)
    mapped.push({
      id,
      headline,
      source: sourceName,
      imageURL,
      originalURL,
      publishedAt,
      summaryCards: description ? [description] : [],
      plainSummary: description || content.slice(0, 240),
      rawDescription: description,
      rawContent: content.slice(0, 2500),
      category: categoryDisplayName(category),
      categories: [category],
      keywords: [],
    })
  }
  return mapped
}

function cricbuzzNewsRecords(payload: unknown): Record<string, unknown>[] {
  const root = asRecord(payload)
  const candidates: unknown[] = []
  if (Array.isArray(payload)) candidates.push(payload)

  for (const key of ["storyList", "stories", "news", "articles", "data", "result", "results", "items", "list"]) {
    const value = root?.[key]
    if (Array.isArray(value)) candidates.push(value)
  }

  for (const key of ["topStories", "mainStories", "latest", "sections"]) {
    const section = asRecord(root?.[key])
    for (const nestedKey of ["storyList", "stories", "news", "articles", "data", "result", "items", "list"]) {
      const nestedValue = section?.[nestedKey]
      if (Array.isArray(nestedValue)) candidates.push(nestedValue)
    }
  }

  const records: Record<string, unknown>[] = []
  for (const candidate of candidates.flatMap((value) => asArray(value))) {
    const record = asRecord(candidate)
    if (!record || asRecord(record.ad)) continue
    records.push(asRecord(record.story) ?? record)
  }
  return records
}

function recursiveNewsRecords(payload: unknown, limit = 80): Record<string, unknown>[] {
  const records: Record<string, unknown>[] = []
  const seen = new Set<unknown>()

  function visit(value: unknown) {
    if (records.length >= limit || value === null || value === undefined || seen.has(value)) return
    if (typeof value !== "object") return
    seen.add(value)

    if (Array.isArray(value)) {
      for (const item of value) visit(item)
      return
    }

    const record = value as Record<string, unknown>
    const nestedStory = asRecord(record.story)
    if (nestedStory) visit(nestedStory)

    const hasHeadline = firstString(record, ["title", "headline", "hline", "name"]) !== null
    const hasArticleSignal = firstString(record, ["summary", "description", "intro", "context", "subtitle", "desc", "url", "link", "webURL", "webUrl"]) !== null
    if (hasHeadline && hasArticleSignal && !asRecord(record.ad)) {
      records.push(record)
    }

    for (const child of Object.values(record)) visit(child)
  }

  visit(payload)
  return records
}

async function cricbuzzNewsFetch(apiKey: string, pageSize: number): Promise<Article[]> {
  const payload = await fetchJSON("https://cricbuzz-cricket.p.rapidapi.com/news/v1/index", {
    headers: {
      "x-rapidapi-key": apiKey,
      "x-rapidapi-host": "cricbuzz-cricket.p.rapidapi.com",
      "content-type": "application/json",
    },
  })

  const mapped: Article[] = []
  const records = cricbuzzNewsRecords(payload)
  for (const [index, item] of (records.length > 0 ? records : recursiveNewsRecords(payload)).entries()) {
    const headline = firstString(item, ["hline", "headline", "title", "name"])
    if (!headline) continue

    const summary = firstString(item, ["intro", "context", "summary", "description"]) ?? ""
    const storyID = firstString(item, ["id", "storyId", "newsId"]) ?? `${headline}|${index}`
    const originalURL = firstString(item, ["url", "link", "webURL", "webUrl"])
    const id = await toID(`${originalURL ?? storyID}|Cricbuzz`)

    mapped.push({
      id,
      headline,
      source: firstString(item, ["source", "publisher", "provider"]) ?? "Cricbuzz",
      imageURL: imageFromRecord(item),
      originalURL,
      publishedAt: isoFromTimestamp(item.pubTime ?? item.publishedTime ?? item.createdTime),
      summaryCards: summary ? [summary] : [],
      plainSummary: summary,
      rawDescription: summary,
      rawContent: summary,
      category: categoryDisplayName("sports"),
      categories: ["sports"],
      keywords: ["cricket", "sports"],
    })

    if (mapped.length >= pageSize) break
  }
  return mapped
}

async function cricketLiveLineNewsFetch(apiKey: string, pageSize: number): Promise<Article[]> {
  const payload = await fetchJSON("https://cricket-live-line1.p.rapidapi.com/news", {
    headers: {
      "x-rapidapi-key": apiKey,
      "x-rapidapi-host": "cricket-live-line1.p.rapidapi.com",
      "content-type": "application/json",
    },
  })

  const mapped: Article[] = []
  const records = cricbuzzNewsRecords(payload)
  for (const [index, item] of (records.length > 0 ? records : recursiveNewsRecords(payload)).entries()) {
    const headline = firstString(item, ["hline", "headline", "title", "name"])
    if (!headline) continue

    const summary = firstString(item, ["intro", "context", "summary", "description", "desc"]) ?? ""
    const storyID = firstString(item, ["id", "storyId", "newsId"]) ?? `${headline}|${index}`
    const originalURL = firstString(item, ["url", "link", "webURL", "webUrl"])
    const id = await toID(`${originalURL ?? storyID}|Cricket Live Line`)

    mapped.push({
      id,
      headline,
      source: firstString(item, ["source", "publisher", "provider"]) ?? "Cricket Live Line",
      imageURL: imageFromRecord(item),
      originalURL,
      publishedAt: isoFromTimestamp(item.pubTime ?? item.publishedTime ?? item.createdTime ?? item.timestamp),
      summaryCards: summary ? [summary] : [],
      plainSummary: summary,
      rawDescription: summary,
      rawContent: summary,
      category: categoryDisplayName("sports"),
      categories: ["sports"],
      keywords: ["cricket", "sports"],
    })

    if (mapped.length >= pageSize) break
  }
  return mapped
}

async function espnCricinfoNewsFetch(apiKey: string, pageSize: number): Promise<Article[]> {
  const payload = await fetchJSON("https://espncricinfo-api.p.rapidapi.com/api/v1/cricketinfo/news", {
    headers: {
      "x-rapidapi-key": apiKey,
      "x-rapidapi-host": "espncricinfo-api.p.rapidapi.com",
      "content-type": "application/json",
    },
  })

  const mapped: Article[] = []
  const records = cricbuzzNewsRecords(payload)
  for (const [index, item] of (records.length > 0 ? records : recursiveNewsRecords(payload)).entries()) {
    const headline = firstString(item, ["hline", "headline", "title", "name"])
    if (!headline) continue

    const summary = firstString(item, ["intro", "context", "summary", "description", "desc"]) ?? ""
    const storyID = firstString(item, ["id", "storyId", "newsId", "story_id", "slug"]) ?? `${headline}|${index}`
    const originalURL = firstString(item, ["url", "link", "webURL", "webUrl"])
    const id = await toID(`${originalURL ?? storyID}|ESPNcricinfo`)

    mapped.push({
      id,
      headline,
      source: firstString(item, ["source", "publisher", "provider"]) ?? "ESPNcricinfo",
      imageURL: imageFromRecord(item),
      originalURL,
      publishedAt: isoFromTimestamp(item.pubTime ?? item.publishedTime ?? item.createdTime ?? item.timestamp),
      summaryCards: summary ? [summary] : [],
      plainSummary: summary,
      rawDescription: summary,
      rawContent: summary,
      category: categoryDisplayName("sports"),
      categories: ["sports"],
      keywords: ["cricket", "sports"],
    })

    if (mapped.length >= pageSize) break
  }
  return mapped
}

async function liveScoreNewsFetch(apiKey: string, pageSize: number): Promise<Article[]> {
  const params = new URLSearchParams({
    countryCode: "US",
    locale: "en",
    bet: "true",
  })
  const payload = await fetchJSON(`https://livescore6.p.rapidapi.com/news/v3/list?${params.toString()}`, {
    headers: {
      "x-rapidapi-key": apiKey,
      "x-rapidapi-host": "livescore6.p.rapidapi.com",
      "content-type": "application/json",
    },
  })

  const mapped: Article[] = []
  const records = recursiveNewsRecords(payload)
  for (const [index, item] of records.entries()) {
    const headline = firstString(item, ["title", "headline", "hline", "name"])
    if (!headline) continue

    const summary = firstString(item, ["summary", "description", "intro", "context", "subtitle", "desc"]) ?? ""
    const storyID = firstString(item, ["id", "newsId", "articleId", "storyId", "slug"]) ?? `${headline}|${index}`
    const originalURL = firstString(item, ["url", "link", "webURL", "webUrl"])
    const id = await toID(`${originalURL ?? storyID}|LiveScore`)

    mapped.push({
      id,
      headline,
      source: firstString(item, ["source", "publisher", "provider", "sourceName"]) ?? "LiveScore",
      imageURL: imageFromRecord(item),
      originalURL,
      publishedAt: isoFromTimestamp(item.pubTime ?? item.publishedTime ?? item.createdTime ?? item.timestamp),
      summaryCards: summary ? [summary] : [],
      plainSummary: summary,
      rawDescription: summary,
      rawContent: summary,
      category: categoryDisplayName("sports"),
      categories: ["sports"],
      keywords: ["sports"],
    })

    if (mapped.length >= pageSize) break
  }
  return mapped
}

function dedupeAndSort(articles: Article[], desiredCount: number) {
  const byKey = new Map<string, Article>()
  for (const article of articles) {
    const key = article.originalURL ?? article.id
    const existing = byKey.get(key)
    if (!existing) {
      byKey.set(key, article)
      continue
    }
    const existingDate = existing.publishedAt ? Date.parse(existing.publishedAt) : 0
    const incomingDate = article.publishedAt ? Date.parse(article.publishedAt) : 0
    if (incomingDate > existingDate) byKey.set(key, article)
  }

  const sorted = Array.from(byKey.values()).sort((a, b) => {
    const aDate = a.publishedAt ? Date.parse(a.publishedAt) : 0
    const bDate = b.publishedAt ? Date.parse(b.publishedAt) : 0
    return bDate - aDate
  })

  return sorted.slice(0, desiredCount)
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders })
  }

  if (request.method !== "GET") {
    return json(405, { error: "Method not allowed." })
  }

  const anonKey = request.headers.get("apikey") ?? Deno.env.get("SUPABASE_ANON_KEY")
  if (!anonKey) {
    return json(500, { error: "Missing configuration." })
  }

  const url = new URL(request.url)
  const desiredCount = clamp(parseIntOr(url.searchParams.get("count"), 60), 12, 120)
  const lang = (url.searchParams.get("lang") ?? "en").slice(0, 5)
  const country = (url.searchParams.get("country") ?? "in").slice(0, 2).toLowerCase()
  const ttlSeconds = clamp(parseIntOr(url.searchParams.get("ttl"), 180), 30, 900)

  const categories: NewsCategory[] = ["world", "politics", "conflict", "technology", "business", "sports"]
  const fromDate = startOfDayISO(new Date())

  const cacheKey = `${fromDate}|${lang}|${country}|${desiredCount}`
  const now = Date.now()
  const cached = feedCache.get(cacheKey)
  if (cached && cached.expiresAt > now) {
    return json(200, { ...cached.payload, cacheHit: true })
  }

  const guardianKey = Deno.env.get("GUARDIAN_API_KEY") ?? ""
  const gnewsKey = Deno.env.get("GNEWS_API_KEY") ?? ""
  const newsAPIKey = Deno.env.get("NEWSAPI_API_KEY") ?? ""
  const rapidAPIKey = Deno.env.get("RAPIDAPI_KEY") ?? ""

  const tasks: Array<() => Promise<Article[]>> = []

  const pageSizePerBucket = 4
  for (const category of categories) {
    if (guardianKey) tasks.push(() => guardianFetch(guardianKey, category, pageSizePerBucket, fromDate))
    if (gnewsKey) tasks.push(() => gnewsFetch(gnewsKey, category, pageSizePerBucket, lang, country))
    if (newsAPIKey) tasks.push(() => newsAPIOrgFetch(newsAPIKey, category, pageSizePerBucket, country))
  }
  if (rapidAPIKey) {
    tasks.push(() => cricbuzzNewsFetch(rapidAPIKey, pageSizePerBucket + 4))
    tasks.push(() => cricketLiveLineNewsFetch(rapidAPIKey, pageSizePerBucket + 4))
    tasks.push(() => espnCricinfoNewsFetch(rapidAPIKey, pageSizePerBucket + 4))
    tasks.push(() => liveScoreNewsFetch(rapidAPIKey, pageSizePerBucket + 4))
  }

  // If no providers are configured, return empty but valid payload.
  if (tasks.length === 0) {
    const payload: FeedResponse = {
      generatedAt: new Date().toISOString(),
      cacheHit: false,
      articles: [],
    }
    feedCache.set(cacheKey, { expiresAt: now + ttlSeconds * 1000, payload })
    return json(200, payload)
  }

  const results = await poolMap(tasks, 6, async (fn) => {
    try {
      return await fn()
    } catch {
      return []
    }
  })

  const merged = results.flatMap((r) => r)
  const finalArticles = dedupeAndSort(merged, desiredCount)

  const payload: FeedResponse = {
    generatedAt: new Date().toISOString(),
    cacheHit: false,
    articles: finalArticles,
  }

  feedCache.set(cacheKey, { expiresAt: now + ttlSeconds * 1000, payload })
  return json(200, payload)
})
