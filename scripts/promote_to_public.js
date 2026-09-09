#!/usr/bin/env node
/* Promote reviewed migration data into the public-facing organizations_public
 * collection using the Admin SDK. Authentication comes from Application
 * Default Credentials or GOOGLE_APPLICATION_CREDENTIALS; no service-account
 * key is stored here.
 *
 * Sources (never mutated by this script):
 *   - migration_output/organizations.jsonl        review.status == "clean"
 *   - migration_output/organizations_reviewed.jsonl review.status == "verified"
 *
 * The two sources are merged by id. A verified record always supersedes a
 * clean-flagged record with the same id (this should not normally happen,
 * since review promotes needs_review -> verified/rejected, but it is
 * detected and logged rather than resolved silently).
 *
 * Safe to re-run: documents are written with the migration's own id as the
 * Firestore document id and fully overwritten, so re-running as more
 * records get verified never creates duplicates.
 */

const fs = require("node:fs");
const readline = require("node:readline");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, GeoPoint, Timestamp } = require("firebase-admin/firestore");

const BATCH_SIZE = 400;
const DEFAULT_CLEAN_INPUT = "migration_output/organizations.jsonl";
const DEFAULT_REVIEWED_INPUT = "migration_output/organizations_reviewed.jsonl";
const DEFAULT_COLLECTION = "organizations_public";

const args = process.argv.slice(2);
function flagValue(name, fallback) {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : fallback;
}

const cleanInputPath = flagValue("--clean-input", DEFAULT_CLEAN_INPUT);
const reviewedInputPath = flagValue("--reviewed-input", DEFAULT_REVIEWED_INPUT);
const collectionName = flagValue("--collection", DEFAULT_COLLECTION);
const projectId = flagValue("--project-id", undefined);

for (const path of [cleanInputPath, reviewedInputPath]) {
  if (!fs.existsSync(path)) {
    console.error(`Input file not found: ${path}`);
    process.exit(1);
  }
}

initializeApp(projectId ? { projectId } : undefined);
const db = getFirestore();

async function readJsonlRecords(path) {
  const input = readline.createInterface({ input: fs.createReadStream(path), crlfDelay: Infinity });
  const records = [];
  for await (const line of input) {
    if (!line.trim()) continue;
    records.push(JSON.parse(line));
  }
  return records;
}

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
  if (copy.review && copy.review.reviewedAt) {
    copy.review = {
      ...copy.review,
      reviewedAt: Timestamp.fromDate(new Date(copy.review.reviewedAt)),
    };
  }
  return copy;
}

async function buildMergedSet() {
  const cleanRecords = (await readJsonlRecords(cleanInputPath))
    .filter((record) => record.review?.status === "clean");
  const verifiedRecords = (await readJsonlRecords(reviewedInputPath))
    .filter((record) => record.review?.status === "verified");

  const merged = new Map();
  for (const record of cleanRecords) {
    if (!record.id) throw new Error(`Record missing id in ${cleanInputPath}`);
    merged.set(record.id, record);
  }

  let conflicts = 0;
  for (const record of verifiedRecords) {
    if (!record.id) throw new Error(`Record missing id in ${reviewedInputPath}`);
    if (merged.has(record.id)) {
      conflicts += 1;
      console.warn(
        `WARNING: id ${record.id} appears as both clean and verified; the verified record supersedes it.`,
      );
    }
    merged.set(record.id, record);
  }

  return { merged, cleanCount: cleanRecords.length, verifiedCount: verifiedRecords.length, conflicts };
}

async function existingDocIds() {
  const refs = await db.collection(collectionName).listDocuments();
  return new Set(refs.map((ref) => ref.id));
}

async function writeAll(records) {
  let batch = db.batch();
  let inBatch = 0;
  for (const record of records) {
    batch.set(db.collection(collectionName).doc(record.id), prepare(record));
    inBatch += 1;
    if (inBatch === BATCH_SIZE) {
      await batch.commit();
      batch = db.batch();
      inBatch = 0;
    }
  }
  if (inBatch > 0) await batch.commit();
}

async function main() {
  const { merged, cleanCount, verifiedCount, conflicts } = await buildMergedSet();
  const existingIds = await existingDocIds();

  const records = Array.from(merged.values());
  let added = 0;
  let updated = 0;
  for (const record of records) {
    if (existingIds.has(record.id)) updated += 1;
    else added += 1;
  }

  await writeAll(records);

  console.log(JSON.stringify({
    collection: collectionName,
    cleanInputPath,
    reviewedInputPath,
    cleanRecordsRead: cleanCount,
    verifiedRecordsRead: verifiedCount,
    conflictsResolvedInFavorOfVerified: conflicts,
    totalNowInCollection: records.length,
    addedSinceLastRun: added,
    updatedSinceLastRun: updated,
  }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
