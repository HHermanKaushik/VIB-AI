import 'package:flutter_test/flutter_test.dart';
import 'package:drishtibution/command_lexicon_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('local lexicon fast path returns canonical intent for English yes',
      () async {
    final service = CommandLexiconService();
    final intent = await service.matchIntent('yes please', 'en-IN');
    expect(intent, 'yes');
  });

  test('local lexicon fast path returns canonical intent for Hindi repeat',
      () async {
    final service = CommandLexiconService();
    final intent = await service.matchIntent('फिर से बोलो', 'hi-IN');
    expect(intent, 'repeat');
  });
}
