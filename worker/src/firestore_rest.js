const TOKEN_URL = "https://oauth2.googleapis.com/token";
const FIRESTORE_SCOPE = "https://www.googleapis.com/auth/datastore";

function base64Url(value) {
  const bytes = new TextEncoder().encode(value);
  let binary = "";
  bytes.forEach((byte) => { binary += String.fromCharCode(byte); });
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function firestoreValue(value) {
  const key = Object.keys(value)[0];
  const raw = value[key];
  if (key === "mapValue") return Object.fromEntries(Object.entries(raw.fields || {}).map(([name, item]) => [name, firestoreValue(item)]));
  if (key === "arrayValue") return (raw.values || []).map(firestoreValue);
  if (key === "nullValue") return null;
  if (key === "integerValue") return Number(raw);
  if (key === "doubleValue") return Number(raw);
  if (key === "booleanValue" || key === "stringValue" || key === "timestampValue") return raw;
  if (key === "geoPointValue") return { lat: raw.latitude, lng: raw.longitude };
  return raw;
}

function documentData(document) {
  return Object.fromEntries(Object.entries(document.fields || {}).map(([name, value]) => [name, firestoreValue(value)]));
}

async function serviceAccountToken(env) {
  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64Url(JSON.stringify({ iss: env.FIREBASE_CLIENT_EMAIL, scope: FIRESTORE_SCOPE, aud: TOKEN_URL, iat: now, exp: now + 3600 }));
  const keyData = env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, "\n");
  const pem = keyData.replace("-----BEGIN PRIVATE KEY-----", "").replace("-----END PRIVATE KEY-----", "").replace(/\s/g, "");
  const binary = Uint8Array.from(atob(pem), (character) => character.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", binary, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`));
  let binarySignature = "";
  new Uint8Array(signature).forEach((byte) => { binarySignature += String.fromCharCode(byte); });
  const response = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${header}.${claims}.${btoa(binarySignature).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")}`,
  });
  if (!response.ok) throw new Error(`Google OAuth token request failed: ${response.status}`);
  return (await response.json()).access_token;
}

export async function queryCleanOrganizations(env) {
  const token = await serviceAccountToken(env);
  const url = `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(env.FIREBASE_PROJECT_ID)}/databases/(default)/documents:runQuery`;
  const response = await fetch(url, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ structuredQuery: {
      from: [{ collectionId: "organizations" }],
      where: { fieldFilter: { field: { fieldPath: "review.status" }, op: "EQUAL", value: { stringValue: "clean" } } },
    } }),
  });
  if (!response.ok) throw new Error(`Firestore query failed: ${response.status}`);
  const rows = await response.json();
  return rows.filter((row) => row.document).map((row) => ({
    id: row.document.name.split("/").pop(),
    ...documentData(row.document),
  }));
}

// Shared REST write primitive for future Worker handlers that need Firestore writes.
export async function commitFirestoreWrites(env, writes) {
  const token = await serviceAccountToken(env);
  const url = `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(env.FIREBASE_PROJECT_ID)}/databases/(default)/documents:commit`;
  const response = await fetch(url, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ writes }),
  });
  if (!response.ok) throw new Error(`Firestore commit failed: ${response.status}`);
  return response.json();
}