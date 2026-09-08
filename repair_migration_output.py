#!/usr/bin/env python3
"""Apply conservative website repairs and emit city proposals for review."""
from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from pathlib import Path
from urllib.parse import urlsplit

WEBSITE_REASON = "website_missing_http_scheme_or_placeholder"
MISSING_CITY_REASON = "missing_city"


def norm(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", value.casefold()).strip()


def plausible_bare_url(value: str) -> bool:
    if not value or re.search(r"\s|[,\\]", value):
        return False
    parsed = urlsplit(f"https://{value}")
    hostname = parsed.hostname or ""
    labels = hostname.split(".")
    return len(labels) >= 2 and all(
        re.fullmatch(r"[a-z0-9](?:[a-z0-9-]*[a-z0-9])?", label, re.I)
        for label in labels
    ) and len(labels[-1]) >= 2


def address_suffix(address: str, state: str, known_cities: dict[str, set[str]]) -> tuple[str, str] | None:
    address_text = norm(address)
    state_text = norm(state)
    if not address_text or not state_text:
        return None
    address_text = re.sub(r"\s+\d{6}\s*$", "", address_text)
    if address_text.endswith(f" {state_text}"):
        address_text = address_text[:-(len(state_text) + 1)].rstrip()
    candidates = [
        (city_norm, city)
        for city_norm, city in known_cities.get(state_text, set())
        if address_text == city_norm or address_text.endswith(f" {city_norm}")
    ]
    if not candidates:
        return None
    candidates.sort(key=lambda item: len(item[0]), reverse=True)
    if len(candidates) > 1 and len(candidates[0][0]) == len(candidates[1][0]):
        return None
    return candidates[0][1], "high"


def repair(input_path: Path, report_path: Path) -> dict:
    records = [json.loads(line) for line in input_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    known_cities: dict[str, set[tuple[str, str]]] = defaultdict(set)
    for record in records:
        location = record.get("location", {})
        city, state = location.get("city"), location.get("state")
        if city and state:
            known_cities[norm(state)].add((norm(city), city))

    website_repairs = 0
    city_proposals = 0
    for record in records:
        review = record.setdefault("review", {})
        reasons = review.setdefault("reasons", [])
        original_reasons = list(reasons)
        contact = record.setdefault("contact", {})
        raw_website = contact.get("rawWebsite") or ""
        website_repaired = (
            plausible_bare_url(raw_website)
            and contact.get("websiteUrl") == f"https://{raw_website}"
        )
        if WEBSITE_REASON in reasons and plausible_bare_url(raw_website):
            contact["websiteUrl"] = f"https://{raw_website}"
            review["reasons"] = [reason for reason in reasons if reason != WEBSITE_REASON]
            reasons = review["reasons"]
            website_repaired = True
        if website_repaired:
            website_repairs += 1

        # This is intentionally based on the original reason set: a city
        # proposal is never made for a record with any other review concern.
        review.pop("cityCandidate", None)
        if original_reasons == [MISSING_CITY_REASON] and not website_repaired:
            location = record.get("location", {})
            candidate = address_suffix(
                location.get("address") or "",
                location.get("state") or "",
                known_cities,
            )
            if candidate:
                review["cityCandidate"] = {
                    "value": candidate[0],
                    "confidence": candidate[1],
                    "source": "address_suffix",
                    "confirmed": False,
                }
                city_proposals += 1

        review["status"] = "clean" if not reasons else "needs_review"

    input_path.write_text("".join(json.dumps(record, ensure_ascii=False) + "\n" for record in records), encoding="utf-8")
    review_records = [record for record in records if record["review"]["status"] == "needs_review"]
    summary = {
        "input": "migration_output/organizations.jsonl",
        "records": len(records),
        "clean": len(records) - len(review_records),
        "needsReview": len(review_records),
        "cleanPercent": round((len(records) - len(review_records)) * 100 / len(records), 2),
        "needsReviewPercent": round(len(review_records) * 100 / len(records), 2),
        "possibleDuplicateRows": sum("possible_duplicate" in record["review"]["reasons"] for record in records),
        "reviewReasons": {},
        "mechanicalFixes": {
            "websiteUrlsNormalized": website_repairs,
            "cityCandidatesProposed": city_proposals,
        },
    }
    for record in review_records:
        for reason in record["review"]["reasons"]:
            summary["reviewReasons"][reason] = summary["reviewReasons"].get(reason, 0) + 1
    report_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, default=Path("migration_output/organizations.jsonl"))
    parser.add_argument("--report", type=Path, default=Path("migration_output/review_report.json"))
    args = parser.parse_args()
    print(json.dumps(repair(args.input, args.report), indent=2))


if __name__ == "__main__":
    main()