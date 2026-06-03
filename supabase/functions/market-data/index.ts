const corsHeaders = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
}

type BudgetPeriod = "hour" | "day" | "month"
type SnapshotSource = "live" | "cached" | "stale"

type MarketSymbol = {
  symbol: string
  ticker: string
  name: string
}

type MarketSnapshot = {
  id: string
  ticker: string
  name: string
  assetType: "equity" | "crypto"
  detailID: string | null
  priceText: string
  changeText: string
  isPositive: boolean
  updatedAt: string | null
  price: number | null
  change: number | null
  changePercent: number | null
  open: number | null
  high: number | null
  low: number | null
  previousClose: number | null
  volume: number | null
  currency: string | null
  exchange: string | null
  rank: number | null
  marketCap: number | null
  marketCount: number | null
  dailyVolume: number | null
  iconURL: string | null
}

type MarketChartPoint = {
  id: string
  date: string
  open: number | null
  high: number | null
  low: number | null
  close: number
  volume: number | null
}

type StockFundamentals = {
  name: string | null
  description: string | null
  sector: string | null
  industry: string | null
  country: string | null
  marketCapitalization: number | null
  peRatio: number | null
  pegRatio: number | null
  dividendYield: number | null
  eps: number | null
  beta: number | null
  fiftyTwoWeekHigh: number | null
  fiftyTwoWeekLow: number | null
  profitMargin: number | null
}

type MarketNewsItem = {
  id: string
  title: string
  publisher: string | null
  url: string | null
  publishedAt: string | null
  summary: string | null
  imageURL: string | null
}

type TechnicalIndicator = {
  id: string
  name: string
  value: number | null
  signal: string | null
  updatedAt: string | null
}

type AnalystStats = {
  recommendation: string | null
  targetMeanPrice: number | null
  targetHighPrice: number | null
  targetLowPrice: number | null
  numberOfAnalystOpinions: number | null
  revenueGrowth: number | null
  grossMargins: number | null
  operatingMargins: number | null
  returnOnEquity: number | null
  forwardPE: number | null
  trailingPE: number | null
  priceToBook: number | null
  enterpriseToRevenue: number | null
  enterpriseToEbitda: number | null
  website: string | null
  fullTimeEmployees: number | null
}

type MarketDetailResponse = {
  generatedAt: string
  source: SnapshotSource
  provider: string
  cacheHit: boolean
  stale: boolean
  updatedAt: string | null
  expiresAt: string | null
  message: string | null
  snapshot: MarketSnapshot
  chart: MarketChartPoint[]
  fundamentals?: StockFundamentals | null
  news?: MarketNewsItem[]
  technicalIndicators?: TechnicalIndicator[]
  analystStats?: AnalystStats | null
}

type MarketDataResponse = {
  generatedAt: string
  source: SnapshotSource
  provider: string | null
  cacheHit: boolean
  stale: boolean
  updatedAt: string | null
  expiresAt: string | null
  message: string | null
  snapshots: MarketSnapshot[]
}

type CryptoStats = {
  totalMarketCap: number | null
  totalVolume24h: number | null
  btcDominance: number | null
  totalCoins: number | null
  totalMarkets: number | null
  totalExchanges: number | null
}

type CryptoStatsResponse = {
  generatedAt: string
  source: SnapshotSource
  provider: string
  cacheHit: boolean
  stale: boolean
  updatedAt: string | null
  expiresAt: string | null
  message: string | null
  stats: CryptoStats
}

type CryptoMovers = {
  gainers: MarketSnapshot[]
  losers: MarketSnapshot[]
}

type CryptoMoversResponse = {
  generatedAt: string
  source: SnapshotSource
  provider: string
  cacheHit: boolean
  stale: boolean
  updatedAt: string | null
  expiresAt: string | null
  message: string | null
  gainers: MarketSnapshot[]
  losers: MarketSnapshot[]
}

type ProviderBudgetConfig = {
  period: BudgetPeriod
  autoLimit: number
  minRefreshMS: number
  quotaBackoffMS: number
  snapshotTTLMS: number
  manualOnly?: boolean
}

type ProviderUsageRecord = {
  provider_id: string
  period: BudgetPeriod
  window_started_at: string
  window_ends_at: string
  auto_limit: number
  used_count: number
  blocked_until: string | null
  manual_only: boolean
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

type ProviderResult = {
  providerID: string
  providerName: string
  source: SnapshotSource
  snapshotRecord: ProviderSnapshotRecord<MarketSnapshot[]> | null
  snapshots: MarketSnapshot[]
}

type ProviderSource = {
  id: string
  name: string
  configured: () => boolean
  run: (symbols: MarketSymbol[]) => Promise<MarketSnapshot[]>
}

type ProviderStatus = {
  providerID: string
  providerName: string
  configured: boolean
  period: BudgetPeriod
  autoLimit: number
  usedCount: number
  remaining: number
  manualOnly: boolean
  blocked: boolean
  blockedUntil: string | null
  windowStartedAt: string
  windowEndsAt: string
  lastAttemptAt: string | null
  lastSuccessAt: string | null
  lastErrorAt: string | null
  lastError: string | null
  caches: {
    scope: string
    generatedAt: string
    expiresAt: string
    stale: boolean
  }[]
}

type ProviderStatusResponse = {
  generatedAt: string
  providers: ProviderStatus[]
}

type CryptoCoin = {
  uuid: string
  symbol: string
  name: string
}

const minuteMS = 60 * 1000
const dayMS = 24 * 60 * 60 * 1000
const scope = "home"

const symbols: MarketSymbol[] = [
  { symbol: "AAPL", ticker: "AAPL", name: "Apple" },
  { symbol: "NVDA", ticker: "NVDA", name: "Nvidia" },
  { symbol: "MSFT", ticker: "MSFT", name: "Microsoft" },
  { symbol: "TSLA", ticker: "TSLA", name: "Tesla" },
  { symbol: "AMZN", ticker: "AMZN", name: "Amazon" },
  { symbol: "META", ticker: "META", name: "Meta" },
  { symbol: "GOOGL", ticker: "GOOGL", name: "Alphabet" },
  { symbol: "AMD", ticker: "AMD", name: "AMD" },
  { symbol: "NFLX", ticker: "NFLX", name: "Netflix" },
  { symbol: "TSM", ticker: "TSM", name: "TSMC" },
  { symbol: "ARM", ticker: "ARM", name: "Arm" },
  { symbol: "SPY", ticker: "SPY", name: "S&P 500 ETF" },
  { symbol: "QQQ", ticker: "QQQ", name: "Nasdaq 100 ETF" },
  { symbol: "COIN", ticker: "COIN", name: "Coinbase" },
  { symbol: "MSTR", ticker: "MSTR", name: "MicroStrategy" },
]

const cryptoCoins: CryptoCoin[] = [
  { uuid: "Qwsogvtv82FCd", symbol: "BTC", name: "Bitcoin" },
  { uuid: "razxDUgYGNAdQ", symbol: "ETH", name: "Ethereum" },
  { uuid: "aKzUVe4Hh_CON", symbol: "USDT", name: "Tether" },
  { uuid: "WcwrkfNI4FUAe", symbol: "BNB", name: "BNB" },
  { uuid: "zNZHO_Sjf", symbol: "SOL", name: "Solana" },
  { uuid: "-l8Mn2pVlRs-p", symbol: "XRP", name: "XRP" },
  { uuid: "qzawljRxB5bYu", symbol: "USDC", name: "USDC" },
  { uuid: "a91GCGd_u96cF", symbol: "DOGE", name: "Dogecoin" },
]

const providerBudgets: Record<string, ProviderBudgetConfig> = {
  "twelvedata": {
    period: "day",
    autoLimit: 20,
    minRefreshMS: 15 * minuteMS,
    quotaBackoffMS: 6 * 60 * minuteMS,
    snapshotTTLMS: 2 * dayMS,
  },
  "finnhub": {
    period: "day",
    autoLimit: 120,
    minRefreshMS: 10 * minuteMS,
    quotaBackoffMS: 6 * 60 * minuteMS,
    snapshotTTLMS: 2 * dayMS,
  },
  "alphavantage": {
    period: "day",
    autoLimit: 8,
    minRefreshMS: 60 * minuteMS,
    quotaBackoffMS: 12 * 60 * minuteMS,
    snapshotTTLMS: 3 * dayMS,
  },
  "coinranking": {
    period: "month",
    autoLimit: 3000,
    minRefreshMS: 10 * minuteMS,
    quotaBackoffMS: 60 * minuteMS,
    snapshotTTLMS: dayMS,
  },
  "yahoofinance": {
    period: "month",
    autoLimit: 45,
    minRefreshMS: 12 * 60 * minuteMS,
    quotaBackoffMS: 12 * 60 * minuteMS,
    snapshotTTLMS: 7 * dayMS,
  },
}

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders })
}

