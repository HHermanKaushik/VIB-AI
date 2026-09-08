const PHASE_0_SERVICE_CATEGORIES = [
  "eye_bank", "eye_care", "healthcare", "education", "vocational_training",
  "rehabilitation", "employment", "financial_support", "assistive_technology",
  "hostel", "advocacy_or_government", "library_or_information",
];
const ALL_SERVICE_CATEGORIES = [...PHASE_0_SERVICE_CATEGORIES, "scholarship", "higher_education"];
const ORGANIZATION_TYPES = [
  "eye_bank", "school", "hospital", "ngo", "government", "vocational_training",
  "rehabilitation_centre", "hostel", "association", "resource_centre", "other",
];
const ELIGIBILITY_KINDS = [
  "disability_status", "age", "education_level", "income", "residency", "gender", "other",
];

export function normalizeIntent(value) {
  const input = value && typeof value === "object" ? value : {};
  const location = input.location && typeof input.location === "object" ? input.location : {};
  const filters = input.firestoreFilters && typeof input.firestoreFilters === "object" ? input.firestoreFilters : {};
  const serviceCategories = Array.isArray(input.serviceCategories)
    ? input.serviceCategories.filter((item) => ALL_SERVICE_CATEGORIES.includes(item)) : [];
  const eligibilitySignals = Array.isArray(input.eligibilitySignals)
    ? input.eligibilitySignals.filter((item) => item && typeof item === "object")
      .filter((item) => ELIGIBILITY_KINDS.includes(item.kind))
      .filter((item) => String(item.sourceText || "").trim())
      .map((item) => ({ kind: item.kind, value: String(item.value || "").trim(), sourceText: String(item.sourceText).trim() }))
    : [];
  return {
    serviceCategories: [...new Set(serviceCategories)],
    location: {
      raw: String(location.raw || "").trim(), state: String(location.state || "").trim(),
      district: String(location.district || "").trim(), city: String(location.city || "").trim(),
    },
    eligibilitySignals,
    firestoreFilters: {
      serviceCodes: [...new Set(Array.isArray(filters.serviceCodes)
        ? filters.serviceCodes.filter((item) => PHASE_0_SERVICE_CATEGORIES.includes(item)) : [])],
      state: String(filters.state || "").trim(), district: String(filters.district || "").trim(),
      organizationTypes: [...new Set(Array.isArray(filters.organizationTypes)
        ? filters.organizationTypes.filter((item) => ORGANIZATION_TYPES.includes(item)) : [])],
    },
  };
}