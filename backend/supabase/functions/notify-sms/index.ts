// Supabase Edge Function: SMS Notification for new messages
// Sends SMS via Twilio with rate limiting (1 per minute max)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const TWILIO_ACCOUNT_SID = Deno.env.get('TWILIO_ACCOUNT_SID')!
const TWILIO_AUTH_TOKEN = Deno.env.get('TWILIO_AUTH_TOKEN')!
const TWILIO_PHONE_NUMBER = Deno.env.get('TWILIO_PHONE_NUMBER')!
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

interface MessagePayload {
  type: 'INSERT'
  table: 'messages'
  record: {
    id: string
    conversation_id: string
    sender_id: string
    content_raw: string
    created_at: string
  }
}

serve(async (req) => {
  try {
    const payload: MessagePayload = await req.json()

    // Only process new message inserts
    if (payload.type !== 'INSERT' || payload.table !== 'messages') {
      return new Response(JSON.stringify({ skipped: true }), { status: 200 })
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
    const message = payload.record

    // Get conversation participants (excluding sender)
    const { data: participants } = await supabase
      .from('conversation_participants')
      .select('user_id')
      .eq('conversation_id', message.conversation_id)
      .neq('user_id', message.sender_id)

    if (!participants || participants.length === 0) {
      return new Response(JSON.stringify({ skipped: 'no recipients' }), { status: 200 })
    }

    // Get sender info for the notification message
    const { data: sender } = await supabase
      .from('users')
      .select('display_name, github_handle')
      .eq('id', message.sender_id)
      .single()

    const senderName = sender?.display_name || sender?.github_handle || 'Someone'

    // Check each participant for notification preferences
    for (const participant of participants) {
      const { data: prefs } = await supabase
        .from('notification_preferences')
        .select('*')
        .eq('user_id', participant.user_id)
        .single()

      if (!prefs || !prefs.sms_enabled || !prefs.phone_number) {
        console.log(`Skipping user ${participant.user_id}: SMS not enabled or no phone`)
        continue
      }

      // Check rate limiting
      const rateLimitSeconds = prefs.rate_limit_seconds || 60
      const { data: canSend } = await supabase
        .rpc('can_send_notification', {
          p_user_id: participant.user_id,
          p_rate_limit_seconds: rateLimitSeconds
        })

      if (!canSend) {
        console.log(`Rate limited for user ${participant.user_id}`)
        continue
      }

      // Check quiet hours (optional)
      if (prefs.quiet_hours_start && prefs.quiet_hours_end) {
        const now = new Date()
        const currentTime = now.toTimeString().slice(0, 5) // HH:MM
        const start = prefs.quiet_hours_start.slice(0, 5)
        const end = prefs.quiet_hours_end.slice(0, 5)

        // Simple quiet hours check (doesn't handle overnight spans perfectly)
        if (currentTime >= start || currentTime < end) {
          console.log(`Quiet hours for user ${participant.user_id}`)
          continue
        }
      }

      // Send SMS via Twilio
      const messagePreview = message.content_raw.slice(0, 100)
      const smsBody = `Async: ${senderName} sent you a message:\n"${messagePreview}${message.content_raw.length > 100 ? '...' : ''}"`

      const twilioUrl = `https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/Messages.json`

      const twilioResponse = await fetch(twilioUrl, {
        method: 'POST',
        headers: {
          'Authorization': 'Basic ' + btoa(`${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}`),
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({
          To: prefs.phone_number,
          From: TWILIO_PHONE_NUMBER,
          Body: smsBody,
        }),
      })

      if (twilioResponse.ok) {
        // Log the notification for rate limiting
        await supabase.from('notification_log').insert({
          user_id: participant.user_id,
          notification_type: 'sms',
          message_preview: messagePreview,
          phone_number: prefs.phone_number,
        })
        console.log(`SMS sent to ${prefs.phone_number}`)
      } else {
        const error = await twilioResponse.text()
        console.error(`Twilio error: ${error}`)
      }
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { 'Content-Type': 'application/json' },
      status: 200,
    })

  } catch (error) {
    console.error('Error:', error)
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { 'Content-Type': 'application/json' },
      status: 500,
    })
  }
})
