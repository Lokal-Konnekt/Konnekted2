import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'discovery_models.dart';

/// Bounded, redirect-free transport. The client is owned by the caller.
class DiscoveryHttp {
  DiscoveryHttp(this.client, {this.timeout = const Duration(seconds: 15)});

  final http.Client client;
  final Duration timeout;
  static const jsonLimit = 2 * 1024 * 1024;

  Future<Map<String, dynamic>> json(
    Uri url, {
    Map<String, String> headers = const {},
    Map<String, Object?>? body,
    Future<void>? cancel,
  }) async {
    final bytes = BytesBuilder(copy: false);
    await transfer(
      url,
      headers: {'Accept': 'application/json', ...headers},
      body: body,
      maxBytes: jsonLimit,
      deadline: timeout,
      onChunk: bytes.add,
      cancel: cancel,
    );
    try {
      final decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Do not expose response content, URLs or credentials in parse errors.
    }
    throw const DiscoveryException('The source returned invalid JSON.');
  }

  Future<void> transfer(
    Uri url, {
    Map<String, String> headers = const {},
    Map<String, Object?>? body,
    required int maxBytes,
    required Duration deadline,
    required FutureOr<void> Function(List<int>) onChunk,
    Future<void>? cancel,
  }) async {
    requireHttps(url.toString());
    final abort = Completer<void>();
    var timedOut = false;
    var cancelled = false;
    final timer = Timer(deadline, () {
      timedOut = true;
      if (!abort.isCompleted) abort.complete();
    });
    if (cancel != null) {
      unawaited(
        cancel.then((_) {
          cancelled = true;
          if (!abort.isCompleted) abort.complete();
        }),
      );
    }
    final request = http.AbortableRequest(
      body == null ? 'GET' : 'POST',
      url,
      abortTrigger: abort.future,
    )..followRedirects = false;
    request.headers.addAll(headers);
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    StreamIterator<List<int>>? chunks;
    try {
      // Observe an already-completed cancellation before initiating another
      // request in a manifest -> resolve -> download chain.
      await Future<void>.value();
      if (abort.isCompleted) {
        throw const DiscoveryException('Request cancelled.');
      }
      // Future.any also bounds injected clients that do not implement abort.
      final pending = client.send(request).then((response) {
        if (abort.isCompleted) {
          unawaited(response.stream.listen(null).cancel());
          throw const DiscoveryException('Request cancelled.');
        }
        return response;
      });
      final response = await Future.any([
        pending,
        abort.future.then<http.StreamedResponse>(
          (_) => throw const DiscoveryException('Request cancelled.'),
        ),
      ]);
      chunks = StreamIterator(response.stream);
      if (response.statusCode != 200) {
        throw DiscoveryException(switch (response.statusCode) {
          401 ||
          403 => 'The source refused access. Check its configuration or token.',
          404 => 'This source or recording is unavailable (HTTP 404).',
          429 => 'The source is rate limiting requests. Try again later.',
          >= 300 && < 400 =>
            'The source redirected the request. Configure its final HTTPS address.',
          _ =>
            'The source returned HTTP ${response.statusCode}. Try again later.',
        });
      }
      if ((response.contentLength ?? 0) > maxBytes) {
        throw const DiscoveryException(
          'The response exceeds the download size limit.',
        );
      }
      var received = 0;
      while (await Future.any([
        chunks.moveNext(),
        abort.future.then<bool>(
          (_) => throw const DiscoveryException('Request cancelled.'),
        ),
      ])) {
        final chunk = chunks.current;
        received += chunk.length;
        if (received > maxBytes) {
          throw const DiscoveryException(
            'The response exceeds the download size limit.',
          );
        }
        await onChunk(chunk);
      }
      if (received == 0 ||
          (response.contentLength != null &&
              received != response.contentLength)) {
        throw const DiscoveryException(
          'The source returned an empty or incomplete response.',
        );
      }
    } catch (error) {
      if (timedOut) {
        throw const DiscoveryException('The source timed out. Try again.');
      }
      if (cancelled) throw const DiscoveryException('Request cancelled.');
      if (error is DiscoveryException) rethrow;
      throw const DiscoveryException(
        'Could not reach the source securely. Check your connection.',
      );
    } finally {
      timer.cancel();
      if (!abort.isCompleted) abort.complete();
      await chunks?.cancel();
    }
  }
}
