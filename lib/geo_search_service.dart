import 'dart:convert';
import 'dart:io';

import 'main.dart' show Resource;
import 'voice_intent_extractor.dart';

/// Result of a [GeoSearchService.search] call. [error] is a user-facing
/// message; when non-null, [resources] is always empty.
class GeoSearchResult {
  const GeoSearchResult({required this.resources, this.error});

  final List<Resource> resources;
  final String? error;

  bool get hasError => error != null;
}

/// Client for the deployed drishtibution-geo Cloudflare Worker, which reads
/// organizations from Firestore, applies the intent's filters, and ranks the
/// remaining records by geographic and service-code match. Reusing this
/// endpoint means ranking and geo-matching are never duplicated client-side.
class GeoSearchService {
  const GeoSearchService();

  static const _endpoint = 'https://drishtibution-geo.jstrust-vib.workers.dev/';

  Future<GeoSearchResult> search(VoiceIntent intent, {int limit = 20}) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(_endpoint));
      request.headers.set('content-type', 'application/json');
      request.write(jsonEncode({
        'data': {
          'intent': intent.toJson(),
          'limit': limit,
        },
      }));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) {
        return const GeoSearchResult(
          resources: <Resource>[],
          error: 'The search service could not be reached. Please try again.',
        );
      }
      final data = jsonDecode(body);
      final results = data is Map<String, dynamic> ? data['results'] : null;
      if (results is! List) {
        return const GeoSearchResult(resources: <Resource>[]);
      }
      final resources = results
          .whereType<Map<String, dynamic>>()
          .map(Resource.fromMap)
          .toList(growable: false);
      return GeoSearchResult(resources: resources);
    } catch (_) {
      return const GeoSearchResult(
        resources: <Resource>[],
        error: 'The search service could not be reached. Please try again.',
      );
    } finally {
      client.close(force: true);
    }
  }
}
