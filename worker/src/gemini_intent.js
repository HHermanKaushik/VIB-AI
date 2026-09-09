// Transcript -> canonical command intent, via Gemini. This is the fallback
// path lib/command_lexicon_service.dart calls when its local phrase/fuzzy
// lexicon match misses. It classifies short spoken commands only (yes/no,
// next/repeat/stop, call/save/share, etc.) — a separate, narrower job from
// the structured service/location/eligibility extraction used by the
// resource-search flow.

export const CANONICAL_INTENTS = [
  "next", "repeat", "more_detail", "stop", "yes", "no",
  "call", "save", "share", "directions", "change_language", "help",
];

const MODEL = "gemini-3.6-flash";

function buildPrompt(transcript, languageCode) {
  return [
    "You classify one short spoken command from a visually-impaired user of an",
    "Indian accessibility app for finding disability support resources. The",
    `user's active language is ${languageCode || "unknown"}. Their speech was`,
    "transcribed as:",
    JSON.stringify(String(transcript)),
    "",
    "Pick exactly one label from this fixed list that best matches what they",
    "meant:",
    CANONICAL_INTENTS.join(", "),
    "",
    "Respond only with the JSON object the schema requires. Never invent a",
    "label outside this exact list, and never answer the user's question or",
    "add commentary — classification only.",
  ].join("\n");
}

export async function classifyIntent(env, transcript, languageCode) {
  const apiKey = env.GEMINI_API_KEY;
  if (!apiKey) throw new Error("GEMINI_API_KEY is not configured");

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${encodeURIComponent(apiKey)}`;
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ parts: [{ text: buildPrompt(transcript, languageCode) }] }],
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: {
          type: "OBJECT",
          properties: {
            intent: { type: "STRING", enum: CANONICAL_INTENTS },
          },
          required: ["intent"],
        },
      },
    }),
  });

  if (!response.ok) {
    throw new Error(`Gemini request failed: ${response.status}`);
  }

  const data = await response.json();
  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) throw new Error("Gemini returned no content");

  const parsed = JSON.parse(text);
  const intent = parsed?.intent;
  return CANONICAL_INTENTS.includes(intent) ? intent : null;
}
