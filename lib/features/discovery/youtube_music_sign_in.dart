import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'youtube_music_account.dart';

const _musicUrl = 'https://music.youtube.com';
const _desktopUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';

/// Interactive sign-in sheet. It only returns after a usable session cookie
/// is present on music.youtube.com.
class YoutubeMusicSignInSheet extends StatefulWidget {
  const YoutubeMusicSignInSheet({super.key});

  static Future<YoutubeMusicSession?> show(BuildContext context) =>
      showModalBottomSheet<YoutubeMusicSession>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const YoutubeMusicSignInSheet(),
      );

  @override
  State<YoutubeMusicSignInSheet> createState() =>
      _YoutubeMusicSignInSheetState();
}

class _YoutubeMusicSignInSheetState extends State<YoutubeMusicSignInSheet> {
  bool _capturing = false;
  String? _error;

  Uri get _signInUri => Uri.https('accounts.google.com', '/ServiceLogin', {
    'ltmpl': 'music',
    'service': 'youtube',
    'continue':
        'https://www.youtube.com/signin?action_handle_signin=true&app=desktop&next=https://music.youtube.com/',
  });

  Future<void> _capture(InAppWebViewController controller, WebUri? uri) async {
    if (_capturing || uri?.host != 'music.youtube.com') return;
    _capturing = true;
    try {
      final cookieList = await CookieManager.instance().getCookies(
        url: WebUri(_musicUrl),
      );
      final cookies = <String, String>{
        for (final cookie in cookieList)
          if (cookie.name.isNotEmpty && '${cookie.value ?? ''}'.isNotEmpty)
            cookie.name: '${cookie.value}',
      };
      final raw = await controller.evaluateJavascript(
        source:
            'JSON.stringify({'
            'sessionIndex: window.ytcfg && ytcfg.get("SESSION_INDEX"),'
            'delegatedSessionId: window.ytcfg && ytcfg.get("DELEGATED_SESSION_ID"),'
            'visitorData: window.ytcfg && ytcfg.get("VISITOR_DATA"),'
            'clientVersion: window.ytcfg && ytcfg.get("INNERTUBE_CLIENT_VERSION")'
            '})',
      );
      Map<String, dynamic> contextValues = {};
      try {
        final decoded = raw is String ? jsonDecode(raw) : raw;
        if (decoded is Map<String, dynamic>) contextValues = decoded;
      } catch (_) {
        // A usable cookie session can still exist when ytcfg is not exposed.
      }
      final session = YoutubeMusicSession(
        cookies: cookies,
        userAgent: _desktopUserAgent,
        sessionIndex: contextValues['sessionIndex']?.toString(),
        delegatedSessionId: contextValues['delegatedSessionId']?.toString(),
        visitorData: contextValues['visitorData']?.toString(),
        clientVersion: contextValues['clientVersion']?.toString(),
      );
      if (session.signedIn && mounted) {
        Navigator.of(context).pop(session);
      } else if (mounted) {
        setState(() {
          _error =
              'Finish signing in on the page. The sheet will close when YouTube Music confirms your session.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not read the YouTube Music session. Try signing in again.';
        });
      }
    } finally {
      _capturing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.sizeOf(context).height * .92,
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sign in to YouTube Music',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      SizedBox(height: 4),
                      Text('Your session is stored securely on this device.',
                          style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(_error!, style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              )),
            ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(_signInUri.toString())),
              initialSettings: InAppWebViewSettings(
                userAgent: _desktopUserAgent,
                javaScriptEnabled: true,
                thirdPartyCookiesEnabled: true,
                domStorageEnabled: true,
                useShouldOverrideUrlLoading: true,
                mediaPlaybackRequiresUserGesture: true,
              ),
              onLoadStop: _capture,
              onReceivedError: (controller, request, error) {
                if (!mounted || request.isForMainFrame != true) return;
                setState(() => _error =
                    'The sign-in page could not be loaded. Check your connection and try again.');
              },
            ),
          ),
        ],
      ),
    );
  }
}
