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
    throw new Error(`Supabase REST ${response.status}: ${body.slice(0, 200)}`)
  }

  if (response.status === 204) return undefined as T
  const text = await response.text()
  return (text ? JSON.parse(text) : undefined) as T
}

async function fetchJobMatches(query: string, country: string) {
  const { url, key } = supabaseCredentials()
  const endpoint = new URL(`${url}/functions/v1/jobs-data`)
  endpoint.searchParams.set("q", query)
  endpoint.searchParams.set("country", country)

  const response = await fetch(endpoint, {
    headers: {
      "apikey": key,
      "authorization": `Bearer ${key}`,
      "content-type": "application/json",
    },
  })

  if (!response.ok) return []
  const payload = await response.json().catch(() => null) as { jobs?: JobListing[] } | null
  return payload?.jobs ?? []
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

function deriveJobQuery(events: JobActivity[]) {
  const explicitQuery = events.find((event) => event.role_query?.trim())?.role_query?.trim()
  if (explicitQuery) return explicitQuery

  const openOrSaved = events.find((event) => event.job_title?.trim())
  if (openOrSaved?.job_title) return openOrSaved.job_title

  const keywords = events.flatMap((event) => event.keywords ?? []).filter(Boolean)
  if (keywords.length > 0) return keywords.slice(0, 4).join(" ")

  return null
}

function dayKey() {
  return new Date().toISOString().slice(0, 10)
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
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i)
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

async function alreadyDelivered(userID: string, notificationType: string, dedupeKey: string) {
  const rows = await supabaseREST<{ id: string }[]>(
    `notification_deliveries?user_id=eq.${userID}&notification_type=eq.${notificationType}&dedupe_key=eq.${encodeURIComponent(dedupeKey)}&status=eq.sent&select=id&limit=1`,
  )
  return rows.length > 0
}

async function writeDelivery(
  userID: string,
  deviceID: string | null,
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
      notification_type: "job_match",
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

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { headers: corsHeaders })
  if (request.method !== "POST") return json(405, { error: "Use POST." })

  try {
    const url = new URL(request.url)
    const body = await request.json().catch(() => ({})) as { dryRun?: boolean; limit?: number }
    const dryRun = body.dryRun ?? url.searchParams.get("dry_run") === "true"
    const limit = Math.max(1, Math.min(body.limit ?? 25, 100))
    const since = new Date(Date.now() - 14 * 24 * 60 * 60 * 1000).toISOString()

    const users = await supabaseREST<{ user_id: string }[]>(
      `notification_preferences?jobs_enabled=eq.true&select=user_id&limit=${limit}`,
    )

    const results = []

    for (const user of users) {
      const devices = await supabaseREST<PushDevice[]>(
        `push_devices?user_id=eq.${user.user_id}&enabled=eq.true&select=id,user_id,device_token,environment`,
      )
      if (devices.length === 0) {
        results.push({ userID: user.user_id, status: "skipped", reason: "no_enabled_devices" })
        continue
      }

      const events = await supabaseREST<JobActivity[]>(
        `job_activity_events?user_id=eq.${user.user_id}&created_at=gte.${encodeURIComponent(since)}&select=event_type,role_query,job_title,company,market,deck,keywords,created_at&order=created_at.desc&limit=20`,
      )

      const query = deriveJobQuery(events)
      if (!query) {
        results.push({ userID: user.user_id, status: "skipped", reason: "no_recent_activity" })
        continue
      }

      const country = countryCode(events[0]?.market)
      const matches = await fetchJobMatches(query, country)
      const job = matches[0]
      if (!job) {
        results.push({ userID: user.user_id, status: "skipped", reason: "no_job_match", query })
        continue
      }

      const dedupeKey = `${dayKey()}:${job.id}`
      if (await alreadyDelivered(user.user_id, "job_match", dedupeKey)) {
        results.push({ userID: user.user_id, status: "skipped", reason: "already_delivered", query, jobID: job.id })
        continue
      }

      const title = `New ${query} role`
      const message = `${job.title} at ${job.company}`
      const payload = {
        aps: {
          alert: { title, body: message },
          sound: "default",
        },
        type: "job_match",
        job_id: job.id,
        url: job.applyURL ?? null,
      }

      if (dryRun) {
        results.push({ userID: user.user_id, status: "dry_run", query, jobID: job.id, title: job.title })
        continue
      }

      for (const device of devices) {
        try {
          await sendAPNs(device.device_token, payload)
          await writeDelivery(user.user_id, device.id, dedupeKey, title, message, "sent", null, job.applyURL ?? null)
          results.push({ userID: user.user_id, deviceID: device.id, status: "sent", query, jobID: job.id })
        } catch (error) {
          const providerMessage = error instanceof Error ? error.message : "Unknown APNs error"
          await writeDelivery(user.user_id, device.id, dedupeKey, title, message, "failed", providerMessage, job.applyURL ?? null)
          results.push({ userID: user.user_id, deviceID: device.id, status: "failed", error: providerMessage })
        }
      }
    }

    return json(200, { dryRun, results })
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown job alerts error"
    return json(500, { error: message })
  }
})
