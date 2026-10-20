import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'youtube_music_account.dart';

const _musicUrl = 'https://music.youtube.com';

/// BitChord's first-party YouTube Music login flow. In particular, do not
/// impersonate desktop Chrome: use Android WebView's real user agent and let
/// Google's ServiceLogin redirect directly to YouTube Music.
Uri youtubeMusicSignInUri() => Uri.https(
  'accounts.google.com',
  '/ServiceLogin',
  {
    'ltmpl': 'music',
    'service': 'youtube',
    'passive': 'true',
    'continue': '$_musicUrl/',
  },
);

const _ytcfgProbe = r'''
(function () {
  try {
    if (!window.ytcfg || typeof window.ytcfg.get !== 'function') return null;
    var get = function (key) {
      var value = window.ytcfg.get(key);
      return (value === undefined || value === null || value === '') ? null : String(value);
    };
    return {
      loggedIn: String(!!window.ytcfg.get('LOGGED_IN')),
      sessionIndex: get('SESSION_INDEX'),
      delegatedSessionId: get('DELEGATED_SESSION_ID'),
      visitorData: get('VISITOR_DATA'),
      clientVersion: get('INNERTUBE_CLIENT_VERSION'),
      userAgent: navigator.userAgent
    };
  } catch (e) {
    return null;
  }
})()
''';

Map<String, dynamic> _decodeYtcfg(Object? raw) {
  Object? decoded = raw;
  // WebView implementations differ in whether they return a JS object or a
  // JSON-encoded string. Accept either without relying on double encoding.
  for (var i = 0; i < 2 && decoded is String; i++) {
    try {
      decoded = jsonDecode(decoded as String);
    } on FormatException {
      return {};
    }
  }
  if (decoded is Map) return Map<String, dynamic>.from(decoded);
  return {};
}

/// Interactive sign-in sheet. A session is saved only after the user confirms
/// the selected YouTube Music profile and the live page reports LOGGED_IN.
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
  InAppWebViewController? _controller;
  bool _pageReady = false;
  bool _capturing = false;
  String? _error;

  Future<void> _onLoadStop(
    InAppWebViewController controller,
    WebUri? uri,
  ) async {
    _controller = controller;
    if (!mounted) return;
    final isMusicPage =
        uri?.scheme == 'https' && uri?.host == 'music.youtube.com';
    setState(() {
      _pageReady = isMusicPage;
      if (isMusicPage) _error = null;
    });
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (_capturing || !_pageReady || controller == null) return;
    setState(() {
      _capturing = true;
      _error = null;
    });

    try {
      final cookieList = await CookieManager.instance().getCookies(
        url: WebUri(_musicUrl),
      );
      final cookies = <String, String>{
        for (final cookie in cookieList)
          if (cookie.name.isNotEmpty && '${cookie.value ?? ''}'.isNotEmpty)
            cookie.name: '${cookie.value}',
      };

      final contextValues = _decodeYtcfg(
        await controller.evaluateJavascript(source: _ytcfgProbe),
      );
      final loggedInValue = contextValues['loggedIn'];
      final loggedIn = loggedInValue == true ||
          '${loggedInValue ?? ''}'.toLowerCase() == 'true';
      if (!loggedIn) {
        if (mounted) {
          setState(() {
            _error =
                'YouTube Music has not confirmed a signed-in profile yet. Finish choosing your account on the page, then try again.';
          });
        }
        return;
      }

      final userAgent = contextValues['userAgent']?.toString().trim() ?? '';
      if (userAgent.isEmpty) {
        if (mounted) {
          setState(() {
            _error =
                'Could not read the browser session. Reload YouTube Music and try again.';
          });
        }
        return;
      }

      final session = YoutubeMusicSession(
        cookies: cookies,
        // Keep the actual Android WebView UA. Replacing it with a desktop UA
        // creates a mismatch between the sign-in page and Innertube requests.
        userAgent: userAgent,
        sessionIndex: contextValues['sessionIndex']?.toString(),
        delegatedSessionId: contextValues['delegatedSessionId']?.toString(),
        visitorData: contextValues['visitorData']?.toString(),
        clientVersion: contextValues['clientVersion']?.toString(),
      );
      if (!session.signedIn) {
        if (mounted) {
          setState(() {
            _error =
                'YouTube Music is open, but no signing cookie was found. Finish signing in and try again.';
          });
        }
        return;
      }

      if (mounted) Navigator.of(context).pop(session);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Could not read the YouTube Music session. Reload the page and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
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
                      Text(
                        'Sign in to YouTube Music',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Your session is stored securely on this device.',
                        style: TextStyle(fontSize: 12),
                      ),
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
              child: Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(youtubeMusicSignInUri().toString()),
              ),
              initialSettings: InAppWebViewSettings(
                // Deliberately omit userAgent: use the native Android
                // WebView identity, as BitChord does.
                javaScriptEnabled: true,
                thirdPartyCookiesEnabled: true,
                domStorageEnabled: true,
                mediaPlaybackRequiresUserGesture: true,
                // Drawn as a texture: as a hybrid-composition view the page
                // stays black under Impeller on Android 12 and later.
                useHybridComposition: false,
              ),
              onWebViewCreated: (controller) => _controller = controller,
              onLoadStop: _onLoadStop,
              onReceivedError: (controller, request, error) {
                if (!mounted || request.isForMainFrame != true) return;
                setState(() {
                  _pageReady = false;
                  _error =
                      'The sign-in page could not be loaded. Check your connection and try again.';
                });
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Choose your YouTube Music profile, then confirm.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed:
                      _pageReady && !_capturing ? _capture : null,
                  child: _capturing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Use this account'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
