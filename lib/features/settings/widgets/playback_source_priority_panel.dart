import 'package:flutter/material.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:http/http.dart' as http;
import 'package:flick/l10n/l10n.dart';
import 'package:flick/features/konnekted/konnekted_discovery.dart';
import 'package:flick/services/playback_source_priority.dart';

class PlaybackSourcePriorityPanel extends StatefulWidget {
  const PlaybackSourcePriorityPanel({super.key});
  @override
  State<PlaybackSourcePriorityPanel> createState() =>
      _PlaybackSourcePriorityPanelState();
}

class _PlaybackSourcePriorityPanelState
    extends State<PlaybackSourcePriorityPanel> {
  final _client = http.Client();
  List<OnlineSource> _sources = [];
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final sources = await onlineSources(_client);
      if (mounted) setState(() => _sources = sources);
    } catch (_) {
      if (mounted)
        setState(
          () =>
              _error = lokalText('Could not load playback sources. Try again.'),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _move(int index, int direction) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await PlaybackSourcePriority.move(
        _sources.map((source) => source.id).toList(),
        index,
        index + direction,
      );
      final ordered = await PlaybackSourcePriority.order(
        _sources,
        (source) => source.id,
      );
      if (mounted) setState(() => _sources = ordered);
    } catch (_) {
      if (mounted)
        setState(
          () =>
              _error = lokalText('Could not save source priority. Try again.'),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_busy) const LinearProgressIndicator(),
      for (var index = 0; index < _sources.length; index++)
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          minLeadingWidth: 24,
          horizontalTitleGap: 12,
          leading: SizedBox(
            width: 24,
            child: Text(
              '${index + 1}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.lokal.muted,
                fontSize: 13,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          title: Text(_sources[index].name),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: lokalText(
                  'Move {source} up',
                  args: {'source': _sources[index].name},
                ),
                onPressed: _busy || index == 0 ? null : () => _move(index, -1),
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
              ),
              IconButton(
                tooltip: lokalText(
                  'Move {source} down',
                  args: {'source': _sources[index].name},
                ),
                onPressed: _busy || index == _sources.length - 1
                    ? null
                    : () => _move(index, 1),
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
            ],
          ),
        ),
      if (_error != null) Text(_error!),
      TextButton.icon(
        onPressed: _busy ? null : _load,
        icon: const Icon(Icons.refresh_rounded),
        label: Text(lokalText('Refresh sources')),
      ),
    ],
  );
}
