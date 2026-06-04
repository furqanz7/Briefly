const corsHeaders = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
}

type BookItem = {
  id: string
  title: string
  authors: string[]
  genre: string
  description: string
  coverURL: string | null
  rating: number | null
  pageCount: number | null
  publishedYear: string
  publisher: string
  source: string
  availability: "Readable" | "Preview" | "Reference"
  previewURL: string | null
  downloadURL: string | null
}

type BudgetPeriod = "hour" | "day" | "month"
type ProviderID =
  | "google"
  | "openlibrary"
  | "gutendex"
  | "realtimebooks"
  | "amazonbooks"
  | "hapibooks"
  | "annasarchive"
  | "superhero"

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

type ProviderRunResult = {
  id: ProviderID
  books: BookItem[]
  error: string | null
}

const minuteMS = 60 * 1000
const dayMS = 24 * 60 * 60 * 1000

const providerBudgets: Record<ProviderID, ProviderBudgetConfig> = {
  google: {
    period: "day",
    autoLimit: 600,
    minRefreshMS: 30 * minuteMS,
    quotaBackoffMS: 2 * 60 * minuteMS,
    snapshotTTLMS: 2 * dayMS,
  },
  openlibrary: {
    period: "day",
    autoLimit: 600,
    minRefreshMS: 30 * minuteMS,
    quotaBackoffMS: 2 * 60 * minuteMS,
    snapshotTTLMS: 2 * dayMS,
  },
  gutendex: {
    period: "day",
    autoLimit: 300,
    minRefreshMS: 60 * minuteMS,
    quotaBackoffMS: 2 * 60 * minuteMS,
    snapshotTTLMS: 3 * dayMS,
  },
  realtimebooks: {
    period: "day",
    autoLimit: 80,
    minRefreshMS: 2 * 60 * minuteMS,
    quotaBackoffMS: 8 * 60 * minuteMS,
    snapshotTTLMS: 3 * dayMS,
  },
  amazonbooks: {
    period: "day",
    autoLimit: 60,
    minRefreshMS: 4 * 60 * minuteMS,
    quotaBackoffMS: 12 * 60 * minuteMS,
    snapshotTTLMS: 5 * dayMS,
  },
  hapibooks: {
    period: "day",
    autoLimit: 60,
    minRefreshMS: 4 * 60 * minuteMS,
    quotaBackoffMS: 12 * 60 * minuteMS,
    snapshotTTLMS: 5 * dayMS,
  },
  annasarchive: {
    period: "day",
    autoLimit: 30,
    minRefreshMS: 6 * 60 * minuteMS,
    quotaBackoffMS: 24 * 60 * minuteMS,
    snapshotTTLMS: 7 * dayMS,
  },
  superhero: {
    period: "day",
    autoLimit: 40,
    minRefreshMS: 6 * 60 * minuteMS,
    quotaBackoffMS: 12 * 60 * minuteMS,
    snapshotTTLMS: 7 * dayMS,
  },
}

const providerStorageVersions: Record<ProviderID, string> = {
  google: "v2",
  openlibrary: "v1",
  gutendex: "v1",
  realtimebooks: "v3",
  amazonbooks: "v2",
  hapibooks: "v2",
  annasarchive: "v3",
  superhero: "v4",
}

function storageProviderID(providerID: ProviderID) {
  return `${providerID}-${providerStorageVersions[providerID]}`
}

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders })
}

function iso(date = new Date()) {
  return date.toISOString().replace(/\.\d{3}Z$/, "Z")
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error)
}

function cleanHTML(value: unknown) {
  return String(value ?? "")
    .replace(/<[^>]+>/g, "")
    .replaceAll("&amp;", "&")
    .replaceAll("&quot;", "\"")
    .replaceAll("&#39;", "'")
    .trim()
}

async function fetchJSON<T>(url: string): Promise<T> {
  const response = await fetchWithTimeout(url, {
    headers: { "content-type": "application/json" },
  })
  if (!response.ok) {
    const body = await response.text().catch(() => "")
    throw new Error(`HTTP ${response.status} ${body.slice(0, 140)}`)
  }
  return await response.json() as T
}

