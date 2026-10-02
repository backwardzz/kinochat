import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'prefs.dart';
import 'tmdb.dart';

/// A search API described by data, so that any JSON API can be plugged in
/// without changing the app: where to send the query and where in the answer
/// the title, the poster and the link are.
class SearchSource {
  const SearchSource({
    required this.id,
    required this.name,
    required this.urlTemplate,
    required this.listPath,
    required this.titlePath,
    required this.linkPath,
    this.linkTemplate = '',
    this.posterPath = '',
    this.subtitlePath = '',
    this.apiKey = '',
    this.headers = const {},
    this.builtIn = false,
    this.keyHint = '',
    this.webBlocked = false,
    this.catalog = false,
  });

  final String id;
  final String name;

  /// `{query}` is replaced with the search text, `{key}` with [apiKey].
  final String urlTemplate;

  /// Dot-separated path to the array of results, e.g. `response.items`.
  /// Empty when the answer itself is the array.
  final String listPath;
  final String titlePath;

  /// Path to the video link (or to an id, together with [linkTemplate]).
  final String linkPath;

  /// Optional, `{value}` is replaced with what [linkPath] found.
  final String linkTemplate;
  final String posterPath;
  final String subtitlePath;
  final String apiKey;
  final Map<String, String> headers;

  final bool builtIn;

  /// Where to get a key, shown for built-in sources that need one.
  final String keyHint;

  /// The service does not answer requests made from a web page.
  final bool webBlocked;

  /// A catalogue of films (TMDB): it describes them but gives no video
  /// links, so it is asked separately from the video search.
  final bool catalog;

  bool get needsKey => urlTemplate.contains('{key}') || _headersNeedKey;
  bool get _headersNeedKey => headers.values.any((v) => v.contains('{key}'));
  bool get ready => !needsKey || apiKey.isNotEmpty;

  /// Ready, and reachable from where the app is running.
  bool get usableHere => ready && !(kIsWeb && webBlocked);

  SearchSource copyWith({
    String? name,
    String? urlTemplate,
    String? listPath,
    String? titlePath,
    String? linkPath,
    String? linkTemplate,
    String? posterPath,
    String? subtitlePath,
    String? apiKey,
    Map<String, String>? headers,
  }) => SearchSource(
    id: id,
    name: name ?? this.name,
    urlTemplate: urlTemplate ?? this.urlTemplate,
    listPath: listPath ?? this.listPath,
    titlePath: titlePath ?? this.titlePath,
    linkPath: linkPath ?? this.linkPath,
    linkTemplate: linkTemplate ?? this.linkTemplate,
    posterPath: posterPath ?? this.posterPath,
    subtitlePath: subtitlePath ?? this.subtitlePath,
    apiKey: apiKey ?? this.apiKey,
    headers: headers ?? this.headers,
    builtIn: builtIn,
    keyHint: keyHint,
    webBlocked: webBlocked,
    catalog: catalog,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': urlTemplate,
    'list': listPath,
    'title': titlePath,
    'link': linkPath,
    'linkTemplate': linkTemplate,
    'poster': posterPath,
    'subtitle': subtitlePath,
    'key': apiKey,
    'headers': headers,
  };

  static SearchSource fromJson(Map<String, dynamic> j) => SearchSource(
    id: j['id'] as String,
    name: (j['name'] as String?) ?? 'Источник',
    urlTemplate: (j['url'] as String?) ?? '',
    listPath: (j['list'] as String?) ?? '',
    titlePath: (j['title'] as String?) ?? '',
    linkPath: (j['link'] as String?) ?? '',
    linkTemplate: (j['linkTemplate'] as String?) ?? '',
    posterPath: (j['poster'] as String?) ?? '',
    subtitlePath: (j['subtitle'] as String?) ?? '',
    apiKey: (j['key'] as String?) ?? '',
    headers: {
      for (final e in ((j['headers'] as Map?) ?? const {}).entries)
        e.key.toString(): e.value.toString(),
    },
  );
}

class SearchResult {
  const SearchResult({
    required this.title,
    required this.link,
    this.poster,
    this.subtitle,
    this.source = '',
  });

  final String title;
  final String link;
  final String? poster;
  final String? subtitle;

  /// Name of the source that returned it.
  final String source;
}

/// What one search over every source brought back.
class CombinedResults {
  const CombinedResults({
    required this.results,
    required this.searched,
    required this.failures,
  });

  /// Results of all sources, taken in turn so that none is buried.
  final List<SearchResult> results;

  /// Names of the sources that were asked.
  final List<String> searched;

  /// Source name → why it gave nothing.
  final Map<String, String> failures;
}

