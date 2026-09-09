import { rankResources } from "./semantic_search.js";
import { queryCleanOrganizations } from "./firestore_rest.js";
import { normalizeIntent } from "./voice_intent.js";
import { classifyIntent } from "./gemini_intent.js";

function errorResponse(message, status = 400) {
  return Response.json({ error: message }, { status });
}

async function handleIntentClassification(body, env) {
  const transcript = body?.transcript;
  const languageCode = body?.languageCode;
  if (typeof transcript !== "string" || !transcript.trim()) {
    return errorResponse("transcript is required");
  }
  try {
    const intent = await classifyIntent(env, transcript, String(languageCode || ""));
    return Response.json({ intent });
  } catch (error) {
    console.error("classifyIntent failed", error);
    return errorResponse("Internal error", 500);
  }
}

async function handleResourceSearch(body, env) {
  const input = body?.data || body || {};
  const rawIntent = input.intent;
  if (!rawIntent || typeof rawIntent !== "object" || Array.isArray(rawIntent)) {
    return errorResponse("intent must be a structured object");
  }

  const requestedLimit = Number(input.limit || 50);
  if (!Number.isInteger(requestedLimit) || requestedLimit < 1) {
    return errorResponse("limit must be a positive integer");
  }
  const origin = input.origin;
  if (origin != null && (typeof origin !== "object"
    || !Number.isFinite(origin.lat) || !Number.isFinite(origin.lng))) {
    return errorResponse("origin must contain numeric lat and lng");
  }
  const radiusKm = Number(input.radiusKm || 50);
  if (!Number.isFinite(radiusKm) || radiusKm <= 0 || radiusKm > 200) {
    return errorResponse("radiusKm must be between 0 and 200");
  }

  try {
    const intent = normalizeIntent(rawIntent);
    const records = await queryCleanOrganizations(env);
    const results = rankResources(records, intent, requestedLimit, { origin, radiusKm });
    return Response.json({
      intent,
      results,
      count: results.length,
      note: "Eligibility signals were extracted for review only; no eligibility rule was inferred or applied.",
    });
  } catch (error) {
    console.error("searchResourcesByIntent failed", error);
    return errorResponse("Internal error", 500);
  }
}

export default {
  async fetch(request, env) {
    if (request.method !== "POST") return new Response("Method Not Allowed", { status: 405 });
    let body;
    try {
      body = await request.json();
    } catch {
      return errorResponse("Invalid JSON payload");
    }

    const { pathname } = new URL(request.url);
    if (pathname === "/intent") {
      return handleIntentClassification(body, env);
    }
    return handleResourceSearch(body, env);
  },
};