function env(name: string) {
  return Deno.env.get(name)?.trim() ?? ""
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
  if (!credentials) throw new Error("Supabase service role secret is not configured for books provider budgeting.")

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
    throw new Error(`Supabase books store: HTTP ${response.status} ${body.slice(0, 160)}`)
  }

  if (response.status === 204) return undefined as T
  const text = await response.text()
  return (text ? JSON.parse(text) : undefined) as T
}

function usageRecord(providerID: ProviderID, now: number): ProviderUsageRecord {
  const budget = providerBudgets[providerID]
  const window = periodWindow(budget.period, now)
  return {
    provider_id: storageProviderID(providerID),
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
    `books_provider_usage?provider_id=eq.${encodeURIComponent(storageProviderID(providerID))}&select=*`
  )
  return records[0] ?? null
}

async function writeUsage(record: ProviderUsageRecord) {
  if (!supabaseRESTCredentials()) return
  await supabaseREST<void>("books_provider_usage?on_conflict=provider_id", {
    method: "POST",
    headers: { "Prefer": "resolution=merge-duplicates,return=minimal" },
    body: JSON.stringify(record),
  })
}

async function readSnapshot(providerID: ProviderID, scope: string) {
  if (!supabaseRESTCredentials()) return null
  const records = await supabaseREST<ProviderSnapshotRecord<BookItem[]>[]>(
    `books_provider_snapshots?provider_id=eq.${encodeURIComponent(storageProviderID(providerID))}&scope=eq.${encodeURIComponent(scope)}&select=*`
  )
  return records[0] ?? null
}

async function writeSnapshot(providerID: ProviderID, scope: string, payload: BookItem[]) {
  if (!supabaseRESTCredentials()) return
  const now = Date.now()
  const budget = providerBudgets[providerID]
  await supabaseREST<void>("books_provider_snapshots?on_conflict=provider_id%2Cscope", {
    method: "POST",
    headers: { "Prefer": "resolution=merge-duplicates,return=minimal" },
    body: JSON.stringify({
      provider_id: storageProviderID(providerID),
      scope,
      payload,
      generated_at: iso(new Date(now)),
      expires_at: iso(new Date(now + budget.snapshotTTLMS)),
      updated_at: iso(new Date(now)),
    }),
  })
}

async function runWithBudget(providerID: ProviderID, scope: string, run: () => Promise<BookItem[]>) {
  const persistentBudgetEnabled = Boolean(supabaseRESTCredentials())
  const budget = providerBudgets[providerID]

  if (!persistentBudgetEnabled) {
    return await run()
  }

  const snapshot = await readSnapshot(providerID, scope)
  const now = Date.now()
  const generatedAt = snapshot ? Date.parse(snapshot.generated_at) : 0

  if (snapshot && generatedAt > 0 && now - generatedAt < budget.minRefreshMS) {
    return snapshot.payload
  }

  let usage = normalizeUsage(providerID, await readUsage(providerID), now)
  const blockedUntil = usage.blocked_until ? Date.parse(usage.blocked_until) : 0

  if (blockedUntil > now || usage.used_count >= usage.auto_limit) {
    if (snapshot) return snapshot.payload
    return []
  }

  const nowISO = iso(new Date(now))
  usage = { ...usage, last_attempt_at: nowISO, updated_at: nowISO }
  await writeUsage(usage)

  try {
    const books = await run()
    await writeSnapshot(providerID, scope, books)
    await writeUsage({
      ...usage,
      used_count: usage.used_count + 1,
      blocked_until: null,
      last_success_at: nowISO,
      last_error_at: null,
      last_error: null,
      updated_at: nowISO,
    })
    return books
  } catch (error) {
    await writeUsage({
      ...usage,
      used_count: usage.used_count + 1,
      blocked_until: iso(new Date(now + providerBackoffMS(providerID, errorMessage(error)))),
      last_error_at: nowISO,
      last_error: errorMessage(error).slice(0, 500),
      updated_at: nowISO,
    })
    if (snapshot) return snapshot.payload
    return []
  }
}

function providerBackoffMS(providerID: ProviderID, message: string) {
  const lower = message.toLowerCase()
  if (lower.includes("aborted") || lower.includes("timeout")) return 5 * minuteMS
  if (lower.includes("http 404") || lower.includes("invalid json")) return 30 * minuteMS
  if (lower.includes("429") || lower.includes("quota") || lower.includes("limit")) {
    return providerBudgets[providerID].quotaBackoffMS
  }
  return Math.min(providerBudgets[providerID].quotaBackoffMS, 60 * minuteMS)
}

