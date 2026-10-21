import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../models/song.dart';
import '../../providers/lokal_remote_provider.dart';
import '../../services/network_cache_service.dart';

final lokalSongAvailableProvider = FutureProvider.autoDispose.family<bool, Song>((
  ref,
  song,
) async {
  if (song.sourceType != 'lokal') return true;
  final connected = ref.watch(
    lokalRemoteControllerProvider.select((value) => value.socketConnected),
  );
  final serverId = song.remoteServerId, remoteId = song.remoteId;
  if (serverId == null || remoteId == null) return false;
  if (await NetworkCacheService().getPath(serverId, remoteId) != null)
    return true;
  if (!connected) return false;
  final credentials = await ref
      .read(lokalRemoteCredentialsStoreProvider)
      .read();
  final server = await Database.networkServers.get(serverId);
  return server != null &&
      server.username ==
          '${credentials?.desktopId}:${credentials?.desktopUserId ?? 'guest'}';
});
