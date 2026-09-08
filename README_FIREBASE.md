# DrishtiBution Firebase setup

This Firebase layout follows the active `karigar-samarthan-mainJuly6` conventions: `firebase.json`, separate Firestore rules/indexes, a Node 24 `functions/` package, and Admin SDK access for trusted writes.

## Project and database

- Firebase project name: `Haathloom`
- Firebase project ID: `haathloom`
- Firebase project number: `612792255819`
- Firestore database: `(default)`
- Primary collection: `organizations/{organizationId}`
- Region: `asia-south1`

The existing Haathloom project is selected in `.firebaserc`. The repository configuration does not contain credentials:

```bash
firebase login
firebase projects:list
firebase use haathloom
```

Do not commit service-account keys. This setup uses the existing `(default)` Firestore database and does not delete or overwrite unrelated collections.

## Install and deploy

From the VIB-AI directory:

```bash
cd functions
npm install
cd ..
firebase use haathloom
firebase deploy --only firestore:rules,firestore:indexes,functions
```

The Firestore rules make `organizations` publicly readable and deny all direct client writes. Cloud Functions and the Admin SDK bypass these rules for trusted server-side operations.

## Filtering API

Flutter calls the callable function `searchOrganizations` through `cloud_functions`:

```dart
final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
    .httpsCallable('searchOrganizations');
final response = await callable.call({
  'serviceCategory': 'rehabilitation',
  'state': 'Maharashtra',
  'district': 'Mumbai',
  'organizationType': 'ngo',
  'search': 'training',
  'limit': 50,
});
```

All filter fields are optional:

- `serviceCategory`: exact controlled code in `services.codes`
- `state`: case-insensitive state text
- `district`: case-insensitive value of `location.city`
- `organizationType`: exact controlled code in `organization.types`
- `search`: case-insensitive substring over organization name, raw services, raw type, and service codes
- `limit`: 1-100, default 50

The function returns `{ results: [...], count: number }` and only returns records whose `review.status` is `clean`. For the current 1,538-row dataset this bounded read-and-filter approach is straightforward. If the collection grows substantially, move free-text search to a dedicated search service or maintain a reviewed token index rather than pretending Firestore is a full-text engine.

## Seed Firestore

The importer reads Phase 0 JSONL and writes in batches of 400 using the Admin SDK. It imports only clean records by default:

```bash
# Use Application Default Credentials or GOOGLE_APPLICATION_CREDENTIALS.
NODE_PATH="$PWD/functions/node_modules" node scripts/import_firestore.js migration_output/organizations.jsonl
```

For local development, authenticate with Application Default Credentials or set `GOOGLE_APPLICATION_CREDENTIALS` to a service-account key kept outside the repository. To deliberately stage flagged records too:

```bash
NODE_PATH="$PWD/functions/node_modules" node scripts/import_firestore.js migration_output/organizations.jsonl --include-review
```

The importer is idempotent for the same document IDs because it uses merge writes. It does not delete existing documents and does not geocode records. `location.geo` remains null until a trusted reviewed geocoding step supplies coordinates.

### One-time Spark-plan seed

Cloud Functions are not required for the initial seed. Create a service account in the Haathloom Google Cloud project with a Firestore write role, create a JSON key, and store it outside this repository. Then run:

```bash
export GOOGLE_APPLICATION_CREDENTIALS="$HOME/.config/gcloud/haathloom-firestore-importer.json"
cd /Users/heatherhome/Desktop/VIB-AI/functions
npm install
cd ..
node scripts/import_firestore.js migration_output/organizations.jsonl
```

Expected result: 436 clean records imported and 1,102 flagged records skipped. To stage all records, including those marked `needs_review`, add `--include-review`. The importer uses the Admin SDK and therefore works on Spark; it does not require Cloud Functions. Do not email, commit, or paste the JSON key into chat.

## Flutter Firebase options

After the Firebase project exists, configure the Flutter targets using the same FlutterFire workflow as Karigar:

```bash
flutter pub add firebase_core cloud_firestore cloud_functions
flutterfire configure --project=haathloom
```

This generates `lib/firebase_options.dart` and platform-specific Firebase configuration. Initialize Firebase before calling Firestore or Functions. The current workspace contains backend configuration only; no guessed Firebase app IDs or credentials have been added.

## Sarvam voice setup

The voice search follows the active Karigar Samarthan pattern from `lib/services/sarvam_service.dart`: record a WAV file locally, send it to `https://api.sarvam.ai/speech-to-text` using `saaras:v3`, then send each result summary to `/text-to-speech` using `bulbul:v3`. DrishtiBution keeps the same REST boundary in `lib/sarvam_service.dart`.

Create the local environment file and add the key from Sarvam:

```bash
cp .env.example .env
open -e .env
```

Set `SARVAM_API_KEY` in `.env`. This file is ignored by Git and the key is not hardcoded in Dart. For a production release, use a backend proxy or platform secret mechanism because a key shipped in a client app can ultimately be extracted.

