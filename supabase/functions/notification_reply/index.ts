import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type"
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = (Deno.env.get("SUPABASE_URL") || "").trim();
    const serviceRole = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "").trim();

    if (!supabaseUrl || !serviceRole) {
      return new Response(JSON.stringify({ error: "Supabase env missing" }), {
        status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" }
      });
    }

    // Get the user from the authorization header
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization header" }), {
        status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" }
      });
    }

    // Create admin client for database operations
    const supabaseAdmin = createClient(supabaseUrl, serviceRole);
    
    // Create user client to verify the token and get user info
    const supabaseUser = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY") || "", {
      global: { headers: { Authorization: authHeader } }
    });

    // Verify user and get their ID
    const { data: { user }, error: userError } = await supabaseUser.auth.getUser();
    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Invalid or expired token" }), {
        status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" }
      });
    }

    const senderId = user.id;

    // Parse request body
    const body = await req.json().catch(() => ({}));
    const chatId = (body?.chat_id ?? "").toString().trim();
    const text = (body?.text ?? "").toString().trim();

    if (!chatId || !text) {
      return new Response(JSON.stringify({ error: "Missing chat_id or text" }), {
        status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" }
      });
    }

    // Verify user is a participant of this chat
    const { data: participant, error: participantError } = await supabaseAdmin
      .from("chat_participants")
      .select("user_id")
      .eq("chat_id", chatId)
      .eq("user_id", senderId)
      .single();

    if (participantError || !participant) {
      return new Response(JSON.stringify({ error: "Not a participant of this chat" }), {
        status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" }
      });
    }

    // Insert the message
    const now = new Date().toISOString();
    const { data: message, error: insertError } = await supabaseAdmin
      .from("messages")
      .insert({
        chat_id: chatId,
        sender_id: senderId,
        content: text,
        message_type: "text",
        is_edited: false,
        is_deleted: false,
        created_at: now,
      })
      .select()
      .single();

    if (insertError) {
      console.error("Insert error:", insertError);
      return new Response(JSON.stringify({ error: "Failed to insert message", details: insertError.message }), {
        status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" }
      });
    }

    // Update the chat's last_message_at
    await supabaseAdmin
      .from("chats")
      .update({ last_message_at: now })
      .eq("id", chatId);

    // Increment unread_count for OTHER participants only (not the sender)
    // This fixes the bug where the sender's own message was being marked as unread
    await supabaseAdmin
      .from("chat_participants")
      .update({ 
        unread_count: supabaseAdmin.rpc('increment_unread', { row_chat_id: chatId, row_user_id: senderId })
      })
      .eq("chat_id", chatId)
      .neq("user_id", senderId);

    // Alternative: Use raw SQL to increment unread for others
    // This is more reliable than the RPC approach
    const { error: unreadError } = await supabaseAdmin.rpc('increment_unread_for_others', {
      p_chat_id: chatId,
      p_sender_id: senderId
    });

    if (unreadError) {
      // Fallback: manually increment unread count for other participants
      console.log("RPC not available, using manual update");
      const { data: otherParticipants } = await supabaseAdmin
        .from("chat_participants")
        .select("user_id, unread_count")
        .eq("chat_id", chatId)
        .neq("user_id", senderId);

      if (otherParticipants) {
        for (const p of otherParticipants) {
          await supabaseAdmin
            .from("chat_participants")
            .update({ unread_count: (p.unread_count || 0) + 1 })
            .eq("chat_id", chatId)
            .eq("user_id", p.user_id);
        }
      }
    }

    // Get sender profile for notification
    const { data: senderProfile } = await supabaseAdmin
      .from("profiles")
      .select("full_name, username, avatar_url")
      .eq("id", senderId)
      .single();

    const senderName = senderProfile?.full_name || senderProfile?.username || "New message";
    const avatarUrl = senderProfile?.avatar_url || "";

    // Get other participant(s) to send notification
    const { data: recipients } = await supabaseAdmin
      .from("chat_participants")
      .select("user_id")
      .eq("chat_id", chatId)
      .neq("user_id", senderId);

    // Send notification to each recipient via notify_message function
    if (recipients && recipients.length > 0) {
      for (const recipient of recipients) {
        try {
          // Call the notify_message function for each recipient
          await fetch(`${supabaseUrl}/functions/v1/notify_message`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "Authorization": `Bearer ${serviceRole}`,
            },
            body: JSON.stringify({
              recipient_id: recipient.user_id,
              chat_id: chatId,
              sender_name: senderName,
              avatar_url: avatarUrl,
              message: {
                messageType: "text",
                content: text,
                senderId: senderId,
              },
            }),
          });
        } catch (notifyError) {
          console.error("Notification error:", notifyError);
        }
      }
    }

    return new Response(JSON.stringify({ 
      ok: true, 
      message_id: message.id,
      chat_id: chatId 
    }), {
      status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" }
    });

  } catch (e: any) {
    console.error("Error:", e);
    return new Response(JSON.stringify({ error: e?.message ?? "Unknown error" }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" }
    });
  }
});
