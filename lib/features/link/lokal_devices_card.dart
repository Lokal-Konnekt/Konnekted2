import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/lokal_tokens.dart';
import '../../l10n/l10n.dart';
import '../../providers/lokal_remote_provider.dart';
import 'lokal_desktop_link_screen.dart';

class LokalDevicesCard extends ConsumerWidget {
  const LokalDevicesCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = ref.watch(lokalRemoteControllerProvider), t = context.lokal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Material(
        color: t.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: t.border),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 8,
          ),
          leading: Icon(Icons.devices_rounded, color: t.accent),
          title: Text(
            l10n.linkDevices,
            style: TextStyle(color: t.text, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            link.configured
                ? '${link.desktopName} · ${link.reachable ? l10n.linkConnected : l10n.linkOffline}'
                : l10n.linkConnectDesktop,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: t.muted),
          ),
          trailing: Icon(Icons.chevron_right_rounded, color: t.muted),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const LokalDesktopLinkScreen()),
          ),
        ),
      ),
    );
  }
}

class LokalOutputPill extends ConsumerWidget {
  const LokalOutputPill({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = ref.watch(lokalRemoteControllerProvider), t = context.lokal;
    if (!link.controlsDesktop) return const SizedBox.shrink();
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const LokalDesktopLinkScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: t.accentSoft,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.desktop_windows_rounded, size: 12, color: t.accent),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                l10n.linkOutputName(link.desktopName),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.accent, fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
