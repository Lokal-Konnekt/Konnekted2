import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flick/features/onboarding/tutorial_targets.dart';
import 'package:flick/l10n/l10n.dart';

/// Steps of the first-run spotlight tour.
///
/// Titles and descriptions are resolved through [title] / [description] rather
/// than stored as fields: enum values are implicitly `const`, so they can only
/// hold compile-time constants, and a localized string is resolved at runtime.
/// Keeping them as fields would pin the whole tour to English.
enum TutorialStep {
  welcome,
  navBar(spotlightTarget: TutorialTarget.navBar),
  songsTab(requiredTabIndex: 1),
  searchEntry(
    spotlightTarget: TutorialTarget.songsSearchBar,
    requiredTabIndex: 1,
  ),
  sortButton(
    spotlightTarget: TutorialTarget.songsSortButton,
    requiredTabIndex: 1,
  ),
  songCardGestures(requiredTabIndex: 1),
  miniPlayer(spotlightTarget: TutorialTarget.miniPlayer),
  settingsTab(requiredTabIndex: 2),
  fullPlayerHint,
  manualPointer(isManualPointer: true);

  const TutorialStep({
    this.spotlightTarget,
    this.requiredTabIndex,
    this.isManualPointer = false,
  });

  final TutorialTarget? spotlightTarget;
  final int? requiredTabIndex;
  final bool isManualPointer;

  /// Localized step title.
  String title(AppLocalizations l10n) => switch (this) {
        TutorialStep.welcome => l10n.welcomeToFlick2,
        TutorialStep.navBar => l10n.navigationBar,
        TutorialStep.songsTab => l10n.songsTab,
        TutorialStep.searchEntry => l10n.search,
        TutorialStep.sortButton => l10n.sortFilter,
        TutorialStep.songCardGestures => l10n.songGestures,
        TutorialStep.miniPlayer => l10n.miniPlayer,
        TutorialStep.settingsTab => l10n.settings,
        TutorialStep.fullPlayerHint => l10n.fullPlayer,
        TutorialStep.manualPointer => l10n.thatSTheTour,
      };

  /// Localized step description.
  String description(AppLocalizations l10n) => switch (this) {
        TutorialStep.welcome => l10n.letSTakeAQuickTour,
        TutorialStep.navBar => l10n.tapIconsToSwitchTabsLong,
        TutorialStep.songsTab => l10n.yourWholeLibraryLivesHereTap,
        TutorialStep.searchEntry => l10n.searchAcrossSongsArtistsAndAlbums,
        TutorialStep.sortButton => l10n.reorderFilterAndShuffleFromThis,
        TutorialStep.songCardGestures => l10n.tapToPlayLongPressFor,
        TutorialStep.miniPlayer => l10n.showsWhatSPlayingTapTo,
        TutorialStep.settingsTab => l10n.customizeAudioDisplayNavigationAnd,
        TutorialStep.fullPlayerHint => l10n.tapTheMiniPlayerForWaveform,
        TutorialStep.manualPointer => l10n.wantEveryControlDocumentedOpenThe,
      };
}

class TutorialState {
  final bool active;
  final int currentStep;
  final bool completed;
  final bool autoStartPending;

  const TutorialState({
    this.active = false,
    this.currentStep = 0,
    this.completed = false,
    this.autoStartPending = false,
  });

  TutorialState copyWith({
    bool? active,
    int? currentStep,
    bool? completed,
    bool? autoStartPending,
  }) {
    return TutorialState(
      active: active ?? this.active,
      currentStep: currentStep ?? this.currentStep,
      completed: completed ?? this.completed,
      autoStartPending: autoStartPending ?? this.autoStartPending,
    );
  }

  TutorialStep get step =>
      TutorialStep.values[currentStep.clamp(0, TutorialStep.values.length - 1)];
  bool get isLastStep => currentStep >= TutorialStep.values.length - 1;
  int get totalSteps => TutorialStep.values.length;
}

class TutorialNotifier extends Notifier<TutorialState> {
  static const _prefKey = 'tutorial_completed';
  bool _initialized = false;

  @override
  TutorialState build() {
    if (!_initialized) {
      _initialized = true;
      Future.microtask(_loadPreference);
    }
    return const TutorialState();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getBool(_prefKey) ?? false;
    if (!ref.mounted) return;
    state = state.copyWith(completed: completed);
  }

  void flagAutoStart() {
    state = const TutorialState(autoStartPending: true, completed: false);
  }

  void start() {
    state = const TutorialState(active: true, currentStep: 0);
  }

  void nextStep() {
    if (state.currentStep < TutorialStep.values.length - 1) {
      state = state.copyWith(currentStep: state.currentStep + 1);
    } else {
      complete();
    }
  }

  void previousStep() {
    if (state.currentStep > 0) {
      state = state.copyWith(currentStep: state.currentStep - 1);
    }
  }

  void skip() {
    complete();
  }

  Future<void> complete() async {
    state = const TutorialState(active: false, completed: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
  }
}

final tutorialProvider = NotifierProvider<TutorialNotifier, TutorialState>(
  TutorialNotifier.new,
);
