/// Rule-based transcript -> structured intent extraction.
///
/// TEMPORARY: this is a stand-in for a Gemini-backed transcript-to-intent
/// endpoint, which does not exist yet. `functions/extractVoiceIntent` is
/// written but undeployed (the Firebase project is on the Spark plan, which
/// blocks Function deployment), and the Cloudflare Worker
/// (`worker/src/index.js`) only accepts an already-structured intent object,
/// not a raw transcript. Until one of those is live, this extractor produces
/// the same shape server-side normalization expects
/// (see worker/src/voice_intent.js normalizeIntent), using keyword and
/// place-name matching instead of an LLM. Swap this out once a real
/// transcript-to-intent endpoint exists.
library;

const List<String> _indianStates = <String>[
  'Andaman and Nicobar',
  'Andhra Pradesh',
  'Arunachal Pradesh',
  'Assam',
  'Bihar',
  'Chandigarh',
  'Chhattisgarh',
  'Delhi',
  'Goa',
  'Gujarat',
  'Haryana',
  'Himachal Pradesh',
  'Jammu and Kashmir',
  'Jharkhand',
  'Karnataka',
  'Kerala',
  'Madhya Pradesh',
  'Maharashtra',
  'Manipur',
  'Meghalaya',
  'Mizoram',
  'Nagaland',
  'Odisha',
  'Pondicherry',
  'Punjab',
  'Rajasthan',
  'Sikkim',
  'Tamil Nadu',
  'Telangana',
  'Tripura',
  'Uttar Pradesh',
  'Uttarakhand',
  'West Bengal',
];

/// Major cities with curated geo coverage in worker/src/geo_regions.js, plus
/// a few other large metros likely to come up in speech.
const List<String> _knownCities = <String>[
  'Mumbai',
  'Navi Mumbai',
  'Thane',
  'Pune',
  'Bengaluru',
  'Bangalore',
  'Chennai',
  'Hyderabad',
  'Kolkata',
  'Ahmedabad',
  'Gandhinagar',
  'Kochi',
  'Jaipur',
  'Lucknow',
  'Gurugram',
  'Gurgaon',
  'Noida',
  'Faridabad',
];

/// One phrase-to-code entry in the service-category keyword table.
class _ServiceKeyword {
  const _ServiceKeyword(this.code, this.phrases);
  final String code;
  final List<String> phrases;
}

/// Phase 0 taxonomy from worker/src/voice_intent.js, plus the two query-only
/// categories (scholarship, higher_education) that do not have a
/// corresponding Firestore service code yet.
const List<_ServiceKeyword> _serviceKeywords = <_ServiceKeyword>[
  _ServiceKeyword('eye_bank', ['eye bank', 'eye donation', 'cornea']),
  _ServiceKeyword('eye_care', [
    'eye care',
    'eye checkup',
    'eye check up',
    'eye clinic',
    'eye hospital',
    'vision test',
    'ophthalmology',
  ]),
  _ServiceKeyword('healthcare', ['healthcare', 'health care', 'medical', 'hospital', 'clinic']),
  _ServiceKeyword('education', ['education', 'school', 'college', 'studies', 'academic']),
  _ServiceKeyword('vocational_training', [
    'vocational',
    'skill training',
    'job training',
    'training centre',
    'training center',
  ]),
  _ServiceKeyword('rehabilitation', ['rehabilitation', 'rehab']),
  _ServiceKeyword('employment', ['employment', 'job', 'jobs', 'placement', 'work']),
  _ServiceKeyword('financial_support', [
    'financial support',
    'financial aid',
    'financial assistance',
    'grant',
    'funding',
  ]),
  _ServiceKeyword('assistive_technology', [
    'assistive technology',
    'assistive device',
    'screen reader',
  ]),
  _ServiceKeyword('hostel', ['hostel', 'accommodation', 'residential school']),
  _ServiceKeyword('advocacy_or_government', ['advocacy', 'government scheme', 'government']),
  _ServiceKeyword('library_or_information', [
    'library',
    'libraries',
    'braille library',
    'braille book',
    'braille',
    'talking book',
    'information centre',
    'information center',
  ]),
  _ServiceKeyword('scholarship', ['scholarship', 'scholarships']),
  _ServiceKeyword('higher_education', ['higher education', 'university']),
];

