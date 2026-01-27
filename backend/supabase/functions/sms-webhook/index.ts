// Supabase Edge Function: SMS Webhook for Twilio
// Handles incoming SMS, stores in Async DB, responds when @STEF mentioned

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY")!;
const TWILIO_ACCOUNT_SID = Deno.env.get("TWILIO_ACCOUNT_SID")!;
const TWILIO_AUTH_TOKEN = Deno.env.get("TWILIO_AUTH_TOKEN")!;
const TWILIO_PHONE_NUMBER = Deno.env.get("TWILIO_PHONE_NUMBER")!;

// Fixed IDs from migration
const STEF_USER_ID = "00000000-0000-0000-0000-000000000001";
const SMS_CONVERSATION_ID = "00000000-0000-0000-0000-000000000002";

// Mention patterns that trigger STEF response
const STEF_MENTIONS = [
  /@stef\b/i,
  /\bstef\b/i,
  /@claude\b/i,
  /\bhey stef\b/i,
];

interface TwilioMessage {
  From: string;
  To: string;
  Body: string;
  MessageSid: string;
}

// Validate Twilio webhook signature to prevent forged requests
async function validateTwilioSignature(req: Request, body: string): Promise<boolean> {
  const signature = req.headers.get("X-Twilio-Signature");
  if (!signature) {
    console.error("Missing X-Twilio-Signature header");
    return false;
  }

  // Get the full URL that Twilio called
  const url = req.url;

  // Parse form data and sort parameters alphabetically (Twilio's algorithm)
  const params = new URLSearchParams(body);
  const sortedParams: string[] = [];
  const keys = Array.from(params.keys()).sort();
  for (const key of keys) {
    sortedParams.push(key + params.get(key));
  }

  // Create the validation string: URL + sorted params
  const validationString = url + sortedParams.join("");

  // HMAC-SHA1 with auth token
  const encoder = new TextEncoder();
  const keyData = encoder.encode(TWILIO_AUTH_TOKEN);
  const messageData = encoder.encode(validationString);

  try {
    const key = await crypto.subtle.importKey(
      "raw",
      keyData,
      { name: "HMAC", hash: "SHA-1" },
      false,
      ["sign"]
    );
    const signatureBytes = await crypto.subtle.sign("HMAC", key, messageData);
    const computed = btoa(String.fromCharCode(...new Uint8Array(signatureBytes)));
    return computed === signature;
  } catch {
    return false;
  }
}

// Escape XML special characters to prevent injection attacks
function escapeXml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

// Validate phone number format (E.164)
function isValidPhoneNumber(phone: string): boolean {
  const phoneRegex = /^\+[1-9]\d{6,14}$/;
  return phoneRegex.test(phone);
}

