# VIB data assessment and Firestore model

## Input assessment

The source file is `blind-schools-eye-banks-ngos-and-other-resources-for-visually-impaired-in-india.csv`.
It contains 1,538 usable records and 13 columns. The first two physical lines are a PHP/Ninja Tables deprecation warning; the actual CSV header starts on line 3. The migration detects that header instead of treating the warning as data.

Observed completeness:

| Field | Non-empty | Main issue |
|---|---:|---|
| Name of Institution | 1,538/1,538 | 1,359 distinct values; repeated names need entity resolution |
| Type of Resource | 1,307/1,538 | 68 distinct non-empty labels, mixed case, slash-combinations, synonyms |
| Address | 1,514/1,538 | free text; 24 missing |
| District / City | 1,157/1,538 | 381 missing |
| State | 1,538/1,538 | casing variants such as `karnataka`, and legacy names |
| PIN Code | 1,353/1,538 | spaces and 8 malformed non-empty values under the migrator's check |
| Contact Number | 1,382/1,538 | multiple numbers, extensions, `#ERROR!`, and prose mixed in |
| Alternate Contact Number | 667/1,538 | same formatting problems; 34 suspicious values |
| Email Address | 829/1,538 | multiple addresses are joined in one cell; 4 rows could not be safely tokenized |
| Website / Social Link | 415/1,538 | 226 non-empty values lack `http(s)://`; social pages and websites are mixed |
| Services Offered | 1,252/1,538 | 994 distinct descriptions; prose contains multiple services |
| Admission Criteria (if any) | 177/1,538 | eligibility is mostly absent and otherwise free text |
| Google Maps Link | 125/1,538 | 35 non-empty values are placeholders such as `Not Available` |

A normalized name + city + state check found 37 likely duplicate groups. The migrator flags all 81 rows belonging to duplicate groups for review; this is intentionally not an automatic merge. Repeated names can represent branches, campuses, or duplicate exports.

### Clean vs manual review

The migration reports **436/1,538 clean (28.35%)** and **1,102/1,538 needing review (71.65%)** for this sample. A record is `clean` only when it has a name, address, city, state, resource type that maps to the controlled taxonomy, and services text that maps to at least one controlled service, with no malformed structured values or duplicate signal. Missing eligibility alone does not trigger review because the source labels it “if any”; it remains `null` and unverified. `repair_migration_output.py` can mechanically normalize plausible bare website domains and add unconfirmed `review.cityCandidate` proposals without changing `location.city`.

This percentage is a migration-readiness measure, not a data-validity judgment. The most common flags are missing city (381), missing services (286), missing type (231), website formatting (226), multi-category type (157), and possible duplicate (81).

## Firestore proposal

Use one primary collection:

```text
organizations/{organizationId}
```

Each document emitted by `migrate_vib.py` has this shape:

```json
{
  "organization": {
    "name": "string",
    "types": ["school", "hostel"],
    "rawType": "string or null"
  },
  "location": {
    "address": "string or null",
    "city": "string or null",
    "state": "canonical Indian state/UT enum or null",
    "postalCode": "six-digit string or null",
    "country": "IN",
    "geo": "GeoPoint or null"
  },
  "services": {
    "codes": ["education", "rehabilitation"],
    "rawDescription": "string or null"
  },
  "eligibility": {
    "rawText": "string or null",
    "criteria": []
  },
  "contact": {
    "phones": ["string"],
    "alternatePhones": ["string"],
    "emails": ["string"],
    "rawEmail": "string or null",
    "websiteUrl": "string or null",
    "rawWebsite": "string or null",
    "mapsUrl": "string or null",
    "rawMapsUrl": "string or null"
  },
  "verification": {
    "status": "unverified | pending | verified | rejected",
    "lastVerifiedAt": "Timestamp or null"
  },
  "provenance": {
    "sourceName": "J.S. Trust VIB database export",
    "sourceFile": "string",
    "sourceRow": "integer",
    "migratedAt": "Timestamp"
  },
  "review": {
    "status": "clean | needs_review",
    "reasons": ["string"]
  }
}
```

Use a Firestore `GeoPoint` only after a trusted geocoding/review workflow. The source has map URLs but no latitude/longitude; the migration therefore emits `geo: null` and never invents coordinates. A later reviewed update can populate `location.geo` and record the geocoding source in provenance.

### Controlled enums

`organization.types` should use these values:

- `eye_bank`
- `school`
- `hospital`
- `ngo`
- `government`
- `vocational_training`
- `rehabilitation_centre`
- `hostel`
- `association`
- `resource_centre`
- `other`

`services.codes` should use these values:

- `eye_bank`, `eye_care`, `healthcare`
- `education`, `vocational_training`, `rehabilitation`
- `employment`, `financial_support`
- `assistive_technology`, `hostel`
- `advocacy_or_government`, `library_or_information`

The migrator only emits a code when an explicit phrase in the source matches a rule. It keeps the complete original description alongside the codes. It does not infer service availability from an organization name.

### Eligibility normalization

Keep `eligibility.rawText` permanently. A reviewed pipeline may populate `criteria` with explicit, source-backed objects such as:

```json
{
  "kind": "disability_percentage_minimum",
  "value": 40,
  "unit": "percent",
  "sourceText": "40% disability certificate or higher required for social services"
}
```

Do not populate structured criteria from implication, and do not treat absent text as “no eligibility.” The current migrator intentionally leaves `criteria` empty for manual review rather than parsing potentially nuanced eligibility language.

## Loading

The script is standard-library Python and does not contact Firebase or a geocoder:

```bash
python3 migrate_vib.py blind-schools-eye-banks-ngos-and-other-resources-for-visually-impaired-in-india.csv
```

Outputs:

- `migration_output/organizations.jsonl`: one Firestore-shaped record per source row
- `migration_output/review_report.json`: counts and review reasons

Import only reviewed records into production. Store the JSONL in a staging collection first, and make duplicate resolution and geocoding explicit human-reviewed steps.