async function fetchRapidJSON<T>(url: string, host: string, apiKey: string, providerName: string): Promise<T> {
  if (!apiKey) throw new Error(`${providerName} RapidAPI key is not configured.`)

  const response = await fetchWithTimeout(url, {
    headers: {
      "x-rapidapi-key": apiKey,
      "x-rapidapi-host": host,
      "content-type": "application/json",
    },
  })
  const text = await response.text()
  if (!response.ok) throw new Error(`${providerName}: HTTP ${response.status} ${text.slice(0, 160)}`)

  try {
    return JSON.parse(text) as T
  } catch {
    throw new Error(`${providerName}: invalid JSON response`)
  }
}

async function fetchWithTimeout(url: string, init: RequestInit = {}, timeoutMS = 9_000) {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), timeoutMS)
  try {
    return await fetch(url, { ...init, signal: controller.signal })
  } finally {
    clearTimeout(timeout)
  }
}

function dedupe(books: BookItem[]) {
  const seen = new Set<string>()
  return books.filter((book) => {
    const key = `${book.title}|${book.authors.join(",")}`.toLowerCase().replace(/\s+/g, " ").trim()
    if (seen.has(key)) return false
    seen.add(key)
    return true
  })
}

function interleaveBySource(groups: BookItem[][]) {
  const buckets = new Map<string, BookItem[]>()
  for (const book of dedupe(groups.flat())) {
    const source = book.source || "Unknown"
    buckets.set(source, [...(buckets.get(source) ?? []), book])
  }

  const orderedSources = Array.from(buckets.keys()).sort((a, b) => {
    const left = sourcePriority(a)
    const right = sourcePriority(b)
    return left === right ? a.localeCompare(b) : left - right
  })

  const output: BookItem[] = []
  let added = true
  while (added) {
    added = false
    for (const source of orderedSources) {
      const bucket = buckets.get(source) ?? []
      const book = bucket.shift()
      if (book) {
        output.push(book)
        added = true
      }
    }
  }

  return output
}

function sourcePriority(source: string) {
  switch (source) {
    case "Google Books": return 0
    case "Realtime Books": return 1
    case "Amazon Books": return 2
    case "Gutendex": return 3
    case "Open Library": return 4
    case "HAPI Books": return 5
    case "Anna's Archive": return 6
    case "Superhero Search": return 7
    default: return 8
  }
}

async function fetchGoogleBooks(query: string, genre: string) {
  const subject = genre === "All" ? "" : `+subject:${genre}`
  const apiKey = env("GOOGLE_BOOKS_API_KEY")
  const pages = await Promise.all([0, 40].map(async (startIndex) => {
    const url = new URL("https://www.googleapis.com/books/v1/volumes")
    url.searchParams.set("q", `${query}${subject}`)
    url.searchParams.set("maxResults", "40")
    url.searchParams.set("startIndex", String(startIndex))
    url.searchParams.set("printType", "books")
    if (apiKey) url.searchParams.set("key", apiKey)
    const payload = await fetchJSON<{ items?: Record<string, unknown>[] }>(url.toString())
    return (payload.items ?? []).map((item, index) => googleBookToItem(item, index + startIndex)).filter(Boolean) as BookItem[]
  }))
  return pages.flat()
}

function googleBookToItem(item: Record<string, unknown>, index: number): BookItem | null {
  const info = objectFrom(item.volumeInfo)
  if (!info) return null
  const title = stringFrom(info.title)
  if (!title) return null
  const imageLinks = objectFrom(info.imageLinks)
  const accessInfo = objectFrom(item.accessInfo)
  const epub = objectFrom(accessInfo?.epub)
  const categories = arrayFrom(info.categories).map(String)
  const authors = arrayFrom(info.authors).map(String)
  const id = stringFrom(item.id) || `google-${index}`
  const cover = stringFrom(imageLinks?.thumbnail)?.replace("http://", "https://") || null
  const download = stringFrom(epub?.downloadLink)

  return {
    id: `google-${slug(id)}`,
    title,
    authors,
    genre: categories[0] ?? "General",
    description: cleanHTML(info.description) || "No summary available yet.",
    coverURL: cover,
    rating: numberFrom(info.averageRating),
    pageCount: numberFrom(info.pageCount),
    publishedYear: String(stringFrom(info.publishedDate)).slice(0, 4),
    publisher: stringFrom(info.publisher) || "Unknown publisher",
    source: "Google Books",
    availability: download ? "Readable" : "Preview",
    previewURL: stringFrom(info.previewLink) || null,
    downloadURL: download || null,
  }
}

