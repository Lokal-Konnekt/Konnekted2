import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/features/spotify/spotify_likes_sync_service.dart';
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
  bool _connected = false, _syncLikes = false;
  @override
  void initState() {
    super.initState();
    SecureSpotifyTokenStore.sessionRevision.addListener(_load);
    unawaited(_load());
  }

  @override
  void dispose() {
    SecureSpotifyTokenStore.sessionRevision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final tokens = await SecureSpotifyTokenStore().readTokens();
    final sync = await SpotifyLikesSyncService.instance.enabled;
    if (mounted)
      setState(() {
        _connected = tokens?.sessionCookie?.isNotEmpty == true;
        _syncLikes = sync;
      });
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await SpotifyOAuthService(tokenStore: SecureSpotifyTokenStore()).logout();
      await SpotifySettingsStore().saveDiscoveryEnabled(false);
      await SpotifyLikesSyncService.instance.setEnabled(false);
      await SpotifyLikesSyncService.instance.resetCursor();
      ref.invalidate(konnektedSpotifyDiscoveryProvider);
      await _load();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not remove the Spotify session. Retry.'),
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
      final revision = SecureSpotifyTokenStore.sessionRevision.value;
      await oauth.signInWithCookie(cookie);
      // Explicit reconnection also retries a settled Canvas miss for the same cookie.
      if (SecureSpotifyTokenStore.sessionRevision.value == revision)
        SecureSpotifyTokenStore.sessionRevision.value++;
      await settings.saveDiscoveryEnabled(true);
      await _load();
      unawaited(SpotifyLikesSyncService.instance.sync());
      if (!mounted) return;
      ref.invalidate(konnektedSpotifyDiscoveryProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(lokalText('Spotify connected.'))));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              lokalText(
                error is SpotifyOAuthException ? error.message : 'Spotify connection failed. Check your network and try again.',
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
  Widget build(BuildContext context) => Column(
    children: [
      LokalSettingRow(
        label: lokalText('Spotify'),
        description: lokalText(
          _connected
              ? 'Cookie saved. Your Spotify session supplies Discovery and Canvas.'
              : 'Add your Spotify cookie for Discovery and Canvas.',
        ),
        stacked: true,
        trailing: Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            LokalSettingButton(
              label: lokalText(
                _busy
                    ? 'Connecting…'
                    : _connected
                    ? 'Update cookie'
                    : 'Enter cookie',
              ),
              onPressed: _busy ? null : () => unawaited(_connect()),
            ),
            if (_connected)
              LokalSettingButton(
                label: lokalText('Remove cookie'),
                onPressed: _busy ? null : () => unawaited(_remove()),
              ),
          ],
        ),
      ),
      LokalSettingRow.toggle(
        label: lokalText('Sync Spotify liked songs'),
        description: lokalText(
          'Watch new Spotify likes from now on and add matching library songs to Favorites. Earlier likes are not imported.',
        ),
        value: _syncLikes,
        enabled: _connected && !_busy,
        onChanged: (value) async {
          setState(() {
            _syncLikes = value;
            _busy = true;
          });
          try {
            await SpotifyLikesSyncService.instance.setEnabled(value);
          } catch (_) {
            if (mounted)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Could not start watching Spotify likes. Check your cookie and retry.',
                  ),
                ),
              );
          }
          await _load();
          if (mounted) setState(() => _busy = false);
        },
      ),
      if (_syncLikes)
        ValueListenableBuilder<String?>(
          valueListenable: SpotifyLikesSyncService.instance.status,
          builder: (context, message, _) => message == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(message),
                ),
        ),
    ],
  );
}