function iso(date = new Date()) {
  return date.toISOString().replace(/\.\d{3}Z$/, "Z")
}

function providerErrorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error)
}

function env(name: string) {
  return Deno.env.get(name)?.trim() ?? ""
}

function budget(providerID: string) {
  return providerBudgets[providerID] ?? {
    period: "day" as BudgetPeriod,
    autoLimit: 0,
    minRefreshMS: dayMS,
    quotaBackoffMS: dayMS,
    snapshotTTLMS: dayMS,
  }
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
  if (!credentials) {
    throw new Error("Supabase service role secret is not configured for market provider budgeting.")
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
    throw new Error(`Supabase market store: HTTP ${response.status} ${body.slice(0, 160)}`)
  }

  if (response.status === 204) return undefined as T
  const text = await response.text()
  return (text ? JSON.parse(text) : undefined) as T
}

function usageRecord(providerID: string, config: ProviderBudgetConfig, now: number): ProviderUsageRecord {
  const window = periodWindow(config.period, now)
  return {
    provider_id: providerID,
    period: config.period,
    window_started_at: window.startedAt,
    window_ends_at: window.endsAt,
    auto_limit: config.autoLimit,
    used_count: 0,
    blocked_until: null,
    manual_only: Boolean(config.manualOnly),
    last_attempt_at: null,
    last_success_at: null,
    last_error_at: null,
    last_error: null,
    updated_at: iso(new Date(now)),
  }
}

function normalizeUsage(providerID: string, config: ProviderBudgetConfig, record: ProviderUsageRecord | null, now: number) {
  const current = usageRecord(providerID, config, now)
  if (!record) return current
  if (record.period !== config.period || Date.parse(record.window_ends_at) <= now) return current
  return {
    ...record,
    auto_limit: config.autoLimit,
    manual_only: Boolean(config.manualOnly),
  }
}

async function readUsage(providerID: string) {
  if (!supabaseRESTCredentials()) return null
  const records = await supabaseREST<ProviderUsageRecord[]>(
    `market_provider_usage?provider_id=eq.${encodeURIComponent(providerID)}&select=*`
  )
  return records[0] ?? null
}

async function writeUsage(record: ProviderUsageRecord) {
  if (!supabaseRESTCredentials()) return
  await supabaseREST<void>("market_provider_usage?on_conflict=provider_id", {
    method: "POST",
    headers: { "Prefer": "resolution=merge-duplicates,return=minimal" },
    body: JSON.stringify(record),
  })
}

async function readProviderSnapshotRecord<T>(providerID: string, snapshotScope: string) {
  if (!supabaseRESTCredentials()) return null
  const records = await supabaseREST<ProviderSnapshotRecord<T>[]>(
    `market_provider_snapshots?provider_id=eq.${encodeURIComponent(providerID)}&scope=eq.${encodeURIComponent(snapshotScope)}&select=*`
  )
  return records[0] ?? null
}

async function readProviderSnapshotSummaries(providerID: string) {
  if (!supabaseRESTCredentials()) return [] as ProviderStatus["caches"]
  const records = await supabaseREST<Array<Pick<ProviderSnapshotRecord<unknown>, "scope" | "generated_at" | "expires_at">>>(
    `market_provider_snapshots?provider_id=eq.${encodeURIComponent(providerID)}&select=scope,generated_at,expires_at&order=generated_at.desc&limit=25`
  )
  const now = Date.now()
  return records.map((record) => ({
    scope: record.scope,
    generatedAt: record.generated_at,
    expiresAt: record.expires_at,
    stale: Date.parse(record.expires_at) <= now,
  }))
}

async function readSnapshot(providerID: string) {
  return await readProviderSnapshotRecord<MarketSnapshot[]>(providerID, scope)
}

async function writeProviderSnapshot<T>(providerID: string, snapshotScope: string, payload: T, ttlMS: number) {
  if (!supabaseRESTCredentials()) return
  const now = Date.now()
  await supabaseREST<void>("market_provider_snapshots?on_conflict=provider_id%2Cscope", {
    method: "POST",
    headers: { "Prefer": "resolution=merge-duplicates,return=minimal" },
    body: JSON.stringify({
      provider_id: providerID,
      scope: snapshotScope,
      payload,
      generated_at: iso(new Date(now)),
      expires_at: iso(new Date(now + ttlMS)),
      updated_at: iso(new Date(now)),
    }),
  })
}

async function writeSnapshot(providerID: string, payload: MarketSnapshot[], ttlMS: number) {
  await writeProviderSnapshot(providerID, scope, payload, ttlMS)
}

function staleResult(source: ProviderSource, snapshot: ProviderSnapshotRecord<MarketSnapshot[]>): ProviderResult {
  return {
    providerID: source.id,
    providerName: source.name,
    source: Date.parse(snapshot.expires_at) > Date.now() ? "cached" : "stale",
    snapshotRecord: snapshot,
    snapshots: snapshot.payload,
  }
}

async function runProvider(source: ProviderSource, force: boolean): Promise<ProviderResult> {
  const config = budget(source.id)
  const persistentBudgetEnabled = Boolean(supabaseRESTCredentials())

  if (!persistentBudgetEnabled) {
    const snapshots = await source.run(symbols)
    return { providerID: source.id, providerName: source.name, source: "live", snapshotRecord: null, snapshots }
  }

  const now = Date.now()
  let usage = normalizeUsage(source.id, config, await readUsage(source.id), now)
  const snapshot = await readSnapshot(source.id)
  const snapshotGeneratedAt = snapshot ? Date.parse(snapshot.generated_at) : 0

  if (!force && snapshot && snapshotGeneratedAt > 0 && now - snapshotGeneratedAt < config.minRefreshMS) {
    return staleResult(source, snapshot)
  }

  if (usage.manual_only) {
    if (snapshot) return staleResult(source, snapshot)
    throw new Error(`${source.name}: automatic provider calls are disabled to protect quota.`)
  }

  const blockedUntil = usage.blocked_until ? Date.parse(usage.blocked_until) : 0
  if (blockedUntil > now) {
    if (snapshot) return staleResult(source, snapshot)
    throw new Error(`${source.name}: paused until ${iso(new Date(blockedUntil))}.`)
  }

  if (usage.used_count >= usage.auto_limit) {
    if (snapshot) return staleResult(source, snapshot)
    throw new Error(`${source.name}: automatic ${usage.period} quota is exhausted.`)
  }

  const nowISO = iso(new Date(now))
  usage = { ...usage, last_attempt_at: nowISO, updated_at: nowISO }
  await writeUsage(usage)

  try {
    const snapshots = await source.run(symbols)
    await writeSnapshot(source.id, snapshots, config.snapshotTTLMS)
    await writeUsage({
      ...usage,
      used_count: usage.used_count + 1,
      blocked_until: null,
      last_success_at: nowISO,
      last_error_at: null,
      last_error: null,
      updated_at: nowISO,
    })
    return { providerID: source.id, providerName: source.name, source: "live", snapshotRecord: null, snapshots }
  } catch (error) {
    const message = providerErrorMessage(error)
    await writeUsage({
      ...usage,
      used_count: usage.used_count + 1,
      blocked_until: iso(new Date(now + config.quotaBackoffMS)),
      last_error_at: nowISO,
      last_error: message.slice(0, 500),
      updated_at: nowISO,
    })
    if (snapshot) return staleResult(source, snapshot)
    throw error
  }
}