const List<String> _phase0ServiceCategories = <String>[
  'eye_bank',
  'eye_care',
  'healthcare',
  'education',
  'vocational_training',
  'rehabilitation',
  'employment',
  'financial_support',
  'assistive_technology',
  'hostel',
  'advocacy_or_government',
  'library_or_information',
];

const List<String> _disabilityStatusPhrases = <String>[
  'blind',
  'visually impaired',
  'low vision',
  'vision impairment',
];

class VoiceLocation {
  const VoiceLocation({
    this.raw = '',
    this.state = '',
    this.district = '',
    this.city = '',
  });

  final String raw;
  final String state;
  final String district;
  final String city;

  Map<String, dynamic> toJson() => {
        'raw': raw,
        'state': state,
        'district': district,
        'city': city,
      };
}

class VoiceEligibilitySignal {
  const VoiceEligibilitySignal({
    required this.kind,
    required this.value,
    required this.sourceText,
  });

  final String kind;
  final String value;
  final String sourceText;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'value': value,
        'sourceText': sourceText,
      };
}

class VoiceFirestoreFilters {
  const VoiceFirestoreFilters({
    this.serviceCodes = const <String>[],
    this.state = '',
    this.district = '',
    this.organizationTypes = const <String>[],
  });

  final List<String> serviceCodes;
  final String state;
  final String district;
  final List<String> organizationTypes;

  Map<String, dynamic> toJson() => {
        'serviceCodes': serviceCodes,
        'state': state,
        'district': district,
        'organizationTypes': organizationTypes,
      };
}

class VoiceIntent {
  const VoiceIntent({
    required this.serviceCategories,
    required this.location,
    required this.eligibilitySignals,
    required this.firestoreFilters,
  });

  final List<String> serviceCategories;
  final VoiceLocation location;
  final List<VoiceEligibilitySignal> eligibilitySignals;
  final VoiceFirestoreFilters firestoreFilters;

  bool get hasAnyFilter =>
      firestoreFilters.serviceCodes.isNotEmpty ||
      firestoreFilters.state.isNotEmpty ||
      firestoreFilters.district.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'serviceCategories': serviceCategories,
        'location': location.toJson(),
        'eligibilitySignals': eligibilitySignals.map((s) => s.toJson()).toList(),
        'firestoreFilters': firestoreFilters.toJson(),
      };
}

class VoiceIntentExtractor {
  const VoiceIntentExtractor();

  VoiceIntent extract(String transcript) {
    final normalized = transcript.toLowerCase();

    final serviceCategories = <String>{};
    for (final keyword in _serviceKeywords) {
      if (keyword.phrases.any(normalized.contains)) {
        serviceCategories.add(keyword.code);
      }
    }

    final location = _extractLocation(normalized);

    final eligibilitySignals = <VoiceEligibilitySignal>[];
    for (final phrase in _disabilityStatusPhrases) {
      if (normalized.contains(phrase)) {
        eligibilitySignals.add(VoiceEligibilitySignal(
          kind: 'disability_status',
          value: phrase,
          sourceText: transcript.trim(),
        ));
        break;
      }
    }

    final serviceCodes = serviceCategories
        .where(_phase0ServiceCategories.contains)
        .toList(growable: false);

    return VoiceIntent(
      serviceCategories: serviceCategories.toList(growable: false),
      location: location,
      eligibilitySignals: eligibilitySignals,
      firestoreFilters: VoiceFirestoreFilters(
        serviceCodes: serviceCodes,
        state: location.state,
        district: location.district,
      ),
    );
  }

  VoiceLocation _extractLocation(String normalized) {
    for (final state in _indianStates) {
      if (normalized.contains(state.toLowerCase())) {
        return VoiceLocation(raw: state, state: state);
      }
    }
    for (final city in _knownCities) {
      if (normalized.contains(city.toLowerCase())) {
        return VoiceLocation(raw: city, city: city);
      }
    }
    return const VoiceLocation();
  }
}
