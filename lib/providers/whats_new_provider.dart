import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flick/providers/app_build_info_provider.dart';
import 'package:flick/features/whats_new/data/changelog_data.dart';
import 'package:flick/providers/app_preferences_provider.dart';

class WhatsNewState {
  const WhatsNewState({required this.currentEntry, required this.pendingEntry});

  /// Current Lokal notes labeled with the installed version and build.
  /// Null while installed build metadata is loading or unavailable.
  final ChangelogEntry? currentEntry;

  /// The entry that should be shown to the user as new, if any.
  final ChangelogEntry? pendingEntry;
}

class WhatsNewNotifier extends Notifier<WhatsNewState> {
  @override
  WhatsNewState build() {
    final info = ref.watch(appBuildInfoProvider).value;
    final lastSeen = ref.watch(appPreferencesProvider).lastSeenChangelogVersion;
    return _resolve(info, lastSeen);
  }

  WhatsNewState _resolve(AppBuildInfo? info, String? lastSeen) {
    if (info == null) {
      return const WhatsNewState(currentEntry: null, pendingEntry: null);
    }
    final current = ChangelogEntry(
      version: info.label,
      date: kLokalReleaseNotes.date,
      sections: kLokalReleaseNotes.sections,
    );
    return WhatsNewState(
      currentEntry: current,
      pendingEntry: lastSeen != null && lastSeen != info.identity
          ? current
          : null,
    );
  }

  /// Re-evaluates whether a "What's New" entry should be presented. Call this
  /// after the app preferences have finished loading so the stored
  /// "last seen" version is accurate.
  void evaluate() {
    final preferences = ref.read(appPreferencesProvider);
    final lastSeen = preferences.lastSeenChangelogVersion;

    state = _resolve(ref.read(appBuildInfoProvider).value, lastSeen);
  }

  /// Marks the running version as seen so the sheet does not re-appear.
  Future<void> markCurrentVersionSeen() async {
    final info = ref.read(appBuildInfoProvider).value;
    if (info == null) return;
    await ref
        .read(appPreferencesProvider.notifier)
        .setLastSeenChangelogVersion(info.identity);
    state = WhatsNewState(currentEntry: state.currentEntry, pendingEntry: null);
  }
}

final whatsNewProvider = NotifierProvider<WhatsNewNotifier, WhatsNewState>(
  WhatsNewNotifier.new,
);
