import 'package:flutter/foundation.dart';

import '../models.dart';

class BackendException implements Exception {
  BackendException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Where rooms live. Two implementations: Supabase and an on-device demo.
abstract class Backend {
  /// True when nothing leaves this device.
  bool get isDemo;

  Future<Room> createRoom(String name);

  /// Null when no room has this code.
  Future<Room?> findRoom(String code);

  Future<RoomSession> join(Room room, UserProfile me);
}

/// A live connection to one room.
abstract class RoomSession {
  Room get room;
  UserProfile get me;

  /// Oldest first.
  ValueListenable<List<ChatMessage>> get messages;
  ValueListenable<List<Member>> get members;

  /// Playback changes made by other people.
  Stream<PlaybackState> get remotePlayback;
  Stream<Reaction> get reactions;

  /// State of the room at the moment of joining.
  PlaybackState get initialPlayback;

  /// Add to the local clock to get server time, in milliseconds.
  int get clockOffsetMs;

  Future<void> sendMessage(String text, {bool system = false});
  Future<void> sendPlayback(PlaybackState state);
  void sendReaction(String emoji);
  Future<void> leave();
}

int serverNowMs(RoomSession s) =>
    DateTime.now().millisecondsSinceEpoch + s.clockOffsetMs;
