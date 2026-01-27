import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.168.0/testing/asserts.ts";

// STEF mention patterns (from sms-webhook/index.ts)
const STEF_MENTIONS = [
  /@stef\b/i,
  /\bstef\b/i,
  /@claude\b/i,
  /\bhey stef\b/i,
];

// Helper: Check if message should trigger STEF response
function shouldTriggerSTEF(message: string): boolean {
  return STEF_MENTIONS.some((pattern) => pattern.test(message));
}

// Helper: Generate TwiML response
function twimlResponse(message?: string): string {
  return message
    ? `<?xml version="1.0" encoding="UTF-8"?><Response><Message>${message}</Message></Response>`
    : `<?xml version="1.0" encoding="UTF-8"?><Response></Response>`;
}

// ============================================================================
// STEF Mention Detection Tests
// ============================================================================

Deno.test("STEF mention: @stef triggers response", () => {
  assertEquals(shouldTriggerSTEF("@stef what's up"), true);
});

Deno.test("STEF mention: @STEF (uppercase) triggers response", () => {
  assertEquals(shouldTriggerSTEF("@STEF help me"), true);
});

Deno.test("STEF mention: standalone 'stef' triggers response", () => {
  assertEquals(shouldTriggerSTEF("hey stef help me"), true);
});

Deno.test("STEF mention: @claude triggers response", () => {
  assertEquals(shouldTriggerSTEF("@claude are you there"), true);
});

Deno.test("STEF mention: 'hey stef' triggers response", () => {
  assertEquals(shouldTriggerSTEF("hey stef, how's the project"), true);
});

Deno.test("STEF mention: 'stefan' does NOT trigger (word boundary)", () => {
  assertEquals(shouldTriggerSTEF("stefan wrote code"), false);
});

Deno.test("STEF mention: 'forestef' does NOT trigger (word boundary)", () => {
  assertEquals(shouldTriggerSTEF("forestef is here"), false);
});

Deno.test("STEF mention: regular message does NOT trigger", () => {
  assertEquals(shouldTriggerSTEF("just a regular message"), false);
});

Deno.test("STEF mention: empty message does NOT trigger", () => {
  assertEquals(shouldTriggerSTEF(""), false);
});

Deno.test("STEF mention: case insensitive - 'Stef' triggers", () => {
  assertEquals(shouldTriggerSTEF("Stef, check this out"), true);
});

// ============================================================================
// TwiML Response Tests
// ============================================================================

Deno.test("TwiML: empty response is valid XML", () => {
  const response = twimlResponse();
  assertStringIncludes(response, '<?xml version="1.0"');
  assertStringIncludes(response, "<Response></Response>");
});

Deno.test("TwiML: message response contains Message element", () => {
  const response = twimlResponse("Hello world");
  assertStringIncludes(response, "<Message>Hello world</Message>");
});

Deno.test("TwiML: response has correct content type structure", () => {
  const response = twimlResponse("Test");
  assertStringIncludes(response, '<?xml version="1.0" encoding="UTF-8"?>');
  assertStringIncludes(response, "<Response>");
  assertStringIncludes(response, "</Response>");
});

// ============================================================================
// Conversation Context Building Tests
// ============================================================================

interface MockMessage {
  is_from_agent: boolean;
  sender?: { display_name: string };
  content_raw: string;
}

function buildConversationContext(history: MockMessage[]): string {
  return history
    .map((msg) => {
      const sender = msg.is_from_agent
        ? "STEF"
        : msg.sender?.display_name || "Unknown";
      return `${sender}: ${msg.content_raw}`;
    })
    .join("\n");
}

Deno.test("Context: formats messages with sender names", () => {
  const history: MockMessage[] = [
    { is_from_agent: false, sender: { display_name: "Bill" }, content_raw: "Hello" },
    { is_from_agent: true, content_raw: "Hi Bill" },
  ];

  const context = buildConversationContext(history);
  assertEquals(context, "Bill: Hello\nSTEF: Hi Bill");
});

Deno.test("Context: handles missing sender name", () => {
  const history: MockMessage[] = [
    { is_from_agent: false, content_raw: "Who am I?" },
  ];

  const context = buildConversationContext(history);
  assertEquals(context, "Unknown: Who am I?");
});

Deno.test("Context: handles empty history", () => {
  const history: MockMessage[] = [];
  const context = buildConversationContext(history);
  assertEquals(context, "");
});

Deno.test("Context: mixed STEF and user messages", () => {
  const history: MockMessage[] = [
    { is_from_agent: false, sender: { display_name: "Noah" }, content_raw: "Hey" },
    { is_from_agent: true, content_raw: "What's up?" },
    { is_from_agent: false, sender: { display_name: "Noah" }, content_raw: "Working on async" },
    { is_from_agent: true, content_raw: "Nice!" },
  ];

  const context = buildConversationContext(history);
  assertStringIncludes(context, "Noah: Hey");
  assertStringIncludes(context, "STEF: What's up?");
  assertStringIncludes(context, "Noah: Working on async");
  assertStringIncludes(context, "STEF: Nice!");
});

// ============================================================================
// Phone Number Validation Tests
// ============================================================================

Deno.test("Phone: valid US number format", () => {
  const phone = "+14125123593";
  const isValid = phone.startsWith("+1") && phone.length === 12;
  assertEquals(isValid, true);
});

Deno.test("Phone: international number detection", () => {
  const phone = "+447911123456";
  const isUS = phone.startsWith("+1") && phone.length === 12;
  assertEquals(isUS, false);
});
