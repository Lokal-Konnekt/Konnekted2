import 'package:shared_preferences/shared_preferences.dart';

/// One order for automatic playback lookups across artist/album pages,
/// recommendations and pending queues. Explicit Search source picks stay exact.
abstract final class PlaybackSourcePriority {
  static const key = 'lokal.playback.source_order';

  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(key);
    if (saved != null) return saved.toSet().toList();
    // Preserve the user's earlier pinned source as their first preference.
    final previous = prefs.getString('lokal.catalogue.playback_source');
    final order = previous == null ? <String>[] : [previous];
    await prefs.setStringList(key, order);
    await prefs.remove('lokal.catalogue.playback_source');
    return order;
  }

  static Future<List<T>> order<T>(
    List<T> available,
    String Function(T) id,
  ) async {
    final saved = await load();
    final sources = {for (final source in available) id(source): source};
    return [
      for (final key in {...saved, ...sources.keys})
        if (sources[key] case final source?) source,
    ];
  }

  static Future<void> move(List<String> visible, int from, int to) async {
    final saved = <String>{...await load(), ...visible}.toList();
    final a = saved.indexOf(visible[from]), b = saved.indexOf(visible[to]);
    final old = saved[a];
    saved[a] = saved[b];
    saved[b] = old;
    await (await SharedPreferences.getInstance()).setStringList(key, saved);
  }
}
