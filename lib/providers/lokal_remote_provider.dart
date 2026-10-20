import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lokal_remote_state.dart';
import '../services/lokal_remote_credentials_store.dart';
import '../services/lokal_remote_service.dart';

final lokalRemoteCredentialsStoreProvider =
    Provider<LokalRemoteCredentialsStore>(
      (ref) => SecureLokalRemoteCredentialsStore(),
    );

final lokalRemoteServiceProvider = Provider<LokalRemoteService>((ref) {
  final service = LokalRemoteService();
  ref.onDispose(service.close);
  return service;
});

final lokalRemoteControllerProvider =
    NotifierProvider<LokalRemoteController, LokalRemoteControllerState>(
      LokalRemoteController.new,
    );

/// Owns one authenticated desktop connection, including polling and bounded
/// reconnects. Remote state never enters the phone's local PlayerService.
class LokalRemoteController extends Notifier<LokalRemoteControllerState> {
  static const _pollInterval = Duration(milliseconds: 1200);
  static const _maximumBackoff = Duration(seconds: 20);

  Timer? _pollTimer;
  LokalRemoteCredentials? _credentials;
  Future<void>? _restoreTask;
  Future<void> _commandTail = Future<void>.value();
  var _polling = false;
  var _shouldPoll = false;
  var _failures = 0;
  var _generation = 0;
  var _disposed = false;

  @override
  LokalRemoteControllerState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _pollTimer?.cancel();
    });
    _restoreTask = _restore();
    unawaited(_restoreTask!);
    return const LokalRemoteControllerState();
  }

  Future<void> _restore() async {
    try {
      final credentials = await ref
          .read(lokalRemoteCredentialsStoreProvider)
          .read();
      if (_disposed || credentials == null) return;
      _credentials = credentials;
      state = state.copyWith(
        config: LokalRemoteConfig.fromCredentials(credentials),
        status: LokalRemoteConnectionStatus.disconnected,
        clearError: true,
      );
    } catch (_) {
      if (!_disposed) {
        state = state.copyWith(
          status: LokalRemoteConnectionStatus.unconfigured,
          error: 'Saved Lokal remote settings could not be read.',
        );
      }
    }
  }

  Future<void> _ensureRestored() async {
    final task = _restoreTask;
    if (task != null) await task;
  }

  Future<void> saveConfiguration({
    required String origin,
    required String remoteToken,
    required String apiKey,
  }) async {
    await _ensureRestored();
    final normalized = LokalRemoteService.normalizeOrigin(origin);
    final credentials = LokalRemoteCredentials(
      origin: normalized,
      remoteToken: remoteToken.trim(),
      apiKey: apiKey.trim(),
    );
    await ref.read(lokalRemoteCredentialsStoreProvider).write(credentials);
    if (_disposed) return;
    _generation++;
    _shouldPoll = false;
    _pollTimer?.cancel();
    _credentials = credentials;
    state = LokalRemoteControllerState(
      config: LokalRemoteConfig.fromCredentials(credentials),
      status: LokalRemoteConnectionStatus.disconnected,
    );
  }

  Future<void> forgetConfiguration() async {
    await ref.read(lokalRemoteCredentialsStoreProvider).clear();
    if (_disposed) return;
    _generation++;
    _shouldPoll = false;
    _pollTimer?.cancel();
    _credentials = null;
    state = const LokalRemoteControllerState();
  }

  void disconnect() {
    _generation++;
    _shouldPoll = false;
    _pollTimer?.cancel();
    if (_disposed) return;
    state = state.copyWith(
      status: state.config == null
          ? LokalRemoteConnectionStatus.unconfigured
          : LokalRemoteConnectionStatus.disconnected,
      clearSnapshot: true,
      clearError: true,
      commandInFlight: false,
    );
  }

  Future<void> connect() async {
    await _ensureRestored();
    if (_disposed) return;
    if (_credentials == null) {
      state = state.copyWith(
        status: LokalRemoteConnectionStatus.unconfigured,
        error: 'Save a Lokal desktop address before connecting.',
      );
      return;
    }
    _generation++;
    _shouldPoll = true;
    _failures = 0;
    _pollTimer?.cancel();
    state = state.copyWith(
      status: LokalRemoteConnectionStatus.connecting,
      clearError: true,
    );
    await _poll();
  }

  Future<void> refresh() async {
    if (!_shouldPoll) return connect();
    _pollTimer?.cancel();
    await _poll();
  }

  Future<void> sendCommand(LokalRemoteAction action, {double? value}) {
    final generation = _generation;
    Future<void> run() async {
      if (_disposed || generation != _generation) return;
      if (!state.reachable || _credentials == null) {
        throw const LokalRemoteNetworkException(
          'Connect to Lokal before sending a remote command.',
        );
      }
      final credentials = _credentials!;
      if (!_disposed) {
        state = state.copyWith(commandInFlight: true, clearError: true);
      }
      try {
        await ref
            .read(lokalRemoteServiceProvider)
            .sendCommand(credentials, action, value: value);
        if (!_disposed && generation == _generation) {
          _pollTimer?.cancel();
          unawaited(_poll());
        }
      } catch (error) {
        if (!_disposed && generation == _generation) {
          _setFailure(error);
        }
        rethrow;
      } finally {
        if (!_disposed && generation == _generation) {
          state = state.copyWith(commandInFlight: false);
        }
      }
    }

    final next = _commandTail.then<void>((_) => run(), onError: (_) => run());
    _commandTail = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  Future<void> _poll() async {
    if (_polling || _disposed || !_shouldPoll) return;
    final credentials = _credentials;
    if (credentials == null) return;
    _polling = true;
    final generation = _generation;
    try {
      final snapshot = await ref
          .read(lokalRemoteServiceProvider)
          .fetchState(credentials);
      if (_disposed || generation != _generation) return;
      _failures = 0;
      final previous = state.snapshot;
      final stale =
          previous != null &&
          previous.updatedAt > 0 &&
          snapshot.updatedAt > 0 &&
          snapshot.updatedAt < previous.updatedAt;
      if (!stale) {
        state = state.copyWith(
          status: LokalRemoteConnectionStatus.connected,
          snapshot: snapshot,
          clearError: true,
          lastSeenAt: DateTime.now(),
        );
      } else {
        state = state.copyWith(
          status: LokalRemoteConnectionStatus.connected,
          clearError: true,
          lastSeenAt: DateTime.now(),
        );
      }
    } catch (error) {
      if (!_disposed && generation == _generation) _setFailure(error);
    } finally {
      _polling = false;
      if (!_disposed && generation == _generation && _shouldPoll) {
        _schedulePoll(_nextDelay());
      }
    }
  }

  Duration _nextDelay() {
    if (_failures == 0) return _pollInterval;
    final seconds = math.min(
      _maximumBackoff.inSeconds,
      1.2 * math.pow(2, _failures - 1),
    );
    return Duration(milliseconds: (seconds * 1000).round());
  }

  void _schedulePoll(Duration delay) {
    _pollTimer?.cancel();
    _pollTimer = Timer(delay, () {
      _pollTimer = null;
      unawaited(_poll());
    });
  }

  void _setFailure(Object error) {
    _failures++;
    final status = error is LokalRemoteAuthException
        ? LokalRemoteConnectionStatus.unauthorized
        : LokalRemoteConnectionStatus.offline;
    final message = error is LokalRemoteException
        ? error.message
        : 'Could not reach Lokal on the local network.';
    state = state.copyWith(status: status, error: message);
  }
}
