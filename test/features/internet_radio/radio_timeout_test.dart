import 'dart:async';

import 'package:flick/features/internet_radio/radio_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('radio operations return normally before their deadline', () async {
    final result = await radioWithTimeout(
      Future<int>.value(42),
      timeout: const Duration(seconds: 1),
      timeoutMessage: 'not used',
    );

    expect(result, 42);
  });

  test('a stalled radio operation fails with a useful timeout error', () async {
    final pending = Completer<void>();

    await expectLater(
      radioWithTimeout(
        pending.future,
        timeout: const Duration(milliseconds: 10),
        timeoutMessage: 'The station stream did not respond in time.',
      ),
      throwsA(
        isA<RadioCatalogException>().having(
          (error) => error.message,
          'message',
          'The station stream did not respond in time.',
        ),
      ),
    );
  });

  test('a malformed catalogue fails instead of returning an empty list', () {
    expect(
      () => parseRadioCatalog({'stations': []}),
      throwsA(isA<RadioCatalogException>()),
    );
  });
}
