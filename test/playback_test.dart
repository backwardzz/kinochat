import 'package:flutter_test/flutter_test.dart';
import 'package:kinochat/models.dart';
import 'package:kinochat/room_controller.dart';

void main() {
  const source = VideoSource(
    kind: VideoKind.youtube,
    ref: 'dQw4w9WgXcQ',
    url: 'https://youtu.be/dQw4w9WgXcQ',
    title: 'Clip',
  );

  test('position advances only while playing', () {
    const playing = PlaybackState(
      source: source,
      playing: true,
      positionMs: 60000,
      atMs: 1000000,
      by: 'A',
    );
    expect(playing.expectedPositionMs(1000000), 60000);
    expect(playing.expectedPositionMs(1012500), 72500);
    // A device whose clock is slightly behind never goes backwards.
    expect(playing.expectedPositionMs(999000), 60000);

    const paused = PlaybackState(
      source: source,
      playing: false,
      positionMs: 60000,
      atMs: 1000000,
      by: 'A',
    );
    expect(paused.expectedPositionMs(1999999), 60000);
  });

  test('state survives the trip through JSON', () {
    const state = PlaybackState(
      source: source,
      playing: true,
      positionMs: 1234,
      atMs: 5678,
      by: 'Аня',
    );
    final back = PlaybackState.fromJson(state.toJson());
    expect(back.source!.key, source.key);
    expect(back.source!.title, 'Clip');
    expect(back.playing, isTrue);
    expect(back.positionMs, 1234);
    expect(back.atMs, 5678);
    expect(back.by, 'Аня');
  });

  test('no video', () {
    expect(PlaybackState.fromJson(null).source, isNull);
    expect(PlaybackState.fromJson(PlaybackState.empty.toJson()).source, isNull);
  });

  test('room codes avoid look-alike characters', () {
    for (var i = 0; i < 200; i++) {
      expect(newRoomCode(), matches(r'^[A-HJKMNP-Z2-9]{6}$'));
    }
  });

  test('formatTime', () {
    expect(formatTime(0), '0:00');
    expect(formatTime(65), '1:05');
    expect(formatTime(3727), '1:02:07');
    expect(formatTime(-5), '0:00');
    expect(formatTime(double.nan), '0:00');
  });
}
