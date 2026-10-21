import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/services/discord_presence_service.dart';
import 'package:flick/core/theme/lokal_tokens.dart';

class DiscordPresenceSettingsTile extends StatelessWidget {
  const DiscordPresenceSettingsTile({super.key});

  @override
  Widget build(BuildContext context) {
    final service = DiscordPresenceService.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(
          lokalText('Share what you’re listening to'),
          style: TextStyle(color: context.lokal.text),
        ),
        subtitle: Text(
          lokalText(service.status),
          style: TextStyle(color: context.lokal.text.withValues(alpha: 0.6)),
        ),
        value: service.enabled && service.configured,
        onChanged: service.configured
            ? (value) => unawaited(service.setEnabled(value))
            : null,
      ),
    );
  }
}
