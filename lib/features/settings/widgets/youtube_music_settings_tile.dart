import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flick/features/discovery/youtube_music_sign_in.dart';
import 'package:flick/features/konnekted/konnekted_discovery.dart';

/// Opt-in YouTube Music account connection, separate from catalog search.
class YoutubeMusicSettingsTile extends ConsumerStatefulWidget {
  const YoutubeMusicSettingsTile({super.key});

  @override
  ConsumerState<YoutubeMusicSettingsTile> createState() =>
      _YoutubeMusicSettingsTileState();
}

class _YoutubeMusicSettingsTileState
    extends ConsumerState<YoutubeMusicSettingsTile> {
  bool _busy = false;

  Future<void> _activate() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final current = ref.read(konnektedYoutubeMusicSessionProvider).value;
      if (current == null) {
        final session = await YoutubeMusicSignInSheet.show(context);
        if (!mounted || session == null) return;
        await ref.read(konnektedYoutubeMusicSessionProvider.notifier).save(session);
      } else {
        final signOut = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Sign out of YouTube Music?'),
            content: const Text(
              'This removes the saved account session from this device.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Sign out'),
              ),
            ],
          ),
        );
        if (!mounted || signOut != true) return;
        await CookieManager.instance().deleteAllCookies();
        await ref.read(konnektedYoutubeMusicSessionProvider.notifier).signOut();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Could not update the YouTube Music account session.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(konnektedYoutubeMusicSessionProvider);
    final signedIn = session.value?.signedIn == true;
    final subtitle = session.when(
      data: (value) => value?.signedIn == true
          ? 'Signed in · Account Discovery available'
          : 'Connect to load your mixes, Likes and history',
      loading: () => 'Checking saved session…',
      error: (_, _) => 'Session could not be read',
    );
    return ListTile(
      leading: const Icon(Icons.music_note_rounded),
      title: const Text('YouTube Music'),
      subtitle: Text(subtitle),
      trailing: _busy || session.isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : TextButton(
              onPressed: _activate,
              child: Text(signedIn ? 'Sign out' : 'Sign in'),
            ),
      onTap: _busy || session.isLoading ? null : _activate,
    );
  }
}
