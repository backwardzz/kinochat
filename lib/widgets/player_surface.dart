import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:url_launcher/url_launcher.dart';

import '../player/player_controller.dart';
import '../player/player_view.dart';
import '../room_controller.dart';
import '../theme.dart';
import 'reactions_layer.dart';

/// What the buttons drawn over the video do.
class SurfaceActions {
  const SurfaceActions({
    required this.immersive,
    required this.chatOpen,
    required this.onAddVideo,
    required this.onToggleChat,
    required this.onBack,
  });

  /// Phone held sideways: the video fills the screen, so it carries the back
  /// and chat buttons itself.
  final bool immersive;
  final bool chatOpen;
  final VoidCallback onAddVideo;
  final VoidCallback onToggleChat;
  final VoidCallback onBack;
}

/// The video with everything drawn over it: controls, notices, reactions.
class PlayerSurface extends StatelessWidget {
  const PlayerSurface({
    super.key,
    required this.controller,
    required this.playerKey,
    required this.reactionsKey,
    required this.actions,
  });

  final RoomController controller;
  final GlobalKey playerKey;
  final GlobalKey<ReactionsLayerState> reactionsKey;
  final SurfaceActions actions;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: ListenableBuilder(
        listenable: Listenable.merge([controller, controller.player]),
        builder: (context, _) {
          final source = controller.source;
          final player = controller.player;
          final error = player.error;

          final Widget? overlay;
          if (source == null) {
            overlay = _EmptyState(actions: actions);
          } else if (error != null) {
            overlay = _ErrorPanel(
              message: error,
              url: source.url,
              actions: actions,
            );
          } else if (!source.syncable) {
            overlay = _EmbedBar(url: source.url, actions: actions);
          } else if (player.status.blocked) {
            // The player page is asking for a tap; stay out of the way.
            overlay = null;
          } else {
            overlay = _Controls(controller: controller, actions: actions);
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              if (source != null)
                PlayerView(key: playerKey, controller: player),
              ?overlay,
              ReactionsLayer(key: reactionsKey),
              Positioned(
                top: 10,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: ValueListenableBuilder<String?>(
                    valueListenable: controller.notice,
                    builder: (context, text, _) => AnimatedOpacity(
                      opacity: text == null ? 0 : 1,
                      duration: const Duration(milliseconds: 180),
                      child: Center(child: _Pill(text: text ?? '')),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xCC000000),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Row along the top edge of the video: back, a label, actions, chat.
class _TopRow extends StatelessWidget {
  const _TopRow({
    required this.actions,
    required this.label,
    this.dim = false,
    this.changeVideo = true,
    this.extra = const [],
  });

  final SurfaceActions actions;
  final String label;
  final bool dim;
  final bool changeVideo;
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (actions.immersive)
          IconButton(
            tooltip: 'Назад',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: actions.onBack,
          )
        else
          const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            maxLines: dim ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: dim
                ? const TextStyle(fontSize: 12, color: kTextDim)
                : const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
        ...extra,
        if (changeVideo)
          IconButton(
            tooltip: 'Другое видео',
            icon: const Icon(Icons.playlist_play_rounded),
            onPressed: actions.onAddVideo,
          ),
        if (actions.immersive)
          IconButton(
            tooltip: actions.chatOpen ? 'Скрыть чат' : 'Показать чат',
            icon: Icon(
              actions.chatOpen
                  ? Icons.chat_bubble_rounded
                  : Icons.chat_bubble_outline_rounded,
            ),
            onPressed: actions.onToggleChat,
          ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.actions});

  final SurfaceActions actions;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.movie_outlined,
                  size: 36,
                  color: Colors.white38,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Видео ещё не выбрано',
                  style: TextStyle(color: kTextDim),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: actions.onAddVideo,
                  icon: const Icon(Icons.add_link_rounded),
                  label: const Text('Добавить видео'),
                ),
              ],
            ),
          ),
        ),
        if (actions.immersive)
          Positioned(
            top: 2,
            left: 4,
            right: 4,
            child: _TopRow(actions: actions, label: '', changeVideo: false),
          ),
      ],
    );
  }
}

/// Our own controls: every press goes through the room, so everyone's
/// player does the same.
class _Controls extends StatefulWidget {
  const _Controls({required this.controller, required this.actions});

  final RoomController controller;
  final SurfaceActions actions;

  @override
  State<_Controls> createState() => _ControlsState();
}

class _ControlsState extends State<_Controls> {
  bool _visible = true;
  Timer? _hideTimer;

  /// Thumb position while dragging and until the player catches up.
  double? _scrub;
  Timer? _scrubTimer;

