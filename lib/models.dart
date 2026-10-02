import 'dart:math';

/// Kinds of video the player host understands.
enum VideoKind { youtube, vk, rutube, file, embed }

VideoKind? videoKindFromName(String? name) {
  for (final k in VideoKind.values) {
    if (k.name == name) return k;
  }
  return null;
}

/// A parsed video reference: what to load and how.
class VideoSource {
  const VideoSource({
    required this.kind,
    required this.ref,
    required this.url,
    this.title,
    this.startSec = 0,
  });

  final VideoKind kind;

  /// Provider-specific id (YouTube id, Rutube id, `oid_id[_hash]` for VK)
  /// or the full URL for [VideoKind.file] and [VideoKind.embed].
  final String ref;

  /// Original link the user pasted.
  final String url;
  final String? title;
  final double startSec;

  /// Pause, play and seek can be driven remotely.
  bool get syncable => kind != VideoKind.embed;

  String get key => '${kind.name}:$ref';

  String get label => switch (kind) {
    VideoKind.youtube => 'YouTube',
    VideoKind.vk => 'VK Видео',
    VideoKind.rutube => 'Rutube',
    VideoKind.file => 'Видеофайл',
    VideoKind.embed => 'Страница',
  };

  VideoSource withTitle(String? t) =>
      VideoSource(kind: kind, ref: ref, url: url, title: t, startSec: startSec);
}

/// Shared playback state of a room. [positionMs] is the position at the
/// moment [atMs] on the server clock; while [playing] it advances from there.
class PlaybackState {
  const PlaybackState({
    required this.source,
    required this.playing,
    required this.positionMs,
    required this.atMs,
    required this.by,
  });

  final VideoSource? source;
  final bool playing;
  final int positionMs;
  final int atMs;
  final String by;

  static const empty = PlaybackState(
    source: null,
    playing: false,
    positionMs: 0,
    atMs: 0,
    by: '',
  );

  int expectedPositionMs(int serverNowMs) {
    if (!playing) return positionMs;
    return positionMs + max(0, serverNowMs - atMs);
  }

  Map<String, dynamic> toJson() => {
    'kind': source?.kind.name,
    'ref': source?.ref,
    'url': source?.url,
    'title': source?.title,
    'playing': playing,
    'pos': positionMs,
    'at': atMs,
    'by': by,
  };

  static PlaybackState fromJson(Map<String, dynamic>? j) {
    if (j == null) return empty;
    final kind = videoKindFromName(j['kind'] as String?);
    final ref = j['ref'] as String?;
    return PlaybackState(
      source: (kind == null || ref == null)
          ? null
          : VideoSource(
              kind: kind,
              ref: ref,
              url: (j['url'] as String?) ?? ref,
              title: j['title'] as String?,
            ),
      playing: j['playing'] == true,
      positionMs: (j['pos'] as num?)?.toInt() ?? 0,
      atMs: (j['at'] as num?)?.toInt() ?? 0,
      by: (j['by'] as String?) ?? '',
    );
  }
}

class Room {
  const Room({required this.id, required this.code, required this.name});

  final String id;
  final String code;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'code': code, 'name': name};

  static Room fromJson(Map<String, dynamic> j) => Room(
    id: j['id'].toString(),
    code: j['code'] as String,
    name: (j['name'] as String?) ?? 'Комната',
  );
}

class UserProfile {
  const UserProfile({required this.id, required this.name});

  final String id;
  final String name;
}

class Member {
  const Member({required this.id, required this.name});

  final String id;
  final String name;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.userId,
    required this.userName,
    required this.text,
    required this.at,
    this.system = false,
  });

  final String id;
  final String userId;
  final String userName;
  final String text;
  final DateTime at;

  /// Service line such as "Аня включила видео".
  final bool system;

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'user_name': userName,
    'body': text,
    'created_at': at.toUtc().toIso8601String(),
    'system': system,
  };

  static ChatMessage fromJson(Map<String, dynamic> j) => ChatMessage(
    id: j['id'].toString(),
    userId: (j['user_id'] as String?) ?? '',
    userName: (j['user_name'] as String?) ?? '',
    text: (j['body'] as String?) ?? '',
    at:
        DateTime.tryParse((j['created_at'] as String?) ?? '')?.toLocal() ??
        DateTime.now(),
    system: j['system'] == true,
  );
}

class Reaction {
  const Reaction({required this.emoji, required this.userName});

  final String emoji;
  final String userName;
}

final _rng = Random.secure();

/// RFC 4122 version 4 id, used for users and messages.
String newId() {
  final b = List<int>.generate(16, (_) => _rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

/// Six characters without look-alikes (no 0/O, 1/I/L).
String newRoomCode() {
  const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  return List.generate(
    6,
    (_) => alphabet[_rng.nextInt(alphabet.length)],
  ).join();
}
