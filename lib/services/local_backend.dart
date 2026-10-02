import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models.dart';
import 'backend.dart';
import 'local_bus.dart';
import 'prefs.dart';

/// Demo mode: rooms are stored on the device. In the browser, tabs of the
/// same site see each other, which is enough to try everything out.
class LocalBackend implements Backend {
  LocalBackend(this._prefs);

  final Prefs _prefs;

  @override
  bool get isDemo => true;

  static String _key(String code) => 'demo_room_$code';

  @override
  Future<Room> createRoom(String name) async {
    final room = Room(id: newId(), code: newRoomCode(), name: name);
    await _prefs.setString(
      _key(room.code),
      jsonEncode({'room': room.toJson(), 'playback': null, 'messages': []}),
    );
    return room;
  }

  @override
  Future<Room?> findRoom(String code) async {
    await _prefs.reload();
    final raw = _prefs.getString(_key(code));
    if (raw == null) return null;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return Room.fromJson(data['room'] as Map<String, dynamic>);
  }

  @override
  Future<RoomSession> join(Room room, UserProfile me) async {
    await _prefs.reload();
    final raw = _prefs.getString(_key(room.code));
    final data = raw == null
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    final session = _LocalSession(
      room: room,
      me: me,
      prefs: _prefs,
      storageKey: _key(room.code),
      initialPlayback: PlaybackState.fromJson(
        data['playback'] as Map<String, dynamic>?,
      ),
      history: [
        for (final m in (data['messages'] as List? ?? const []))
          ChatMessage.fromJson(m as Map<String, dynamic>),
      ],
    );
    session._start();
    return session;
  }
}

class _LocalSession implements RoomSession {
  _LocalSession({
    required this.room,
    required this.me,
    required this._prefs,
    required this._storageKey,
    required this.initialPlayback,
    required List<ChatMessage> history,
  }) : _playback = initialPlayback,
       messages = ValueNotifier(history),
       _bus = LocalBus('kinochat_demo');

  @override
  final Room room;
  @override
  final UserProfile me;
  @override
  final PlaybackState initialPlayback;
  @override
  final ValueNotifier<List<ChatMessage>> messages;
  @override
  final ValueNotifier<List<Member>> members = ValueNotifier(const []);

  final Prefs _prefs;
  final String _storageKey;
  final LocalBus _bus;
  final String _instance = newId();
  final _playbackCtl = StreamController<PlaybackState>.broadcast();
  final _reactionCtl = StreamController<Reaction>.broadcast();
  final _seen = <String, ({Member member, DateTime at})>{};
  PlaybackState _playback;
  Timer? _heartbeat;

  @override
  Stream<PlaybackState> get remotePlayback => _playbackCtl.stream;
  @override
  Stream<Reaction> get reactions => _reactionCtl.stream;
  @override
  int get clockOffsetMs => 0;

  void _start() {
    _bus.onMessage = _onBus;
    _beat();
    _heartbeat = Timer.periodic(const Duration(seconds: 4), (_) => _beat());
    _post('hello', {});
  }

  void _post(String type, Map<String, dynamic> body) {
    _bus.post({
      'room': room.code,
      'type': type,
      'from': _instance,
      'name': me.name,
      'uid': me.id,
      ...body,
    });
  }

  void _beat() {
    _post('here', {});
    _refreshMembers();
  }

  void _refreshMembers() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 10));
    _seen.removeWhere((_, v) => v.at.isBefore(cutoff));
    members.value = [
      Member(id: me.id, name: me.name),
      ..._seen.values.map((v) => v.member),
    ];
  }

  void _onBus(Map<String, dynamic> m) {
    if (m['room'] != room.code || m['from'] == _instance) return;
    final from = m['from'] as String;
    switch (m['type']) {
      case 'hello':
        _post('here', {});
        continue here;
      here:
      case 'here':
        _seen[from] = (
          member: Member(
            id: (m['uid'] as String?) ?? from,
            name: (m['name'] as String?) ?? 'Гость',
          ),
          at: DateTime.now(),
        );
        _refreshMembers();
      case 'bye':
        _seen.remove(from);
        _refreshMembers();
      case 'msg':
        final msg = ChatMessage.fromJson(m['msg'] as Map<String, dynamic>);
        if (messages.value.every((x) => x.id != msg.id)) {
          messages.value = [...messages.value, msg];
        }
      case 'playback':
        _playback = PlaybackState.fromJson(m['state'] as Map<String, dynamic>?);
        _playbackCtl.add(_playback);
      case 'reaction':
        _reactionCtl.add(
          Reaction(
            emoji: (m['emoji'] as String?) ?? '',
            userName: (m['name'] as String?) ?? '',
          ),
        );
    }
  }

  Future<void> _persist() => _prefs.setString(
    _storageKey,
    jsonEncode({
      'room': room.toJson(),
      'playback': _playback.source == null ? null : _playback.toJson(),
      'messages': [
        for (final m in messages.value.reversed.take(200).toList().reversed)
          m.toJson(),
      ],
    }),
  );

  @override
  Future<void> sendMessage(String text, {bool system = false}) async {
    final msg = ChatMessage(
      id: newId(),
      userId: me.id,
      userName: me.name,
      text: text,
      at: DateTime.now(),
      system: system,
    );
    messages.value = [...messages.value, msg];
    _post('msg', {'msg': msg.toJson()});
    await _persist();
  }

  @override
  Future<void> sendPlayback(PlaybackState state) async {
    _playback = state;
    _post('playback', {'state': state.toJson()});
    await _persist();
  }

  @override
  void sendReaction(String emoji) => _post('reaction', {'emoji': emoji});

  @override
  Future<void> leave() async {
    _heartbeat?.cancel();
    _post('bye', {});
    _bus.close();
    await _playbackCtl.close();
    await _reactionCtl.close();
  }
}