async function fetchOpenLibrary(query: string, genre: string) {
  const url = new URL("https://openlibrary.org/search.json")
  url.searchParams.set("q", genre === "All" ? query : `${query} ${genre}`)
  url.searchParams.set("limit", "50")
  const payload = await fetchJSON<{ docs?: Record<string, unknown>[] }>(url.toString())
  return (payload.docs ?? []).map((item, index) => openLibraryToItem(item, index)).filter(Boolean) as BookItem[]
}

function openLibraryToItem(item: Record<string, unknown>, index: number): BookItem | null {
  const title = stringFrom(item.title)
  if (!title) return null
  const authors = arrayFrom(item.author_name).map(String)
  const subjects = arrayFrom(item.subject).map(String)
  const publishers = arrayFrom(item.publisher).map(String)
  const key = stringFrom(item.key) || `openlibrary-${index}`
  const coverID = numberFrom(item.cover_i)

  return {
    id: `openlibrary-${slug(key)}`,
    title,
    authors,
    genre: subjects[0] ?? "General",
    description: "Open Library reference with editions, metadata, and catalog details.",
    coverURL: coverID ? `https://covers.openlibrary.org/b/id/${coverID}-L.jpg` : null,
    rating: numberFrom(item.ratings_average),
    pageCount: numberFrom(item.number_of_pages_median),
    publishedYear: numberFrom(item.first_publish_year)?.toString() ?? "",
    publisher: publishers[0] ?? "Open Library",
    source: "Open Library",
    availability: "Reference",
    previewURL: `https://openlibrary.org${key}`,
    downloadURL: null,
  }
}

async function fetchGutendex(query: string, genre: string) {
  const url = new URL("https://gutendex.com/books")
  url.searchParams.set("search", genre === "All" ? query : `${query} ${genre}`)
  const payload = await fetchJSON<{ results?: Record<string, unknown>[] }>(url.toString())
  return (payload.results ?? []).map((item, index) => gutendexToItem(item, index)).filter(Boolean) as BookItem[]
}

function gutendexToItem(item: Record<string, unknown>, index: number): BookItem | null {
  const title = stringFrom(item.title)
  if (!title) return null
  const formats = objectFrom(item.formats) ?? {}
  const authors = arrayFrom(item.authors)
    .map((author) => stringFrom(objectFrom(author)?.name))
    .filter(Boolean)
  const subjects = arrayFrom(item.subjects).map(String)
  const id = numberFrom(item.id) ?? index
  const download = stringFrom(formats["application/epub+zip"])
    || stringFrom(formats["text/html"])
    || stringFrom(formats["text/plain; charset=utf-8"])

  return {
    id: `gutendex-${id}`,
    title,
    authors,
    genre: subjects[0] ?? "Classic",
    description: "Public domain edition with readable and downloadable formats.",
    coverURL: stringFrom(formats["image/jpeg"]) || null,
    rating: null,
    pageCount: null,
    publishedYear: "Public domain",
    publisher: "Project Gutenberg",
    source: "Gutendex",
    availability: download ? "Readable" : "Reference",
    previewURL: stringFrom(formats["text/html"]) || null,
    downloadURL: download || null,
  }
}

