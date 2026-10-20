import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:flick/core/theme/lokal_tokens.dart';

import 'spotiflac_packages.dart';

/// An add-on's verification or login page, opened in the app the way
/// desktop opens it in its own window. When the page hands back to the
/// add-on (a `spotiflac://` link or the add-on's OAuth callback) the sheet
/// finishes the login and closes; closing it early just leaves access as it
/// was.
class SpotiflacAuthSheet extends StatefulWidget {
  const SpotiflacAuthSheet({
    super.key,
    required this.packages,
    required this.addon,
    required this.url,
  });

  final SpotiflacPackages packages;
  final SpotiflacAddon addon;
  final String url;

  /// Opens [url]; true once the add-on accepted the page's callback.
  static Future<bool> show(
    BuildContext context, {
    required SpotiflacPackages packages,
    required SpotiflacAddon addon,
    required String url,
  }) async =>
      await showModalBottomSheet<bool>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) =>
            SpotiflacAuthSheet(packages: packages, addon: addon, url: url),
      ) ==
      true;

  @override
  State<SpotiflacAuthSheet> createState() => _SpotiflacAuthSheetState();
}

class _SpotiflacAuthSheetState extends State<SpotiflacAuthSheet> {
  String? _error;
  bool _finishing = false;

  Future<NavigationActionPolicy> _navigate(
    InAppWebViewController controller,
    NavigationAction action,
  ) async {
    final url = action.request.url?.toString() ?? '';
    final key = widget.addon.key;
    bool callback;
    try {
      callback = await widget.packages.isAuthCallback(key, url);
    } catch (_) {
      callback = false;
    }
    if (callback) {
      if (!_finishing) unawaited(_finish(url));
      return NavigationActionPolicy.CANCEL;
    }
    final scheme = action.request.url?.scheme ?? '';
    // Only web pages load here: app links never leave the sheet.
    return scheme == 'https' || scheme == 'about' || scheme == 'data'
        ? NavigationActionPolicy.ALLOW
        : NavigationActionPolicy.CANCEL;
  }

  Future<void> _finish(String url) async {
    setState(() {
      _finishing = true;
      _error = null;
    });
    try {
      final result = await widget.packages.authCallback(widget.addon.key, url);
      if (!mounted) return;
      if (result['success'] == false) {
        setState(() {
          _finishing = false;
          _error =
              '${result['error'] ?? 'The add-on didn’t accept this login.'}';
        });
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _finishing = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.lokal;
    return Container(
      height: MediaQuery.sizeOf(context).height * .92,
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.addon.displayName,
                        style: TextStyle(
                          color: tokens.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Finish on the page. This closes by itself when '
                        'the add-on confirms access.',
                        style: TextStyle(color: tokens.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: Icon(Icons.close_rounded, color: tokens.muted),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                _error!,
                style: TextStyle(color: tokens.red, fontSize: 12),
              ),
            ),
          if (_finishing) LinearProgressIndicator(color: tokens.accent),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.url)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                thirdPartyCookiesEnabled: true,
                useShouldOverrideUrlLoading: true,
                mediaPlaybackRequiresUserGesture: true,
                incognito: true,
                // Same black-page workaround as the YouTube Music sign-in.
                useHybridComposition: false,
              ),
              shouldOverrideUrlLoading: _navigate,
              onReceivedError: (controller, request, error) {
                if (!mounted || request.isForMainFrame != true) return;
                // A refused app link is reported as an error: not one to show.
                if (request.url.scheme != 'https') return;
                setState(
                  () => _error =
                      'The page couldn’t be loaded. Check your connection '
                      'and try again.',
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
