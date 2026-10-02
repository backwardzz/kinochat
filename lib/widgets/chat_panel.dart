import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../models.dart';
import '../services/backend.dart';
import '../theme.dart';

const quickReactions = ['❤️', '😂', '😮', '😢', '👍', '🔥'];

/// Message list and input. With [overlay] it is drawn see-through, to sit on
/// top of the video in landscape.
class ChatPanel extends StatefulWidget {
  const ChatPanel({
    super.key,
    required this.session,
    required this.onReaction,
    this.overlay = false,
    this.onClose,
  });

  final RoomSession session;
  final ValueChanged<String> onReaction;
  final bool overlay;
  final VoidCallback? onClose;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  bool _showReactions = false;

  /// On a phone the keyboard's Enter breaks the line and the button sends;
  /// with a physical keyboard Enter sends.
  static final bool _touchKeyboard =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    setState(() {});
    if (!_touchKeyboard) _focus.requestFocus();
    try {
      await widget.session.sendMessage(text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final overlay = widget.overlay;
    return Material(
      color: overlay ? const Color(0xB3000000) : kBackground,
      child: Column(
        children: [
          if (widget.onClose != null)
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Чат',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Скрыть чат',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
          Expanded(
            child: ValueListenableBuilder<List<ChatMessage>>(
              valueListenable: widget.session.messages,
              builder: (context, messages, _) {
                if (messages.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Сообщений пока нет.\nНапишите первым.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: kTextDim, height: 1.4),
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final index = messages.length - 1 - i;
                    final m = messages[index];
                    final prev = index > 0 ? messages[index - 1] : null;
                    final grouped =
                        prev != null &&
                        !prev.system &&
                        !m.system &&
                        prev.userId == m.userId &&
                        m.at.difference(prev.at).inMinutes < 3;
                    return _MessageRow(
                      message: m,
                      mine: m.userId == widget.session.me.id,
                      showName: !grouped,
                      overlay: overlay,
                    );
                  },
                );
              },
            ),
          ),
          if (_showReactions)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final e in quickReactions)
                    InkResponse(
                      radius: 22,
                      onTap: () => widget.onReaction(e),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(e, style: const TextStyle(fontSize: 24)),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Реакции',
                  icon: Icon(
                    _showReactions
                        ? Icons.emoji_emotions_rounded
                        : Icons.emoji_emotions_outlined,
                    color: _showReactions ? kAccent : kTextDim,
                  ),
                  onPressed: () =>
                      setState(() => _showReactions = !_showReactions),
                ),
                Expanded(
                  child: TextField(
                    controller: _input,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: maxMessageLength,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: _touchKeyboard
                        ? TextInputAction.newline
                        : TextInputAction.send,
                    // The default handler drops focus after "send".
                    onEditingComplete: () {},
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Сообщение',
                      counterText: '',
                      isDense: true,
                      fillColor: overlay ? const Color(0x33FFFFFF) : null,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton.filled(
                  tooltip: 'Отправить',
                  onPressed: _input.text.trim().isEmpty ? null : _send,
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.message,
    required this.mine,
    required this.showName,
    required this.overlay,
  });

  final ChatMessage message;
  final bool mine;
  final bool showName;
  final bool overlay;

  @override
  Widget build(BuildContext context) {
    if (message.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text(
            message.text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kTextDim, fontSize: 12),
          ),
        ),
      );
    }
    final time =
        '${message.at.hour.toString().padLeft(2, '0')}:'
        '${message.at.minute.toString().padLeft(2, '0')}';
    final bubbleColor = mine
        ? const Color(0xFF5A2327)
        : (overlay ? const Color(0x40FFFFFF) : kSurfaceHigh);

    return Padding(
      padding: EdgeInsets.only(top: showName ? 8 : 2),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            margin: EdgeInsets.only(left: mine ? 40 : 0, right: mine ? 0 : 40),
            padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showName && !mine)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      message.userName,
                      style: TextStyle(
                        color: colorForUser(message.userId),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 8,
                  children: [
                    Text(
                      message.text,
                      style: const TextStyle(fontSize: 14.5, height: 1.3),
                    ),
                    Text(
                      time,
                      style: const TextStyle(color: kTextDim, fontSize: 10.5),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
