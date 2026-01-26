import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.168.0/testing/asserts.ts";

// ============================================================================
// Message Preview Formatting Tests
// ============================================================================

function formatMessagePreview(rawContent: string, maxLength = 100): string {
  if (rawContent.length <= maxLength) {
    return rawContent;
  }
  return rawContent.slice(0, maxLength) + "...";
}

function formatSMSBody(senderName: string, preview: string): string {
  return `Async: ${senderName} sent you a message:\n"${preview}"`;
}

Deno.test("Preview: short message is not truncated", () => {
  const message = "Hello there";
  const preview = formatMessagePreview(message);
  assertEquals(preview, "Hello there");
  assertEquals(preview.includes("..."), false);
});

Deno.test("Preview: long message is truncated at 100 chars", () => {
  const message = "a".repeat(150);
  const preview = formatMessagePreview(message);
  assertEquals(preview.length, 103); // 100 + "..."
  assertEquals(preview.endsWith("..."), true);
});

Deno.test("Preview: exactly 100 chars is not truncated", () => {
  const message = "b".repeat(100);
  const preview = formatMessagePreview(message);
  assertEquals(preview, message);
  assertEquals(preview.includes("..."), false);
});

Deno.test("SMS body: includes sender name", () => {
  const body = formatSMSBody("Bill", "Hello");
  assertStringIncludes(body, "Bill");
  assertStringIncludes(body, "Async:");
});

Deno.test("SMS body: includes message preview", () => {
  const body = formatSMSBody("Noah", "Check this out");
  assertStringIncludes(body, "Check this out");
});

// ============================================================================
// Quiet Hours Logic Tests
// ============================================================================

interface QuietHoursConfig {
  start: string; // "HH:MM" format
  end: string;   // "HH:MM" format
}

function isQuietHours(currentTime: string, config: QuietHoursConfig): boolean {
  const [currentHour, currentMin] = currentTime.split(":").map(Number);
  const [startHour, startMin] = config.start.split(":").map(Number);
  const [endHour, endMin] = config.end.split(":").map(Number);

  const currentMinutes = currentHour * 60 + currentMin;
  const startMinutes = startHour * 60 + startMin;
  const endMinutes = endHour * 60 + endMin;

  // Handle overnight spans (e.g., 22:00 to 07:00)
  if (startMinutes > endMinutes) {
    return currentMinutes >= startMinutes || currentMinutes < endMinutes;
  }

  return currentMinutes >= startMinutes && currentMinutes < endMinutes;
}

const defaultQuietHours: QuietHoursConfig = { start: "22:00", end: "07:00" };

Deno.test("Quiet hours: 2:30 AM is quiet (overnight span)", () => {
  const result = isQuietHours("02:30", defaultQuietHours);
  assertEquals(result, true);
});

Deno.test("Quiet hours: 23:00 is quiet (after start)", () => {
  const result = isQuietHours("23:00", defaultQuietHours);
  assertEquals(result, true);
});

Deno.test("Quiet hours: 6:59 AM is quiet (before end)", () => {
  const result = isQuietHours("06:59", defaultQuietHours);
  assertEquals(result, true);
});

Deno.test("Quiet hours: 7:00 AM is NOT quiet (at end)", () => {
  const result = isQuietHours("07:00", defaultQuietHours);
  assertEquals(result, false);
});

Deno.test("Quiet hours: 14:00 is NOT quiet (afternoon)", () => {
  const result = isQuietHours("14:00", defaultQuietHours);
  assertEquals(result, false);
});

Deno.test("Quiet hours: 21:59 is NOT quiet (before start)", () => {
  const result = isQuietHours("21:59", defaultQuietHours);
  assertEquals(result, false);
});

// ============================================================================
// Rate Limiting Logic Tests
// ============================================================================

function canSendNotification(
  lastNotificationTime: Date | null,
  rateLimitSeconds: number
): boolean {
  if (!lastNotificationTime) return true;
  const elapsed = Date.now() - lastNotificationTime.getTime();
  return elapsed >= rateLimitSeconds * 1000;
}

Deno.test("Rate limit: allows first notification (no previous)", () => {
  const canSend = canSendNotification(null, 60);
  assertEquals(canSend, true);
});

Deno.test("Rate limit: blocks within cooldown period", () => {
  const thirtySecondsAgo = new Date(Date.now() - 30000);
  const canSend = canSendNotification(thirtySecondsAgo, 60);
  assertEquals(canSend, false);
});

Deno.test("Rate limit: allows after cooldown period", () => {
  const seventySecondsAgo = new Date(Date.now() - 70000);
  const canSend = canSendNotification(seventySecondsAgo, 60);
  assertEquals(canSend, true);
});

Deno.test("Rate limit: allows exactly at cooldown boundary", () => {
  const exactlySixtySecondsAgo = new Date(Date.now() - 60000);
  const canSend = canSendNotification(exactlySixtySecondsAgo, 60);
  assertEquals(canSend, true);
});

// ============================================================================
// Participant Filtering Tests
// ============================================================================

interface Participant {
  user_id: string;
  phone_number?: string;
}

const STEF_USER_ID = "00000000-0000-0000-0000-000000000001";

function getNotificationRecipients(
  participants: Participant[],
  senderId: string
): Participant[] {
  return participants.filter(
    (p) => p.user_id !== senderId && p.user_id !== STEF_USER_ID && p.phone_number
  );
}

Deno.test("Recipients: excludes sender", () => {
  const participants: Participant[] = [
    { user_id: "user-1", phone_number: "+1111" },
    { user_id: "user-2", phone_number: "+2222" },
  ];
  const recipients = getNotificationRecipients(participants, "user-1");
  assertEquals(recipients.length, 1);
  assertEquals(recipients[0].user_id, "user-2");
});

Deno.test("Recipients: excludes STEF", () => {
  const participants: Participant[] = [
    { user_id: "user-1", phone_number: "+1111" },
    { user_id: STEF_USER_ID, phone_number: "+0000" },
    { user_id: "user-2", phone_number: "+2222" },
  ];
  const recipients = getNotificationRecipients(participants, "user-1");
  assertEquals(recipients.length, 1);
  assertEquals(recipients[0].user_id, "user-2");
});

Deno.test("Recipients: excludes users without phone numbers", () => {
  const participants: Participant[] = [
    { user_id: "user-1", phone_number: "+1111" },
    { user_id: "user-2" }, // No phone
    { user_id: "user-3", phone_number: "+3333" },
  ];
  const recipients = getNotificationRecipients(participants, "user-1");
  assertEquals(recipients.length, 1);
  assertEquals(recipients[0].user_id, "user-3");
});

Deno.test("Recipients: returns empty array when no valid recipients", () => {
  const participants: Participant[] = [
    { user_id: "user-1", phone_number: "+1111" },
  ];
  const recipients = getNotificationRecipients(participants, "user-1");
  assertEquals(recipients.length, 0);
});
