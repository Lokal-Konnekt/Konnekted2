import 'package:flick/services/tidal_atmos_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('finds Dolby Atmos in the catalog modes, not only the quality tier', () {
    expect(tidalAtmosAvailable({
      'audioQuality': 'LOW', 'audioModes': ['STEREO', 'DOLBY_ATMOS'],
    }), isTrue);
    expect(tidalAtmosAvailable({'audio_mode': 'DOLBY_ATMOS'}), isTrue);
    expect(tidalAtmosAvailable({'audio_quality': 'DOLBY_ATMOS'}), isTrue);
  });

  test('lossless, hi-res and multichannel alone do not prove Atmos', () {
    expect(tidalAtmosAvailable({
      'audioQuality': 'HI_RES_LOSSLESS', 'audioModes': ['STEREO'],
    }), isFalse);
    expect(tidalAtmosAvailable({
      'codec': 'eac3', 'channels': 6, 'audioMode': 'STEREO',
    }), isFalse);
    expect(tidalAtmosAvailable({}), isFalse);
  });
}