class SearchException implements Exception {
  SearchException(this.message);
  final String message;
  @override
  String toString() => message;
}

const _builtIn = <SearchSource>[
  SearchSource(
    id: 'youtube',
    name: 'YouTube',
    urlTemplate:
        'https://www.googleapis.com/youtube/v3/search'
        '?part=snippet&type=video&videoEmbeddable=true&maxResults=25'
        '&q={query}&key={key}',
    listPath: 'items',
    titlePath: 'snippet.title',
    linkPath: 'id.videoId',
    linkTemplate: 'https://www.youtube.com/watch?v={value}',
    posterPath: 'snippet.thumbnails.medium.url',
    subtitlePath: 'snippet.channelTitle',
    builtIn: true,
    keyHint:
        'Бесплатный ключ YouTube Data API v3: console.cloud.google.com → '
        'APIs & Services → Credentials → Create API key.',
  ),
  SearchSource(
    id: 'rutube',
    name: 'Rutube',
    urlTemplate:
        'https://rutube.ru/api/search/video/?query={query}&format=json',
    listPath: 'results',
    titlePath: 'title',
    linkPath: 'video_url',
    posterPath: 'thumbnail_url',
    subtitlePath: 'author.name',
    builtIn: true,
    webBlocked: true,
  ),
  SearchSource(
    id: 'vk',
    name: 'VK Видео',
    urlTemplate:
        'https://api.vk.com/method/video.search'
        '?q={query}&count=30&adult=0&v=5.199&access_token={key}',
    listPath: 'response.items',
    titlePath: 'title',
    linkPath: 'player',
    posterPath: 'image.-1.url',
    builtIn: true,
    keyHint:
        'Нужен ключ доступа VK с правом «видео»: dev.vk.com → Мои приложения '
        '→ создать приложение → получить токен пользователя.',
    webBlocked: true,
  ),
  SearchSource(
    id: 'tmdb',
    name: 'TMDB',
    urlTemplate: 'https://api.themoviedb.org/3/search/multi?api_key={key}',
    listPath: 'results',
    titlePath: 'title',
    linkPath: '',
    builtIn: true,
    catalog: true,
    keyHint:
        'Каталог фильмов и сериалов: описания, постеры, рейтинги, трейлеры. '
        'Самих фильмов в нём нет. Бесплатный ключ: themoviedb.org → '
        'зарегистрироваться → Settings → API → Create. Подойдёт и «API Key», '
        'и «API Read Access Token».',
  ),
];

/// Built-in and user-defined sources, and running a search through one.
class SearchService extends ChangeNotifier {
  SearchService(this._prefs) {
    _load();
  }

  final Prefs _prefs;
  static const _kCustom = 'search_sources';
  static const _kKeys = 'search_keys';

  List<SearchSource> _custom = [];
  Map<String, String> _builtInKeys = {};

  List<SearchSource> get sources => [
    for (final s in _builtIn) s.copyWith(apiKey: _builtInKeys[s.id] ?? ''),
    ..._custom,
  ];

  void _load() {
    try {
      final raw = _prefs.getString(_kCustom);
      if (raw != null) {
        _custom = [
          for (final j in jsonDecode(raw) as List)
            SearchSource.fromJson(j as Map<String, dynamic>),
        ];
      }
      final keys = _prefs.getString(_kKeys);
      if (keys != null) {
        _builtInKeys = {
          for (final e in (jsonDecode(keys) as Map).entries)
            e.key.toString(): e.value.toString(),
        };
      }
    } catch (_) {}
  }

  Future<void> save(SearchSource source) async {
    if (source.builtIn) {
      _builtInKeys[source.id] = source.apiKey;
      await _prefs.setString(_kKeys, jsonEncode(_builtInKeys));
    } else {
      final i = _custom.indexWhere((s) => s.id == source.id);
      if (i >= 0) {
        _custom[i] = source;
      } else {
        _custom.add(source);
      }
      await _prefs.setString(
        _kCustom,
        jsonEncode([for (final s in _custom) s.toJson()]),
      );
    }
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _custom.removeWhere((s) => s.id == id);
    await _prefs.setString(
      _kCustom,
      jsonEncode([for (final s in _custom) s.toJson()]),
    );
    notifyListeners();
  }

  Future<List<SearchResult>> search(SearchSource source, String query) async =>
      parseResults(source, await fetch(source, query));

  /// The film catalogue, when its key is set.
  Tmdb? get tmdb {
    final key = _builtInKeys['tmdb'] ?? '';
    return key.isEmpty ? null : Tmdb(key);
  }

  /// Sources that return videos and can be used here.
  List<SearchSource> get videoSources => [
    for (final s in sources)
      if (s.usableHere && !s.catalog) s,
  ];

