import { createClient } from "jsr:@supabase/supabase-js@2"

const corsHeaders = {
  "Content-Type": "application/json",
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed." }), {
      status: 405,
      headers: corsHeaders,
    })
  }

  const authorization = request.headers.get("Authorization")
  const anonKey = request.headers.get("apikey") ?? Deno.env.get("SUPABASE_ANON_KEY")
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
  const supabaseURL = Deno.env.get("SUPABASE_URL")

  if (!authorization?.startsWith("Bearer ") || !anonKey || !serviceRoleKey || !supabaseURL) {
    return new Response(JSON.stringify({ error: "Missing configuration." }), {
      status: 500,
      headers: corsHeaders,
    })
  }

  const accessToken = authorization.replace("Bearer ", "").trim()

  const userResponse = await fetch(`${supabaseURL}/auth/v1/user`, {
    method: "GET",
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
  })

  if (!userResponse.ok) {
    return new Response(JSON.stringify({ error: "Unauthorized." }), {
      status: 401,
      headers: corsHeaders,
    })
  }

  const user = await userResponse.json()

  if (!user?.id) {
    return new Response(JSON.stringify({ error: "Unauthorized." }), {
      status: 401,
      headers: corsHeaders,
    })
  }

  const adminClient = createClient(supabaseURL, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  })

  const { error: deleteError } = await adminClient.auth.admin.deleteUser(user.id)

  if (deleteError) {
    return new Response(
      JSON.stringify({ error: deleteError.message || "Could not delete account." }),
      {
        status: 400,
        headers: corsHeaders,
      }
    )
  }

  return new Response(JSON.stringify({ success: true }), {
    status: 200,
    headers: corsHeaders,
  })
})