async function fetchAmazonBooks(query: string, genre: string) {
  const apiKey = env("AMAZON_BOOKS_RAPIDAPI_KEY") || env("RAPIDAPI_KEY")
  const host = "amazon-books-data-api1.p.rapidapi.com"
  const year = query.match(/\b(1[5-9]\d{2}|20\d{2})\b/)?.[0]
  const searches: Array<{ path: string; params: Record<string, string>; strict: boolean }> = [
    { path: "book_title", params: { book_title: query, limit: "100" }, strict: true },
    ...(year ? [{ path: "year_of_publication", params: { year_of_publication: year, limit: "100" }, strict: false }] : []),
    { path: "books", params: { limit: "150" }, strict: false },
  ]

  const groups: BookItem[][] = []
  const errors: string[] = []
  for (const search of searches) {
    try {
      const url = rapidURL(`https://${host}/api/${search.path}`, search.params)
      const payload = await fetchRapidJSON<Record<string, unknown>>(url, host, apiKey, "Amazon Books")
      const books = recordsFromPayload(payload)
        .map((record, index) => genericBookToItem(record, index, "amazon-books", "Amazon Books", query, genre, search.strict))
        .filter(Boolean) as BookItem[]
      if (books.length) groups.push(books)
    } catch (error) {
      errors.push(errorMessage(error))
    }
  }
  if (!groups.length && errors.length) throw new Error(errors.join(" | "))
  return groups.flat()
}

async function fetchRealtimeBooks(query: string, genre: string) {
  const apiKey = env("REALTIME_BOOKS_RAPIDAPI_KEY") || env("REAL_TIME_BOOKS_RAPIDAPI_KEY") || env("RAPIDAPI_KEY")
  const host = "real-time-books-data.p.rapidapi.com"
  const pages = await Promise.all([1, 2, 3].map(async (page) => {
    try {
      const url = rapidURL(`https://${host}/search`, {
        query: genre === "All" ? query : `${query} ${genre}`,
        page: String(page),
        document_type: "any",
        view_type: "any",
        country: "us",
        language: "en",
      })
      const payload = await fetchRapidJSON<Record<string, unknown>>(url, host, apiKey, "Realtime Books")
      return recordsFromPayload(payload)
        .map((record, index) => genericBookToItem(record, index + (page - 1) * 20, "realtime-books", "Realtime Books", query, genre, false))
        .filter(Boolean) as BookItem[]
    } catch {
      return []
    }
  }))
  return pages.flat()
}

async function fetchHAPIBooks(query: string, genre: string) {
  const apiKey = env("HAPI_BOOKS_RAPIDAPI_KEY") || env("RAPIDAPI_KEY")
  const host = "hapi-books.p.rapidapi.com"
  const attempts = [
    rapidURL(`https://${host}/top_authors`, {}),
  ]

  const groups: BookItem[][] = []
  const errors: string[] = []
  for (const url of attempts) {
    try {
      const payload = await fetchRapidJSON<Record<string, unknown>>(url, host, apiKey, "HAPI Books")
      const books = recordsFromPayload(payload)
        .map((record, index) => hapiRecordToItem(record, index, query, genre, false))
        .filter(Boolean) as BookItem[]
      if (books.length) groups.push(books)
    } catch (error) {
      errors.push(errorMessage(error))
    }
  }
  if (!groups.length && errors.length) throw new Error(errors.join(" | "))
  return groups.flat()
}

async function fetchAnnasArchive(query: string, genre: string) {
  const apiKey = env("ANNAS_ARCHIVE_RAPIDAPI_KEY") || env("ANNA_ARCHIVE_RAPIDAPI_KEY") || env("RAPIDAPI_KEY")
  const host = "annas-archive-api.p.rapidapi.com"
  const text = genre === "All" ? query : `${query} ${genre}`
  const attempts = [
    rapidURL(`https://${host}/search`, { query: text, q: text }),
    rapidURL(`https://${host}/search/book`, { query: text, q: text }),
    rapidURL(`https://${host}/searchBook`, { query: text, q: text }),
  ]
  const groups: BookItem[][] = []
  const errors: string[] = []
  for (const url of attempts) {
    try {
      const payload = await fetchRapidJSON<Record<string, unknown>>(url, host, apiKey, "Anna's Archive")
      const books = recordsFromPayload(payload)
        .map((record, index) => annasRecordToItem(record, index, query, genre, false))
        .filter(Boolean) as BookItem[]
      if (books.length) groups.push(books)
    } catch (error) {
      errors.push(errorMessage(error))
    }
  }
  if (!groups.length && errors.length) throw new Error(errors.join(" | "))
  return groups.flat()
}

