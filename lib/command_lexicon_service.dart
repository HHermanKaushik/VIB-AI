import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

class CommandLexiconService {
  static const Set<String> canonicalIntents = {
    'next',
    'repeat',
    'more_detail',
    'stop',
    'yes',
    'no',
    'call',
    'save',
    'share',
    'directions',
    'change_language',
    'help',
  };

  Map<String, dynamic>? _lexicon;
  bool _loaded = false;

  Future<Map<String, dynamic>> load() async {
    if (_loaded && _lexicon != null) return _lexicon!;
    final raw = await rootBundle.loadString('assets/command_lexicon.json');
    final decoded = jsonDecode(raw);
    _lexicon = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    _loaded = true;
    return _lexicon!;
  }

  Future<Map<String, dynamic>?> getLanguageLexicon(String languageCode) async {
    final lexicon = await load();
    final languages = lexicon['languages'];
    if (languages is! Map<String, dynamic>) return null;
    return languages[languageCode] as Map<String, dynamic>?;
  }

  Future<String?> matchIntent(
      String transcript, String activeLanguageCode) async {
    final lexicon = await getLanguageLexicon(activeLanguageCode);
    if (lexicon == null) return null;

    final intents = lexicon['intents'];
    if (intents is! Map<String, dynamic>) return null;

    final normalizedTranscript = _normalize(transcript);
    for (final entry in intents.entries) {
      final intent = entry.key;
      final target = entry.value;
      if (target is! Map<String, dynamic>) continue;

      final phrases = target['phrases'];
      if (phrases is! List<dynamic>) continue;

      for (final phrase in phrases) {
        if (phrase is! String) continue;
        final normalizedPhrase = _normalize(phrase);

        if (normalizedTranscript.contains(normalizedPhrase)) {
          return intent;
        }

        final dist =
            _levenshteinDistance(normalizedTranscript, normalizedPhrase);
        final threshold = _fuzzyThreshold(normalizedPhrase);
        if (dist <= threshold) {
          return intent;
        }
      }
    }

    return null;
  }

  Future<String?> resolveYesNo(
    String transcript,
    String activeLanguageCode,
  ) async {
    final matchedIntent = await matchIntent(transcript, activeLanguageCode);
    if (matchedIntent == 'yes') return 'yes';
    if (matchedIntent == 'no') return 'no';

    final geminiIntent =
        await fallbackGeminiIntent(transcript, activeLanguageCode);
    if (geminiIntent == 'yes') return 'yes';
    if (geminiIntent == 'no') return 'no';

    return null;
  }

  Future<String?> fallbackGeminiIntent(
    String transcript,
    String activeLanguageCode,
  ) async {
    final base =
        Uri.parse('https://drishtibution-geo.jstrust-vib.workers.dev/intent');
    final client = HttpClient();
    try {
      final request = await client.postUrl(base);
      request.headers.set('content-type', 'application/json');
      request.headers.set('x-active-language', activeLanguageCode);
      request.write(jsonEncode({
        'transcript': transcript,
        'languageCode': activeLanguageCode,
      }));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) return null;
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      if (data is Map<String, dynamic>) {
        final intent = data['intent'];
        if (intent is String && canonicalIntents.contains(intent))
          return intent;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  String _normalize(String input) {
    var value = input.toLowerCase().trim();
    value = value.replaceAll(RegExp(r'[^a-z0-9\u0900-\u097f\s]'), '');
    value = value.replaceAll(RegExp(r'\s+'), ' ');
    return value;
  }

  int _fuzzyThreshold(String phrase) {
    final length = _normalize(phrase).length;
    if (length <= 3) return 1;
    if (length <= 6) return 2;
    return 3;
  }

  int _levenshteinDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final previous = List<int>.filled(b.length + 1, 0);
    final current = List<int>.filled(b.length + 1, 0);
    for (var j = 0; j <= b.length; j++) {
      previous[j] = j;
    }

    for (var i = 1; i <= a.length; i++) {
      current[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        final deletion = previous[j] + 1;
        final insertion = current[j - 1] + 1;
        final substitution = previous[j - 1] + cost;
        final best = deletion < insertion ? deletion : insertion;
        current[j] = best < substitution ? best : substitution;
      }
      for (var j = 0; j <= b.length; j++) {
        previous[j] = current[j];
      }
    }

    return previous[b.length];
  }
}
