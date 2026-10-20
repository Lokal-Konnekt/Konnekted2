import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';

/// The surfaces settings pages are built on: solid theme colours, like Home
/// and Library, and never a blur of what is behind them.

/// The solid card a section's rows sit on: the theme's surface with its
/// border.
class LokalSettingsCard extends StatelessWidget {
  const LokalSettingsCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Defaults to the theme's surface.
  final Color? color;

  /// Defaults to the theme's border.
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? t.surface,
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        border: Border.all(color: borderColor ?? t.border),
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

/// The hairline between two rows of a card.
class LokalSettingsDivider extends StatelessWidget {
  const LokalSettingsDivider({super.key});

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: 1,
    indent: 16,
    endIndent: 16,
    color: context.lokal.border,
  );
}

/// Free content on a settings page, lined up with the sections' cards.
class LokalSettingsBlock extends StatelessWidget {
  const LokalSettingsBlock({super.key, required this.child, this.top = 22});

  final Widget child;
  final double top;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: EdgeInsets.fromLTRB(16, top, 16, 0), child: child);
}

/// A short note: muted on the theme's raised surface, tinted orange for a
/// [warning].
class LokalSettingsNotice extends StatelessWidget {
  const LokalSettingsNotice({
    super.key,
    required this.text,
    this.warning = false,
    this.icon,
  });

  final String text;
  final bool warning;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: warning ? t.orange.withValues(alpha: .10) : t.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: warning ? t.orange.withValues(alpha: .35) : t.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon ??
                (warning
                    ? Icons.warning_amber_rounded
                    : Icons.info_outline_rounded),
            size: 18,
            color: warning ? t.orange : t.muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: LokalTheme.sans,
                fontSize: 12.5,
                height: 1.4,
                color: t.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A text field's decoration for settings: solid surface, theme border and
/// the accent on focus.
InputDecoration lokalInputDecoration(
  BuildContext context, {
  String? label,
  String? hint,
  String? helper,
  String? errorText,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  final t = context.lokal;
  OutlineInputBorder border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: color),
  );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    helperMaxLines: 3,
    errorText: errorText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    isDense: true,
    filled: true,
    fillColor: t.surface2,
    labelStyle: TextStyle(color: t.muted, fontFamily: LokalTheme.sans),
    hintStyle: TextStyle(color: t.muted2, fontFamily: LokalTheme.sans),
    helperStyle: TextStyle(color: t.muted, fontSize: 11.5),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: border(t.border),
    enabledBorder: border(t.border),
    disabledBorder: border(t.border),
    focusedBorder: border(t.accent),
    errorBorder: border(t.red),
    focusedErrorBorder: border(t.red),
  );
}

/// A capsule for a page's action: accent-filled when [primary], otherwise
/// on the raised surface; red when [destructive].
class LokalSettingsActionButton extends StatelessWidget {
  const LokalSettingsActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = true,
    this.destructive = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary;
  final bool destructive;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    final fill = destructive
        ? t.red.withValues(alpha: .12)
        : primary
        ? t.accent
        : t.surface3;
    final ink = destructive
        ? t.red
        : primary
        ? t.onAccent
        : t.text;
    final line = destructive
        ? t.red.withValues(alpha: .4)
        : primary
        ? t.accent
        : t.border2;
    return Opacity(
      opacity: onPressed == null ? .45 : 1,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        child: Material(
          color: fill,
          shape: StadiumBorder(side: BorderSide(color: line)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onPressed!();
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: ink),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: LokalTheme.sans,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A bottom sheet for settings: the theme's surface, an optional DM Mono
/// [title] and a plain dimmed barrier, no blur.
Future<T?> showLokalSettingsSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  bool isScrollControlled = false,
}) {
  final t = context.lokal;
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: t.surface,
    barrierColor: Colors.black.withValues(alpha: t.isLight ? .25 : .5),
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: isScrollControlled,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      side: BorderSide(color: t.border),
    ),
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                title.toUpperCase(),
                style: LokalTheme.label(context.lokal),
              ),
            ),
          Flexible(child: builder(context)),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// One choice in a [showLokalSettingsSheet] list.
class LokalSheetOption extends StatelessWidget {
  const LokalSheetOption({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.description,
    this.icon,
  });

  final String label;
  final String? description;
  final bool selected;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: selected ? t.accent : t.muted),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: LokalTheme.sans,
                        fontSize: 15,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected ? t.accent : t.text,
                      ),
                    ),
                    if (description != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          description!,
                          style: TextStyle(fontSize: 12.5, color: t.muted),
                        ),
                      ),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check_rounded, color: t.accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// A settings sub-page: the theme's background (like Home and Library), the
/// large title and its content scrolling under it.
///
/// [children] are usually sections; wrap free content in
/// [LokalSettingsBlock] to line it up with them. The header is given by
/// [header] so this file stays free of the kit.
class LokalSettingsPageFrame extends StatelessWidget {
  const LokalSettingsPageFrame({
    super.key,
    required this.header,
    required this.children,
    this.controller,
  });

  final Widget header;
  final List<Widget> children;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.lokal.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          controller: controller,
          padding: EdgeInsets.only(
            bottom: 32 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [header, ...children],
        ),
      ),
    );
  }
}