async function runProviderTask<T>(
  providerID: string,
  taskScope: string,
  run: () => Promise<T>
): Promise<T> {
  const config = budget(providerID)
  const persistentBudgetEnabled = Boolean(supabaseRESTCredentials())

  if (!persistentBudgetEnabled) return await run()

  const now = Date.now()
  let usage = normalizeUsage(providerID, config, await readUsage(providerID), now)
  const snapshot = await readProviderSnapshotRecord<T>(providerID, taskScope)
  const snapshotGeneratedAt = snapshot ? Date.parse(snapshot.generated_at) : 0

  if (snapshot && snapshotGeneratedAt > 0 && now - snapshotGeneratedAt < config.minRefreshMS) {
    return snapshot.payload
  }

  const blockedUntil = usage.blocked_until ? Date.parse(usage.blocked_until) : 0
  if (blockedUntil > now) {
    if (snapshot) return snapshot.payload
    throw new Error(`${providerID} is paused until ${iso(new Date(blockedUntil))}.`)
  }

  if (usage.used_count >= usage.auto_limit) {
    if (snapshot) return snapshot.payload
    throw new Error(`${providerID} automatic ${usage.period} quota is exhausted.`)
  }

  const nowISO = iso(new Date(now))
  usage = { ...usage, last_attempt_at: nowISO, updated_at: nowISO }
  await writeUsage(usage)

  try {
    const value = await run()
    await writeProviderSnapshot(providerID, taskScope, value, config.snapshotTTLMS)
    await writeUsage({
      ...usage,
      used_count: usage.used_count + 1,
      blocked_until: null,
      last_success_at: nowISO,
      last_error_at: null,
      last_error: null,
      updated_at: nowISO,
    })
    return value
  } catch (error) {
    const message = providerErrorMessage(error)
    await writeUsage({
      ...usage,
      used_count: usage.used_count + 1,
      blocked_until: iso(new Date(now + config.quotaBackoffMS)),
      last_error_at: nowISO,
      last_error: message.slice(0, 500),
      updated_at: nowISO,
    })
    if (snapshot) return snapshot.payload
    throw error
  }
}

function priceText(price: number) {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: 2,
  }).format(price)
}

function changeText(change: number, percent: number | null) {
  const sign = change >= 0 ? "+" : ""
  const base = `${sign}${change.toFixed(2)}`
  return percent === null ? base : `${base} (${sign}${percent.toFixed(2)}%)`
}

function numberFrom(value: unknown) {
  if (typeof value === "number" && Number.isFinite(value)) return value
  if (typeof value === "string") {
    const parsed = Number.parseFloat(value.replace("%", ""))
    return Number.isFinite(parsed) ? parsed : null
  }
  return null
}

async function fetchJSON(url: string, provider: string) {
  const response = await fetch(url)
  const text = await response.text()
  if (!response.ok) throw new Error(`${provider}: HTTP ${response.status} ${text.slice(0, 160)}`)
  try {
    return JSON.parse(text)
  } catch {
    throw new Error(`${provider}: invalid JSON response`)
  }
}

async function fetchTwelveData(symbolSet: MarketSymbol[]) {
  const apiKey = env("TWELVEDATA_API_KEY")
  if (!apiKey) throw new Error("Twelve Data key is not configured.")

  const allowedSymbols = symbolSet.slice(0, 6)
  const symbolQuery = allowedSymbols.map((symbol) => symbol.symbol).join(",")
  const url = `https://api.twelvedata.com/quote?symbol=${encodeURIComponent(symbolQuery)}&apikey=${encodeURIComponent(apiKey)}`
  const payload = await fetchJSON(url, "Twelve Data") as Record<string, unknown>
  if (String(payload.status ?? "").toLowerCase() === "error") {
    throw new Error(`Twelve Data: ${String(payload.message ?? "provider error")}`)
  }

  const results = allowedSymbols.flatMap((symbol) => {
    const quote = asQuoteRecord(payload, symbol.symbol)
    if (!quote) return []
    const snapshot = twelveDataQuoteToSnapshot(symbol, quote)
    return snapshot ? [snapshot] : []
  })

  if (!results.length) throw new Error("Twelve Data: no usable quotes returned.")
  return results
}

function asQuoteRecord(payload: Record<string, unknown>, symbol: string) {
  if (typeof payload.symbol === "string") return payload
  const record = payload[symbol]
  return record && typeof record === "object" && !Array.isArray(record)
    ? record as Record<string, unknown>
    : null
}

function twelveDataQuoteToSnapshot(symbol: MarketSymbol, payload: Record<string, unknown>) {
  const price = numberFrom(payload.close)
  const change = numberFrom(payload.change)
  if (price === null || change === null) return null
  const percent = numberFrom(payload.percent_change)
  const timestamp = numberFrom(payload.timestamp)
  return toSnapshot(
    symbol,
    price,
    change,
    percent,
    timestamp ? new Date(timestamp * 1000).toISOString() : null,
    {
      open: numberFrom(payload.open),
      high: numberFrom(payload.high),
      low: numberFrom(payload.low),
      previousClose: numberFrom(payload.previous_close),
      volume: numberFrom(payload.volume),
      currency: stringFrom(payload.currency),
      exchange: stringFrom(payload.exchange),
    }
  )
}

async function fetchFinnhub(symbolSet: MarketSymbol[]) {
  const apiKey = env("FINNHUB_API_KEY")
  if (!apiKey) throw new Error("Finnhub key is not configured.")

  const results = await Promise.all(symbolSet.map(async (symbol) => {
    const url = `https://finnhub.io/api/v1/quote?symbol=${encodeURIComponent(symbol.symbol)}&token=${encodeURIComponent(apiKey)}`
    const payload = await fetchJSON(url, "Finnhub") as Record<string, unknown>
    const price = numberFrom(payload.c)
    const change = numberFrom(payload.d)
    if (price === null || change === null || (price === 0 && change === 0 && numberFrom(payload.t) === 0)) {
      throw new Error(`Finnhub: missing quote for ${symbol.symbol}`)
    }
    const timestamp = numberFrom(payload.t)
    return toSnapshot(symbol, price, change, numberFrom(payload.dp), timestamp ? new Date(timestamp * 1000).toISOString() : null)
  }))

  return results
}

async function fetchAlphaVantage(symbolSet: MarketSymbol[]) {
  const apiKey = env("ALPHAVANTAGE_API_KEY")
  if (!apiKey) throw new Error("Alpha Vantage key is not configured.")

  const results = await Promise.all(symbolSet.slice(0, 5).map(async (symbol) => {
    const url = `https://www.alphavantage.co/query?function=GLOBAL_QUOTE&symbol=${encodeURIComponent(symbol.symbol)}&apikey=${encodeURIComponent(apiKey)}`
    const payload = await fetchJSON(url, "Alpha Vantage") as Record<string, unknown>
    if (payload.Note || payload.Information || payload["Error Message"]) {
      throw new Error(`Alpha Vantage: ${String(payload.Note ?? payload.Information ?? payload["Error Message"])}`)
    }

    const quote = payload["Global Quote"] as Record<string, unknown> | undefined
    const price = numberFrom(quote?.["05. price"])
    const change = numberFrom(quote?.["09. change"])
    if (price === null || change === null) throw new Error(`Alpha Vantage: missing quote for ${symbol.symbol}`)
    const percent = numberFrom(quote?.["10. change percent"])
    const latestTradingDayValue = quote?.["07. latest trading day"]
    const latestTradingDay = typeof latestTradingDayValue === "string"
      ? new Date(`${latestTradingDayValue}T00:00:00Z`).toISOString()
      : null
    return toSnapshot(symbol, price, change, percent, latestTradingDay)
  }))

  return results
}

function toSnapshot(
  symbol: MarketSymbol,
  price: number,
  change: number,
  percent: number | null,
  updatedAt: string | null,
  extra: Partial<MarketSnapshot> = {}
): MarketSnapshot {
  return {
    id: symbol.symbol,
    ticker: symbol.ticker,
    name: symbol.name,
    assetType: "equity",
    detailID: symbol.symbol,
    priceText: priceText(price),
    changeText: changeText(change, percent),
    isPositive: change >= 0,
    updatedAt,
    price,
    change,
    changePercent: percent,
    open: extra.open ?? null,
    high: extra.high ?? null,
    low: extra.low ?? null,
    previousClose: extra.previousClose ?? null,
    volume: extra.volume ?? null,
    currency: extra.currency ?? null,
    exchange: extra.exchange ?? null,
    rank: extra.rank ?? null,
    marketCap: extra.marketCap ?? null,
    marketCount: extra.marketCount ?? null,
    dailyVolume: extra.dailyVolume ?? null,
    iconURL: extra.iconURL ?? null,
  }
}

