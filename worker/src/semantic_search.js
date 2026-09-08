import { geoMatch, locationExplanation } from "./geo_reasoning.js";

const PHASE_0_SERVICE_CATEGORIES = [
  "eye_bank", "eye_care", "healthcare", "education", "vocational_training",
  "rehabilitation", "employment", "financial_support", "assistive_technology",
  "hostel", "advocacy_or_government", "library_or_information",
];

const SERVICE_LABELS = {
  eye_bank: "eye bank services", eye_care: "eye care", healthcare: "healthcare",
  education: "education", vocational_training: "vocational training",
  rehabilitation: "rehabilitation", employment: "employment support",
  financial_support: "financial support", assistive_technology: "assistive technology",
  hostel: "hostel facilities", advocacy_or_government: "advocacy or government services",
  library_or_information: "library or information services",
};

function values(value) {
  return Array.isArray(value) ? value.filter((item) => typeof item === "string") : [];
}

function firstSentence(value) {
  const cleaned = String(value || "").replace(/\s+/g, " ").trim();
  if (!cleaned) return "";
  const sentence = cleaned.split(/[.!?]/)[0].trim();
  return sentence || cleaned;
}

function locationText(record) {
  const location = record.location || {};
  return [location.city, location.state].map((value) => String(value || "").trim())
    .filter(Boolean).join(", ");
}

export function buildMatchExplanation(record, matchedServiceCategories, geographicMatch) {
  const organization = record.organization || {};
  const services = record.services || {};
  const name = String(organization.name || "Unnamed organization").trim();
  const location = locationText(record);
  const labels = matchedServiceCategories.map((code) => SERVICE_LABELS[code] || code).join(" and ");
  const sourceDescription = firstSentence(services.rawDescription);
  const locationPart = location ? `; listed location: ${location}` : "";
  const geographicPart = geographicMatch
    ? `; geographic match: ${locationExplanation(geographicMatch)}` : "";

  if (labels && sourceDescription) {
    return `${name} matches ${labels}${locationPart}${geographicPart}; stored service description: "${sourceDescription}."`;
  }
  if (labels) return `${name} is listed with ${labels}${locationPart}${geographicPart}.`;
  if (sourceDescription) {
    return `${name} matched the requested location or organization filters${locationPart}${geographicPart}; stored service description: "${sourceDescription}."`;
  }
  return `${name} matched the requested location or organization filters${locationPart}${geographicPart}, but this record has no stored service description.`;
}

export function rankResources(records, intent, limit = 100, geoOptions = {}) {
  const filters = intent.firestoreFilters || {};
  const location = {
    ...(intent.location || {}),
    state: intent.location?.state || filters.state || "",
    district: intent.location?.district || filters.district || "",
  };
  const requested = values(filters.serviceCodes).filter((code) => PHASE_0_SERVICE_CATEGORIES.includes(code));
  const uniqueRequested = [...new Set(requested)];
  return records.map((record) => ({ record, geographicMatch: geoMatch(record, location, geoOptions.origin, geoOptions.radiusKm) }))
    .filter(({ record, geographicMatch }) => geographicMatch.included
      && (!values(filters.organizationTypes).length
        || values(filters.organizationTypes).some((type) => values(record.organization?.types).includes(type))))
    .map(({ record, geographicMatch }) => {
      const codes = values(record.services?.codes);
      const matchedServiceCategories = uniqueRequested.filter((code) => codes.includes(code));
      return {
        id: record.id,
        ...record,
        match: {
          matchedServiceCategories,
          matchCount: matchedServiceCategories.length,
          requestedServiceCategoryCount: uniqueRequested.length,
          location: {
            kind: geographicMatch.kind,
            ...(geographicMatch.regionLabel ? { regionLabel: geographicMatch.regionLabel } : {}),
            ...(geographicMatch.distanceKm !== undefined ? { distanceKm: geographicMatch.distanceKm } : {}),
          },
          explanation: buildMatchExplanation(record, matchedServiceCategories, geographicMatch),
        },
      };
    })
    .sort((left, right) => right.match.matchCount !== left.match.matchCount
      ? right.match.matchCount - left.match.matchCount
      : String(left.organization?.name || "").localeCompare(String(right.organization?.name || "")))
    .slice(0, Math.max(1, Math.min(Number(limit) || 100, 100)));
}