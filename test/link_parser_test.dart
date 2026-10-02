import 'package:flutter_test/flutter_test.dart';
import 'package:kinochat/models.dart';
import 'package:kinochat/services/link_parser.dart';

void main() {
  group('YouTube', () {
    test('watch link', () {
      final s = parseVideoLink('https://www.youtube.com/watch?v=dQw4w9WgXcQ')!;
      expect(s.kind, VideoKind.youtube);
      expect(s.ref, 'dQw4w9WgXcQ');
      expect(s.syncable, isTrue);
    });

    test('short link with start time', () {
      final s = parseVideoLink('https://youtu.be/dQw4w9WgXcQ?t=1m30s')!;
      expect(s.kind, VideoKind.youtube);
      expect(s.ref, 'dQw4w9WgXcQ');
      expect(s.startSec, 90);
    });

    test('shorts, embed, mobile, no scheme', () {
      for (final link in [
        'https://www.youtube.com/shorts/dQw4w9WgXcQ',
        'https://www.youtube.com/embed/dQw4w9WgXcQ',
        'https://m.youtube.com/watch?v=dQw4w9WgXcQ&list=abc',
        'youtube.com/watch?v=dQw4w9WgXcQ',
      ]) {
        final s = parseVideoLink(link)!;
        expect(s.kind, VideoKind.youtube, reason: link);
        expect(s.ref, 'dQw4w9WgXcQ', reason: link);
      }
    });

    test('channel page is not a video', () {
      final s = parseVideoLink('https://www.youtube.com/@somechannel')!;
      expect(s.kind, VideoKind.embed);
    });
  });

  test('Rutube', () {
    const id = '7358ddc35dd78d6f136be8e99f8be457';
    for (final link in [
      'https://rutube.ru/video/$id/',
      'https://rutube.ru/play/embed/$id',
      'https://rutube.ru/video/$id/?t=120',
    ]) {
      final s = parseVideoLink(link)!;
      expect(s.kind, VideoKind.rutube, reason: link);
      expect(s.ref, id, reason: link);
    }
    expect(parseVideoLink('https://rutube.ru/video/$id/?t=120')!.startSec, 120);
  });

  test('VK Видео', () {
    expect(
      parseVideoLink('https://vk.com/video-22822305_456242110')!.ref,
      '-22822305_456242110',
    );
    expect(
      parseVideoLink('https://vkvideo.ru/video-22822305_456242110')!.kind,
      VideoKind.vk,
    );
    expect(
      parseVideoLink('https://vk.com/feed?z=video-1_2%2Fabc')!.ref,
      '-1_2',
    );
    final ext = parseVideoLink(
      'https://vk.com/video_ext.php?oid=-1&id=2&hash=abcdef',
    )!;
    expect(ext.kind, VideoKind.vk);
    expect(ext.ref, '-1_2_abcdef');
  });

  test('direct files', () {
    for (final link in [
      'https://example.com/films/movie.mp4',
      'https://example.com/live/index.m3u8?token=1',
      'https://cdn.example.com/a/b/clip.WEBM',
    ]) {
      final s = parseVideoLink(link)!;
      expect(s.kind, VideoKind.file, reason: link);
      expect(s.ref, link, reason: link);
      expect(s.syncable, isTrue);
    }
  });

  test('any other page opens without sync', () {
    final s = parseVideoLink('https://example.com/watch/123')!;
    expect(s.kind, VideoKind.embed);
    expect(s.syncable, isFalse);
  });

  test('not a link', () {
    expect(parseVideoLink(''), isNull);
    expect(parseVideoLink('привет'), isNull);
    expect(parseVideoLink('ftp://example.com/a.mp4'), isNull);
    expect(parseVideoLink('javascript:alert(1)'), isNull);
  });
}