async function fetchSuperheroBooks(query: string) {
  const genericQueries = new Set(["award winning books", "bestsellers", "fiction", "business", "technology", "all"])
  if (genericQueries.has(query.toLowerCase())) return []
  const apiKey = env("SUPERHERO_BOOKS_RAPIDAPI_KEY") || env("SUPERHERO_RAPIDAPI_KEY") || env("RAPIDAPI_KEY")
  const host = "superhero-search.p.rapidapi.com"
  const url = rapidURL(`https://${host}/api/`, { hero: query })
  const payload = await fetchRapidJSON<Record<string, unknown>>(url, host, apiKey, "Superhero Search")
  const records = recordsFromPayload(payload)
  const direct = superheroRecordToItem(payload, 0, query)
  const books = records
    .map((record, index) => superheroRecordToItem(record, index, query))
    .filter(Boolean) as BookItem[]
  return direct && !books.length ? [direct] : books
}

function genericBookToItem(
  record: Record<string, unknown>,
  index: number,
  idPrefix: string,
  source: string,
  query: string,
  genre: string,
  strictMatch = true,
): BookItem | null {
  const title = firstString(record, [
    "title",
    "book_title",
    "bookTitle",
    "name",
    "book_name",
    "volume_title",
    "document_title",
  ])
  if (!title || (strictMatch && !recordMatches(record, query, genre))) return null

  const authors = firstStringArray(record, [
    "authors",
    "author",
    "book_author",
    "bookAuthor",
    "author_name",
    "creators",
  ])
  const rawID = firstString(record, ["id", "book_id", "bookId", "isbn", "isbn13", "asin", "key", "md5"]) ?? `${title}-${index}`
  const description = firstString(record, [
    "description",
    "summary",
    "synopsis",
    "subtitle",
    "overview",
    "snippet",
    "text",
  ])
  const cover = firstString(record, [
    "cover",
    "cover_url",
    "coverURL",
    "image",
    "image_url",
    "thumbnail",
    "thumbnail_url",
    "book_image",
  ])
  const preview = firstString(record, [
    "url",
    "link",
    "preview",
    "preview_url",
    "previewLink",
    "amazon_url",
    "info_url",
    "canonical_url",
  ])

  return {
    id: `${idPrefix}-${slug(rawID)}`,
    title,
    authors,
    genre: firstString(record, ["genre", "category", "categories", "subject", "subjects"]) ?? (genre === "All" ? "General" : genre),
    description: cleanHTML(description) || `${source} reference with available book metadata.`,
    coverURL: normalizedURL(cover),
    rating: numberFrom(record.rating) ?? numberFrom(record.averageRating) ?? numberFrom(record.average_rating),
    pageCount: numberFrom(record.pageCount) ?? numberFrom(record.pages) ?? numberFrom(record.number_of_pages),
    publishedYear: publishedYearFrom(record),
    publisher: firstString(record, ["publisher", "book_publisher", "publisher_name"]) ?? source,
    source,
    availability: "Reference",
    previewURL: normalizedURL(preview),
    downloadURL: null,
  }
}

function hapiRecordToItem(record: Record<string, unknown>, index: number, query: string, genre: string, strictMatch = true): BookItem | null {
  const generic = genericBookToItem(record, index, "hapi-books", "HAPI Books", query, genre, strictMatch)
  if (generic) return generic

  const author = firstString(record, ["name", "author", "full_name", "author_name"])
  if (!author || (strictMatch && !recordMatches(record, query, genre))) return null
  const rawID = firstString(record, ["id", "author_id", "key"]) ?? `${author}-${index}`
  return {
    id: `hapi-author-${slug(rawID)}`,
    title: `Books by ${author}`,
    authors: [author],
    genre: genre === "All" ? "Author" : genre,
    description: "Popular author profile from HAPI Books. Use this as a discovery prompt for related titles.",
    coverURL: normalizedURL(firstString(record, ["image", "image_url", "photo", "avatar"])),
    rating: numberFrom(record.rating),
    pageCount: null,
    publishedYear: "",
    publisher: "HAPI Books",
    source: "HAPI Books",
    availability: "Reference",
    previewURL: normalizedURL(firstString(record, ["url", "link"])),
    downloadURL: null,
  }
}

