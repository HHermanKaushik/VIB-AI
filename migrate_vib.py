#!/usr/bin/env python3
"""Conservatively migrate the VIB CSV to Firestore-shaped JSONL.

No external packages are required. Unknown values stay in raw fields and add
review reasons instead of being silently classified.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import html
import json
import re
import unicodedata
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SOURCE_COLUMNS = [
    "Name of Institution", "Type of Resource", "Address", "District / City",
    "State", "PIN Code", "Contact Number", "Alternate Contact Number",
    "Email Address", "Website / Social Link", "Services Offered",
    "Admission Criteria (if any)", "Google Maps Link",
]
PLACEHOLDERS = {"not available", "n/a", "na", "-", "#error!"}
SERVICE_RULES = {
    "eye_bank": ("eye bank", "eye donation", "cornea"),
    "eye_care": ("eye care", "eye hospital", "ophthalm", "vision care"),
    "education": ("school", "education", "student"),
    "vocational_training": ("vocational", "training", "skill development"),
    "rehabilitation": ("rehabilitation", "rehab", "community based rehabilitation"),
    "employment": ("employment", "placement", "self employment", "income generation"),
    "assistive_technology": ("assistive", "accessibility tech", "equipment", "technology"),
    "financial_support": ("loan", "finance", "financial", "fund"),
    "hostel": ("hostel", "accommodation", "residential"),
    "healthcare": ("hospital", "medical", "health", "clinic"),
    "advocacy_or_government": ("government", "act", "policy", "grievance", "advocacy"),
    "library_or_information": ("library", "resource centre", "resource center", "information"),
}
TYPE_RULES = {
    "eye_bank": ("eye bank",),
    "school": ("school",),
    "hospital": ("hospital",),
    "ngo": ("ngo",),
    "government": ("government", "govt", "government body", "government department"),
    "vocational_training": ("vocational", "training", "teacher training"),
    "rehabilitation_centre": ("rehabilitation", "rehabiliation"),
    "hostel": ("hostel",),
    "association": ("association",),
    "resource_centre": ("resource centre", "resource center"),
    "other": ("other",),
}

def clean(value: str | None) -> str:
    value = html.unescape(value or "").replace("\u00a0", " ")
    return re.sub(r"\s+", " ", value).strip()

def norm(value: str) -> str:
    value = unicodedata.normalize("NFKD", value.casefold())
    value = value.encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", " ", value).strip()

def is_placeholder(value: str) -> bool:
    return value.casefold() in PLACEHOLDERS

def split_contacts(value: str) -> list[str]:
    if not value or is_placeholder(value):
        return []
    # Keep the original value elsewhere; these are conservative tokenizations.
    return [x.strip() for x in re.split(r"\s*(?:,|;|/|\\)\s*", value) if x.strip()]

def split_emails(value: str) -> list[str]:
    return [x for x in split_contacts(value) if re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", x)]

def parse_url(value: str) -> str | None:
    if not value or is_placeholder(value):
        return None
    return value if re.match(r"^https?://", value, re.I) else None

def extract_types(raw: str) -> list[str]:
    value = norm(raw)
    found = []
    for enum, phrases in TYPE_RULES.items():
        if any(re.search(r"\b" + re.escape(norm(p)) + r"\b", value) for p in phrases):
            found.append(enum)
    return found

def extract_services(raw: str) -> list[str]:
    value = norm(raw)
    return [enum for enum, phrases in SERVICE_RULES.items()
            if any(re.search(r"\b" + re.escape(norm(p)) + r"\b", value) for p in phrases)]

def make_record(row: dict[str, str], source_row: int, duplicate_key: str | None) -> dict[str, Any]:
    get = lambda field: clean(row.get(field))
    name, raw_type, address = get("Name of Institution"), get("Type of Resource"), get("Address")
    city, state, pin = get("District / City"), get("State"), get("PIN Code")
    services_raw, eligibility_raw = get("Services Offered"), get("Admission Criteria (if any)")
    primary, alternate, email = get("Contact Number"), get("Alternate Contact Number"), get("Email Address")
    website, maps = get("Website / Social Link"), get("Google Maps Link")
    types, services = extract_types(raw_type), extract_services(services_raw)
    reasons: list[str] = []
    if not name: reasons.append("missing_name")
    if not address: reasons.append("missing_address")
    if not city: reasons.append("missing_city")
    if not state: reasons.append("missing_state")
    if not raw_type: reasons.append("missing_resource_type")
    elif not types: reasons.append("unmapped_resource_type")
    elif len(types) > 1: reasons.append("multi_category_resource_type")
    if not services_raw: reasons.append("missing_services_description")
    elif not services: reasons.append("unmapped_services_description")
    if pin and not re.fullmatch(r"\d{6}", pin.replace(" ", "")): reasons.append("invalid_pin_format")
    if email and not split_emails(email): reasons.append("email_contains_unparsed_values")
    if website and not parse_url(website): reasons.append("website_missing_http_scheme_or_placeholder")
    if maps and not parse_url(maps): reasons.append("maps_link_missing_http_scheme_or_placeholder")
    if primary and (len(re.sub(r"\D", "", primary)) < 7 or re.search(r"[A-Za-z]", primary)):
        reasons.append("primary_contact_needs_review")
    if alternate and (len(re.sub(r"\D", "", alternate)) < 7 or re.search(r"[A-Za-z]", alternate)):
        reasons.append("alternate_contact_needs_review")
    if duplicate_key: reasons.append("possible_duplicate")
    source_hash = hashlib.sha256(f"{source_row}:{name}:{address}".encode()).hexdigest()[:24]
    return {
        "id": source_hash,
        "organization": {"name": name, "types": types, "rawType": raw_type},
        "location": {"address": address or None, "city": city or None, "state": state or None,
                      "postalCode": pin.replace(" ", "") or None, "country": "IN",
                      "geo": None},
        "services": {"codes": services, "rawDescription": services_raw or None},
        "eligibility": {"rawText": eligibility_raw or None, "criteria": []},
        "contact": {"phones": split_contacts(primary), "alternatePhones": split_contacts(alternate),
                     "emails": split_emails(email), "rawEmail": email or None,
                     "websiteUrl": parse_url(website), "rawWebsite": website or None,
                     "mapsUrl": parse_url(maps), "rawMapsUrl": maps or None},
        "verification": {"status": "unverified", "lastVerifiedAt": None},
        "provenance": {"sourceName": "J.S. Trust VIB database export", "sourceFile": SOURCE_FILE,
                       "sourceRow": source_row, "migratedAt": datetime.now(timezone.utc).isoformat()},
        "review": {"status": "needs_review" if reasons else "clean", "reasons": reasons},
    }

SOURCE_FILE = "blind-schools-eye-banks-ngos-and-other-resources-for-visually-impaired-in-india.csv"

def load_rows(path: Path) -> tuple[list[dict[str, str]], int]:
    lines = path.read_text(encoding="utf-8-sig").splitlines()
    header_index = next((i for i, line in enumerate(lines) if "Name of Institution" in line), None)
    if header_index is None:
        raise ValueError("Could not find the expected CSV header")
    return list(csv.DictReader(lines[header_index:])), header_index + 1

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("--output-dir", type=Path, default=Path("migration_output"))
    args = parser.parse_args()
    rows, header_line = load_rows(args.input)
    keys: defaultdict[tuple[str, str, str], list[int]] = defaultdict(list)
    for index, row in enumerate(rows, start=header_line + 1):
        keys[(norm(clean(row.get("Name of Institution"))), norm(clean(row.get("District / City"))),
              norm(clean(row.get("State"))))].append(index)
    duplicate_rows = {row_number for group in keys.values() if len(group) > 1 for row_number in group}
    records = []
    for index, row in enumerate(rows, start=header_line + 1):
        key = (norm(clean(row.get("Name of Institution"))), norm(clean(row.get("District / City"))), norm(clean(row.get("State"))))
        records.append(make_record(row, index, "|".join(key) if index in duplicate_rows else None))
    args.output_dir.mkdir(parents=True, exist_ok=True)
    with (args.output_dir / "organizations.jsonl").open("w", encoding="utf-8") as out:
        for record in records: out.write(json.dumps(record, ensure_ascii=False) + "\n")
    review = [r for r in records if r["review"]["status"] == "needs_review"]
    summary = {"input": str(args.input), "records": len(records), "headerLine": header_line,
               "clean": len(records) - len(review), "needsReview": len(review),
               "cleanPercent": round((len(records) - len(review)) * 100 / len(records), 2),
               "needsReviewPercent": round(len(review) * 100 / len(records), 2),
               "possibleDuplicateRows": len(duplicate_rows), "reviewReasons": {}}
    for record in review:
        for reason in record["review"]["reasons"]:
            summary["reviewReasons"][reason] = summary["reviewReasons"].get(reason, 0) + 1
    (args.output_dir / "review_report.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))

if __name__ == "__main__":
    main()
