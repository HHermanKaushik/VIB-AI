# Phase 0 geographic coverage

The source audit found 1,538 records across 38 raw state/UT labels and 336 distinct non-empty district/city values. State labels include casing variants, so application filters should canonicalize them before matching.

Canonical state/UT labels observed in the sample:

- Andaman and Nicobar
- Andhra Pradesh
- Arunachal Pradesh
- Assam
- Bihar
- Chandigarh
- Chhattisgarh
- Delhi
- Daman and Diu
- Dadar and Nagar Haveli
- Goa
- Gujarat
- Haryana
- Himachal Pradesh
- Jammu and Kashmir
- Jharkhand
- Karnataka
- Kerala
- Madhya Pradesh
- Maharashtra
- Manipur
- Meghalaya
- Mizoram
- Nagaland
- Odisha
- Pondicherry
- Punjab
- Rajasthan
- Sikkim
- Tamil Nadu
- Telangana
- Tripura
- Uttar Pradesh
- Uttarakhand
- West Bengal

The most represented states in the raw sample are Maharashtra (237), Delhi (164), Gujarat (140), Tamil Nadu (129), Uttar Pradesh (104), Rajasthan (81), Karnataka (80), West Bengal (80), Odisha (65), Telangana (59), and Madhya Pradesh (57). These counts describe records, not population or service availability.

## Curated regions currently included

The geo layer includes explicit district lists for:

- Delhi NCR: Delhi; selected Haryana, Uttar Pradesh, and Rajasthan NCR districts
- Mumbai Metropolitan Region
- Bengaluru metropolitan region
- Chennai metropolitan region
- Hyderabad metropolitan region
- Kolkata metropolitan region
- Pune metropolitan region
- Ahmedabad-Gandhinagar region
- Kochi region
- Jaipur region
- Lucknow region

These are operational lookup regions, not claims that every listed district is officially identical to the metro boundary. The table lives in `functions/geo_regions.js`; district membership should be reviewed before adding more regions.

## Coordinate limitation

Phase 0 supplied map URLs but no latitude/longitude values. The migration intentionally emitted `location.geo: null` for all records. Therefore:

- Curated matching can use explicit stored state/city text.
- Straight-line fallback is inactive for current records until reviewed coordinates are added.
- The search Function accepts an explicit user `origin` `{ "lat": number, "lng": number }` and uses a maximum 200 km radius, default 50 km.
- It never geocodes or guesses an origin or organization coordinate.

Every expanded result carries `match.location.kind` and an explanation that says either `in the stated location` or `in the nearby <region>` / `within <distance> km of the stated location`. The client should display that distinction verbatim or equivalently so a nearby result is not presented as a literal local match.
