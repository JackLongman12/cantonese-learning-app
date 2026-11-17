import 'package:duk/platform/word_voice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the default is "Phone voice 2 (online)", else the first online voice', () {
    const local = PhoneVoice('yue-hk-x-jar-local', 'yue-HK');
    const jar = PhoneVoice('yue-hk-x-jar-network', 'yue-HK', online: true);
    const yuc = PhoneVoice('yue-hk-x-yuc-network', 'yue-HK', online: true);
    // the picker's order: online first, then by name
    expect(WordVoice.defaultVoice([jar, yuc, local]), yuc);
    // only one online voice: that one
    expect(WordVoice.defaultVoice([jar, local]), jar);
    // none online: the engine's own default voice
    expect(WordVoice.defaultVoice([local]), isNull);
    expect(WordVoice.defaultVoice(const []), isNull);
  });
}
