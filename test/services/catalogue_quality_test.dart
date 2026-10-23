import 'package:flutter_test/flutter_test.dart';
import 'package:flick/services/catalogue_quality.dart';
import 'package:flick/features/konnekted/konnekted_discovery.dart';

void main() {
  test('catalogue quality includes only supplied bit depth and rate', () {
    expect(catalogueQualityLabel('24bit/96kHz'), '24-bit / 96 kHz');
    expect(catalogueQualityLabel('16bit/44.1kHz'), '16-bit / 44.1 kHz');
    expect(catalogueQualityLabel('24bit'), '24-bit');
    expect(catalogueQualityLabel('HI_RES_LOSSLESS'), 'Hi-res lossless');
    expect(catalogueQualityLabel(null), '');
    expect(catalogueQualityLabel(''), '');
  });

  test('Tidal Atmos transport errors do not imply unavailable tier', () {
    const error = 'Quality DOLBY_ATMOS failed without confirmation that the '
        'requested tier is unavailable | API attempt 1: TimeoutException '
        'after 0:00:30.000000';
    expect(tidalAtmosTransportFailure(error), isTrue);
    expect(tidalAtmosTransportMessage(error), contains('timed out'));
    expect(tidalAtmosTransportFailure('DOLBY_ATMOS API: HTTP 502 for /dl/tid'), isTrue);
    expect(tidalAtmosTransportMessage('HTTP 502 for /dl/tid'), contains('HTTP 502'));
    expect(tidalAtmosTransportFailure('QUALITY_UNAVAILABLE'), isFalse);
  });
}