function stringFrom(value: unknown) {
  return typeof value === "string" && value.trim() ? value.trim() : null
}

async function fetchTwelveDataDetail(symbol: MarketSymbol) {
  const apiKey = env("TWELVEDATA_API_KEY")
  if (!apiKey) throw new Error("Twelve Data key is not configured.")

  const homeSnapshot = await readSnapshot("twelvedata")
    .then((record) => record?.payload.find((candidate) => candidate.id === symbol.symbol) ?? null)
    .catch(() => null)

  const [quotePayload, timeSeriesPayload] = await Promise.all([
    homeSnapshot
      ? Promise.resolve(null)
      : fetchJSON(`https://api.twelvedata.com/quote?symbol=${encodeURIComponent(symbol.symbol)}&apikey=${encodeURIComponent(apiKey)}`, "Twelve Data"),
    fetchJSON(`https://api.twelvedata.com/time_series?symbol=${encodeURIComponent(symbol.symbol)}&interval=1day&outputsize=30&apikey=${encodeURIComponent(apiKey)}`, "Twelve Data"),
  ])

  let snapshot = homeSnapshot
  if (!snapshot && quotePayload) {
    const quote = quotePayload as Record<string, unknown>
    if (String(quote.status ?? "").toLowerCase() === "error") {
      throw new Error(`Twelve Data: ${String(quote.message ?? "provider error")}`)
    }
    snapshot = twelveDataQuoteToSnapshot(symbol, quote)
  }
  if (!snapshot) throw new Error(`Twelve Data: missing quote for ${symbol.symbol}`)

  const chartPayload = timeSeriesPayload as Record<string, unknown>
  const values = Array.isArray(chartPayload.values) ? chartPayload.values : []
  const chart = values.flatMap((value): MarketChartPoint[] => {
    if (!value || typeof value !== "object" || Array.isArray(value)) return []
    const record = value as Record<string, unknown>
    const date = stringFrom(record.datetime)
    const close = numberFrom(record.close)
    if (!date || close === null) return []
    return [{
      id: `${symbol.symbol}-${date}`,
      date: new Date(`${date}T00:00:00Z`).toISOString(),
      open: numberFrom(record.open),
      high: numberFrom(record.high),
      low: numberFrom(record.low),
      close,
      volume: numberFrom(record.volume),
    }]
  }).reverse()

  return { snapshot, chart }
}

async function fetchAlphaVantageOverview(symbol: MarketSymbol): Promise<StockFundamentals> {
  const apiKey = env("ALPHAVANTAGE_API_KEY")
  if (!apiKey) throw new Error("Alpha Vantage key is not configured.")

  const payload = await fetchJSON(
    `https://www.alphavantage.co/query?function=OVERVIEW&symbol=${encodeURIComponent(symbol.symbol)}&apikey=${encodeURIComponent(apiKey)}`,
    "Alpha Vantage"
  ) as Record<string, unknown>
  if (payload.Note || payload.Information || payload["Error Message"]) {
    throw new Error(`Alpha Vantage: ${String(payload.Note ?? payload.Information ?? payload["Error Message"])}`)
  }
  if (!stringFrom(payload.Symbol)) throw new Error(`Alpha Vantage: missing overview for ${symbol.symbol}`)

  return {
    name: stringFrom(payload.Name),
    description: stringFrom(payload.Description),
    sector: stringFrom(payload.Sector),
    industry: stringFrom(payload.Industry),
    country: stringFrom(payload.Country),
    marketCapitalization: numberFrom(payload.MarketCapitalization),
    peRatio: numberFrom(payload.PERatio),
    pegRatio: numberFrom(payload.PEGRatio),
    dividendYield: numberFrom(payload.DividendYield),
    eps: numberFrom(payload.EPS),
    beta: numberFrom(payload.Beta),
    fiftyTwoWeekHigh: numberFrom(payload["52WeekHigh"]),
    fiftyTwoWeekLow: numberFrom(payload["52WeekLow"]),
    profitMargin: numberFrom(payload.ProfitMargin),
  }
}

function yahooFinanceHeaders() {
  const apiKey = env("YH_FINANCE_RAPIDAPI_KEY") || env("RAPIDAPI_KEY")
  if (!apiKey) throw new Error("YH Finance RapidAPI key is not configured.")
  return {
    "x-rapidapi-key": apiKey,
    "x-rapidapi-host": "yahoo-finance15.p.rapidapi.com",
    "content-type": "application/json",
  }
}

async function fetchYahooFinanceJSON(path: string) {
  const response = await fetch(`https://yahoo-finance15.p.rapidapi.com${path}`, {
    headers: yahooFinanceHeaders(),
  })
  const text = await response.text()
  if (!response.ok) throw new Error(`YH Finance: HTTP ${response.status} ${text.slice(0, 160)}`)
  try {
    return JSON.parse(text) as Record<string, unknown>
  } catch {
    throw new Error("YH Finance: invalid JSON response")
  }
}

function firstString(record: Record<string, unknown>, keys: string[]) {
  for (const key of keys) {
    const value = yahooString(record[key])
    if (value) return value
  }
  return null
}

function firstNumber(record: Record<string, unknown>, keys: string[]) {
  for (const key of keys) {
    const value = yahooNumber(record[key])
    if (value !== null) return value
  }
  return null
}

function yahooString(value: unknown): string | null {
  const direct = stringFrom(value)
  if (direct) return direct
  if (!value || typeof value !== "object" || Array.isArray(value)) return null
  const record = value as Record<string, unknown>
  return stringFrom(record.fmt) ?? stringFrom(record.longFmt) ?? stringFrom(record.raw)
}

function yahooNumber(value: unknown): number | null {
  const direct = numberFrom(value)
  if (direct !== null) return direct
  if (!value || typeof value !== "object" || Array.isArray(value)) return null
  const record = value as Record<string, unknown>
  return numberFrom(record.raw) ?? numberFrom(record.fmt) ?? numberFrom(record.longFmt)
}

function nestedRecord(value: unknown, path: string[]) {
  let current = value
  for (const key of path) {
    if (!current || typeof current !== "object" || Array.isArray(current)) return null
    current = (current as Record<string, unknown>)[key]
  }
  return current && typeof current === "object" && !Array.isArray(current)
    ? current as Record<string, unknown>
    : null
}

function stockModulePayload(payload: Record<string, unknown>) {
  return nestedRecord(payload, ["body"]) ??
    nestedRecord(payload, ["data"]) ??
    nestedRecord(payload, ["quoteSummary", "result"]) ??
    payload
}

function firstUnixTimestamp(record: Record<string, unknown>, keys: string[]) {
  for (const key of keys) {
    const value = record[key]
    if (typeof value === "number" && Number.isFinite(value)) return value
    if (typeof value === "string" && /^\d+$/.test(value.trim())) {
      const parsed = Number.parseInt(value.trim(), 10)
      if (Number.isFinite(parsed)) return parsed
    }
  }
  return null
}

function newsItemsFrom(value: unknown): Record<string, unknown>[] {
  if (Array.isArray(value)) {
    return value.flatMap((item): Record<string, unknown>[] =>
      item && typeof item === "object" && !Array.isArray(item) ? [item as Record<string, unknown>] : []
    )
  }

  if (!value || typeof value !== "object" || Array.isArray(value)) return []
  const record = value as Record<string, unknown>
  for (const key of ["body", "data", "news", "items", "result"]) {
    const nested = newsItemsFrom(record[key])
    if (nested.length) return nested
  }
  return []
}