  static const _timeStyle = TextStyle(
    fontSize: 12,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _scrubTimer?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && widget.controller.state.playing && _scrub == null) {
        setState(() => _visible = false);
      }
    });
  }

  void _toggle() {
    setState(() => _visible = !_visible);
    if (_visible) _scheduleHide();
  }

  void _act(VoidCallback action) {
    action();
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final status = c.player.status;
    final ended = status.phase == PlayerPhase.ended;
    final playing = c.state.playing && !ended;
    final visible = _visible || !playing;
    final duration = status.duration;
    final position = (_scrub ?? status.time).clamp(
      0.0,
      duration > 0 ? duration : double.infinity,
    );
    final buffering =
        status.phase == PlayerPhase.buffering ||
        (playing && status.phase == PlayerPhase.idle);

    return PointerInterceptor(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (buffering && !visible)
              const Center(
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white,
                  ),
                ),
              ),
            AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: IgnorePointer(
                ignoring: !visible,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xB3000000),
                        Color(0x33000000),
                        Color(0x33000000),
                        Color(0xCC000000),
                      ],
                      stops: [0, .28, .62, 1],
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: 2,
                        left: 4,
                        right: 4,
                        child: _TopRow(
                          actions: widget.actions,
                          label: c.title ?? c.source?.label ?? '',
                        ),
                      ),
                      // centre: back 10 s, play/pause, forward 10 s
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Назад на 10 секунд',
                              iconSize: 32,
                              icon: const Icon(Icons.replay_10_rounded),
                              onPressed: () => _act(() => c.seekBy(-10)),
                            ),
                            const SizedBox(width: 18),
                            SizedBox(
                              width: 64,
                              height: 64,
                              child: buffering
                                  ? const Padding(
                                      padding: EdgeInsets.all(14),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        color: Colors.white,
                                      ),
                                    )
                                  : IconButton.filled(
                                      tooltip: ended
                                          ? 'Сначала'
                                          : playing
                                          ? 'Пауза'
                                          : 'Смотреть',
                                      iconSize: 38,
                                      style: IconButton.styleFrom(
                                        backgroundColor: const Color(
                                          0x66000000,
                                        ),
                                        foregroundColor: Colors.white,
                                      ),
                                      icon: Icon(
                                        ended
                                            ? Icons.replay_rounded
                                            : playing
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                      ),
                                      onPressed: () => _act(c.togglePlay),
                                    ),
                            ),
                            const SizedBox(width: 18),
                            IconButton(
                              tooltip: 'Вперёд на 10 секунд',
                              iconSize: 32,
                              icon: const Icon(Icons.forward_10_rounded),
                              onPressed: () => _act(() => c.seekBy(10)),
                            ),
                          ],
                        ),
                      ),
                      // bottom: time and seek bar
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 2,
                        child: Row(
                          children: [
                            Text(formatTime(position), style: _timeStyle),
                            Expanded(
                              child: Slider(
                                value: duration > 0 ? position : 0,
                                max: duration > 0 ? duration : 1,
                                onChanged: duration > 0
                                    ? (v) {
                                        _hideTimer?.cancel();
                                        _scrubTimer?.cancel();
                                        setState(() => _scrub = v);
                                      }
                                    : null,
                                onChangeEnd: (v) {
                                  c.seekTo(v);
                                  // Hold the thumb until the player reports
                                  // the new position.
                                  _scrubTimer = Timer(
                                    const Duration(milliseconds: 1500),
                                    () {
                                      if (mounted) {
                                        setState(() => _scrub = null);
                                      }
                                    },
                                  );
                                  _scheduleHide();
                                },
                              ),
                            ),
                            Text(
                              duration > 0 ? formatTime(duration) : '—',
                              style: _timeStyle,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _openOutside(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// Strip over a page that cannot be controlled: the page stays tappable.
class _EmbedBar extends StatelessWidget {
  const _EmbedBar({required this.url, required this.actions});

  final String url;
  final SurfaceActions actions;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: PointerInterceptor(
        child: ColoredBox(
          color: const Color(0xE6000000),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _TopRow(
              actions: actions,
              label: 'Страница без синхронизации: каждый запускает видео сам',
              dim: true,
              extra: [
                IconButton(
                  tooltip: 'Открыть в браузере',
                  icon: const Icon(Icons.open_in_new_rounded, size: 20),
                  onPressed: () => _openOutside(url),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.message,
    required this.url,
    required this.actions,
  });

  final String message;
  final String url;
  final SurfaceActions actions;

  @override
  Widget build(BuildContext context) {
    return PointerInterceptor(
      child: ColoredBox(
        color: const Color(0xF2000000),
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Color(0xFFFFB74D),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(height: 1.35),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        OutlinedButton(
                          onPressed: () => _openOutside(url),
                          child: const Text('Открыть в браузере'),
                        ),
                        FilledButton(
                          onPressed: actions.onAddVideo,
                          child: const Text('Другое видео'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (actions.immersive)
              Positioned(
                top: 2,
                left: 4,
                right: 4,
                child: _TopRow(actions: actions, label: '', changeVideo: false),
              ),
          ],
        ),
      ),
    );
  }
}
