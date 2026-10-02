import 'dart:async';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'player/player_controller.dart';
import 'services/backend.dart';

/// Keeps the local player in step with the room.
///
/// The room has one shared [PlaybackState]. Whoever presses play, pause or
/// seeks publishes a new state; everyone else steers their player towards it.
class RoomController extends ChangeNotifier {
  RoomController(this.session) : state = session.initialPlayback {
    player.onHostReady = _onHostReady;
    player.addListener(_reconcile);
    _playbackSub = session.remotePlayback.listen(_onRemote);
  }

  final RoomSession session;
  final PlayerController player = PlayerController();

  PlaybackState state;

  /// Short line about what someone else just did, e.g. "Аня · пауза".
  final ValueNotifier<String?> notice = ValueNotifier(null);

  late final StreamSubscription<PlaybackState> _playbackSub;
  Timer? _noticeTimer;
  String? _loadedKey;
  DateTime _lastCommand = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastDriftFix = DateTime.fromMillisecondsSinceEpoch(0);

  static const _settle = Duration(milliseconds: 1200);
  static const _driftFixEvery = Duration(seconds: 4);
  static const _maxDriftSec = 2.0;

  VideoSource? get source => state.source;

  double get expectedSec =>
      state.expectedPositionMs(serverNowMs(session)) / 1000;

  /// Title from search results, or the one the player found out by itself.
  String? get title => state.source?.title ?? player.status.title;

  // ---- actions of the person holding this device -------------------------

  Future<void> setVideo(VideoSource src) {
    return _publish(
      PlaybackState(
        source: src,
        playing: src.syncable,
        positionMs: (src.startSec * 1000).round(),
        atMs: serverNowMs(session),
        by: session.me.name,
      ),
    );
  }

  Future<void> closeVideo() {
    return _publish(
      PlaybackState(
        source: null,
        playing: false,
        positionMs: 0,
        atMs: serverNowMs(session),
        by: session.me.name,
      ),
    );
  }

  Future<void> togglePlay() {
    final src = state.source;
    if (src == null || !src.syncable) return Future.value();
    // After the end, the button starts the video over.
    final ended = player.status.phase == PlayerPhase.ended;
    final at = ended ? 0.0 : _localTime();
    return _publish(
      PlaybackState(
        source: src,
        playing: !state.playing || ended,
        positionMs: (at * 1000).round(),
        atMs: serverNowMs(session),
        by: session.me.name,
      ),
    );
  }

  Future<void> seekTo(double sec) {
    final src = state.source;
    if (src == null || !src.syncable) return Future.value();
    final d = player.status.duration;
    final target = d > 0 ? sec.clamp(0.0, d) : (sec < 0 ? 0.0 : sec);
    return _publish(
      PlaybackState(
        source: src,
        playing: state.playing,
        positionMs: (target * 1000).round(),
        atMs: serverNowMs(session),
        by: session.me.name,
      ),
    );
  }

  Future<void> seekBy(double deltaSec) => seekTo(_localTime() + deltaSec);

  double _localTime() {
    final s = player.status;
    final known = s.kind != null && _loadedKey == state.source?.key;
    return known ? s.time : expectedSec;
  }

  Future<void> _publish(PlaybackState next) async {
    state = next;
    _apply(seek: true);
    notifyListeners();
    try {
      await session.sendPlayback(next);
    } catch (e) {
      _showNotice('Не удалось отправить: нет связи');
    }
  }

  // ---- changes made by others --------------------------------------------

  void _onRemote(PlaybackState next) {
    final prev = state;
    state = next;
    _apply(seek: true);
    _showNotice(_describe(prev, next));
    notifyListeners();
  }

  String _describe(PlaybackState prev, PlaybackState next) {
    final who = next.by.isEmpty ? 'Кто-то' : next.by;
    if (next.source == null) return '$who · видео закрыто';
    if (prev.source?.key != next.source!.key) return '$who · новое видео';
    if (prev.playing != next.playing) {
      return next.playing ? '$who · воспроизведение' : '$who · пауза';
    }
    return '$who · перемотка на ${formatTime(next.positionMs / 1000)}';
  }

  void _showNotice(String text) {
    notice.value = text;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 3), () => notice.value = null);
  }

  // ---- steering the player -----------------------------------------------

  void _onHostReady() {
    _loadedKey = null;
    _apply(seek: true);
  }

  /// Pushes the room state into the player right away.
  void _apply({required bool seek}) {
    if (!player.hostReady) return;
    final src = state.source;
    if (src == null) {
      if (_loadedKey != null) player.stop();
      _loadedKey = null;
      return;
    }
    final target = expectedSec;
    if (_loadedKey != src.key) {
      _loadedKey = src.key;
      player.load(src, startSec: target, autoplay: state.playing);
      _lastCommand = DateTime.now();
      return;
    }
    if (!src.syncable) return;
    if (seek && (player.status.time - target).abs() > 0.7) player.seek(target);
    if (state.playing) {
      player.play();
    } else {
      player.pause();
    }
    _lastCommand = DateTime.now();
    _lastDriftFix = _lastCommand;
  }

  /// Runs on every player report; nudges the player when it has wandered off.
  void _reconcile() {
    final src = state.source;
    if (src == null || !src.syncable || !player.hostReady) return;
    if (_loadedKey != src.key) {
      _apply(seek: true);
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastCommand) < _settle) return;

    final s = player.status;
    if (s.kind == null || s.blocked || player.error != null) return;

    final target = expectedSec;
    final pastEnd = s.duration > 0 && target > s.duration + 1;

    if (state.playing) {
      if (s.phase == PlayerPhase.paused && !pastEnd) {
        player.play();
        _lastCommand = now;
      } else if (s.phase == PlayerPhase.playing &&
          !pastEnd &&
          (s.time - target).abs() > _maxDriftSec &&
          now.difference(_lastDriftFix) > _driftFixEvery) {
        player.seek(target);
        _lastDriftFix = now;
        _lastCommand = now;
      }
    } else {
      if (s.phase == PlayerPhase.playing || s.phase == PlayerPhase.buffering) {
        player.pause();
        _lastCommand = now;
      } else if (s.phase == PlayerPhase.paused &&
          (s.time - target).abs() > _maxDriftSec &&
          now.difference(_lastDriftFix) > _driftFixEvery) {
        player.seek(target);
        _lastDriftFix = now;
        _lastCommand = now;
      }
    }
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _playbackSub.cancel();
    player.removeListener(_reconcile);
    player.dispose();
    notice.dispose();
    super.dispose();
  }
}

/// `1:05` or `1:02:07`.
String formatTime(double seconds) {
  final total = seconds.isFinite && seconds > 0 ? seconds.floor() : 0;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}
