#!/usr/bin/env node
/* Import Phase 0 JSONL into Firestore using the Admin SDK.
 * Authentication comes from Application Default Credentials or
 * GOOGLE_APPLICATION_CREDENTIALS; no service-account key is stored here.
 */

const fs = require("node:fs");
const readline = require("node:readline");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, GeoPoint, Timestamp } = require("firebase-admin/firestore");

const BATCH_SIZE = 400;
const DEFAULT_INPUT = "migration_output/organizations.jsonl";
const args = process.argv.slice(2);
const inputPath = args.find((arg) => !arg.startsWith("--")) || DEFAULT_INPUT;
const includeReview = args.includes("--include-review");
const projectIndex = args.indexOf("--project-id");
const projectId = projectIndex >= 0 ? args[projectIndex + 1] : undefined;
const collectionIndex = args.indexOf("--collection");
const collectionName = collectionIndex >= 0 ? args[collectionIndex + 1] : "organizations";

if (!fs.existsSync(inputPath)) {
  console.error(`Input file not found: ${inputPath}`);
  process.exit(1);
}

initializeApp(projectId ? { projectId } : undefined);
const db = getFirestore();

function prepare(record) {
  const copy = { ...record };
  if (copy.location && copy.location.geo && typeof copy.location.geo === "object") {
    const { lat, lng } = copy.location.geo;
    if (Number.isFinite(Number(lat)) && Number.isFinite(Number(lng))) {
      copy.location = { ...copy.location, geo: new GeoPoint(Number(lat), Number(lng)) };
    }
  }
  if (copy.provenance && copy.provenance.migratedAt) {
    copy.provenance = {
      ...copy.provenance,
      migratedAt: Timestamp.fromDate(new Date(copy.provenance.migratedAt)),
    };
  }
  return copy;
}

async function flush(records) {
  if (!records.length) return;
  const batch = db.batch();
  for (const record of records) {
    if (!record.id) throw new Error("Every record must have an id");
    batch.set(db.collection(collectionName).doc(record.id), prepare(record), { merge: true });
  }
  await batch.commit();
}

async function main() {
  const input = readline.createInterface({ input: fs.createReadStream(inputPath), crlfDelay: Infinity });
  let pending = [];
  let read = 0;
  let imported = 0;
  let skipped = 0;

  for await (const line of input) {
    if (!line.trim()) continue;
    read += 1;
    const record = JSON.parse(line);
    if (!includeReview && record.review?.status !== "clean") {
      skipped += 1;
      continue;
    }
    pending.push(record);
    if (pending.length === BATCH_SIZE) {
      await flush(pending);
      imported += pending.length;
      pending = [];
      console.log(`Imported ${imported} records...`);
    }
  }

  await flush(pending);
  imported += pending.length;
  console.log(JSON.stringify({ inputPath, collectionName, read, imported, skipped, includeReview }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
