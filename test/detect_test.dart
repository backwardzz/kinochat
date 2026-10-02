import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinochat/services/detect.dart';
import 'package:kinochat/services/search.dart';

void main() {
  test('Rutube-shaped answer', () {
    final found = detectPaths(
      jsonDecode('''
      {"count": 2, "has_next": false, "results": [
        {"id": "7358ddc35dd78d6f136be8e99f8be457", "title": "Девчата",
         "video_url": "https://rutube.ru/video/7358ddc35dd78d6f136be8e99f8be457/",
         "embed_url": "https://rutube.ru/play/embed/7358ddc35dd78d6f136be8e99f8be457",
         "thumbnail_url": "https://pic.rtbcdn.ru/video/a/b.jpg",
         "duration": 5769,
         "category": {"id": 4, "name": "Фильмы"},
         "author": {"id": 1, "name": "Мосфильм",
                    "avatar_url": "https://pic.rtbcdn.ru/user/c.jpg",
                    "site_url": "https://rutube.ru/channel/1/"}},
        {"id": "0123456789abcdef0123456789abcdef", "title": "Иван Васильевич",
         "video_url": "https://rutube.ru/video/0123456789abcdef0123456789abcdef/",
         "embed_url": "https://rutube.ru/play/embed/0123456789abcdef0123456789abcdef",
         "thumbnail_url": "https://pic.rtbcdn.ru/video/d/e.jpg",
         "duration": 5400,
         "category": {"id": 4, "name": "Фильмы"},
         "author": {"id": 1, "name": "Мосфильм",
                    "avatar_url": "https://pic.rtbcdn.ru/user/c.jpg",
                    "site_url": "https://rutube.ru/channel/1/"}}
      ]}
    '''),
    )!;
    expect(found.listPath, 'results');
    expect(found.linkPath, 'video_url');
    expect(found.titlePath, 'title');
    expect(found.posterPath, 'thumbnail_url');
    expect(found.subtitlePath, 'author.name');
  });

  test('nested answer with files inside a list', () {
    final found = detectPaths(
      jsonDecode('''
      {"batchcomplete": true, "query": {"pages": [
        {"pageid": 1, "title": "File:Sintel.webm", "imageinfo": [
          {"thumburl": "https://thumb.example.org/a/330px-Sintel.webm.jpg",
           "url": "https://upload.example.org/a/Sintel.webm",
           "descriptionurl": "https://example.org/wiki/File:Sintel.webm"}]},
        {"pageid": 2, "title": "File:Trailer.ogv", "imageinfo": [
          {"thumburl": "https://thumb.example.org/b/330px-Trailer.ogv.jpg",
           "url": "https://upload.example.org/b/Trailer.ogv",
           "descriptionurl": "https://example.org/wiki/File:Trailer.ogv"}]}
      ]}}
    '''),
    )!;
    expect(found.listPath, 'query.pages');
    expect(found.linkPath, 'imageinfo.0.url');
    expect(found.titlePath, 'title');
    expect(found.posterPath, 'imageinfo.0.thumburl');
  });

  test('answer that is a bare list, with a year', () {
    final found = detectPaths(
      jsonDecode('''
      [{"name": "Фильм", "year": 1975, "poster": "https://x/p.png",
        "genres": [{"name": "комедия"}],
        "stream": "https://cdn.example.com/f/1/index.m3u8"},
       {"name": "Другой фильм", "year": 1980, "poster": "https://x/q.png",
        "genres": [{"name": "драма"}],
        "stream": "https://cdn.example.com/f/2/index.m3u8"}]
    '''),
    )!;
    expect(found.listPath, '');
    expect(found.linkPath, 'stream');
    expect(found.titlePath, 'name');
    expect(found.posterPath, 'poster');
    expect(found.subtitlePath, 'year');
  });

  test('flat answer with several look-alike fields', () {
    final found = detectPaths(
      jsonDecode('''
      {"resultCount": 2, "results": [
        {"wrapperType": "track", "kind": "music-video",
         "artistName": "Artist", "trackName": "Song",
         "trackCensoredName": "Song",
         "artistViewUrl": "https://music.example.com/artist/1",
         "trackViewUrl": "https://music.example.com/video/2",
         "previewUrl": "https://video.example.com/a/b/clip.m4v",
         "artworkUrl30": "https://img.example.com/30x30bb.jpg",
         "artworkUrl100": "https://img.example.com/100x100bb.jpg",
         "primaryGenreName": "Pop", "country": "USA"},
        {"wrapperType": "track", "kind": "music-video",
         "artistName": "Other", "trackName": "Tune",
         "trackCensoredName": "Tune",
         "artistViewUrl": "https://music.example.com/artist/3",
         "trackViewUrl": "https://music.example.com/video/4",
         "previewUrl": "https://video.example.com/c/d/clip.m4v",
         "artworkUrl30": "https://img.example.com/30x30bb.jpg",
         "artworkUrl100": "https://img.example.com/100x100bb.jpg",
         "primaryGenreName": "Rock", "country": "USA"}
      ]}
    '''),
    )!;
    expect(found.listPath, 'results');
    expect(found.linkPath, 'previewUrl');
    expect(found.titlePath, 'trackName');
    expect(found.posterPath, 'artworkUrl100');
    expect(found.subtitlePath, 'artistName');
  });

  test('the list of results is told apart from other lists', () {
    final found = detectPaths(
      jsonDecode('''
      {"filters": [{"name": "Год", "url": "https://x/filters/year"}],
       "data": {"items": [
         {"title": "A", "iframe_src": "//player.example.com/embed/1"},
         {"title": "B", "iframe_src": "//player.example.com/embed/2"},
         {"title": "C", "iframe_src": "//player.example.com/embed/3"}]}}
    '''),
    )!;
    expect(found.listPath, 'data.items');
    expect(found.linkPath, 'iframe_src');
  });

  test('detected paths give working results', () {
    final json = jsonDecode('''
      {"data": {"items": [
        {"title": "A", "iframe_src": "//player.example.com/embed/1"}]}}
    ''');
    final found = detectPaths(json)!;
    final results = parseResults(
      SearchSource(
        id: 't',
        name: 'Test',
        urlTemplate: 'https://x/?q={query}',
        listPath: found.listPath,
        titlePath: found.titlePath,
        linkPath: found.linkPath,
      ),
      json,
    );
    expect(results.single.link, 'https://player.example.com/embed/1');
    expect(results.single.source, 'Test');
  });

  test('nothing that looks like videos', () {
    expect(detectPaths(jsonDecode('{"error": "bad key"}')), isNull);
    expect(detectPaths(jsonDecode('{"items": []}')), isNull);
    expect(
      detectPaths(jsonDecode('{"items": [{"title": "A", "id": 5}]}')),
      isNull,
    );
    expect(detectPaths(jsonDecode('"text"')), isNull);
  });

  test('interleave takes from each list in turn', () {
    expect(
      interleave([
        [1, 2, 3],
        <int>[],
        [10, 20],
      ]),
      [1, 10, 2, 20, 3],
    );
    expect(interleave(<List<int>>[]), isEmpty);
  });
}
