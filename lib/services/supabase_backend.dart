import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models.dart';
import 'backend.dart';

/// Rooms and history in Postgres, live events over a Realtime channel.
/// The schema is in `supabase/schema.sql`.
class SupabaseBackend implements Backend {
  SupabaseBackend._(this._client);

  final SupabaseClient _client;

  static Future<SupabaseBackend> connect() async {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
    return SupabaseBackend._(Supabase.instance.client);
  }

  @override
  bool get isDemo => false;

  @override
  Future<Room> createRoom(String name) async {
    // A code collision is unlikely but cheap to retry.
    for (var attempt = 0; ; attempt++) {
      try {
        final row = await _client
            .from('rooms')
            .insert({'code': newRoomCode(), 'name': name})
            .select()
            .single();
        return Room.fromJson(row);
      } on PostgrestException catch (e) {
        if (e.code != '23505' || attempt >= 3) {
          throw BackendException('Не удалось создать комнату: ${e.message}');
        }
      }
    }
  }

  @override
  Future<Room?> findRoom(String code) async {
    final row = await _client
        .from('rooms')
        .select()
        .eq('code', code)
        .maybeSingle();
    return row == null ? null : Room.fromJson(row);
  }

  @override
  Future<RoomSession> join(Room room, UserProfile me) async {
    final t0 = DateTime.now().millisecondsSinceEpoch;
    final List<dynamic> results;
    try {
      results = await Future.wait<dynamic>([
        _client.from('rooms').select('playback').eq('id', room.id).single(),
        _client
            .from('messages')
            .select()
            .eq('room_id', room.id)
            .order('created_at', ascending: false)
            .limit(200),
        _client.rpc('server_time'),
      ]);
    } on PostgrestException catch (e) {
      throw BackendException('Не удалось открыть комнату: ${e.message}');
    }
    final t1 = DateTime.now().millisecondsSinceEpoch;

    final serverTime = DateTime.tryParse(results[2].toString());
    final offset = serverTime == null
        ? 0
        : serverTime.millisecondsSinceEpoch - (t0 + t1) ~/ 2;

    final history = [
      for (final row in (results[1] as List).reversed)
        ChatMessage.fromJson(row as Map<String, dynamic>),
    ];

    final session = _SupabaseSession(
      client: _client,
      room: room,
      me: me,
      clockOffsetMs: offset,
      initialPlayback: PlaybackState.fromJson(
        (results[0] as Map<String, dynamic>)['playback']
            as Map<String, dynamic>?,
      ),
      history: history,
    );
    await session._subscribe();

    // The list of who is here arrives right after subscribing.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (session.members.value.length > maxRoomMembers) {
      await session.leave();
      throw BackendException('В комнате уже $maxRoomMembers человек.');
    }
    return session;
  }
}

class _SupabaseSession implements RoomSession {
  _SupabaseSession({
    required this._client,
    required this.room,
    required this.me,
    required this.clockOffsetMs,
    required this.initialPlayback,
    required List<ChatMessage> history,
  }) : messages = ValueNotifier(history);

  final SupabaseClient _client;
  late final RealtimeChannel _channel;

  @override
  final Room room;
  @override
  final UserProfile me;
  @override
  final int clockOffsetMs;
  @override
  final PlaybackState initialPlayback;
  @override
  final ValueNotifier<List<ChatMessage>> messages;
  @override
  final ValueNotifier<List<Member>> members = ValueNotifier(const []);

  final _playbackCtl = StreamController<PlaybackState>.broadcast();
  final _reactionCtl = StreamController<Reaction>.broadcast();

  @override
  Stream<PlaybackState> get remotePlayback => _playbackCtl.stream;
  @override
  Stream<Reaction> get reactions => _reactionCtl.stream;

  /// Broadcast callbacks receive `{event, type, payload}`.
  static Map<String, dynamic> _body(Map<String, dynamic> raw) {
    final inner = raw['payload'];
    return inner is Map ? Map<String, dynamic>.from(inner) : raw;
  }

  Future<void> _subscribe() async {
    final joined = Completer<void>();
    _channel = _client.channel(
      'room:${room.id}',
      opts: RealtimeChannelConfig(key: me.id),
    );
    _channel
        .onBroadcast(
          event: 'msg',
          callback: (raw) => _addMessage(ChatMessage.fromJson(_body(raw))),
        )
        .onBroadcast(
          event: 'playback',
          callback: (raw) =>
              _playbackCtl.add(PlaybackState.fromJson(_body(raw))),
        )
        .onBroadcast(
          event: 'reaction',
          callback: (raw) {
            final b = _body(raw);
            _reactionCtl.add(
              Reaction(
                emoji: (b['emoji'] as String?) ?? '',
                userName: (b['name'] as String?) ?? '',
              ),
            );
          },
        )
        .onPresenceSync((_) => _syncMembers())
        .subscribe((status, error) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            await _channel.track({'id': me.id, 'name': me.name});
            if (!joined.isCompleted) joined.complete();
          } else if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            if (!joined.isCompleted) {
              joined.completeError(
                BackendException('Нет связи с сервером. Проверьте интернет.'),
              );
            }
          }
        });
    await joined.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () =>
          throw BackendException('Сервер не отвечает. Попробуйте ещё раз.'),
    );
  }

  void _syncMembers() {
    final byId = <String, Member>{};
    for (final state in _channel.presenceState()) {
      for (final p in state.presences) {
        final id = (p.payload['id'] as String?) ?? state.key;
        byId[id] = Member(
          id: id,
          name: (p.payload['name'] as String?) ?? 'Гость',
        );
      }
    }
    byId.putIfAbsent(me.id, () => Member(id: me.id, name: me.name));
    members.value = [byId[me.id]!, ...byId.values.where((m) => m.id != me.id)];
  }

  void _addMessage(ChatMessage msg) {
    if (messages.value.any((m) => m.id == msg.id)) return;
    messages.value = [...messages.value, msg];
  }

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
    _addMessage(msg);
    final json = msg.toJson();
    // Broadcast delivers instantly; the insert keeps history for late joiners.
    unawaited(_channel.sendBroadcastMessage(event: 'msg', payload: json));
    try {
      await _client.from('messages').insert({
        'id': msg.id,
        'room_id': room.id,
        'user_id': msg.userId,
        'user_name': msg.userName,
        'body': msg.text,
        'system': msg.system,
      });
    } on PostgrestException catch (e) {
      throw BackendException('Сообщение не сохранилось: ${e.message}');
    }
  }

  @override
  Future<void> sendPlayback(PlaybackState state) async {
    final json = state.toJson();
    unawaited(_channel.sendBroadcastMessage(event: 'playback', payload: json));
    await _client
        .from('rooms')
        .update({'playback': state.source == null ? null : json})
        .eq('id', room.id);
  }

  @override
  void sendReaction(String emoji) {
    unawaited(
      _channel.sendBroadcastMessage(
        event: 'reaction',
        payload: {'emoji': emoji, 'name': me.name},
      ),
    );
  }

  @override
  Future<void> leave() async {
    try {
      await _channel.untrack();
      await _client.removeChannel(_channel);
    } catch (_) {}
    await _playbackCtl.close();
    await _reactionCtl.close();
  }
}
