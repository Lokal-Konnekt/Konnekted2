import 'package:flick/features/spotiflac/spotiflac_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('signed headers match desktop byte for byte', () {
    // Expected values come from desktop's electron/spotiflac/session.js.
    final headers = spotiflacSignedHeaders(
      {
        'headerPrefix': 'X-Zarz-',
        'schemeLabel': 'ZARZ-HMAC-V1',
        'appVersion': 'tidal-web@1.2.5',
        'platform': 'extension',
        'timeWindowSeconds': 300,
      },
      {'session_id': 'sid1', 'session_secret': 'sec'},
      'post',
      'https://api.zarz.moe/v2/tickets',
      '{"a":"é"}',
      now: DateTime.fromMicrosecondsSinceEpoch(1760937314949123, isUtc: true),
      nonce: 'abcd',
    );
    expect(headers['X-Zarz-Timestamp'], '2025-10-20T05:15:14.949Z');
    expect(
      headers['X-Zarz-Body-SHA256'],
      'b3a092a6af48807fa9482b2ee140105575daa26d5b24b3c0e60a7e2dee6683b1',
    );
    expect(
      headers['X-Zarz-Signature'],
      'd_UznKcHXh1P8UujgutVoKaevKApl08RhCSwPeee7fE',
    );
  });
}
