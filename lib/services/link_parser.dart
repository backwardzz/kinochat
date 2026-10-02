import '../models.dart';

final _ytId = RegExp(r'^[A-Za-z0-9_-]{11}$');
final _rutubeId = RegExp(r'^[0-9a-f]{32}$');
final _vkPair = RegExp(r'video(-?\d+)_(\d+)');
final _fileExt = RegExp(
  r'\.(mp4|m4v|webm|ogv|ogg|mov|m3u8)$',
  caseSensitive: false,
);

/// Turns a pasted link into something the player can load.
/// Returns null when the text is not an http(s) link.
VideoSource? parseVideoLink(String input, {String? title}) {
  var text = input.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasAuthority) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (!uri.host.contains('.')) return null;

  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^(www|m)\.'), '');
  final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();

  VideoSource make(VideoKind kind, String ref, {double start = 0}) =>
      VideoSource(
        kind: kind,
        ref: ref,
        url: text,
        title: title,
        startSec: start,
      );

  // YouTube
  if (host == 'youtu.be' && seg.isNotEmpty && _ytId.hasMatch(seg.first)) {
    return make(VideoKind.youtube, seg.first, start: _startOf(uri));
  }
  if (host.endsWith('youtube.com') || host.endsWith('youtube-nocookie.com')) {
    String? id;
    if (seg.isNotEmpty && seg.first == 'watch') {
      id = uri.queryParameters['v'];
    } else if (seg.length >= 2 &&
        const {'embed', 'shorts', 'live', 'v'}.contains(seg.first)) {
      id = seg[1];
    }
    if (id != null && _ytId.hasMatch(id)) {
      return make(VideoKind.youtube, id, start: _startOf(uri));
    }
  }

  // Rutube
  if (host.endsWith('rutube.ru')) {
    for (final s in seg) {
      if (_rutubeId.hasMatch(s)) {
        return make(VideoKind.rutube, s, start: _startOf(uri));
      }
    }
  }

  // VK Видео
  if (host.endsWith('vk.com') ||
      host.endsWith('vk.ru') ||
      host.endsWith('vkvideo.ru')) {
    final q = uri.queryParameters;
    if (uri.path.contains('video_ext.php') &&
        q['oid'] != null &&
        q['id'] != null) {
      final hash = q['hash'];
      return make(
        VideoKind.vk,
        '${q['oid']}_${q['id']}${hash == null ? '' : '_$hash'}',
      );
    }
    final m = _vkPair.firstMatch(uri.path) ?? _vkPair.firstMatch(q['z'] ?? '');
    if (m != null) {
      return make(VideoKind.vk, '${m.group(1)}_${m.group(2)}');
    }
  }

  // Direct file
  if (_fileExt.hasMatch(uri.path)) {
    return make(VideoKind.file, text);
  }

  return make(VideoKind.embed, text);
}

/// Reads `t=90`, `t=1m30s`, `start=90`.
double _startOf(Uri uri) {
  final raw = uri.queryParameters['t'] ?? uri.queryParameters['start'];
  if (raw == null || raw.isEmpty) return 0;
  final plain = double.tryParse(raw);
  if (plain != null) return plain;
  final m = RegExp(r'^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$').firstMatch(raw);
  if (m == null) return 0;
  final h = int.tryParse(m.group(1) ?? '') ?? 0;
  final min = int.tryParse(m.group(2) ?? '') ?? 0;
  final s = int.tryParse(m.group(3) ?? '') ?? 0;
  return (h * 3600 + min * 60 + s).toDouble();
}
