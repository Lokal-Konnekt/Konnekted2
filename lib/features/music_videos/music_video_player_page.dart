import 'dart:async';

import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/internet_radio/radio_providers.dart';
import 'package:flick/features/konnekted/library/lokal_library_kit.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/player_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// The app's identity as the embed's referrer, as YouTube asks of apps that
/// embed its player in a WebView (its application id as an https origin).
const _appOrigin = 'https://com.lokalkonnekt.konnekted2';

final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');

/// The page holding YouTube's official IFrame embed for [videoId].
@visibleForTesting
String musicVideoEmbedHtml(String videoId) {
  assert(_videoId.hasMatch(videoId));
  final src = Uri.https('www.youtube.com', '/embed/$videoId', {
    'autoplay': '1',
    'playsinline': '1',
    'rel': '0',
    'origin': _appOrigin,
  });
  return '''<!doctype html>
<html><head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="strict-origin-when-cross-origin">
<style>html,body{margin:0;height:100%;background:#000}
iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style>
</head><body>
<iframe src="$src" title="YouTube video player"
 allow="autoplay; encrypted-media; picture-in-picture; fullscreen"
 referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>
</body></html>''';
}

/// Opens [song]'s music video, pausing what is playing first.
Future<void> openMusicVideo(
  BuildContext context,
  WidgetRef ref,
  Song song,
  String videoId,
) async {
  if (!_videoId.hasMatch(videoId)) return;
  if (ref.read(isPlayingProvider)) {
    await ref.read(playerProvider.notifier).pause();
  }
  if (ref.read(radioPlayerProvider).station != null) {
    await ref.read(radioPlayerProvider.notifier).stop();
  }
  if (!context.mounted) return;
  await pushLokal(context, MusicVideoPlayerPage(song: song, videoId: videoId));
}

/// A song's video in YouTube's own embedded player: no stream extraction,
/// no cookies or account (an incognito WebView), only youtube.com/embed.
class MusicVideoPlayerPage extends StatelessWidget {
  const MusicVideoPlayerPage({
    super.key,
    required this.song,
    required this.videoId,
  });

  final Song song;
  final String videoId;

  Future<NavigationActionPolicy> _navigate(
    InAppWebViewController controller,
    NavigationAction action,
  ) async {
    // The embed itself loads in its frame; a link out of it (the YouTube
    // logo, "Watch on YouTube") opens in the YouTube app or browser.
    if (action.isForMainFrame != true) return NavigationActionPolicy.ALLOW;
    final url = action.request.url;
    if (url == null || url.toString() == '$_appOrigin/') {
      return NavigationActionPolicy.ALLOW;
    }
    if (url.scheme == 'https') {
      unawaited(launchUrl(url, mode: LaunchMode.externalApplication));
    }
    return NavigationActionPolicy.CANCEL;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LokalPageBar(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                  Text(
                    song.artist,
                    style: TextStyle(fontSize: 16, color: t.muted),
                  ),
                ],
              ),
            ),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: InAppWebView(
                initialData: InAppWebViewInitialData(
                  data: musicVideoEmbedHtml(videoId),
                  baseUrl: WebUri('$_appOrigin/'),
                  historyUrl: WebUri('$_appOrigin/'),
                ),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,
                  incognito: true,
                  thirdPartyCookiesEnabled: false,
                  useShouldOverrideUrlLoading: true,
                  supportMultipleWindows: false,
                  // Same black-page workaround as the YouTube Music sign-in.
                  useHybridComposition: false,
                ),
                shouldOverrideUrlLoading: _navigate,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Text(
                'Played by YouTube’s embedded player.',
                style: TextStyle(color: t.muted2, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
