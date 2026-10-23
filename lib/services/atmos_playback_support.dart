import 'package:flutter/services.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffprobe_kit.dart';
import 'package:flick/services/atmos_diagnostics.dart';

/// Android's MediaExtractor can report the generic audio/eac3 MIME for an
/// E-AC-3 JOC track. In that case, independently inspect the *file* with
/// FFprobe (already bundled for Mornye) before deciding the provider sent
/// stereo. Never rely on the catalogue, filename or advertised quality.
class AtmosPlaybackSupport {
  AtmosPlaybackSupport._();

  static const _channel = MethodChannel('lokal/atmos');

  static Future<bool> get available async {
    try {
      final caps = await _channel.invokeMapMethod<String, dynamic>('capabilities');
      final available = caps?['available'] == true;
      AtmosDiagnostics.record('capability', {
        'available': available,
        'jocDecoder': caps?['jocDecoder'] == true,
        'passthrough': caps?['passthrough'] == true,
        if (caps?['sdk'] is int) 'sdk': caps!['sdk'] as int,
        'reason': available ? 'native_route_available' : 'native_route_unavailable',
      });
      return available;
    } on PlatformException catch (error) {
      AtmosDiagnostics.record('capability_error', {
        'errorClass': 'PlatformException',
        'errorCode': error.code,
      });
      return false;
    } on MissingPluginException {
      AtmosDiagnostics.record('capability_error', {
        'reason': 'missing_plugin',
      });
      return false;
    }
  }

  /// Only an E-AC-3 stream with an explicit JOC/Dolby Atmos profile counts.
  /// Plain E-AC-3, AAC, FLAC, marketing metadata and file extensions do not.
  static bool isJocProfile(Map<dynamic, dynamic> stream) {
    final codec = '${stream['codec_name'] ?? stream['codec'] ?? ''}'
        .trim().toLowerCase();
    if (codec != 'eac3' && codec != 'e-ac-3' && codec != 'ec-3' &&
        codec != 'eac3-joc') return false;
    final profile = '${stream['profile'] ?? ''}'.trim();
    return RegExp(r'(?:dolby[^\r\n]*atmos|\bjoc\b)', caseSensitive: false)
        .hasMatch(profile);
  }

  static String _codecCategory(List<Map<String, dynamic>> streams) {
    if (streams.isEmpty) return 'none';
    final audio = streams.where((entry) =>
        '${entry['codec_type'] ?? 'audio'}'.toLowerCase() == 'audio');
    if (audio.isEmpty) return 'none';
    final raw = '${audio.first['codec_name'] ?? ''}'.toLowerCase();
    if ({'eac3', 'e-ac-3', 'ec-3', 'eac3-joc'}.contains(raw)) return 'eac3';
    if (raw == 'flac') return 'flac';
    if (raw == 'aac') return 'aac';
    if (raw == 'alac') return 'alac';
    return 'other';
  }

  static Future<List<Map<String, dynamic>>> _probeStreams(String path) async {
    // No transcoding or bitstream rewrite: only metadata inspection.
    final session = await FFprobeKit.getMediaInformation(path, 12000);
    final info = await session.getMediaInformation();
    return [
      for (final stream in info?.getStreams() ?? [])
        Map<String, dynamic>.from(stream.getAllProperties()),
    ];
  }

  /// Verify the staged local audio, never the catalogue. A native false may
  /// mean generic MIME, not a stereo file, hence the second probe.
  /// [probeStreams] injects an isolated FFprobe result in unit tests.
  static Future<bool> isJocFile(
    String path, {
    Future<List<Map<String, dynamic>>> Function(String path)? probeStreams,
  }) async {
    var native = false;
    try {
      native = await _channel.invokeMethod<bool>('inspect', {'path': path}) == true;
    } on PlatformException catch (error) {
      AtmosDiagnostics.record('native_probe_error', {
        'errorClass': 'PlatformException', 'errorCode': error.code,
      });
    } on MissingPluginException {
      AtmosDiagnostics.record('native_probe_error', {'reason': 'missing_plugin'});
    }
    AtmosDiagnostics.record('native_probe', {
      'encoded': native,
      'outcome': native ? 'confirmed' : 'not_confirmed',
    });
    if (native) {
      AtmosDiagnostics.record('source_probe', {
        'encoded': true, 'codec': 'eac3_joc', 'source': 'android',
        'outcome': 'confirmed',
      });
      return true;
    }

    try {
      final streams = await (probeStreams ?? _probeStreams)(path);
      final audio = streams.where((entry) =>
          '${entry['codec_type'] ?? 'audio'}'.toLowerCase() == 'audio');
      final verified = audio.any(isJocProfile);
      AtmosDiagnostics.record('ffprobe_result', {
        'codec': _codecCategory(streams),
        'trackCount': streams.length,
        'encoded': verified,
        'outcome': verified ? 'confirmed' : 'not_confirmed',
      });
      AtmosDiagnostics.record('source_probe', {
        'encoded': verified,
        'codec': verified ? 'eac3_joc' : _codecCategory(streams),
        'source': 'ffprobe',
        'outcome': verified ? 'confirmed' : 'not_confirmed',
      });
      return verified;
    } catch (error) {
      // A missing / failing probe must never approve an Atmos file.
      AtmosDiagnostics.record('ffprobe_error', {
        'errorClass': error.runtimeType.toString(),
        'reason': 'probe_unavailable',
      });
      AtmosDiagnostics.record('source_probe', {
        'encoded': false, 'codec': 'unverified',
        'outcome': 'probe_failed',
      });
      return false;
    }
  }
}
