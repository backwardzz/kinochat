import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Carries demo-mode events between browser tabs of the same site.
class LocalBus {
  LocalBus(String name) : _channel = web.BroadcastChannel(name) {
    _channel.onmessage = (web.MessageEvent e) {
      final data = e.data;
      if (data.isA<JSString>()) {
        try {
          final decoded = jsonDecode((data as JSString).toDart);
          if (decoded is Map<String, dynamic>) onMessage?.call(decoded);
        } catch (_) {}
      }
    }.toJS;
  }

  final web.BroadcastChannel _channel;

  void Function(Map<String, dynamic> message)? onMessage;

  void post(Map<String, dynamic> message) {
    _channel.postMessage(jsonEncode(message).toJS);
  }

  void close() => _channel.close();
}
