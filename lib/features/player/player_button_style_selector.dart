import 'package:flutter/material.dart';
import 'player_button_appearance.dart';

/// Same three controls in both modes; only the button surfaces change.
class PlayerButtonStyleSelector extends StatelessWidget {
  const PlayerButtonStyleSelector({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: PlayerButtonAppearance.instance,
    builder: (context, unboxed, _) => SegmentedButton<bool>(
      segments: const [
        ButtonSegment(value: false, label: Text('Boxed')),
        ButtonSegment(value: true, label: Text('Unboxed')),
      ],
      selected: {unboxed},
      onSelectionChanged: (values) =>
          PlayerButtonAppearance.instance.setUnboxed(values.first),
    ),
  );
}
