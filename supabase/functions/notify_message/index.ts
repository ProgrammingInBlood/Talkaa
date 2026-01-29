import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type"
};

function base64urlEncode(data: Uint8Array): string {
  let str = btoa(String.fromCharCode(...data));
  return str.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function base64urlFromString(s: string): string {
  return base64urlEncode(new TextEncoder().encode(s));
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const clean = pem.replace(/-----BEGIN PRIVATE KEY-----/g, '').replace(/-----END PRIVATE KEY-----/g, '').replace(/\r?\n/g, '');
  const binary = atob(clean);
  const bytes = new Uint8Array(binary.length);
  for(let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

async function getAccessToken(clientEmail: string, privateKeyPem: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: clientEmail,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600
  };
  const unsigned = `${base64urlFromString(JSON.stringify(header))}.${base64urlFromString(JSON.stringify(claims))}`;
  const keyData = pemToArrayBuffer(privateKeyPem);
  const key = await crypto.subtle.importKey("pkcs8", keyData, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned));
  const jwt = `${unsigned}.${base64urlEncode(new Uint8Array(signature))}`;
  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt })
  });
  const tokenJson = await tokenRes.json();
  if (!tokenRes.ok) throw new Error(`OAuth token error: ${tokenRes.status} ${JSON.stringify(tokenJson)}`);
  const accessToken = tokenJson.access_token;
  if (!accessToken) throw new Error("No access_token in OAuth response");
  return accessToken;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    let projectId = (Deno.env.get("FCM_PROJECT_ID") || "").trim();
    let clientEmail = (Deno.env.get("GOOGLE_CLIENT_EMAIL") || "").trim();
    let privateKey = (Deno.env.get("GOOGLE_PRIVATE_KEY") || "").trim();
    const supabaseUrl = (Deno.env.get("SUPABASE_URL") || "").trim();
    const serviceRole = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "").trim();

    if (!projectId || !clientEmail || !privateKey) {
      return new Response(JSON.stringify({ error: "Missing FCM_PROJECT_ID / GOOGLE_CLIENT_EMAIL / GOOGLE_PRIVATE_KEY env" }), {
        status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" }
      });
    }
    if (!supabaseUrl || !serviceRole) {
      return new Response(JSON.stringify({ error: "Supabase env missing" }), {
        status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" }
      });
    }
    privateKey = privateKey.replace(/\\n/g, "\n");

    const supabase = createClient(supabaseUrl, serviceRole);
    const body = await req.json().catch(() => ({}));
    const recipient_id = (body?.recipient_id ?? "").toString();
    const chat_id = (body?.chat_id ?? "").toString();
    const message = body?.message ?? {};
    const sender_name = (body?.sender_name ?? "").toString();
    const avatar_url = (body?.avatar_url ?? "").toString();

    if (!recipient_id || !chat_id || !message) {
      return new Response(JSON.stringify({ error: "Missing recipient_id/chat_id/message" }), {
        status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" }
      });
    }

    const { data: tokens, error: tokenErr } = await supabase.from("device_tokens").select("token, platform").eq("user_id", recipient_id);
    if (tokenErr) {
      return new Response(JSON.stringify({ error: tokenErr.message }), {
        status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" }
      });
    }

    const registrationTokens = (tokens ?? []).map((t: any) => ({ token: t.token, platform: (t.platform || 'unknown').toString() })).filter((t: any) => !!t.token);
    if (!registrationTokens.length) {
      return new Response(JSON.stringify({ ok: true, sent: 0, reason: "no tokens" }), {
        status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" }
      });
    }

    // Extract message data - support both camelCase and snake_case inputs
    const content = (message?.content ?? "").toString();
    const type = (message?.messageType ?? message?.message_type ?? "text").toString();
    const fileUrl = (message?.fileUrl ?? message?.file_url ?? "").toString();
    const sender_id = (message?.senderId ?? message?.sender_id ?? "").toString();

    const title = sender_name ? `${sender_name}` : "New message";
    const bodyText = content ? content : (type === "image" ? "📷 Photo" : "Tap to view");

    const accessToken = await getAccessToken(clientEmail, privateKey);
    const endpointBase = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

    let successes = 0;
    const results: any[] = [];

    for (const entry of registrationTokens) {
      const token = entry.token;
      const platform = entry.platform;

      // FCM data payload - MUST use camelCase keys (FCM doesn't allow underscores)
      const baseMessage: any = {
        token,
        data: {
          chatId: chat_id,
          senderId: sender_id,
          messageType: type,
          content,
          fileUrl,
          senderName: sender_name,
          avatarUrl: avatar_url
        }
      };

      if (platform === 'ios') {
        baseMessage.apns = {
          headers: { 'apns-push-type': 'alert', 'apns-priority': '10' },
          payload: { aps: { alert: { title, body: bodyText }, sound: 'default', category: 'message' } }
        };
      } else if (platform === 'android') {
        baseMessage.android = { priority: 'high' };
      }

      const v1Payload = { message: baseMessage };
      const res = await fetch(endpointBase, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${accessToken}` },
        body: JSON.stringify(v1Payload)
      });
      const json = await res.json().catch(() => ({}));
      results.push({ token, platform, status: res.status, response: json });
      if (res.ok) successes++;
    }

    const overallStatus = successes > 0 ? 200 : 502;
    return new Response(JSON.stringify({ ok: successes > 0, sent: registrationTokens.length, successes, results, projectId }), {
      status: overallStatus, headers: { ...corsHeaders, "Content-Type": "application/json" }
    });
  } catch (e: any) {
    return new Response(JSON.stringify({ error: e?.message ?? "Unknown error" }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" }
    });
  }
});
