import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../config.dart';
import '../main.dart';
import '../models.dart';
import '../room_controller.dart';
import '../services/backend.dart';
import '../theme.dart';
import '../widgets/chat_panel.dart';
import '../widgets/player_surface.dart';
import '../widgets/reactions_layer.dart';
import 'add_video_sheet.dart';

/// Video and chat of one room.
///
/// Three arrangements, chosen by the window: phone upright (video on top,
/// chat below), wide screen (chat beside the video) and phone sideways
/// (video fills the screen, chat floats over it).
class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key, required this.session});

  final RoomSession session;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  late final RoomController _controller = RoomController(widget.session);
  final _playerKey = GlobalKey();
  final _reactionsKey = GlobalKey<ReactionsLayerState>();
  late final StreamSubscription<Reaction> _reactionSub;

  bool _chatOpen = true;
  bool _immersive = false;

  /// Latest message from someone else, shown briefly while the chat is hidden.
  ChatMessage? _toast;
  Timer? _toastTimer;
  int _seenMessages = 0;

  RoomSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _reactionSub = _session.reactions.listen(
      (r) => _reactionsKey.currentState?.spawn(r.emoji),
    );
    _seenMessages = _session.messages.value.length;
    _session.messages.addListener(_onMessages);
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _session.messages.removeListener(_onMessages);
    _reactionSub.cancel();
    _controller.dispose();
    _session.leave();
    _setImmersive(false);
    super.dispose();
  }

  void _onMessages() {
    final all = _session.messages.value;
    if (all.length > _seenMessages && _immersive && !_chatOpen) {
      final last = all.last;
      if (last.userId != _session.me.id && !last.system) {
        _toastTimer?.cancel();
        setState(() => _toast = last);
        _toastTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) setState(() => _toast = null);
        });
      }
    }
    _seenMessages = all.length;
  }

  void _setImmersive(bool on) {
    if (kIsWeb) return;
    SystemChrome.setEnabledSystemUIMode(
      on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  void _react(String emoji) {
    _reactionsKey.currentState?.spawn(emoji);
    _session.sendReaction(emoji);
  }

  Future<void> _addVideo() async {
    final source = await showModalBottomSheet<VideoSource>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const AddVideoSheet(),
    );
    if (source == null) return;
    await _controller.setVideo(source);
    final title = source.title;
    unawaited(
      _session
          .sendMessage(
            title == null
                ? '${_session.me.name} включает видео (${source.label})'
                : '${_session.me.name} включает «$title»',
            system: true,
          )
          .catchError((_) {}),
    );
  }

  Future<void> _invite() async {
    final services = ServicesScope.of(context);
    final room = _session.room;
    await Clipboard.setData(
      ClipboardData(
        text:
            'Заходи смотреть вместе в «${room.name}» ($appName):\n'
            '${services.inviteLink(room)}\n'
            'Код комнаты: ${room.code}',
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Приглашение скопировано')));
  }

  void _showMembers() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => ValueListenableBuilder<List<Member>>(
        valueListenable: _session.members,
        builder: (context, members, _) => PointerInterceptor(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'В комнате: ${members.length}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final m in members)
                ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 15,
                    backgroundColor: colorForUser(m.id),
                    child: Text(
                      m.name.characters.first.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  title: Text(
                    m.id == _session.me.id ? '${m.name} (вы)' : m.name,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final pad = media.padding;
    final keyboard = media.viewInsets.bottom;

    final immersive = size.width > size.height && size.height < 520;
    final wide = !immersive && size.width >= 900;
    if (immersive != _immersive) {
      _immersive = immersive;
      _setImmersive(immersive);
    }

    const headerHeight = 56.0;
    final Rect header;
    final Rect video;
    final Rect chat;

    if (immersive) {
      const chatWidth = 300.0;
      header = Rect.zero;
      video = Offset.zero & size;
      chat = Rect.fromLTWH(
        size.width - chatWidth - pad.right,
        0,
        chatWidth,
        size.height - keyboard,
      );
    } else if (wide) {
      const chatWidth = 380.0;
      header = Rect.fromLTWH(0, pad.top, size.width, headerHeight);
      video = Rect.fromLTRB(
        pad.left,
        header.bottom,
        size.width - chatWidth,
        size.height - pad.bottom,
      );
      chat = Rect.fromLTRB(
        video.right,
        header.bottom,
        size.width - pad.right,
        size.height - pad.bottom - keyboard,
      );
    } else {
      header = Rect.fromLTWH(0, pad.top, size.width, headerHeight);
      final videoHeight = (size.width * 9 / 16).clamp(
        0.0,
        (size.height - header.bottom) * 0.45,
      );
      video = Rect.fromLTWH(0, header.bottom, size.width, videoHeight);
      chat = Rect.fromLTRB(
        0,
        video.bottom,
        size.width,
        size.height - (keyboard > 0 ? keyboard : pad.bottom),
      );
    }

    final chatVisible = !immersive || _chatOpen;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: immersive ? Colors.black : kBackground,
      // The video keeps its place in this list in every arrangement, so
      // turning the phone does not restart it.
      body: Stack(
        children: [
          Positioned.fromRect(
            rect: video,
            child: PlayerSurface(
              controller: _controller,
              playerKey: _playerKey,
              reactionsKey: _reactionsKey,
              actions: SurfaceActions(
                immersive: immersive,
                chatOpen: _chatOpen,
                rightInset: immersive && _chatOpen ? size.width - chat.left : 0,
                onAddVideo: _addVideo,
                onToggleChat: () => setState(() {
                  _chatOpen = !_chatOpen;
                  _toast = null;
                }),
                onBack: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
          Positioned.fromRect(
            rect: header,
            child: Offstage(
              offstage: immersive,
              child: _Header(
                session: _session,
                onInvite: _invite,
                onMembers: _showMembers,
              ),
            ),
          ),
          Positioned.fromRect(
            rect: chat,
            child: Offstage(
              offstage: !chatVisible,
              child: PointerInterceptor(
                intercepting: immersive,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: wide
                        ? const Border(left: BorderSide(color: kOutline))
                        : null,
                  ),
                  child: ChatPanel(
                    session: _session,
                    overlay: immersive,
                    onReaction: _react,
                    onClose: immersive
                        ? () => setState(() => _chatOpen = false)
                        : null,
                  ),
                ),
              ),
            ),
          ),
          if (immersive && !_chatOpen && _toast != null)
            Positioned(
              left: 16 + pad.left,
              bottom: 56,
              child: IgnorePointer(child: _MessageToast(message: _toast!)),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.session,
    required this.onInvite,
    required this.onMembers,
  });

  final RoomSession session;
  final VoidCallback onInvite;
  final VoidCallback onMembers;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kBackground,
      child: Row(
        children: [
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Выйти из комнаты',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onMembers,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      session.room.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    ValueListenableBuilder<List<Member>>(
                      valueListenable: session.members,
                      builder: (context, members, _) => Text(
                        '${members.length} онлайн · код ${session.room.code}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: kTextDim),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onInvite,
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: const Text('Пригласить'),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _MessageToast extends StatelessWidget {
  const _MessageToast({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xCC000000),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${message.userName}  ',
                style: TextStyle(
                  color: colorForUser(message.userId),
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextSpan(text: message.text),
            ],
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13.5, height: 1.3),
        ),
      ),
    );
  }
}
