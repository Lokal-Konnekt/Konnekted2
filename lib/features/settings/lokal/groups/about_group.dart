import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flick/core/constants/app_constants.dart';
import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/manual/screens/manual_screen.dart';
import 'package:flick/features/settings/screens/logs_screen.dart';
import 'package:flick/features/settings/screens/privacy_policy_screen.dart';
import 'package:flick/features/whats_new/widgets/whats_new_bottom_sheet.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/providers/tutorial_provider.dart';
import 'package:flick/widgets/lokal/lokal_logo.dart';
import 'package:flick/widgets/lokal/settings/lokal_settings_kit.dart';

void _push(BuildContext context, Widget page) => unawaited(
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)),
);

/// Where Lokal for Android's releases are published.
const lokalReleasesUrl = 'https://github.com/Lokal-Konnekt/Konnekted2/releases';

bool _licencesRegistered = false;

/// The open-source licences, with Flick's MIT licence (this app grew from
/// Flick) and the bundled Chinese font's added to the packages' own.
void openLokalLicences(BuildContext context) {
  if (!_licencesRegistered) {
    _licencesRegistered = true;
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks([
        'Flick',
      ], l10n.mitLicenseCopyrightC2026Flick);
      yield LicenseEntryWithLineBreaks([
        'Noto Sans SC',
      ], await rootBundle.loadString('assets/fonts/NotoSansSC-OFL.txt'));
    });
  }
  unawaited(
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const LicensePage(
          applicationName: 'Lokal',
          applicationVersion: kAppVersion,
          applicationIcon: Padding(
            padding: EdgeInsets.all(8),
            child: LokalLogo(size: 48),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) throw StateError('No app opened the link');
  } catch (_) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('Couldn’t open the link.')),
    );
  }
}

/// About: version, updates, what's new, help, licences, privacy and logs.
List<LokalSettingsSection> aboutSettings(BuildContext context, WidgetRef ref) {
  final t = context.lokal;
  return [
    LokalSettingsSection(
      title: 'About',
      children: [
        LokalSettingRow(
          label: 'Version',
          description: 'The version you’re running.',
          trailing: Text(
            kAppVersion,
            style: LokalTheme.label(t, size: 12, color: t.text),
          ),
        ),
        LokalSettingLink(
          label: 'Updates',
          description: 'New versions are published on GitHub.',
          onTap: () => unawaited(_open(context, lokalReleasesUrl)),
        ),
        LokalSettingLink(
          label: 'What’s new',
          description: 'What changed in this version.',
          onTap: () => unawaited(WhatsNewBottomSheet.show<void>(context)),
        ),
      ],
    ),
    LokalSettingsSection(
      title: 'Help',
      children: [
        LokalSettingLink(
          label: 'Help',
          description: 'Every control, explained.',
          onTap: () => _push(context, const ManualScreen()),
        ),
        LokalSettingLink(
          label: 'Interactive tutorial',
          description: 'A step-by-step tour of the app.',
          onTap: () {
            ref.read(tutorialProvider.notifier).start();
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
        ),
      ],
    ),
    LokalSettingsSection(
      title: 'Legal',
      children: [
        LokalSettingLink(
          label: 'Licences',
          description: 'The open-source software Lokal is built with.',
          onTap: () => openLokalLicences(context),
        ),
        LokalSettingLink(
          label: 'Privacy',
          description: 'What Lokal keeps and what it sends.',
          onTap: () => _push(context, const PrivacyPolicyScreen()),
        ),
      ],
    ),
    LokalSettingsSection(
      title: 'Debug',
      children: [
        LokalSettingLink(
          label: 'Debug logs',
          description: 'Lokal’s logs, to attach to a bug report.',
          onTap: () => _push(context, const LogsScreen()),
        ),
      ],
    ),
  ];
}
