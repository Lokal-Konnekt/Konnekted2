import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'spotiflac_packages.dart';
import 'spotiflac_runtime.dart';
import 'spotiflac_storage.dart';

/// The app's one SpotiFLAC package manager, as desktop keeps one in its main
/// process. Nothing is read or started until something asks for it.
class SpotiflacService extends ChangeNotifier {
  SpotiflacService._();

  static final instance = SpotiflacService._();

  Future<SpotiflacPackages>? _packages;

  /// The loaded package manager.
  Future<SpotiflacPackages> get packages => _packages ??= _open();

  Future<SpotiflacPackages> _open() async {
    try {
      final root = Directory(
        p.join((await getApplicationSupportDirectory()).path, 'spotiflac'),
      );
      const native = NativeSpotiflac();
      final packages = SpotiflacPackages(
        root,
        storage: SpotiflacStorage(root, sealer: native),
      );
      await packages.load();
      return packages;
    } catch (_) {
      _packages = null; // Try again next time.
      rethrow;
    }
  }

  /// Tells screens showing add-ons that something changed.
  void changed() => notifyListeners();

  /// Add-ons that can find and download songs right now, in install order.
  Future<List<SpotiflacAddon>> playable() async {
    final packages = await this.packages;
    return [
      for (final addon in packages.addons)
        if (addon.enabled &&
            addon.downloads &&
            addon.searches &&
            packages.access(addon).ready)
          addon,
    ];
  }
}