  /// Asks every video source that can be used here, all at once.
  Future<CombinedResults> searchAll(String query) async {
    final usable = videoSources;
    final failures = <String, String>{};
    final lists = await Future.wait([
      for (final s in usable)
        search(s, query).catchError((Object e) {
          failures[s.name] = e is SearchException
              ? e.message
              : 'Не удалось разобрать ответ.';
          return const <SearchResult>[];
        }),
    ]);
    return CombinedResults(
      results: interleave(lists),
      searched: [for (final s in usable) s.name],
      failures: failures,
    );
  }

  /// The decoded JSON answer of [source] for [query].
  Future<dynamic> fetch(SearchSource source, String query) async {
    if (!source.ready) {
      throw SearchException('Для «${source.name}» нужен ключ API.');
    }
    String fill(String template) => template
        .replaceAll('{query}', Uri.encodeQueryComponent(query))
        .replaceAll('{key}', Uri.encodeQueryComponent(source.apiKey));

    final uri = Uri.tryParse(fill(source.urlTemplate));
    if (uri == null || !uri.hasScheme) {
      throw SearchException('Неверный адрес API.');
    }

    final http.Response response;
    try {
      response = await http
          .get(
            uri,
            headers: {
              for (final e in source.headers.entries)
                e.key: e.value.replaceAll('{key}', source.apiKey),
            },
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw SearchException(
        kIsWeb
            ? 'Сервис не ответил. Многие API не принимают запросы из '
                  'браузера — в приложении для Android этот источник '
                  'может работать.'
            : 'Сервис не ответил. Проверьте интернет и адрес API.',
      );
    }
    if (response.statusCode != 200) {
      throw SearchException(switch (response.statusCode) {
        400 || 401 || 403 =>
          'Сервис отклонил запрос (${response.statusCode}). '
              'Проверьте ключ API.',
        429 => 'Слишком много запросов, попробуйте позже.',
        _ => 'Сервис вернул ошибку ${response.statusCode}.',
      });
    }

    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw SearchException('Ответ сервиса — не JSON.');
    }
  }
}

/// Merges lists by taking one item from each in turn.
List<T> interleave<T>(List<List<T>> lists) {
  final out = <T>[];
  final longest = lists.fold<int>(0, (m, l) => l.length > m ? l.length : m);
  for (var i = 0; i < longest; i++) {
    for (final list in lists) {
      if (i < list.length) out.add(list[i]);
    }
  }
  return out;
}

/// Pulls results out of an API answer according to the paths of [source].
List<SearchResult> parseResults(SearchSource source, dynamic json) {
  final list = readPath(json, source.listPath);
  if (list is! List) {
    throw SearchException(
      source.listPath.isEmpty
          ? 'В ответе нет списка результатов.'
          : 'В ответе нет списка по пути «${source.listPath}».',
    );
  }
  final out = <SearchResult>[];
  for (final item in list) {
    final value = readPath(item, source.linkPath)?.toString();
    if (value == null || value.isEmpty) continue;
    final link = source.linkTemplate.isEmpty
        ? _withScheme(value)
        : source.linkTemplate.replaceAll('{value}', value);
    final title = source.titlePath.isEmpty
        ? null
        : readPath(item, source.titlePath)?.toString();
    final rawPoster = source.posterPath.isEmpty
        ? null
        : readPath(item, source.posterPath)?.toString();
    final poster = rawPoster == null ? null : _withScheme(rawPoster);
    final subtitle = source.subtitlePath.isEmpty
        ? null
        : readPath(item, source.subtitlePath)?.toString();
    out.add(
      SearchResult(
        title: (title == null || title.isEmpty) ? link : _unescape(title),
        link: link,
        poster: (poster != null && poster.startsWith('http')) ? poster : null,
        subtitle: subtitle == null ? null : _unescape(subtitle),
        source: source.name,
      ),
    );
  }
  return out;
}

/// `//host/path` is a link without a scheme; such links mean https.
String _withScheme(String url) => url.startsWith('//') ? 'https:$url' : url;

/// Walks `a.b.0.c` through maps and lists. A negative number counts from the
/// end of a list. An empty path returns [json] itself.
dynamic readPath(dynamic json, String path) {
  dynamic cur = json;
  if (path.trim().isEmpty) return cur;
  for (final part in path.split('.')) {
    final key = part.trim();
    if (cur is Map) {
      cur = cur[key];
    } else if (cur is List) {
      var i = int.tryParse(key);
      if (i == null) return null;
      if (i < 0) i += cur.length;
      if (i < 0 || i >= cur.length) return null;
      cur = cur[i];
    } else {
      return null;
    }
  }
  return cur;
}

String _unescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>');
