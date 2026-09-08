import test from "node:test";
import assert from "node:assert/strict";
import { rankResources } from "../src/semantic_search.js";

test("preserves curated-region and distance match output", () => {
  const records = [
    { id: "one", organization: { name: "Alpha", types: ["ngo"] }, location: { city: "Delhi", state: "Delhi" }, services: { codes: ["education"] } },
    { id: "two", organization: { name: "Pune", types: ["ngo"] }, location: { city: "Pune", state: "Maharashtra", geo: { lat: 18.5204, lng: 73.8567 } }, services: { codes: ["education"] } },
  ];
  const curated = rankResources(records, { location: { raw: "Delhi NCR" }, firestoreFilters: { serviceCodes: [], state: "", district: "", organizationTypes: [] } });
  assert.equal(curated[0].match.location.kind, "nearby_region");
  assert.equal(curated[0].match.location.regionLabel, "Delhi NCR");
  const distance = rankResources(records, { location: { raw: "A place without a curated region" }, firestoreFilters: { serviceCodes: [], state: "", district: "", organizationTypes: [] } }, 100, { origin: { lat: 18.52, lng: 73.85 }, radiusKm: 10 });
  assert.equal(distance[0].match.location.kind, "nearby_region");
  assert.equal(distance[0].match.location.distanceKm, 0.7);
});