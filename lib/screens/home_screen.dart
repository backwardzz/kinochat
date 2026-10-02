import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../main.dart';
import '../models.dart';
import '../services/backend.dart';
import '../theme.dart';
import 'room_screen.dart';
import 'sources_screen.dart';
import 'welcome_screen.dart';

/// Create a room, join one by code, or reopen a recent one.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialCode});

  /// Code from an invite link; the room is opened right away.
  final String? initialCode;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _code = TextEditingController();
  bool _busy = false;

  Services get _services => ServicesScope.of(context);

  @override
  void initState() {
    super.initState();
    final code = widget.initialCode;
    if (code != null) {
      _code.text = code;
      WidgetsBinding.instance.addPostFrameCallback((_) => _joinByCode());
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<Room?> Function() getRoom) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final room = await getRoom();
      if (room == null) return;
      final services = _services;
      final session = await services.backend.join(room, services.profile);
      await services.prefs.rememberRoom(room);
      if (!mounted) {
        await session.leave();
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => RoomScreen(session: session)),
      );
    } on BackendException catch (e) {
      _say(e.message);
    } catch (_) {
      _say('Не получилось открыть комнату. Проверьте интернет.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: 'Новая комната',
        hint: 'Название',
        initial: 'Комната ${_services.profile.name}',
        action: 'Создать',
        maxLength: 40,
      ),
    );
    if (name == null) return;
    await _run(() => _services.backend.createRoom(name));
  }

  Future<void> _joinByCode() async {
    final code = _code.text.trim().toUpperCase();
    if (code.length != 6) {
      _say('Код комнаты — 6 символов.');
      return;
    }
    await _run(() async {
      final room = await _services.backend.findRoom(code);
      if (room == null) _say('Комната с кодом $code не найдена.');
      return room;
    });
  }

  Future<void> _rename() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: 'Ваше имя',
        hint: 'Имя',
        initial: _services.profile.name,
        action: 'Сохранить',
        maxLength: 24,
      ),
    );
    if (name == null) return;
    await _services.prefs.setUserName(name);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final services = _services;
    final text = Theme.of(context).textTheme;
    final recent = services.prefs.recentRooms;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            const AppMark(size: 30),
            const SizedBox(width: 10),
            Text(
              appName,
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Источники поиска',
            icon: const Icon(Icons.travel_explore_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SourcesScreen()),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _rename,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Привет, ${services.profile.name}',
                            overflow: TextOverflow.ellipsis,
                            style: text.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.edit_rounded,
                          size: 18,
                          color: kTextDim,
                        ),
                      ],
                    ),
                  ),
                ),
                if (services.backend.isDemo) ...[
                  const SizedBox(height: 8),
                  const _DemoBanner(),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _create,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Создать комнату'),
                ),
                const SizedBox(height: 20),
                Text(
                  'Войти по коду',
                  style: text.titleSmall?.copyWith(color: kTextDim),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _code,
                        maxLength: 6,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp('[A-Za-z0-9]'),
                          ),
                          _UpperCase(),
                        ],
                        style: const TextStyle(
                          fontSize: 18,
                          letterSpacing: 4,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'ABC123',
                          counterText: '',
                        ),
                        onSubmitted: (_) => _joinByCode(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: _busy ? null : _joinByCode,
                      child: const Text('Войти'),
                    ),
                  ],
                ),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                if (recent.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Text(
                    'Недавние комнаты',
                    style: text.titleSmall?.copyWith(color: kTextDim),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < recent.length; i++) ...[
                          if (i > 0) const Divider(),
                          ListTile(
                            leading: const Icon(Icons.meeting_room_outlined),
                            title: Text(
                              recent[i].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              recent[i].code,
                              style: const TextStyle(
                                color: kTextDim,
                                letterSpacing: 2,
                              ),
                            ),
                            trailing: IconButton(
                              tooltip: 'Убрать из списка',
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () async {
                                await services.prefs.forgetRoom(recent[i].code);
                                if (mounted) setState(() {});
                              },
                            ),
                            onTap: _busy
                                ? null
                                : () {
                                    _code.text = recent[i].code;
                                    _joinByCode();
                                  },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DemoBanner extends StatelessWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x33FFB74D),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFFFB74D)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Демо-режим: сервер не подключён. Комнаты работают только '
              'на этом устройстве.',
              style: TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.hint,
    required this.initial,
    required this.action,
    required this.maxLength,
  });

  final String title;
  final String hint;
  final String initial;
  final String action;
  final int maxLength;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _ctl = TextEditingController(
    text: widget.initial.length > widget.maxLength
        ? widget.initial.substring(0, widget.maxLength)
        : widget.initial,
  );

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _ctl.text.trim();
    if (v.isNotEmpty) Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctl,
        autofocus: true,
        maxLength: widget.maxLength,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: widget.hint, counterText: ''),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.action)),
      ],
    );
  }
}