function annasRecordToItem(record: Record<string, unknown>, index: number, query: string, genre: string, strictMatch = true): BookItem | null {
  const item = genericBookToItem(record, index, "annas-archive", "Anna's Archive", query, genre, strictMatch)
  if (!item) return null
  const md5 = firstString(record, ["md5", "hash"])
  return {
    ...item,
    availability: "Reference",
    previewURL: item.previewURL ?? (md5 ? `https://annas-archive.org/md5/${md5}` : null),
    downloadURL: null,
  }
}

function superheroRecordToItem(record: Record<string, unknown>, index: number, query: string): BookItem | null {
  const name = firstString(record, ["name", "hero", "title"])
  if (!name || !recordMatches(record, query, "All")) return null
  const biography = objectFrom(record.biography) ?? {}
  const appearance = objectFrom(record.appearance) ?? {}
  const publisher = firstString(biography, ["publisher"]) ?? firstString(record, ["publisher"]) ?? "Superhero Search"
  const fullName = firstString(biography, ["full-name", "fullName"])
  const race = firstString(appearance, ["race"])
  const description = [
    fullName ? `Full name: ${fullName}` : null,
    publisher ? `Publisher: ${publisher}` : null,
    race ? `Profile: ${race}` : null,
  ].filter(Boolean).join(". ")

  return {
    id: `superhero-${slug(firstString(record, ["id"]) ?? `${name}-${index}`)}`,
    title: `${name} reading profile`,
    authors: [publisher],
    genre: "Comics",
    description: description || "Superhero and comics reference profile.",
    coverURL: normalizedURL(firstString(objectFrom(record.image) ?? record, ["url", "image", "image_url"])),
    rating: null,
    pageCount: null,
    publishedYear: "",
    publisher,
    source: "Superhero Search",
    availability: "Reference",
    previewURL: null,
    downloadURL: null,
  }
}

function objectFrom(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : null
}

function arrayFrom(value: unknown): unknown[] {
  return Array.isArray(value) ? value : []
}

function recordsFromPayload(payload: unknown): Record<string, unknown>[] {
  if (Array.isArray(payload)) return payload.flatMap(recordArrayItem)
  const record = objectFrom(payload)
  if (!record) return []

  for (const key of ["data", "results", "items", "books", "documents", "docs", "records", "response", "authors", "heroes", "villains"]) {
    const nested = record[key]
    if (Array.isArray(nested)) return nested.flatMap(recordArrayItem)
    const nestedRecord = objectFrom(nested)
    if (nestedRecord) {
      const records = recordsFromPayload(nestedRecord)
      if (records.length) return records
    }
  }

  return [record]
}

function recordArrayItem(value: unknown): Record<string, unknown>[] {
  const record = objectFrom(value)
  return record ? [record] : []
}

function stringFrom(value: unknown): string {
  if (typeof value === "string") return value.trim()
  if (typeof value === "number" && Number.isFinite(value)) return String(value)
  return ""
}

function numberFrom(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value
  if (typeof value === "string") {
    const parsed = Number(value.replace(/[^0-9.-]+/g, ""))
    return Number.isFinite(parsed) ? parsed : null
  }
  return null
}

function slug(value: string) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")
}

function rapidURL(baseURL: string, params: Record<string, string>) {
  const url = new URL(baseURL)
  for (const [key, value] of Object.entries(params)) {
    if (value) url.searchParams.set(key, value)
  }
  return url.toString()
}

function normalizedURL(value: string | null | undefined) {
  if (!value) return null
  if (value.startsWith("//")) return `https:${value}`
  if (value.startsWith("http://")) return value.replace("http://", "https://")
  if (value.startsWith("https://")) return value
  return null
}

function firstString(record: Record<string, unknown>, keys: string[]): string | null {
  for (const key of keys) {
    const value = record[key]
    const direct = stringFrom(value)
    if (direct) return direct
    if (Array.isArray(value)) {
      const values: string[] = value.flatMap((item: unknown): string[] => {
        const text = stringFrom(item)
        if (text) return [text]
        const nested = objectFrom(item)
        const nestedText = nested ? firstString(nested, ["name", "title", "text", "value"]) : null
        return nestedText ? [nestedText] : []
      })
      if (values.length) return values.join(", ")
    }
    const nested = objectFrom(value)
    if (nested) {
      const nestedText = firstString(nested, ["name", "title", "text", "value", "url", "href"])
      if (nestedText) return nestedText
    }
  }
  return null
}