async function fetchYahooFinanceMarketNews(): Promise<MarketNewsItem[]> {
  const payload = await fetchYahooFinanceJSON("/api/v1/markets/news")
  const records = newsItemsFrom(payload)
  const items = records.flatMap((record, index): MarketNewsItem[] => {
    const title = firstString(record, ["title", "headline", "name"])
    if (!title) return []
    const timestamp = firstUnixTimestamp(record, ["providerPublishTime", "publishedAt", "pubDate", "time"])
    const publishedAt = timestamp
      ? new Date(timestamp > 10_000_000_000 ? timestamp : timestamp * 1000).toISOString()
      : firstString(record, ["published_at", "published", "date"])
    const image = record.thumbnail && typeof record.thumbnail === "object" && !Array.isArray(record.thumbnail)
      ? firstString(record.thumbnail as Record<string, unknown>, ["url", "originalUrl"])
      : null
    return [{
      id: firstString(record, ["uuid", "id", "guid", "link"]) ?? `yh-news-${index}`,
      title,
      publisher: firstString(record, ["publisher", "source", "provider"]),
      url: firstString(record, ["link", "url"]),
      publishedAt,
      summary: firstString(record, ["summary", "description"]),
      imageURL: image ?? firstString(record, ["image", "imageUrl", "thumbnail"]),
    }]
  })
  if (!items.length) throw new Error("YH Finance: no usable market news returned.")
  return items.slice(0, 6)
}

function indicatorRecordsFrom(value: unknown): Record<string, unknown>[] {
  if (Array.isArray(value)) {
    return value.flatMap((item): Record<string, unknown>[] =>
      item && typeof item === "object" && !Array.isArray(item) ? [item as Record<string, unknown>] : []
    )
  }

  if (!value || typeof value !== "object" || Array.isArray(value)) return []
  const record = value as Record<string, unknown>
  for (const key of ["body", "data", "values", "result", "indicators"]) {
    const nested = indicatorRecordsFrom(record[key])
    if (nested.length) return nested
  }
  return [record]
}

function firstIndicatorValue(payload: unknown, keys: string[]) {
  const records = indicatorRecordsFrom(payload)
  for (const record of records) {
    const value = firstNumber(record, keys)
    if (value !== null) {
      return {
        value,
        updatedAt: firstString(record, ["datetime", "date", "timestamp", "time"]),
      }
    }
  }
  return null
}

function rsiSignal(value: number | null) {
  if (value === null) return null
  if (value >= 70) return "Overbought"
  if (value <= 30) return "Oversold"
  return "Neutral"
}

function smaSignal(price: number | null | undefined, value: number | null) {
  if (price === null || price === undefined || value === null) return null
  if (price > value) return "Price above average"
  if (price < value) return "Price below average"
  return "At average"
}

async function fetchYahooFinanceIndicator(symbol: MarketSymbol, indicator: "rsi" | "sma"): Promise<TechnicalIndicator | null> {
  const params = new URLSearchParams({
    symbol: symbol.symbol,
    interval: "1d",
    time_period: "14",
    series_type: "close",
  })
  const payload = await fetchYahooFinanceJSON(`/api/v1/markets/indicators/${indicator}?${params}`)
  const latest = firstIndicatorValue(payload, [indicator, indicator.toUpperCase(), "value"])
  if (!latest) throw new Error(`YH Finance: no usable ${indicator.toUpperCase()} returned.`)

  return {
    id: indicator,
    name: indicator === "rsi" ? "RSI 14D" : "SMA 14D",
    value: latest.value,
    signal: indicator === "rsi" ? rsiSignal(latest.value) : null,
    updatedAt: latest.updatedAt,
  }
}

async function fetchYahooFinanceTechnicalIndicators(symbol: MarketSymbol, price: number | null | undefined) {
  const [rsi, sma] = await Promise.all([
    runProviderTask("yahoofinance", `indicator:rsi:${symbol.symbol}`, () => fetchYahooFinanceIndicator(symbol, "rsi")).catch(() => null),
    runProviderTask("yahoofinance", `indicator:sma:${symbol.symbol}`, () => fetchYahooFinanceIndicator(symbol, "sma")).catch(() => null),
  ])

  return [rsi, sma].flatMap((indicator): TechnicalIndicator[] => {
    if (!indicator) return []
    if (indicator.id === "sma") return [{ ...indicator, signal: smaSignal(price, indicator.value) }]
    return [indicator]
  })
}

function hasAnalystStats(stats: AnalystStats) {
  return Object.values(stats).some((value) => value !== null)
}

async function fetchYahooFinanceAnalystStats(symbol: MarketSymbol): Promise<AnalystStats | null> {
  const params = new URLSearchParams({
    ticker: symbol.symbol,
    module: "financial-data",
  })
  const payload = await fetchYahooFinanceJSON(`/api/v1/markets/stock/modules?${params}`)
  const body = stockModulePayload(payload)
  const financialData = nestedRecord(body, ["financialData"]) ?? body
  const keyStats = nestedRecord(body, ["defaultKeyStatistics"]) ?? body
  const profile = nestedRecord(body, ["assetProfile"]) ?? body
  const trend = nestedRecord(body, ["recommendationTrend", "trend"]) ?? null
  const firstTrend = Array.isArray(trend) && trend[0] && typeof trend[0] === "object"
    ? trend[0] as Record<string, unknown>
    : null

  const recommendation = firstString(financialData, ["recommendationKey", "recommendationMean"]) ??
    (firstTrend ? firstString(firstTrend, ["period"]) : null)

  const stats: AnalystStats = {
    recommendation,
    targetMeanPrice: firstNumber(financialData, ["targetMeanPrice", "targetMedianPrice"]),
    targetHighPrice: firstNumber(financialData, ["targetHighPrice"]),
    targetLowPrice: firstNumber(financialData, ["targetLowPrice"]),
    numberOfAnalystOpinions: firstNumber(financialData, ["numberOfAnalystOpinions"]),
    revenueGrowth: firstNumber(financialData, ["revenueGrowth"]),
    grossMargins: firstNumber(financialData, ["grossMargins"]),
    operatingMargins: firstNumber(financialData, ["operatingMargins"]),
    returnOnEquity: firstNumber(financialData, ["returnOnEquity"]),
    forwardPE: firstNumber(keyStats, ["forwardPE"]),
    trailingPE: firstNumber(keyStats, ["trailingPE"]),
    priceToBook: firstNumber(keyStats, ["priceToBook"]),
    enterpriseToRevenue: firstNumber(keyStats, ["enterpriseToRevenue"]),
    enterpriseToEbitda: firstNumber(keyStats, ["enterpriseToEbitda"]),
    website: firstString(profile, ["website"]),
    fullTimeEmployees: firstNumber(profile, ["fullTimeEmployees"]),
  }

  return hasAnalystStats(stats) ? stats : null
}

async function fetchStockDetail(symbol: MarketSymbol) {
  const [marketDetail, fundamentals, news, analystStats] = await Promise.all([
    fetchTwelveDataDetail(symbol),
    runProviderTask("alphavantage", `overview:${symbol.symbol}`, () => fetchAlphaVantageOverview(symbol)).catch(() => null),
    runProviderTask("yahoofinance", "market-news", fetchYahooFinanceMarketNews).catch(() => [] as MarketNewsItem[]),
    runProviderTask("yahoofinance", `modules:${symbol.symbol}`, () => fetchYahooFinanceAnalystStats(symbol)).catch(() => null),
  ])
  const technicalIndicators = await fetchYahooFinanceTechnicalIndicators(symbol, marketDetail.snapshot.price)

  return { ...marketDetail, fundamentals, news, technicalIndicators, analystStats }
}

function coinrankingHeaders() {
  const apiKey = env("COINRANKING_RAPIDAPI_KEY") || env("RAPIDAPI_KEY")
  if (!apiKey) throw new Error("Coinranking RapidAPI key is not configured.")
  return {
    "x-rapidapi-key": apiKey,
    "x-rapidapi-host": "coinranking1.p.rapidapi.com",
    "content-type": "application/json",
  }
}

async function fetchCoinrankingJSON(path: string) {
  const response = await fetch(`https://coinranking1.p.rapidapi.com${path}`, {
    headers: coinrankingHeaders(),
  })
  const text = await response.text()
  if (!response.ok) throw new Error(`Coinranking: HTTP ${response.status} ${text.slice(0, 160)}`)
  try {
    const payload = JSON.parse(text) as Record<string, unknown>
    if (String(payload.status ?? "").toLowerCase() === "fail") {
      throw new Error(String(payload.message ?? "provider error"))
    }
    return payload
  } catch (error) {
    if (error instanceof Error && error.message !== "provider error") throw error
    throw new Error("Coinranking: invalid JSON response")
  }
}

