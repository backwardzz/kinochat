import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinochat/services/tmdb.dart';

void main() {
  test('films and series are read, people are skipped', () {
    final films = parseTmdbFilms(
      jsonDecode('''
      {"page": 1, "results": [
        {"id": 603, "media_type": "movie", "title": "Матрица",
         "release_date": "1999-03-31", "overview": "Хакер Нео узнаёт…",
         "poster_path": "/abc.jpg", "vote_average": 8.2, "vote_count": 25000},
        {"id": 1399, "media_type": "tv", "name": "Игра престолов",
         "first_air_date": "2011-04-17", "overview": "",
         "poster_path": null, "vote_average": 0, "vote_count": 0},
        {"id": 6384, "media_type": "person", "name": "Киану Ривз"},
        {"id": 7, "media_type": "movie", "title": "", "release_date": ""}
      ]}
    '''),
    );
    expect(films, hasLength(2));

    final movie = films[0];
    expect(movie.id, 603);
    expect(movie.isSeries, isFalse);
    expect(movie.title, 'Матрица');
    expect(movie.year, '1999');
    expect(movie.poster, 'https://image.tmdb.org/t/p/w342/abc.jpg');
    expect(movie.rating, 8.2);

    final series = films[1];
    expect(series.isSeries, isTrue);
    expect(series.title, 'Игра престолов');
    expect(series.year, '2011');
    expect(series.poster, isNull);
    // No votes yet is not the same as a rating of zero.
    expect(series.rating, isNull);
  });

  test('an error answer gives no films', () {
    expect(parseTmdbFilms(jsonDecode('{"success": false}')), isEmpty);
    expect(parseTmdbFilms(jsonDecode('[]')), isEmpty);
  });

  test('the official YouTube trailer is preferred', () {
    final key = pickTrailerKey(
      jsonDecode('''
      {"id": 603, "results": [
        {"site": "YouTube", "type": "Featurette", "key": "feat", "official": true},
        {"site": "YouTube", "type": "Teaser", "key": "teaser", "official": true},
        {"site": "Vimeo", "type": "Trailer", "key": "vimeo", "official": true},
        {"site": "YouTube", "type": "Trailer", "key": "fan", "official": false},
        {"site": "YouTube", "type": "Trailer", "key": "official", "official": true}
      ]}
    '''),
    );
    expect(key, 'official');
  });

  test('a teaser will do when there is no trailer', () {
    expect(
      pickTrailerKey(
        jsonDecode('''
        {"results": [
          {"site": "YouTube", "type": "Clip", "key": "clip"},
          {"site": "YouTube", "type": "Teaser", "key": "teaser"}
        ]}
      '''),
      ),
      'teaser',
    );
  });

  test('no trailer', () {
    expect(pickTrailerKey(jsonDecode('{"results": []}')), isNull);
    expect(
      pickTrailerKey(
        jsonDecode(
          '{"results": [{"site": "Vimeo", "type": "Trailer", "key": "v"}]}',
        ),
      ),
      isNull,
    );
  });
}