The voice screen supports explicit English (`en-IN`) and Hindi (`hi-IN`) input modes. Code-switched speech may be transcribed incorrectly when one language is selected; users should select the dominant language and retry. Full Hindi and English API testing requires a real Sarvam key, microphone permission, and a physical or simulated device, so static analysis cannot validate transcription quality.

## Resource details and actions

Search result cards open `lib/resource_detail_screen.dart`. The detail screen shows the stored organization profile: address, services, raw eligibility text, phone, email, website, and verification date. It also provides accessible actions for:

- Sarvam read-aloud on screen open and a manual Read aloud action
- native phone dialer via `tel:`
- owner-authenticated Save/Remove using `users/{uid}/saved/{resourceId}`
- system Share sheet via `share_plus`, with a text-only summary from stored fields
- Google Maps directions using the stored address

The route implements `WidgetsBindingObserver`; leaving for the dialer, Maps, or share sheet does not pop the detail route or recreate its state. On resume it announces that the user returned to the same resource.

### Phone Auth setup

Enable **Authentication → Sign-in method → Phone** for the `haathloom` Firebase project. Then run:

```bash
flutterfire configure --project=haathloom
```

For Android phone auth, add the app's SHA-1 and SHA-256 fingerprints in Firebase project settings. For iOS, configure the APNs capabilities/key required by Firebase phone authentication. Test phone verification on a real device; Firebase app-verification behavior differs on emulators.

### Accessibility and resume test

On an Android device with TalkBack enabled:

1. Search for a resource and double tap its result to open the profile.
2. Confirm TalkBack announces the profile fields and distinct labels for Call, Save, Share, Directions, and Read aloud.
3. Double tap Call, return with the system Back gesture, and confirm the same profile remains open with its Save state and scroll position intact.
4. Repeat with Maps and the Share sheet.

The automated widget test validates that the app renders, but native dialer, SMS verification, Share, Maps, Sarvam audio, and TalkBack behavior require device testing and were not simulated in CI.

## Feedback capture

After returning from a call, Maps, or sharing, the detail screen offers a feedback dialog; it is also available as an explicit **Share feedback** action. The questions are:

- Did they answer your call? (`yes`, `no`, `unknown`)
- Was the information accurate? (`yes`, `partly`, `no`, `unsure`)
- Was the service available? (`yes`, `no`, `unsure`)
- Was contacting them helpful? (`yes`, `no`, `unsure`)
- Anything else? Optional free-text notes

Users authenticate with phone sign-in before submission. Responses are stored at:

```text
organizations/{resourceId}/feedback/{feedbackId}
```

Each response includes the action that preceded the prompt, the four answers, optional notes, `reporterUserId`, and a server-generated `createdAt` timestamp. Feedback reads, updates, and deletes are denied by Firestore rules; it is not public resource data. No score, ranking, verification status, or other resource field is calculated from feedback yet.

## WordPress opportunities webhook

The WordPress integration is in `wordpress-plugins/drishtibution-opportunities/drishtibution-opportunities.php`. It follows the Karigar Samarthan webhook pattern in `Downloads/karigar-samarthan-mainJuly6/functions/index.js`: POST-only `onRequest`, HMAC over the raw request body, early rejection for invalid signatures/payloads, logger calls, and an Admin SDK upsert.

### Opportunity fields

The `opportunity` custom post type is titled **Opportunities / News Bulletins** and supports:

- Common: title, summary, full description, opportunity type, organization, source URL, eligibility text, deadline, application URL, contact email, contact phone, language, address, city, district, state, country
- `job`: employer, role, employment type, experience, skills, salary text
- `education`: institution, program, level, duration, fee text
- `training`: provider, program, mode, duration, fee text
- `scheme`: provider, benefits text, application process

Published posts are sent to `receiveOpportunityWebhook`, which validates the source, action, post ID, publish status, type, title, organization, source URL, and description/summary before writing to:

```text
opportunities/wp_{wordpressPostId}
```

Malformed JSON or validation failures are rejected with HTTP 400 and logged in the private `webhook_errors` collection with a payload hash. Invalid signatures receive HTTP 401. Firestore writes happen only after validation succeeds, so partial records are not written.

### Install and configure

1. Deploy the Function after the Haathloom project can run Cloud Functions.
2. Set the shared secret interactively:

```bash
firebase functions:secrets:set OPPORTUNITIES_WEBHOOK_SECRET --project haathloom
firebase deploy --project haathloom --only functions
```

3. In WordPress, copy the plugin directory into `wp-content/plugins/`, activate **DrishtiBution Opportunities**, and add this to `wp-config.php` without committing the value:

```php
define('DRISHTI_OPPORTUNITIES_WEBHOOK_SECRET', 'the-same-secret-used-in-Firebase');
```

