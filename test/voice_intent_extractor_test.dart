import 'package:flutter_test/flutter_test.dart';

import 'package:drishtibution/voice_intent_extractor.dart';

void main() {
  const extractor = VoiceIntentExtractor();

  test('extracts scholarship, hostel, and Delhi from a natural request', () {
    final intent = extractor.extract(
      'I am blind, live near Delhi, and need a scholarship and a hostel',
    );

    expect(intent.serviceCategories, containsAll(['scholarship', 'hostel']));
    expect(intent.location.state, 'Delhi');
    expect(intent.firestoreFilters.state, 'Delhi');
    // scholarship has no Phase 0 Firestore service code yet.
    expect(intent.firestoreFilters.serviceCodes, ['hostel']);
    expect(intent.eligibilitySignals, isNotEmpty);
    expect(intent.eligibilitySignals.first.kind, 'disability_status');
  });

  test('extracts library category and Mumbai from a Braille query', () {
    final intent = extractor.extract('Are there any Braille libraries in Mumbai');

    expect(intent.serviceCategories, contains('library_or_information'));
    expect(intent.firestoreFilters.serviceCodes, ['library_or_information']);
    expect(intent.location.city, 'Mumbai');
    expect(intent.location.state, isEmpty);
  });
}