function coinRecordToSnapshot(record: Record<string, unknown>, fallback?: CryptoCoin): MarketSnapshot | null {
  const uuid = stringFrom(record.uuid) ?? fallback?.uuid
  const symbol = stringFrom(record.symbol) ?? fallback?.symbol
  const name = stringFrom(record.name) ?? fallback?.name
  const price = numberFrom(record.price)
  if (!uuid || !symbol || !name || price === null) return null

  const percent = numberFrom(record.change)
  const change = price * ((percent ?? 0) / 100)
  return {
    id: uuid,
    ticker: symbol,
    name,
    assetType: "crypto",
    detailID: uuid,
    priceText: priceText(price),
    changeText: changeText(change, percent),
    isPositive: (percent ?? 0) >= 0,
    updatedAt: null,
    price,
    change,
    changePercent: percent,
    open: null,
    high: null,
    low: null,
    previousClose: null,
    volume: null,
    currency: "USD",
    exchange: "Coinranking",
    rank: numberFrom(record.rank),
    marketCap: numberFrom(record.marketCap),
    marketCount: numberFrom(record.numberOfMarkets),
    dailyVolume: numberFrom(record["24hVolume"]),
    iconURL: stringFrom(record.iconUrl),
  }
}

async function fetchCoinrankingCrypto() {
  const payload = await fetchCoinrankingJSON("/coins?referenceCurrencyUuid=yhjMzLPhuIDl&timePeriod=24h&tiers[]=1&orderBy=marketCap&orderDirection=desc&limit=8&offset=0")
  const data = payload.data as Record<string, unknown> | undefined
  const coins = Array.isArray(data?.coins) ? data.coins : []
  const snapshots = coins.flatMap((coin): MarketSnapshot[] => {
    if (!coin || typeof coin !== "object" || Array.isArray(coin)) return []
    const snapshot = coinRecordToSnapshot(coin as Record<string, unknown>)
    return snapshot ? [snapshot] : []
  })
  if (!snapshots.length) throw new Error("Coinranking: no usable coins returned.")
  return snapshots
}

async function fetchCoinrankingTrending() {
  const payload = await fetchCoinrankingJSON("/coins/trending?referenceCurrencyUuid=yhjMzLPhuIDl&timePeriod=24h&limit=8")
  const data = payload.data as Record<string, unknown> | undefined
  const coins = Array.isArray(data?.coins) ? data.coins : []
  const snapshots = coins.flatMap((coin): MarketSnapshot[] => {
    if (!coin || typeof coin !== "object" || Array.isArray(coin)) return []
    const snapshot = coinRecordToSnapshot(coin as Record<string, unknown>)
    return snapshot ? [snapshot] : []
  })
  if (!snapshots.length) throw new Error("Coinranking: no usable trending coins returned.")
  return snapshots
}

async function fetchCoinrankingSearch(query: string) {
  const payload = await fetchCoinrankingJSON(`/coins?referenceCurrencyUuid=yhjMzLPhuIDl&timePeriod=24h&search=${encodeURIComponent(query)}&limit=10&offset=0`)
  const data = payload.data as Record<string, unknown> | undefined
  const coins = Array.isArray(data?.coins) ? data.coins : []
  const snapshots = coins.flatMap((coin): MarketSnapshot[] => {
    if (!coin || typeof coin !== "object" || Array.isArray(coin)) return []
    const snapshot = coinRecordToSnapshot(coin as Record<string, unknown>)
    return snapshot ? [snapshot] : []
  })
  if (!snapshots.length) throw new Error("Coinranking: no usable search results returned.")
  return snapshots
}

async function fetchCoinrankingStats(): Promise<CryptoStats> {
  const payload = await fetchCoinrankingJSON("/stats?referenceCurrencyUuid=yhjMzLPhuIDl")
  const data = payload.data && typeof payload.data === "object" && !Array.isArray(payload.data)
    ? payload.data as Record<string, unknown>
    : null
  const stats = data?.stats && typeof data.stats === "object" && !Array.isArray(data.stats)
    ? data.stats as Record<string, unknown>
    : data
  if (!stats) {
    throw new Error("Coinranking: no usable stats returned.")
  }
  const record = stats
  return {
    totalMarketCap: numberFrom(record.totalMarketCap ?? record.marketCap),
    totalVolume24h: numberFrom(record.total24hVolume ?? record.totalVolume ?? record.volume24h),
    btcDominance: numberFrom(record.btcDominance ?? record.btcDominancePercentage),
    totalCoins: numberFrom(record.totalCoins ?? record.coins),
    totalMarkets: numberFrom(record.totalMarkets ?? record.markets),
    totalExchanges: numberFrom(record.totalExchanges ?? record.exchanges),
  }
}

async function fetchCoinrankingMovers(): Promise<CryptoMovers> {
  const [gainersPayload, losersPayload] = await Promise.all([
    fetchCoinrankingJSON("/coins?referenceCurrencyUuid=yhjMzLPhuIDl&timePeriod=24h&tiers[]=1&orderBy=change&orderDirection=desc&limit=8&offset=0"),
    fetchCoinrankingJSON("/coins?referenceCurrencyUuid=yhjMzLPhuIDl&timePeriod=24h&tiers[]=1&orderBy=change&orderDirection=asc&limit=8&offset=0"),
  ])

  const snapshotsFromPayload = (payload: Record<string, unknown>) => {
    const data = payload.data as Record<string, unknown> | undefined
    const coins = Array.isArray(data?.coins) ? data.coins : []
    return coins.flatMap((coin): MarketSnapshot[] => {
      if (!coin || typeof coin !== "object" || Array.isArray(coin)) return []
      const snapshot = coinRecordToSnapshot(coin as Record<string, unknown>)
      return snapshot ? [snapshot] : []
    })
  }

  const gainers = snapshotsFromPayload(gainersPayload)
  const losers = snapshotsFromPayload(losersPayload)
  if (!gainers.length && !losers.length) throw new Error("Coinranking: no usable movers returned.")
  return { gainers, losers }
}

async function fetchCoinrankingDetail(coin: CryptoCoin) {
  const [coinPayload, historyPayload] = await Promise.all([
    fetchCoinrankingJSON(`/coin/${encodeURIComponent(coin.uuid)}?referenceCurrencyUuid=yhjMzLPhuIDl&timePeriod=24h`),
    fetchCoinrankingJSON(`/coin/${encodeURIComponent(coin.uuid)}/history?referenceCurrencyUuid=yhjMzLPhuIDl&timePeriod=30d`),
  ])

  const coinData = (coinPayload.data as Record<string, unknown> | undefined)?.coin
  const snapshot = coinData && typeof coinData === "object" && !Array.isArray(coinData)
    ? coinRecordToSnapshot(coinData as Record<string, unknown>, coin)
    : null
  if (!snapshot) throw new Error(`Coinranking: missing coin details for ${coin.symbol}`)

  const history = (historyPayload.data as Record<string, unknown> | undefined)?.history
  const chart = (Array.isArray(history) ? history : []).flatMap((value): MarketChartPoint[] => {
    if (!value || typeof value !== "object" || Array.isArray(value)) return []
    const record = value as Record<string, unknown>
    const timestamp = numberFrom(record.timestamp)
    const close = numberFrom(record.price)
    if (!timestamp || close === null) return []
    const date = new Date(timestamp * 1000).toISOString()
    return [{
      id: `${coin.uuid}-${timestamp}`,
      date,
      open: null,
      high: null,
      low: null,
      close,
      volume: null,
    }]
  }).reverse()

  return { snapshot, chart }
}

const providers: ProviderSource[] = [
  { id: "twelvedata", name: "Twelve Data", configured: () => Boolean(env("TWELVEDATA_API_KEY")), run: fetchTwelveData },
  { id: "finnhub", name: "Finnhub", configured: () => Boolean(env("FINNHUB_API_KEY")), run: fetchFinnhub },
  { id: "alphavantage", name: "Alpha Vantage", configured: () => Boolean(env("ALPHAVANTAGE_API_KEY")), run: fetchAlphaVantage },
]

const providerNames: Record<string, string> = {
  twelvedata: "Twelve Data",
  finnhub: "Finnhub",
  alphavantage: "Alpha Vantage",
  coinranking: "Coinranking",
  yahoofinance: "YH Finance",
}

