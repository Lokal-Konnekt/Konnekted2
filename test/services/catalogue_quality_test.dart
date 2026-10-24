import 'package:flutter_test/flutter_test.dart';
import 'package:flick/services/catalogue_quality.dart';
import 'package:flick/features/konnekted/konnekted_discovery.dart';
import 'package:flick/features/morneye/morneye_packages.dart';
import 'package:flick/features/discovery/discovery_models.dart';
import 'package:flick/models/song.dart';
import 'package:flick/widgets/lokal/lokal_quality.dart';

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
    final playing = Song(
      id: 'qobuz', title: 'Track', artist: 'Artist',
      duration: Duration.zero, fileType: qobuz.fileType,
      resolution: qobuz.resolution, bitDepth: qobuz.bitDepth,
      sampleRate: qobuz.sampleRate,
      filePath: 'lokal-progressive://audio/id',
      sourcePackage: 'konnekted.progressive',
    );
    expect(LokalQualityTier.of(playing), LokalQualityTier.hiRes,
        reason: 'Search catalogue measurements survive the player handoff');

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

  test('Amazon search never labels configured FLAC preference as track quality', () {
    expect(morneyeAdvertisedQuality(null), isNull);
    expect(morneyeAdvertisedQuality(''), isNull);
    expect(morneyeAdvertisedQuality('  '), isNull);
    expect(morneyeAdvertisedQuality('24bit/96kHz'), '24bit/96kHz');
    expect(catalogueAudioDetails(quality: morneyeAdvertisedQuality(null)), isEmpty);
  });

  test('Amazon reuses probed Full Player quality for repeat Search results', () {
    const played = Song(
      id: 'amazon-downloaded', title: 'Song', artist: 'Artist',
      duration: Duration(minutes: 3), fileType: 'FLAC',
      bitDepth: 24, sampleRate: 96000,
    );
    final details = morneyeSearchAudioDetails(verifiedPlayback: played);
    expect(details.codec, 'FLAC');
    expect(details.bitDepth, 24);
    expect(details.sampleRate, 96000);
    expect(catalogueAudioDetails(
      codec: details.codec,
      bitDepth: details.bitDepth,
      sampleRate: details.sampleRate,
    ), 'FLAC · 24-bit / 96 kHz');

    final advertised = morneyeSearchAudioDetails(
      codec: 'AAC', bitDepth: null, sampleRate: 48000,
      verifiedPlayback: played,
    );
    expect(advertised.codec, 'AAC',
        reason: 'A fresh source observation takes precedence over cache');
    expect(advertised.sampleRate, 48000);
    expect(morneyeSearchAudioDetails().codec, isNull,
        reason: 'An unplayed Amazon track cannot inherit Best FLAC');
    expect(morneyeSearchAudioDetails().sampleRate, isNull);
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
