import { CURATED_REGIONS } from "./geo_regions.js";

function text(value) {
  return String(value || "")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function finiteCoordinate(value) {
  return typeof value === "number" && Number.isFinite(value);
}

export function haversineKm(first, second) {
  const radians = (degrees) => degrees * Math.PI / 180;
  const latitudeDelta = radians(second.lat - first.lat);
  const longitudeDelta = radians(second.lng - first.lng);
  const firstLatitude = radians(first.lat);
  const secondLatitude = radians(second.lat);
  const a = Math.sin(latitudeDelta / 2) ** 2
    + Math.cos(firstLatitude) * Math.cos(secondLatitude)
    * Math.sin(longitudeDelta / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

export function validPoint(point) {
  return point && finiteCoordinate(point.lat) && finiteCoordinate(point.lng)
    && point.lat >= -90 && point.lat <= 90
    && point.lng >= -180 && point.lng <= 180;
}

function locationTerms(location) {
  return [location.raw, location.state, location.district, location.city]
    .filter(Boolean)
    .map(text);
}

export function findCuratedRegion(location) {
  const terms = locationTerms(location);
  return CURATED_REGIONS.find((region) => {
    const regionTerm = text(region.label);
    const regionId = text(region.id);
    return terms.some((term) => term === regionTerm || term === regionId
      || term.includes(regionTerm) || term.includes(regionId));
  });
}

function exactLocationMatch(record, location) {
  const stored = record.location || {};
  const requestedState = text(location.state);
  const requestedDistrict = text(location.district || location.city);
  if (!requestedState && !requestedDistrict) return false;
  return (!requestedState || text(stored.state) === requestedState)
    && (!requestedDistrict || text(stored.city) === requestedDistrict);
}

function curatedLocationMatch(record, region) {
  const stored = record.location || {};
  const storedState = text(stored.state);
  const storedDistrict = text(stored.city);
  const states = region.states.map(text);
  const districts = region.districts.map(text);
  if (!states.includes(storedState)) return false;
  // A record without a district cannot be safely placed in a district-curated region.
  return Boolean(storedDistrict) && districts.includes(storedDistrict);
}

export function geoMatch(record, location, origin, radiusKm = 50) {
  const hasLocationText = locationTerms(location).length > 0;
  if (!hasLocationText && !validPoint(origin)) {
    return { included: true, kind: "unfiltered" };
  }

  if (exactLocationMatch(record, location)) {
    return { included: true, kind: "literal" };
  }

  const region = findCuratedRegion(location);
  if (region && curatedLocationMatch(record, region)) {
    return {
      included: true,
      kind: "nearby_region",
      regionId: region.id,
      regionLabel: region.label,
    };
  }

  const storedGeo = record.location?.geo;
  if (validPoint(origin) && validPoint(storedGeo)) {
    const distanceKm = haversineKm(origin, storedGeo);
    if (distanceKm <= radiusKm) {
      return {
        included: true,
        kind: "nearby_region",
        distanceKm: Math.round(distanceKm * 10) / 10,
      };
    }
  }

  return { included: false, kind: "outside_requested_area" };
}

export function locationExplanation(match) {
  if (match.kind === "literal") return "in the stated location";
  if (match.kind === "nearby_region") {
    if (match.regionLabel) return `in the nearby ${match.regionLabel}`;
    return `within ${match.distanceKm} km of the stated location`;
  }
  return "without a geographic restriction";
}