function firstStringArray(record: Record<string, unknown>, keys: string[]): string[] {
  const value = firstString(record, keys)
  if (!value) return []
  return value.split(/,\s*|;\s*|\s+and\s+/).map((item: string) => item.trim()).filter(Boolean)
}

function publishedYearFrom(record: Record<string, unknown>) {
  const value = firstString(record, [
    "publishedYear",
    "published_year",
    "year",
    "year_of_publication",
    "publishedDate",
    "published_date",
    "publication_date",
    "date",
  ])
  const match = value?.match(/\d{4}/)
  return match?.[0] ?? ""
}

function recordMatches(record: Record<string, unknown>, query: string, genre: string) {
  const haystack = JSON.stringify(record).toLowerCase()
  const queryTokens = query.toLowerCase().split(/\s+/).filter((token) => token.length > 2)
  const genreTokens = genre === "All" ? [] : genre.toLowerCase().split(/\s+/).filter((token) => token.length > 2)
  const queryMatches = !queryTokens.length || queryTokens.some((token) => haystack.includes(token))
  const genreMatches = !genreTokens.length || genreTokens.some((token) => haystack.includes(token))
  return queryMatches || genreMatches
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })

  const url = new URL(request.url)
  const query = url.searchParams.get("q")?.trim() || "award winning books"
  const genre = url.searchParams.get("genre")?.trim() || "All"
  const debugProviders = url.searchParams.get("debugProviders") === "1"
  const scope = slug(`${query}-${genre}`) || "default"
  const groups: BookItem[][] = []

  const providers = [
    { id: "google" as const, run: () => fetchGoogleBooks(query, genre) },
    { id: "openlibrary" as const, run: () => fetchOpenLibrary(query, genre) },
    { id: "gutendex" as const, run: () => fetchGutendex(query, genre) },
    { id: "realtimebooks" as const, run: () => fetchRealtimeBooks(query, genre) },
    { id: "amazonbooks" as const, run: () => fetchAmazonBooks(query, genre) },
    { id: "hapibooks" as const, run: () => fetchHAPIBooks(query, genre) },
    { id: "annasarchive" as const, run: () => fetchAnnasArchive(query, genre) },
    { id: "superhero" as const, run: () => fetchSuperheroBooks(query) },
  ]

  const results: ProviderRunResult[] = await Promise.all(providers.map(async (provider) => {
    try {
      const books = debugProviders ? await provider.run() : await runWithBudget(provider.id, scope, provider.run)
      return { id: provider.id, books, error: null }
    } catch (error) {
      return { id: provider.id, books: [] as BookItem[], error: errorMessage(error) }
    }
  }))

  for (const result of results) {
    if (result.books.length) groups.push(result.books)
  }

  const books = interleaveBySource(groups).slice(0, 96)
  if (!books.length) {
    return json(200, {
      generatedAt: new Date().toISOString(),
      source: "fixture",
      message: "Showing sample books while the library refreshes.",
      providerDiagnostics: debugProviders ? providerDiagnostics(results) : [],
      books: fixtureBooks,
    })
  }

  return json(200, {
    generatedAt: new Date().toISOString(),
    source: "live",
    message: null,
    providerDiagnostics: debugProviders ? providerDiagnostics(results) : [],
    books,
  })
})

function providerDiagnostics(results: ProviderRunResult[]) {
  return results.map((result) => ({
    provider: result.id,
    count: result.books.length,
    sources: sourceCounts(result.books),
    error: result.error,
  }))
}

function sourceCounts(books: BookItem[]) {
  const counts: Record<string, number> = {}
  for (const book of books) counts[book.source] = (counts[book.source] ?? 0) + 1
  return counts
}

const fixtureBooks: BookItem[] = [
  {
    id: "fixture-moon-library",
    title: "The Midnight Library",
    authors: ["Matt Haig"],
    genre: "Fiction",
    description: "A reflective novel about choices, regret, and alternate lives.",
    coverURL: null,
    rating: 4.1,
    pageCount: 304,
    publishedYear: "2020",
    publisher: "Canongate",
    source: "Fixture",
    availability: "Preview",
    previewURL: null,
    downloadURL: null,
  },
]
