import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinochat/services/search.dart';

void main() {
  group('readPath', () {
    final json = jsonDecode('''
      {"a": {"b": [{"c": 1}, {"c": 2}, {"c": 3}]}, "s": "text"}
    ''');

    test('walks maps and lists', () {
      expect(readPath(json, 'a.b.0.c'), 1);
      expect(readPath(json, 'a.b.-1.c'), 3);
      expect(readPath(json, 's'), 'text');
    });

    test('empty path returns the value itself', () {
      expect(readPath(json, ''), same(json));
    });

    test('missing pieces give null', () {
      expect(readPath(json, 'a.x.c'), isNull);
      expect(readPath(json, 'a.b.7.c'), isNull);
      expect(readPath(json, 's.deeper'), isNull);
      expect(readPath(json, 'a.b.name'), isNull);
    });
  });

  group('parseResults', () {
    test('YouTube-shaped answer with an id and a link template', () {
      const source = SearchSource(
        id: 't',
        name: 't',
        urlTemplate: 'https://x/?q={query}',
        listPath: 'items',
        titlePath: 'snippet.title',
        linkPath: 'id.videoId',
        linkTemplate: 'https://www.youtube.com/watch?v={value}',
        posterPath: 'snippet.thumbnails.medium.url',
        subtitlePath: 'snippet.channelTitle',
      );
      final results = parseResults(
        source,
        jsonDecode('''
        {"items": [
          {"id": {"videoId": "dQw4w9WgXcQ"},
           "snippet": {"title": "Tom &amp; Jerry", "channelTitle": "Ch",
                       "thumbnails": {"medium": {"url": "https://i/1.jpg"}}}},
          {"id": {"kind": "channel"}, "snippet": {"title": "no video id"}}
        ]}
      '''),
      );
      expect(results, hasLength(1));
      expect(results.first.title, 'Tom & Jerry');
      expect(results.first.link, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(results.first.poster, 'https://i/1.jpg');
      expect(results.first.subtitle, 'Ch');
    });

    test('answer that is a bare list', () {
      const source = SearchSource(
        id: 't',
        name: 't',
        urlTemplate: 'https://x/?q={query}',
        listPath: '',
        titlePath: 'name',
        linkPath: 'file',
      );
      final results = parseResults(
        source,
        jsonDecode('[{"name": "A", "file": "https://x/a.mp4"}]'),
      );
      expect(results.single.link, 'https://x/a.mp4');
      expect(results.single.poster, isNull);
    });

    test('wrong list path is reported', () {
      const source = SearchSource(
        id: 't',
        name: 't',
        urlTemplate: 'https://x/?q={query}',
        listPath: 'data.items',
        titlePath: 'name',
        linkPath: 'file',
      );
      expect(
        () => parseResults(source, jsonDecode('{"data": {}}')),
        throwsA(isA<SearchException>()),
      );
    });
  });

  test('a source knows when it needs a key', () {
    const withKey = SearchSource(
      id: 'a',
      name: 'a',
      urlTemplate: 'https://x/?q={query}&key={key}',
      listPath: '',
      titlePath: '',
      linkPath: 'l',
    );
    expect(withKey.needsKey, isTrue);
    expect(withKey.ready, isFalse);
    expect(withKey.copyWith(apiKey: 'k').ready, isTrue);

    const inHeader = SearchSource(
      id: 'b',
      name: 'b',
      urlTemplate: 'https://x/?q={query}',
      listPath: '',
      titlePath: '',
      linkPath: 'l',
      headers: {'Authorization': 'Bearer {key}'},
    );
    expect(inHeader.needsKey, isTrue);
  });
}
