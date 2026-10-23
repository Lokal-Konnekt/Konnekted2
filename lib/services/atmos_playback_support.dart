import 'package:flutter/services.dart';
import 'package:flick/services/atmos_diagnostics.dart';

/// Checks Android's licensed E-AC-3 JOC decoder or a compatible direct route
/// at playback time. The catalogue flag alone never authorizes Atmos.
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

  /// Inspects the downloaded MP4 stream, not Tidal's metadata. False for
  /// stereo E-AC-3, unsupported containers and non-Android platforms.
  static Future<bool> isJocFile(String path) async {
    try {
      final joc = await _channel.invokeMethod<bool>('inspect', {'path': path}) == true;
      AtmosDiagnostics.record('source_probe', {
        'encoded': joc,
        'codec': joc ? 'eac3_joc' : 'unverified',
        'outcome': joc ? 'confirmed' : 'not_confirmed',
      });
      return joc;
    } on PlatformException catch (error) {
      AtmosDiagnostics.record('source_probe_error', {
        'errorClass': 'PlatformException',
        'errorCode': error.code,
      });
      return false;
    } on MissingPluginException {
      AtmosDiagnostics.record('source_probe_error', {
        'reason': 'missing_plugin',
      });
      return false;
    }
  }
}
