import 'package:flutter/material.dart';
import 'package:flick/services/lyrics_service.dart';
import 'package:flick/services/lyrics_translation_service.dart';
import 'package:flick/core/theme/lokal_tokens.dart';

class LyricsSublineButtons extends StatefulWidget {
  const LyricsSublineButtons({
    super.key,
    required this.lyrics,
    required this.onChanged,
  });
  final LyricsData lyrics;
  final ValueChanged<LyricsData?> onChanged;
  @override
  State<LyricsSublineButtons> createState() => _LyricsSublineButtonsState();
}

class _LyricsSublineButtonsState extends State<LyricsSublineButtons> {
  String? _mode;
  bool _busy = false;
  int _generation = 0;
  @override
  void didUpdateWidget(LyricsSublineButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.lyrics, widget.lyrics)) {
      _generation++;
      _mode = null;
      _busy = false;
    }
  }

  Future<void> _toggle(String mode) async {
    final generation = ++_generation;
    if (_mode == mode) {
      setState(() {
        _mode = null;
        _busy = false;
      });
      widget.onChanged(null);
      return;
    }
    setState(() {
      _mode = mode;
      _busy = true;
    });
    LyricsData? result;
    if (mode == 'translate' &&
        widget.lyrics.lines.any((l) => l.translation?.isNotEmpty == true)) {
      result = widget.lyrics;
    } else {
      result = await LyricsTranslationService.convert(
        widget.lyrics,
        romanize: mode == 'romanize',
        target: Localizations.localeOf(context).languageCode,
        current: () => mounted && generation == _generation,
      );
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _busy = false;
      if (result == null) _mode = null;
    });
    widget.onChanged(result);
    if (result == null)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mode == 'romanize'
                ? 'Romanization unavailable for these lyrics.'
                : 'Translation unavailable. Try again later.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final mode in ['translate', 'romanize'])
        IconButton(
          tooltip: mode == 'translate' ? 'Translate lyrics' : 'Romanize lyrics',
          visualDensity: VisualDensity.compact,
          isSelected: _mode == mode,
          icon: _busy && _mode == mode
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  mode == 'translate'
                      ? Icons.translate_rounded
                      : Icons.abc_rounded,
                  size: 22,
                  color: _mode == mode ? context.lokal.accent : null,
                ),
          onPressed: () => _toggle(mode),
        ),
    ],
  );
}