serve(async (req) => {
  try {
    // Clone request to read body for validation
    const bodyText = await req.clone().text();

    // Validate Twilio signature to prevent forged requests
    const isValid = await validateTwilioSignature(req, bodyText);
    if (!isValid) {
      console.error("Invalid Twilio signature - rejecting request");
      return new Response("Forbidden", { status: 403 });
    }

    // Parse Twilio webhook (form-urlencoded)
    const formData = await req.formData();
    const message: TwilioMessage = {
      From: formData.get("From") as string,
      To: formData.get("To") as string,
      Body: formData.get("Body") as string,
      MessageSid: formData.get("MessageSid") as string,
    };

    // Validate phone number format
    if (!isValidPhoneNumber(message.From)) {
      console.error("Invalid phone number format");
      return twimlResponse("Invalid phone number");
    }

    // Sanitize phone number for logging (don't expose full number in logs)
    const sanitizedPhone = message.From.slice(0, 4) + "***" + message.From.slice(-2);
    console.log(`SMS from ${sanitizedPhone}: [message received]`);

    // Initialize Supabase client with service role
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    // Get or create user by phone number
    const { data: userData, error: userError } = await supabase.rpc(
      "get_or_create_user_by_phone",
      {
        p_phone: message.From,
        p_display_name: message.From, // Will be updated later with real name
      }
    );

    if (userError) {
      console.error("Error getting/creating user:", userError);
      return twimlResponse("Error processing message");
    }

    const userId = userData;

    // Ensure user is a participant in the SMS conversation
    await supabase.from("conversation_participants").upsert(
      {
        conversation_id: SMS_CONVERSATION_ID,
        user_id: userId,
        role: "member",
      },
      { onConflict: "conversation_id,user_id" }
    );

    // Store the incoming message
    const { error: msgError } = await supabase.from("messages").insert({
      conversation_id: SMS_CONVERSATION_ID,
      sender_id: userId,
      content_raw: message.Body,
      source: "sms",
      agent_context: { twilio_sid: message.MessageSid },
    });

    if (msgError) {
      console.error("Error storing message:", msgError);
    }

    // Check if STEF was mentioned
    const shouldRespond = STEF_MENTIONS.some((pattern) =>
      pattern.test(message.Body)
    );

    if (shouldRespond) {
      // Get conversation history for context
      const { data: history } = await supabase
        .from("messages")
        .select(
          `
          content_raw,
          content_processed,
          is_from_agent,
          created_at,
          sender:users(display_name, github_handle)
        `
        )
        .eq("conversation_id", SMS_CONVERSATION_ID)
        .order("created_at", { ascending: false })
        .limit(20);

      // Build context for Claude
      const conversationContext = (history || [])
        .reverse()
        .map((msg: any) => {
          const sender = msg.is_from_agent
            ? "STEF"
            : msg.sender?.display_name || "Unknown";
          return `${sender}: ${msg.content_raw}`;
        })
        .join("\n");

      // Call Claude API
      const claudeResponse = await fetch(
        "https://api.anthropic.com/v1/messages",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "x-api-key": ANTHROPIC_API_KEY,
            "anthropic-version": "2023-06-01",
          },
          body: JSON.stringify({
            model: "claude-sonnet-4-20250514",
            max_tokens: 300, // Keep SMS responses concise
            system: `You are STEF, an AI participant in a group SMS chat between Bill (chickensintrees) and Noah (ginzatron). They are developers collaborating on the Async project - an AI-mediated messaging app.

Your role:
- Be helpful, concise, and conversational (this is SMS, keep it short)
- You have context of their project from previous conversations
- When asked about project status, reference what you know
- Be witty but professional
- Keep responses under 160 characters when possible (SMS limit)

Current conversation:`,
            messages: [
              {
                role: "user",
                content: `${conversationContext}\n\nRespond to the latest message. Keep it brief for SMS.`,
              },
            ],
          }),
        }
      );

      const claudeData = await claudeResponse.json();
      const stefResponse =
        claudeData.content?.[0]?.text || "Sorry, I hit a snag. Try again?";

      // Store STEF's response
      await supabase.from("messages").insert({
        conversation_id: SMS_CONVERSATION_ID,
        sender_id: STEF_USER_ID,
        content_raw: stefResponse,
        is_from_agent: true,
        source: "sms",
      });

      // Send SMS response via Twilio
      await sendTwilioSMS(message.From, stefResponse);

      // Also send to other participants (group chat behavior)
      const { data: participants } = await supabase
        .from("conversation_participants")
        .select("user:users(phone_number)")
        .eq("conversation_id", SMS_CONVERSATION_ID)
        .neq("user_id", userId)
        .neq("user_id", STEF_USER_ID);

      for (const p of participants || []) {
        const phone = (p as any).user?.phone_number;
        if (phone) {
          await sendTwilioSMS(phone, `STEF: ${stefResponse}`);
        }
      }

      return twimlResponse(); // Empty TwiML, we're sending via API
    }

    // No mention, just acknowledge receipt
    return twimlResponse();
  } catch (error) {
    console.error("Webhook error:", error);
    return twimlResponse("Error processing message");
  }
});

// Send SMS via Twilio REST API
async function sendTwilioSMS(to: string, body: string) {
  const url = `https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/Messages.json`;

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Authorization:
        "Basic " + btoa(`${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}`),
    },
    body: new URLSearchParams({
      To: to,
      From: TWILIO_PHONE_NUMBER,
      Body: body,
    }),
  });

  if (!response.ok) {
    console.error("Twilio send failed:", await response.text());
  }
}

// Return TwiML response (empty or with message)
// Uses escapeXml to prevent XML injection attacks
function twimlResponse(message?: string) {
  const body = message
    ? `<?xml version="1.0" encoding="UTF-8"?><Response><Message>${escapeXml(message)}</Message></Response>`
    : `<?xml version="1.0" encoding="UTF-8"?><Response></Response>`;

  return new Response(body, {
    headers: { "Content-Type": "text/xml" },
  });
}
