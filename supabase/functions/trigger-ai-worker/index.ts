import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const AI_WORKER_URL    = Deno.env.get("AI_WORKER_URL")!
const SUPABASE_URL     = Deno.env.get("SUPABASE_URL")!
const SUPABASE_SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!

serve(async (req) => {
  try {
    const payload = await req.json()
    const record  = payload.record  // new report row

    if (!record?.id || !record?.image_url) {
      return new Response("Missing report data", { status: 400 })
    }

    console.log(`Triggering AI analysis for report ${record.id}`)

    // Call FastAPI AI worker
    const response = await fetch(`${AI_WORKER_URL}/analyze`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        report_id: record.id,
        image_url: record.image_url,
      }),
    })

    if (!response.ok) {
      const err = await response.text()
      console.error("AI worker error:", err)
      return new Response(`AI worker failed: ${err}`, { status: 500 })
    }

    const result = await response.json()
    console.log(`AI analysis complete for ${record.id}:`, result.severity)

    return new Response(JSON.stringify({ success: true, result }), {
      headers: { "Content-Type": "application/json" },
    })
  } catch (error) {
    console.error("Edge function error:", error)
    return new Response(`Error: ${error.message}`, { status: 500 })
  }
})
