import 'dart:convert';

import 'package:http/http.dart' as http;

import 'search.dart';

/// A film or a series from the TMDB catalogue. The catalogue describes films;
/// it has no films themselves, only trailers.
class Film {
  const Film({
    required this.id,
    required this.isSeries,
    required this.title,
    this.year,
    this.overview = '',
    this.poster,
    this.rating,
  });

  final int id;
  final bool isSeries;
  final String title;
  final String? year;
  final String overview;
  final String? poster;

  /// Out of 10; null when nobody has voted yet.
  final double? rating;
}

/// Films and series out of a `/search/multi` answer; people are skipped.
List<Film> parseTmdbFilms(dynamic json) {
  final results = json is Map ? json['results'] : null;
  if (results is! List) return const [];
  final out = <Film>[];
  for (final r in results) {
    if (r is! Map) continue;
    final type = r['media_type'];
    if (type != 'movie' && type != 'tv') continue;
    final id = r['id'];
    final title = (r['title'] ?? r['name'])?.toString() ?? '';
    if (id is! int || title.isEmpty) continue;
    final date = (r['release_date'] ?? r['first_air_date'])?.toString() ?? '';
    final poster = r['poster_path']?.toString();
    final votes = (r['vote_count'] as num?) ?? 0;
    final rating = (r['vote_average'] as num?)?.toDouble();
    out.add(
      Film(
        id: id,
        isSeries: type == 'tv',
        title: title,
        year: date.length >= 4 ? date.substring(0, 4) : null,
        overview: r['overview']?.toString() ?? '',
        poster: (poster == null || poster.isEmpty)
            ? null
            : 'https://image.tmdb.org/t/p/w342$poster',
        rating: votes > 0 && rating != null && rating > 0 ? rating : null,
      ),
    );
  }
  return out;
}

/// YouTube id of the best video in a `/videos` answer: an official trailer
/// if there is one, then any trailer, then a teaser.
String? pickTrailerKey(dynamic json) {
  final results = json is Map ? json['results'] : null;
  if (results is! List) return null;
  String? best;
  var bestRank = 0;
  for (final v in results) {
    if (v is! Map || v['site'] != 'YouTube') continue;
    final key = v['key']?.toString();
    if (key == null || key.isEmpty) continue;
    final rank = switch (v['type']) {
      'Trailer' => v['official'] == true ? 4 : 3,
      'Teaser' => 2,
      _ => 1,
    };
    if (rank > bestRank) {
      bestRank = rank;
      best = key;
    }
  }
  return best;
}

/// Calls to the TMDB API with the user's key (a v3 key or a v4 token).
class Tmdb {
  Tmdb(this._key);

  final String _key;
  static const _base = 'https://api.themoviedb.org/3';

  /// v4 read tokens are JWTs and go into a header; v3 keys into the address.
  bool get _isToken => _key.startsWith('eyJ');

  Future<dynamic> _get(String path, Map<String, String> params) async {
    final uri = Uri.parse('$_base$path')
        .replace(queryParameters: {...params, if (!_isToken) 'api_key': _key});
    final http.Response response;
    try {
      response = await http
          .get(uri, headers: {if (_isToken) 'Authorization': 'Bearer $_key'})
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw SearchException(
        'TMDB не ответил. В некоторых странах он открывается только '
        'через VPN.',
      );
    }
    if (response.statusCode == 401) {
      throw SearchException('TMDB не принял ключ. Проверьте его.');
    }
    if (response.statusCode != 200) {
      throw SearchException('TMDB вернул ошибку ${response.statusCode}.');
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<List<Film>> search(String query) async => parseTmdbFilms(
    await _get('/search/multi', {
      'query': query,
      'language': 'ru-RU',
      'include_adult': 'false',
    }),
  );

  /// YouTube id of the trailer: the Russian one, else the original.
  Future<String?> trailerKey(Film film) async {
    final path = '/${film.isSeries ? 'tv' : 'movie'}/${film.id}/videos';
    final russian = pickTrailerKey(await _get(path, {'language': 'ru-RU'}));
    if (russian != null) return russian;
    return pickTrailerKey(await _get(path, {'language': 'en-US'}));
  }
}

/// Shown wherever TMDB data is: their terms ask for it.
const tmdbNotice =
    'Данные о фильмах — TMDB. Приложение использует TMDB API, но не '
    'одобрено и не сертифицировано TMDB.';
