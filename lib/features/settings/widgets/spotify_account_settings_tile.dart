import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/features/spotify/spotify_library_screen.dart';
import 'package:flick/features/spotify/spotify_oauth.dart';
import 'package:flick/features/spotify/spotify_storage.dart';
import 'package:flick/features/konnekted/konnekted_discovery.dart';
import 'package:flick/widgets/lokal/settings/lokal_settings_kit.dart';

/// The canonical Spotify cookie entry, sharing the existing secure token store.
class SpotifyAccountSettingsTile extends ConsumerStatefulWidget {
  const SpotifyAccountSettingsTile({super.key});
  @override
  ConsumerState<SpotifyAccountSettingsTile> createState() =>
      _SpotifyAccountSettingsTileState();
}

class _SpotifyAccountSettingsTileState
    extends ConsumerState<SpotifyAccountSettingsTile> {
  bool _busy = false;

  Future<void> _connect() async {
    if (_busy) return;
    setState(() => _busy = true);
    final controller = TextEditingController();
    final cookie = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(lokalText('Connect Spotify')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              lokalText(
                'Paste the sp_dc session cookie from your signed-in Spotify web session. It is stored encrypted on this device.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: lokalText('Spotify sp_dc cookie'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(lokalText('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(lokalText('Connect')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted) return;
    if (cookie == null) {
      setState(() => _busy = false);
      return;
    }
    try {
      final settings = SpotifySettingsStore();
      final oauth = SpotifyOAuthService(tokenStore: settings.tokenStore);
      await oauth.signInWithCookie(cookie);
      await settings.saveDiscoveryEnabled(true);
      if (!mounted) return;
      ref.invalidate(konnektedSpotifyDiscoveryProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(lokalText('Spotify connected.'))));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              lokalText(
                'Could not connect Spotify. Check the sp_dc cookie and try again.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => LokalSettingRow(
    label: lokalText('Spotify'),
    description: lokalText(
      'Connect your account to load personal shelves and manage your library.',
    ),
    stacked: true,
    trailing: Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        LokalSettingButton(
          label: lokalText(_busy ? 'Connecting…' : 'Enter cookie'),
          onPressed: _busy ? null : () => unawaited(_connect()),
        ),
        LokalSettingButton(
          label: lokalText('Manage Spotify library'),
          onPressed: () => unawaited(
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SpotifyLibraryScreen(),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
