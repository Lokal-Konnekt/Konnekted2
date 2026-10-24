import 'package:flutter_test/flutter_test.dart';
import 'package:flick/services/catalogue_quality.dart';
import 'package:flick/features/konnekted/konnekted_discovery.dart';
import 'package:flick/features/morneye/morneye_packages.dart';
import 'package:flick/features/discovery/discovery_models.dart';

void main() {
  test('early HTTP and Morneye streams retain only advertised quality', () {
    final qobuz = advertisedOnlineAudio(
      codec: 'FLAC', quality: '24bit/96kHz',
      bitDepth: null, sampleRate: null,
    );
    expect(qobuz.fileType, 'FLAC');
    expect(qobuz.bitDepth, 24);
    expect(qobuz.sampleRate, 96000);
    expect(qobuz.resolution, '24bit/96kHz');

    final cd = advertisedOnlineAudio(
      codec: 'FLAC', quality: '16bit/44.1kHz',
      bitDepth: null, sampleRate: null,
    );
    expect(cd.sampleRate, 44100);
    final generic = advertisedOnlineAudio(
      codec: 'FLAC', quality: 'HI_RES_LOSSLESS',
      bitDepth: null, sampleRate: null,
    );
    expect(generic.bitDepth, isNull);
    expect(generic.sampleRate, isNull,
        reason: 'A broad tier cannot prove the actual sample rate');
    final opus = advertisedOnlineAudio(
      codec: 'OPUS', quality: '320kbps',
      bitDepth: null, sampleRate: null,
    );
    expect(opus.fileType, 'OPUS');
    expect(opus.resolution, '320kbps');
  });

  test('Amazon search labels requested tier without inventing measurement', () {
    final addon = MorneyeAddon(
      key: 'amzn', name: 'amazon', digest: 'test', installedAt: 0,
      methods: const ['searchTracks', 'download'],
      manifest: {
        'name': 'amazon',
        'type': ['download_provider'],
        'qualityOptions': [
          {'id': 'best', 'label': 'FLAC Best Available', 'kind': 'lossless'},
          {'id': 'opus', 'label': 'Opus 320kbps', 'kind': 'lossy'},
        ],
      },
    );
    expect(morneyeAdvertisedOrRequestedQuality(
      addon: addon, advertised: null,
      preferences: const {'downloadQuality': 'best'},
    ), 'Requested: FLAC Best Available');
    expect(morneyeAdvertisedOrRequestedQuality(
      addon: addon, advertised: '24bit/96kHz',
      preferences: const {'downloadQuality': 'best'},
    ), '24bit/96kHz');
  });

  test('catalogue quality includes only supplied bit depth and rate', () {
    expect(catalogueQualityLabel('24bit/96kHz'), '24-bit / 96 kHz');
    expect(catalogueQualityLabel('16bit/44.1kHz'), '16-bit / 44.1 kHz');
    expect(catalogueQualityLabel('24bit'), '24-bit');
    expect(catalogueQualityLabel('HI_RES_LOSSLESS'), 'Hi-res lossless');
    expect(catalogueQualityLabel('1411kbps'), '1411kbps');
    expect(catalogueAudioDetails(quality: '1411kbps'), '1411kbps');
    expect(catalogueAudioDetails(quality: '320kbps'), '320kbps');
    expect(catalogueQualityLabel(null), '');
    expect(catalogueQualityLabel(''), '');
  });

  test('all catalogue formats display genuine bit depth and sample rate', () {
    expect(catalogueAudioDetails(
      quality: 'HI_RES_LOSSLESS', bitDepth: 24, sampleRate: 96000,
    ), '24-bit / 96 kHz');
    expect(catalogueAudioDetails(
      quality: 'LOSSLESS', bitDepth: 16, sampleRate: 44100,
    ), '16-bit / 44.1 kHz');
    expect(catalogueAudioDetails(
      quality: '24bit/96kHz', bitDepth: 24,
    ), '24-bit / 96 kHz');
    expect(catalogueAudioDetails(quality: 'LOSSLESS'), 'Lossless');
    expect(catalogueAudioDetails(codec: 'FLAC', bitDepth: 24,
      sampleRate: 192000), 'FLAC · 24-bit / 192 kHz');
    expect(catalogueAudioDetails(), isEmpty);
  });

  test('Mornye normalizes Hz and fractional kHz from provider metadata', () {
    MorneyeTrack track(Map<String, Object?> details) => MorneyeTrack.of({
      'id': 't1', 'name': 'Song', 'artists': ['Artist'], ...details,
    }, 'a-tidal');

    expect(track({'bit_depth': 24, 'sampling_rate': 44.1}).bitDepth, 24);
    expect(track({'bit_depth': 24, 'sampling_rate': 44.1}).sampleRate, 44100);
    expect(track({'bitDepth': 16, 'sampleRate': 48000}).sampleRate, 48000);
    expect(track({'sample_rate': '96 kHz'}).sampleRate, 96000);
    expect(track({'sampling_rate': 88200}).sampleRate, 88200);
    expect(track({}).sampleRate, isNull);
    expect(track({}).bitDepth, isNull);
  });

  test('Atmos requests remain explicit and use a separate source identity', () {
    const stereo = DiscoveryTrack(
      id: '123', title: 'Track', artist: 'Artist',
      source: DiscoverySource.morneye, addonId: 'tidal',
      atmosAvailable: true, catalogueBitDepth: 24,
      catalogueSampleRate: 96000, catalogueQuality: 'HI_RES_LOSSLESS',
    );
    final atmos = stereo.requestAtmos();
    expect(stereo.atmosRequested, isFalse);
    expect(atmos.atmosRequested, isTrue);
    expect(atmos.atmosAvailable, isTrue);
    expect(atmos.catalogueBitDepth, 24);
    expect(atmos.catalogueSampleRate, 96000);
    expect(atmos.key, isNot(stereo.key));
    expect(atmos.atmosDownload, isFalse);
    final download = stereo.requestAtmos(downloadOnly: true);
    expect(download.atmosRequested, isTrue);
    expect(download.atmosDownload, isTrue);
    expect(download.key, atmos.key, reason: 'Both request the same JOC source');
    expect(atmos.withArtwork('https://example.test/cover.jpg').atmosRequested,
        isTrue);
    expect(download.withArtwork('https://example.test/cover.jpg').atmosDownload,
        isTrue);
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
    const api502 = 'Quality DOLBY_ATMOS failed without confirmation that '
        'the requested tier is unavailable | DOLBY_ATMOS API attempt 1: '
        'HTTP 502 for /dl/tid; DOLBY_ATMOS API attempt 2: HTTP 502 for /dl/tid';
    expect(tidalAtmosErrorMentionsMode(api502), isTrue);
    expect(tidalAtmosTransportFailure(api502), isTrue);
    expect(tidalAtmosTransportMessage(api502),
        'Tidal Atmos unavailable: download service HTTP 502. '
        'No Atmos stream was received. Retry later.');
    expect(tidalAtmosErrorMentionsMode('HTTP 502 from Qobuz'), isFalse);
    expect(tidalAtmosTierUnavailable('QUALITY_UNAVAILABLE'), isTrue);
    expect(tidalAtmosTierUnavailable(
        'TIDAL API did not report EAC3_JOC for this track'), isTrue);
    expect(tidalAtmosTierUnavailable(api502), isFalse);
    expect(tidalAtmosTransportMessage(
        'DOLBY_ATMOS API attempt 1: TimeoutException after 0:00:30'),
        contains('timed out'));
  });
}