4. Create and publish a test opportunity. The plugin sends the signed request to the Function URL and the Function upserts the matching document. If the secret is absent in WordPress, it intentionally sends nothing.

The plugin uses `blocking => false`; inspect WordPress HTTP logs and the `webhook_errors` collection when testing delivery. The Function tests are in `functions/opportunity_validation.test.js` and do not write production data.

## Gemini voice-intent extraction

`functions/extractVoiceIntent` accepts only a raw transcript and returns query intent. It does not receive organization documents, does not answer the user, and does not generate resource facts. The client or a later trusted workflow must use the returned `firestoreFilters` to query `organizations`; organization names, phone numbers, and eligibility rules always come from Firestore.

The response contract is:

```json
{
  "serviceCategories": ["education", "scholarship", "higher_education"],
  "location": { "raw": "Bengaluru", "state": "", "district": "", "city": "Bengaluru" },
  "eligibilitySignals": [
    { "kind": "age", "value": "19", "sourceText": "I am 19" }
  ],
  "firestoreFilters": {
    "serviceCodes": ["education"],
    "state": "",
    "district": "",
    "organizationTypes": []
  }
}
```

`serviceCategories` uses the Phase 0 service taxonomy (`eye_bank`, `eye_care`, `healthcare`, `education`, `vocational_training`, `rehabilitation`, `employment`, `financial_support`, `assistive_technology`, `hostel`, `advocacy_or_government`, `library_or_information`) plus query-intent labels `scholarship` and `higher_education`. `firestoreFilters.serviceCodes` is restricted to the Phase 0 codes, so unsupported concepts remain visible as intent but cannot become invented Firestore services. Eligibility signals are limited to `disability_status`, `age`, `education_level`, `income`, `residency`, `gender`, and `other`, and each requires source text.

The Gemini prompt and few-shot examples are in `functions/voice_intent.js`. They include realistic Hindi-English and English queries and explicitly prohibit organization facts, phone numbers, and eligibility-rule invention.

Because Haathloom is currently on Spark, the Function cannot deploy until the project is upgraded to Blaze. When deployment is available, store the Gemini key as a Firebase secret rather than in Flutter or a checked-in file:

```bash
firebase functions:secrets:set GEMINI_API_KEY --project haathloom
firebase deploy --project haathloom --only functions
```

The secret prompt accepts the key interactively. Do not place the key in `functions/index.js`, `.env`, the Flutter app, or chat. The Function uses Gemini `gemini-2.5-flash` with JSON response mode and a response schema, then applies server-side allowlist normalization before returning intent.

## Geographic reasoning

The geo layer is implemented in `functions/geo_regions.js`, `functions/geo_reasoning.js`, and `functions/semantic_search.js`. It includes curated district lookup tables for Delhi NCR, Mumbai, Bengaluru, Chennai, Hyderabad, Kolkata, Pune, Ahmedabad-Gandhinagar, Kochi, Jaipur, and Lucknow. The actual Phase 0 state coverage and its limitations are listed in [PHASE_0_COVERAGE.md](PHASE_0_COVERAGE.md).

Call the intent search with an optional explicit device/geocoder origin:

```javascript
const response = await searchResourcesByIntent({
  intent: structuredIntent,
  origin: { lat: 28.6139, lng: 77.2090 },
  radiusKm: 50,
  limit: 20,
});
```

The Function first applies literal state/city matches, then curated region matches, then straight-line distance fallback for records with reviewed `location.geo` coordinates. Each result includes `match.location.kind` (`literal` or `nearby_region`) and the explanation says when the result came from a nearby region or distance radius. Phase 0 did not contain coordinates, so the distance fallback currently returns no coordinate-based matches until reviewed enrichment populates `location.geo`.

## Intent-based semantic search

`functions/searchResourcesByIntent` accepts the structured object returned by `extractVoiceIntent`:

```javascript
const callable = getFunctions().httpsCallable('searchResourcesByIntent');
const response = await callable({
  intent: structuredIntent,
  limit: 20,
});
```

The Function reads only `organizations` documents with `review.status == "clean"`. It applies the intent's state, district, and organization-type filters, then ranks remaining records by the number of exact overlaps between `firestoreFilters.serviceCodes` and the stored `services.codes` array. Results include:

```json
{
  "match": {
    "matchedServiceCategories": ["education", "hostel"],
    "matchCount": 2,
    "requestedServiceCategoryCount": 2,
    "explanation": "..."
  }
}
```

The explanation is deterministic and built only from stored organization name, stored location, stored service codes, and the first sentence of stored `services.rawDescription`. It never asks Gemini to explain a match and cannot truthfully claim a service such as a scholarship when that service is absent from the record. Query-only categories such as `scholarship` and `higher_education` remain in the intent, but do not match records until the database taxonomy contains corresponding reviewed service codes. Eligibility signals are returned for review context only; they are not used as rules because the database does not establish eligibility from user speech.