function providerConfigured(providerID: string) {
  if (providerID === "twelvedata") return Boolean(env("TWELVEDATA_API_KEY"))
  if (providerID === "finnhub") return Boolean(env("FINNHUB_API_KEY"))
  if (providerID === "alphavantage") return Boolean(env("ALPHAVANTAGE_API_KEY"))
  if (providerID === "coinranking") return Boolean(env("COINRANKING_RAPIDAPI_KEY") || env("RAPIDAPI_KEY"))
  if (providerID === "yahoofinance") return Boolean(env("YH_FINANCE_RAPIDAPI_KEY") || env("RAPIDAPI_KEY"))
  return false
}

async function providerStatusResponse() {
  const now = Date.now()
  const providerIDs = Object.keys(providerBudgets)
  const statuses = await Promise.all(providerIDs.map(async (providerID) => {
    const config = budget(providerID)
    const usage = normalizeUsage(providerID, config, await readUsage(providerID), now)
    const caches = await readProviderSnapshotSummaries(providerID)
    return {
      providerID,
      providerName: providerNames[providerID] ?? providerID,
      configured: providerConfigured(providerID),
      period: usage.period,
      autoLimit: usage.auto_limit,
      usedCount: usage.used_count,
      remaining: Math.max(usage.auto_limit - usage.used_count, 0),
      manualOnly: usage.manual_only,
      blocked: usage.blocked_until ? Date.parse(usage.blocked_until) > now : false,
      blockedUntil: usage.blocked_until,
      windowStartedAt: usage.window_started_at,
      windowEndsAt: usage.window_ends_at,
      lastAttemptAt: usage.last_attempt_at,
      lastSuccessAt: usage.last_success_at,
      lastErrorAt: usage.last_error_at,
      lastError: usage.last_error,
      caches,
    } satisfies ProviderStatus
  }))

  return json(200, {
    generatedAt: iso(new Date(now)),
    providers: statuses,
  } satisfies ProviderStatusResponse)
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })
  if (request.method !== "GET") return json(405, { message: "Method not allowed" })

  const url = new URL(request.url)
  const force = url.searchParams.get("force") === "1"
  const kind = url.searchParams.get("kind")?.trim().toLowerCase()
  const coinParam = url.searchParams.get("coin")?.trim()

  if (kind === "provider-status" || url.searchParams.get("providerStatus") === "1") {
    return await providerStatusResponse()
  }

  if (coinParam) {
    const coin = cryptoCoins.find((candidate) =>
      candidate.uuid === coinParam || candidate.symbol.toLowerCase() === coinParam.toLowerCase()
    ) ?? {
      uuid: coinParam,
      symbol: coinParam.toUpperCase(),
      name: coinParam,
    }
    try {
      const detail = await runProviderTask(
        "coinranking",
        `crypto-detail:${coin.uuid}`,
        () => fetchCoinrankingDetail(coin)
      )
      return json(200, {
        generatedAt: iso(),
        source: "live",
        provider: "Coinranking",
        cacheHit: false,
        stale: false,
        updatedAt: iso(),
        expiresAt: iso(new Date(Date.now() + budget("coinranking").minRefreshMS)),
        message: null,
        snapshot: detail.snapshot,
        chart: detail.chart,
      } satisfies MarketDetailResponse)
    } catch (error) {
      const cachedDetail = await readProviderSnapshotRecord<{ snapshot: MarketSnapshot; chart: MarketChartPoint[] }>(
        "coinranking",
        `crypto-detail:${coin.uuid}`
      ).catch(() => null)
      if (cachedDetail) {
        return json(200, {
          generatedAt: iso(),
          source: "stale",
          provider: "Coinranking",
          cacheHit: true,
          stale: true,
          updatedAt: cachedDetail.generated_at,
          expiresAt: cachedDetail.expires_at,
          message: providerErrorMessage(error),
          snapshot: cachedDetail.payload.snapshot,
          chart: cachedDetail.payload.chart,
        } satisfies MarketDetailResponse)
      }

      return json(200, {
        generatedAt: iso(),
        source: "stale",
        provider: "Coinranking",
        cacheHit: false,
        stale: true,
        updatedAt: null,
        expiresAt: null,
        message: providerErrorMessage(error),
        snapshot: {
          id: coin.uuid,
          ticker: coin.symbol,
          name: coin.name,
          assetType: "crypto",
          detailID: coin.uuid,
          priceText: "--",
          changeText: "Waiting for data",
          isPositive: true,
          updatedAt: null,
          price: null,
          change: null,
          changePercent: null,
          open: null,
          high: null,
          low: null,
          previousClose: null,
          volume: null,
          currency: "USD",
          exchange: "Coinranking",
          rank: null,
          marketCap: null,
          marketCount: null,
          dailyVolume: null,
          iconURL: null,
        },
        chart: [],
      } satisfies MarketDetailResponse)
    }
  }

  if (kind === "crypto") {
    try {
      const detail = await runProviderTask("coinranking", "crypto-home", fetchCoinrankingCrypto)
      const record = await readProviderSnapshotRecord<MarketSnapshot[]>("coinranking", "crypto-home")
      return json(200, {
        generatedAt: iso(),
        source: "live",
        provider: "Coinranking",
        cacheHit: false,
        stale: false,
        updatedAt: record?.generated_at ?? iso(),
        expiresAt: record?.expires_at ?? iso(new Date(Date.now() + budget("coinranking").minRefreshMS)),
        message: null,
        snapshots: detail,
      } satisfies MarketDataResponse)
    } catch (error) {
      const snapshot = await readProviderSnapshotRecord<MarketSnapshot[]>("coinranking", "crypto-home").catch(() => null)
      if (snapshot) {
        return json(200, {
          generatedAt: iso(),
          source: Date.parse(snapshot.expires_at) > Date.now() ? "cached" : "stale",
          provider: "Coinranking",
          cacheHit: true,
          stale: Date.parse(snapshot.expires_at) <= Date.now(),
          updatedAt: snapshot.generated_at,
          expiresAt: snapshot.expires_at,
          message: providerErrorMessage(error),
          snapshots: snapshot.payload,
        } satisfies MarketDataResponse)
      }

      return json(200, {
        generatedAt: iso(),
        source: "stale",
        provider: "Coinranking",
        cacheHit: false,
        stale: true,
        updatedAt: null,
        expiresAt: null,
        message: providerErrorMessage(error),
        snapshots: [],
      } satisfies MarketDataResponse)
    }
  }

  if (kind === "crypto-trending") {
    try {
      const detail = await runProviderTask("coinranking", "crypto-trending", fetchCoinrankingTrending)
      const record = await readProviderSnapshotRecord<MarketSnapshot[]>("coinranking", "crypto-trending")
      return json(200, {
        generatedAt: iso(),
        source: "live",
        provider: "Coinranking",
        cacheHit: false,
        stale: false,
        updatedAt: record?.generated_at ?? iso(),
        expiresAt: record?.expires_at ?? iso(new Date(Date.now() + budget("coinranking").minRefreshMS)),
        message: null,
        snapshots: detail,
      } satisfies MarketDataResponse)
    } catch (error) {
      const snapshot = await readProviderSnapshotRecord<MarketSnapshot[]>("coinranking", "crypto-trending").catch(() => null)
      if (snapshot) {
        return json(200, {
          generatedAt: iso(),
          source: Date.parse(snapshot.expires_at) > Date.now() ? "cached" : "stale",
          provider: "Coinranking",
          cacheHit: true,
          stale: Date.parse(snapshot.expires_at) <= Date.now(),
          updatedAt: snapshot.generated_at,
          expiresAt: snapshot.expires_at,
          message: providerErrorMessage(error),
          snapshots: snapshot.payload,
        } satisfies MarketDataResponse)
      }

      return json(200, {
        generatedAt: iso(),
        source: "stale",
        provider: "Coinranking",
        cacheHit: false,
        stale: true,
        updatedAt: null,
        expiresAt: null,
        message: providerErrorMessage(error),
        snapshots: [],
      } satisfies MarketDataResponse)
    }
  }

  if (kind === "crypto-search") {
    const query = url.searchParams.get("q")?.trim() ?? ""
    if (query.length < 2) {
      return json(200, {
        generatedAt: iso(),
        source: "cached",
        provider: "Coinranking",
        cacheHit: true,
        stale: false,
        updatedAt: null,
        expiresAt: null,
        message: null,
        snapshots: [],
      } satisfies MarketDataResponse)
    }

    const searchScope = `crypto-search:${query.toLowerCase().replace(/[^a-z0-9_-]+/g, "-").slice(0, 80)}`
    try {
      const snapshots = await runProviderTask("coinranking", searchScope, () => fetchCoinrankingSearch(query))
      const record = await readProviderSnapshotRecord<MarketSnapshot[]>("coinranking", searchScope)
      return json(200, {
        generatedAt: iso(),
        source: "live",
        provider: "Coinranking",
        cacheHit: false,
        stale: false,
        updatedAt: record?.generated_at ?? iso(),
        expiresAt: record?.expires_at ?? iso(new Date(Date.now() + budget("coinranking").minRefreshMS)),
        message: null,
        snapshots,
      } satisfies MarketDataResponse)
    } catch (error) {
      const snapshot = await readProviderSnapshotRecord<MarketSnapshot[]>("coinranking", searchScope).catch(() => null)
      if (snapshot) {
        return json(200, {
          generatedAt: iso(),
          source: Date.parse(snapshot.expires_at) > Date.now() ? "cached" : "stale",
          provider: "Coinranking",
          cacheHit: true,
          stale: Date.parse(snapshot.expires_at) <= Date.now(),
          updatedAt: snapshot.generated_at,
          expiresAt: snapshot.expires_at,
          message: providerErrorMessage(error),
          snapshots: snapshot.payload,
        } satisfies MarketDataResponse)
      }

      return json(200, {
        generatedAt: iso(),
        source: "stale",
        provider: "Coinranking",
        cacheHit: false,
        stale: true,
        updatedAt: null,
        expiresAt: null,
        message: providerErrorMessage(error),
        snapshots: [],
      } satisfies MarketDataResponse)
    }
  }

  if (kind === "crypto-stats") {
    try {
      const stats = await runProviderTask("coinranking", "crypto-stats", fetchCoinrankingStats)
      const record = await readProviderSnapshotRecord<CryptoStats>("coinranking", "crypto-stats")
      return json(200, {
        generatedAt: iso(),
        source: "live",
        provider: "Coinranking",
        cacheHit: false,
        stale: false,
        updatedAt: record?.generated_at ?? iso(),
        expiresAt: record?.expires_at ?? iso(new Date(Date.now() + budget("coinranking").minRefreshMS)),
        message: null,
        stats,
      } satisfies CryptoStatsResponse)
    } catch (error) {
      const snapshot = await readProviderSnapshotRecord<CryptoStats>("coinranking", "crypto-stats").catch(() => null)
      if (snapshot) {
        return json(200, {
          generatedAt: iso(),
          source: Date.parse(snapshot.expires_at) > Date.now() ? "cached" : "stale",
          provider: "Coinranking",
          cacheHit: true,
          stale: Date.parse(snapshot.expires_at) <= Date.now(),
          updatedAt: snapshot.generated_at,
          expiresAt: snapshot.expires_at,
          message: providerErrorMessage(error),
          stats: snapshot.payload,
        } satisfies CryptoStatsResponse)
      }

      return json(200, {
        generatedAt: iso(),
        source: "stale",
        provider: "Coinranking",
        cacheHit: false,
        stale: true,
        updatedAt: null,
        expiresAt: null,
        message: providerErrorMessage(error),
        stats: {
          totalMarketCap: null,
          totalVolume24h: null,
          btcDominance: null,
          totalCoins: null,
          totalMarkets: null,
          totalExchanges: null,
        },
      } satisfies CryptoStatsResponse)
    }
  }

  if (kind === "crypto-movers") {
    try {
      const movers = await runProviderTask("coinranking", "crypto-movers", fetchCoinrankingMovers)
      const record = await readProviderSnapshotRecord<CryptoMovers>("coinranking", "crypto-movers")
      return json(200, {
        generatedAt: iso(),
        source: "live",
        provider: "Coinranking",
        cacheHit: false,
        stale: false,
        updatedAt: record?.generated_at ?? iso(),
        expiresAt: record?.expires_at ?? iso(new Date(Date.now() + budget("coinranking").minRefreshMS)),
        message: null,
        gainers: movers.gainers,
        losers: movers.losers,
      } satisfies CryptoMoversResponse)
    } catch (error) {
      const snapshot = await readProviderSnapshotRecord<CryptoMovers>("coinranking", "crypto-movers").catch(() => null)
      if (snapshot) {
        return json(200, {
          generatedAt: iso(),
          source: Date.parse(snapshot.expires_at) > Date.now() ? "cached" : "stale",
          provider: "Coinranking",
          cacheHit: true,
          stale: Date.parse(snapshot.expires_at) <= Date.now(),
          updatedAt: snapshot.generated_at,
          expiresAt: snapshot.expires_at,
          message: providerErrorMessage(error),
          gainers: snapshot.payload.gainers,
          losers: snapshot.payload.losers,
        } satisfies CryptoMoversResponse)
      }

      return json(200, {
        generatedAt: iso(),
        source: "stale",
        provider: "Coinranking",
        cacheHit: false,
        stale: true,
        updatedAt: null,
        expiresAt: null,
        message: providerErrorMessage(error),
        gainers: [],
        losers: [],
      } satisfies CryptoMoversResponse)
    }
  }

  const symbolParam = url.searchParams.get("symbol")?.trim().toUpperCase()
  if (symbolParam) {
    const symbol = symbols.find((candidate) => candidate.symbol === symbolParam)
    if (!symbol) return json(400, { message: "Unsupported market symbol." })
    try {
      const detail = await runProviderTask(
        "twelvedata",
        `detail:${symbol.symbol}`,
        () => fetchStockDetail(symbol)
      )
      return json(200, {
        generatedAt: iso(),
        source: "live",
        provider: "Twelve Data",
        cacheHit: false,
        stale: false,
        updatedAt: iso(),
        expiresAt: iso(new Date(Date.now() + budget("twelvedata").minRefreshMS)),
        message: null,
        snapshot: detail.snapshot,
        chart: detail.chart,
        fundamentals: detail.fundamentals,
        news: detail.news,
        technicalIndicators: detail.technicalIndicators,
        analystStats: detail.analystStats,
      } satisfies MarketDetailResponse)
    } catch (error) {
      const cachedSnapshot = await readSnapshot("twelvedata")
        .then((record) => record?.payload.find((candidate) => candidate.id === symbol.symbol) ?? null)
        .catch(() => null)
      return json(200, {
        generatedAt: iso(),
        source: "stale",
        provider: "Twelve Data",
        cacheHit: false,
        stale: true,
        updatedAt: null,
        expiresAt: null,
        message: providerErrorMessage(error),
        snapshot: cachedSnapshot ?? toSnapshot(symbol, 0, 0, null, null),
        chart: [],
      } satisfies MarketDetailResponse)
    }
  }

  const errors: string[] = []

  for (const provider of providers.filter((candidate) => candidate.configured())) {
    try {
      const result = await runProvider(provider, force)
      const snapshotUpdatedAt = result.snapshotRecord?.generated_at ?? iso()
      const body: MarketDataResponse = {
        generatedAt: iso(),
        source: result.source,
        provider: result.providerName,
        cacheHit: result.source !== "live",
        stale: result.source === "stale",
        updatedAt: result.source === "live" ? iso() : snapshotUpdatedAt,
        expiresAt: result.snapshotRecord?.expires_at ?? iso(new Date(Date.now() + budget(result.providerID).minRefreshMS)),
        message: result.source === "stale" ? "Showing stale market data because live quota is paused or exhausted." : null,
        snapshots: result.snapshots,
      }
      return json(200, body)
    } catch (error) {
      errors.push(providerErrorMessage(error))
    }
  }

  const message = errors[0] ?? "No market data provider is configured."
  return json(200, {
    generatedAt: iso(),
    source: "stale",
    provider: null,
    cacheHit: false,
    stale: true,
    updatedAt: null,
    expiresAt: null,
    message,
    snapshots: [],
  } satisfies MarketDataResponse)
})
