import '../models.dart';
import 'link_parser.dart';

/// Where the useful fields are in an API answer, as dot-separated paths.
class DetectedPaths {
  const DetectedPaths({
    required this.listPath,
    required this.linkPath,
    this.titlePath = '',
    this.posterPath = '',
    this.subtitlePath = '',
  });

  final String listPath;
  final String linkPath;
  final String titlePath;
  final String posterPath;
  final String subtitlePath;
}

/// Looks at a search answer and works out where the list of results is and
/// which fields hold the video link, the title and the poster, so that the
/// person plugging in an API does not have to describe its format.
///
/// Returns null when nothing in the answer looks like a list of videos.
DetectedPaths? detectPaths(dynamic json) {
  final lists = <String, List<dynamic>>{};
  void walk(dynamic node, String path, int depth) {
    if (node is List) {
      // Lists inside results (genres, images) are not result lists.
      if (node.isNotEmpty && node.first is Map) lists[path] = node;
    } else if (node is Map && depth < 5) {
      for (final e in node.entries) {
        final key = e.key.toString();
        walk(e.value, path.isEmpty ? key : '$path.$key', depth + 1);
      }
    }
  }

  walk(json, '', 0);

  DetectedPaths? best;
  var bestScore = 0.0;
  for (final entry in lists.entries) {
    final items = entry.value.whereType<Map>().take(8);
    final leaves = [for (final item in items) _leaves(item)];

    // The list whose items carry the most convincing video links wins.
    final link = _bestPath(leaves, _linkScore);
    if (link.path.isEmpty || link.score <= bestScore) continue;
    bestScore = link.score;
    best = DetectedPaths(
      listPath: entry.key,
      linkPath: link.path,
      titlePath: _bestPath(leaves, _titleScore).path,
      posterPath: _bestPath(leaves, _posterScore).path,
      subtitlePath: _bestPath(leaves, _subtitleScore).path,
    );
  }
  return best;
}

/// The path whose values, summed over the sampled results, score highest.
/// An empty path means nothing scored at all.
({String path, double score}) _bestPath(
  List<Map<String, Object>> leaves,
  double Function(String path, Object value) score,
) {
  var winner = '';
  var top = 0.0;
  for (final path in {for (final l in leaves) ...l.keys}) {
    var total = 0.0;
    for (final l in leaves) {
      final v = l[path];
      if (v != null) total += score(path, v);
    }
    if (total <= 0) continue;
    // Among equals the shorter path is the more likely one.
    total -= path.split('.').length * 0.01;
    if (total > top) {
      top = total;
      winner = path;
    }
  }
  return (path: winner, score: top);
}

/// Scalar values of one result keyed by path. Of a nested list only the first
/// and the last element are looked at.
Map<String, Object> _leaves(Map<dynamic, dynamic> item) {
  final out = <String, Object>{};
  void walk(dynamic node, String path, int depth) {
    if (node is Map) {
      if (depth >= 4) return;
      for (final e in node.entries) {
        final key = e.key.toString();
        walk(e.value, path.isEmpty ? key : '$path.$key', depth + 1);
      }
    } else if (node is List) {
      if (node.isEmpty || depth >= 4) return;
      walk(node.first, '$path.0', depth + 1);
      if (node.length > 1) walk(node.last, '$path.-1', depth + 1);
    } else if (node is String || node is num) {
      out[path] = node as Object;
    }
  }

  walk(item, '', 0);
  return out;
}

bool _isUrl(Object v) =>
    v is String &&
    (v.startsWith('https://') || v.startsWith('http://') || v.startsWith('//'));

final _imageExt = RegExp(
  r'\.(jpe?g|png|webp|gif|avif|svg)($|[?#])',
  caseSensitive: false,
);

bool _has(String path, List<String> words) {
  final p = path.toLowerCase();
  return words.any(p.contains);
}

/// The field's own name, without the names of what it is nested in.
String _field(String path) => path.split('.').last.toLowerCase();

const _pictureWords = [
  'poster',
  'thumb',
  'image',
  'img',
  'cover',
  'preview',
  'picture',
  'screenshot',
  'backdrop',
  'artwork',
];

/// Things a result mentions that are about someone or something else.
const _notTheVideo = [
  'avatar',
  'logo',
  'icon',
  'author',
  'artist',
  'channel',
  'user',
  'genre',
  'category',
  'collection',
  'country',
];

double _linkScore(String path, Object value) {
  if (!_isUrl(value)) return 0;
  final url = value as String;
  final field = _field(path);
  if (_imageExt.hasMatch(url)) return 0;
  final parsed = parseVideoLink(url.startsWith('//') ? 'https:$url' : url);
  if (parsed == null) return 0;
  final playable = parsed.kind != VideoKind.embed;
  // `previewUrl` may well be a video; a page under such a name is not.
  if (!playable && _has(field, _pictureWords)) return 0;
  // A link the player can drive beats a page that only opens.
  var score = playable ? 4.0 : 1.0;
  if (_has(field, ['video', 'file', 'stream', 'hls', 'm3u8', 'mp4'])) {
    score *= 1.6;
  } else if (_has(field, ['player', 'embed', 'iframe'])) {
    score *= 1.4;
  } else if (_has(field, ['url', 'link', 'href', 'src'])) {
    // Plain `url` is more likely the thing itself than `descriptionurl`.
    score *= const ['url', 'link', 'href', 'src'].contains(field) ? 1.3 : 1.2;
  }
  if (_has(path, _notTheVideo)) score *= 0.2;
  return score;
}

double _titleScore(String path, Object value) {
  if (value is! String || _isUrl(value)) return 0;
  final text = value.trim();
  if (text.isEmpty || text.length > 200) return 0;
  final last = _field(path);
  if (_has(path, _notTheVideo) || _has(path, ['file', 'slug', 'type'])) {
    return 0.1;
  }
  if (last == 'title' || last == 'name') return 3;
  if (last.contains('title') || last.contains('name')) {
    // `trackName`, `movieTitle` name the thing itself.
    return _has(last, ['track', 'movie', 'film', 'video']) ? 2.5 : 2;
  }
  if (const ['caption', 'label', 'headline'].contains(last)) return 1.5;
  return 0;
}

final _trailingNumber = RegExp(r'(\d+)$');

double _posterScore(String path, Object value) {
  if (!_isUrl(value)) return 0;
  if (_has(path, ['avatar', 'logo', 'icon'])) return 0;
  final field = _field(path);
  final named = _has(field, _pictureWords);
  final looksLikeImage = _imageExt.hasMatch(value as String);
  if (!named && !looksLikeImage) return 0;
  var score = (named ? 2.0 : 0.0) + (looksLikeImage ? 1.0 : 0.0);
  if (_has(path, _notTheVideo)) score *= 0.2;
  // Of `artworkUrl30` and `artworkUrl100` the bigger picture is better.
  final size = int.tryParse(_trailingNumber.firstMatch(field)?.group(1) ?? '');
  if (size != null) score += size.clamp(0, 2000) / 100000;
  return score;
}

double _subtitleScore(String path, Object value) {
  if (_isUrl(value)) return 0;
  final last = _field(path);
  if (last == 'year') return 3;
  if (value is! String || value.trim().isEmpty || value.length > 80) return 0;
  if (_has(path, ['author', 'artist', 'channel']) &&
      (last.contains('name') || last.contains('title'))) {
    return 2;
  }
  return 0;
}
