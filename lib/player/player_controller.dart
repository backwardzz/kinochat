import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models.dart';

enum PlayerPhase { idle, paused, playing, buffering, ended }

/// Last report from the player page.
class PlayerStatus {
  const PlayerStatus({
    this.kind,
    this.phase = PlayerPhase.idle,
    this.time = 0,
    this.duration = 0,
    this.blocked = false,
    this.title,
  });

  final VideoKind? kind;
  final PlayerPhase phase;
  final double time;
  final double duration;

  /// The browser refused to start playback without a tap on the video.
  final bool blocked;
  final String? title;
}

/// Talks to `assets/player/player.html`. The view supplies the transport:
/// postMessage in the browser, a JavaScript channel in the app.
class PlayerController extends ChangeNotifier {
  void Function(String json)? _sink;
  bool _hostReady = false;

  PlayerStatus status = const PlayerStatus();
  String? error;

  bool get hostReady => _hostReady;

  /// Called when the page (re)starts: it has nothing loaded, so whoever
  /// drives the player has to load the video again.
  VoidCallback? onHostReady;

  void attach(void Function(String json) sink) {
    _sink = sink;
  }

  void detach() {
    _sink = null;
    _hostReady = false;
  }

  void handleHostMessage(String json) {
    final Map<String, dynamic> m;
    try {
      m = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (m['ev']) {
      case 'ready':
        _hostReady = true;
        status = const PlayerStatus();
        onHostReady?.call();
        notifyListeners();
      case 'state':
        _hostReady = true;
        status = PlayerStatus(
          kind: videoKindFromName(m['kind'] as String?),
          phase: switch (m['st']) {
            'playing' => PlayerPhase.playing,
            'paused' => PlayerPhase.paused,
            'buffering' => PlayerPhase.buffering,
            'ended' => PlayerPhase.ended,
            _ => PlayerPhase.idle,
          },
          time: (m['t'] as num?)?.toDouble() ?? 0,
          duration: (m['d'] as num?)?.toDouble() ?? 0,
          blocked: m['blocked'] == true,
          title: m['title'] as String?,
        );
        notifyListeners();
      case 'error':
        error = (m['msg'] as String?) ?? 'Не удалось воспроизвести видео.';
        notifyListeners();
    }
  }

  /// Commands sent before the page is up are dropped; [onHostReady] is the
  /// cue to send the current state.
  void _send(Map<String, dynamic> cmd) {
    if (!_hostReady) return;
    cmd['kc'] = 1;
    _sink?.call(jsonEncode(cmd));
  }

  void load(VideoSource source, {double startSec = 0, bool autoplay = false}) {
    error = null;
    _send({
      'cmd': 'load',
      'kind': source.kind.name,
      'ref': source.ref,
      'start': startSec,
      'autoplay': autoplay,
    });
  }

  void play() => _send({'cmd': 'play'});
  void pause() => _send({'cmd': 'pause'});
  void seek(double sec) => _send({'cmd': 'seek', 't': sec});

  void stop() {
    error = null;
    _send({'cmd': 'stop'});
  }
}
