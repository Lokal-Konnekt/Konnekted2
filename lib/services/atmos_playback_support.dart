import 'package:flutter/services.dart';

/// Checks Android's licensed E-AC-3 JOC decoder or a compatible direct route
/// at playback time. The catalogue flag alone never authorizes Atmos.
class AtmosPlaybackSupport {
  AtmosPlaybackSupport._();

  static const _channel = MethodChannel('lokal/atmos');

  static Future<bool> get available async {
    try {
      final caps = await _channel.invokeMapMethod<String, dynamic>('capabilities');
      return caps?['available'] == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Inspects the downloaded MP4 stream, not Tidal's metadata. False for
  /// stereo E-AC-3, unsupported containers and non-Android platforms.
  static Future<bool> isJocFile(String path) async {
    try {
      return await _channel.invokeMethod<bool>('inspect', {'path': path}) == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
