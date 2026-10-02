import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../services/link_parser.dart';
import '../services/search.dart';
import '../theme.dart';

/// Search sources: the built-in ones and any API the user plugs in.
class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final search = ServicesScope.of(context).search;
    return Scaffold(
      appBar: AppBar(title: const Text('Источники поиска')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SourceEditScreen()),
        ),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Свой API'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListenableBuilder(
              listenable: search,
              builder: (context, _) {
                final sources = search.sources;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
                      child: Text(
                        'Через источник приложение ищет видео по названию. '
                        'Можно подключить любой API, который отвечает в JSON.',
                        style: TextStyle(color: kTextDim, height: 1.4),
                      ),
                    ),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (var i = 0; i < sources.length; i++) ...[
                            if (i > 0) const Divider(),
                            _SourceTile(source: sources[i]),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source});

  final SearchSource source;

  @override
  Widget build(BuildContext context) {
    final String status;
    if (!source.ready) {
      status = 'Нужен ключ API';
    } else if (kIsWeb && source.webBlocked) {
      status = 'Работает в приложении для Android, в браузере — нет';
    } else {
      status = source.builtIn ? 'Встроенный' : 'Свой API';
    }
    return ListTile(
      leading: Icon(
        source.builtIn ? Icons.verified_outlined : Icons.api_rounded,
        color: source.ready ? null : const Color(0xFFFFB74D),
      ),
      title: Text(source.name),
      subtitle: Text(status, style: const TextStyle(color: kTextDim)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SourceEditScreen(source: source),
        ),
      ),
    );
  }
}

/// Add or edit a source. For built-in ones only the key can be changed.
class SourceEditScreen extends StatefulWidget {
  const SourceEditScreen({super.key, this.source});

  final SearchSource? source;

  @override
  State<SourceEditScreen> createState() => _SourceEditScreenState();
}

class _SourceEditScreenState extends State<SourceEditScreen> {
  late final SearchSource? _initial = widget.source;
  late final _name = TextEditingController(text: _initial?.name ?? '');
  late final _url = TextEditingController(text: _initial?.urlTemplate ?? '');
  late final _key = TextEditingController(text: _initial?.apiKey ?? '');
  late final _headers = TextEditingController(
    text: (_initial?.headers ?? const {}).entries
        .map((e) => '${e.key}: ${e.value}')
        .join('\n'),
  );
  late final _list = TextEditingController(text: _initial?.listPath ?? '');
  late final _title = TextEditingController(text: _initial?.titlePath ?? '');
  late final _link = TextEditingController(text: _initial?.linkPath ?? '');
  late final _linkTemplate = TextEditingController(
    text: _initial?.linkTemplate ?? '',
  );
  late final _poster = TextEditingController(text: _initial?.posterPath ?? '');
  late final _subtitle = TextEditingController(
    text: _initial?.subtitlePath ?? '',
  );
  final _testQuery = TextEditingController(text: 'кино');

  bool _testing = false;
  String? _testOutcome;
  bool _testOk = false;

  bool get _builtIn => _initial?.builtIn ?? false;

  @override
  void dispose() {
    for (final c in [
      _name,
      _url,
      _key,
      _headers,
      _list,
      _title,
      _link,
      _linkTemplate,
      _poster,
      _subtitle,
      _testQuery,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> _parseHeaders() {
    final out = <String, String>{};
    for (final line in _headers.text.split('\n')) {
      final i = line.indexOf(':');
      if (i <= 0) continue;
      final k = line.substring(0, i).trim();
      final v = line.substring(i + 1).trim();
      if (k.isNotEmpty && v.isNotEmpty) out[k] = v;
    }
    return out;
  }

  SearchSource _build() {
    final initial = _initial;
    if (initial != null && initial.builtIn) {
      return initial.copyWith(apiKey: _key.text.trim());
    }
    return SearchSource(
      id: initial?.id ?? newId(),
      name: _name.text.trim().isEmpty ? 'Мой источник' : _name.text.trim(),
      urlTemplate: _url.text.trim(),
      apiKey: _key.text.trim(),
      headers: _parseHeaders(),
      listPath: _list.text.trim(),
      titlePath: _title.text.trim(),
      linkPath: _link.text.trim(),
      linkTemplate: _linkTemplate.text.trim(),
      posterPath: _poster.text.trim(),
      subtitlePath: _subtitle.text.trim(),
    );
  }

  String? _validate(SearchSource s) {
    if (s.builtIn) return null;
    if (!s.urlTemplate.startsWith('http')) {
      return 'Укажите адрес API, он начинается с https://';
    }
    if (!s.urlTemplate.contains('{query}')) {
      return 'В адресе должно быть {query} — туда подставится текст поиска.';
    }
    if (s.linkPath.isEmpty) return 'Укажите поле со ссылкой на видео.';
    return null;
  }

  Future<void> _test() async {
    final source = _build();
    final problem = _validate(source);
    if (problem != null) {
      setState(() {
        _testOk = false;
        _testOutcome = problem;
      });
      return;
    }
    setState(() {
      _testing = true;
      _testOutcome = null;
    });
    try {
      final results = await ServicesScope.of(context).search
          .search(source, _testQuery.text.trim());
      if (!mounted) return;
      if (results.isEmpty) {
        setState(() {
          _testOk = false;
          _testOutcome = 'Запрос прошёл, но результатов нет. Проверьте поля.';
        });
      } else {
        final first = results.first;
        final parsed = parseVideoLink(first.link);
        final kind = parsed == null
            ? 'не ссылка — проверьте поле ссылки'
            : parsed.syncable
            ? '${parsed.label}, синхронизация будет работать'
            : 'обычная страница, откроется без синхронизации';
        setState(() {
          _testOk = parsed != null;
          _testOutcome =
              'Найдено: ${results.length}\n'
              'Первый результат: ${first.title}\n'
              '${first.link}\n'
              'Вид ссылки: $kind';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testOutcome = e.toString();
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final source = _build();
    final problem = _validate(source);
    if (problem != null) {
      setState(() {
        _testOk = false;
        _testOutcome = problem;
      });
      return;
    }
    await ServicesScope.of(context).search.save(source);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить источник?'),
        content: Text('«${_initial!.name}» пропадёт из поиска.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await ServicesScope.of(context).search.remove(_initial!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final initial = _initial;
    final needsKey = initial?.needsKey ?? true;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          initial == null
              ? 'Свой API'
              : _builtIn
              ? initial.name
              : 'Источник',
        ),
        actions: [
          if (initial != null && !_builtIn)
            IconButton(
              tooltip: 'Удалить',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _delete,
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                if (_builtIn) ...[
                  if (kIsWeb && initial!.webBlocked)
                    const _Note(
                      'Этот сервис не отвечает на запросы из браузера. '
                      'Поиск по нему работает в приложении для Android; '
                      'ссылки с него открываются везде.',
                    ),
                  if (needsKey) ...[
                    _Note(initial!.keyHint),
                    _field(_key, 'Ключ API', mono: true),
                  ] else
                    const _Note('Ключ не нужен, источник готов к работе.'),
                ] else ...[
                  _field(_name, 'Название', hint: 'Например: Мой каталог'),
                  _field(
                    _url,
                    'Адрес поиска',
                    hint: 'https://example.com/api/search?q={query}&key={key}',
                    help:
                        '{query} — текст поиска, {key} — ключ из поля ниже '
                        '(если он нужен).',
                    mono: true,
                    lines: 2,
                  ),
                  _field(_key, 'Ключ API (если нужен)', mono: true),
                  _field(
                    _headers,
                    'Заголовки (если нужны)',
                    hint: 'Authorization: Bearer {key}',
                    help: 'По одному на строку: Имя: значение.',
                    mono: true,
                    lines: 2,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Где в ответе искать данные',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Путь — названия полей через точку, например '
                    'data.items или snippet.title. Число — номер элемента '
                    'в списке (0 — первый, -1 — последний).',
                    style: TextStyle(
                      color: kTextDim,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _field(
                    _list,
                    'Список результатов',
                    hint: 'results',
                    help: 'Пусто, если ответ — сразу список.',
                    mono: true,
                  ),
                  _field(_title, 'Название', hint: 'title', mono: true),
                  _field(
                    _link,
                    'Ссылка на видео',
                    hint: 'video_url',
                    help:
                        'Прямая ссылка на файл либо ссылка YouTube, VK Видео '
                        'или Rutube — тогда будет синхронизация.',
                    mono: true,
                  ),
                  _field(
                    _linkTemplate,
                    'Шаблон ссылки (если в поле только id)',
                    hint: 'https://example.com/video/{value}.mp4',
                    mono: true,
                  ),
                  _field(_poster, 'Постер', hint: 'poster.url', mono: true),
                  _field(_subtitle, 'Подпись', hint: 'year', mono: true),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _testQuery,
                        decoration: const InputDecoration(
                          hintText: 'Запрос для проверки',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: _testing ? null : _test,
                      child: _testing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Проверить'),
                    ),
                  ],
                ),
                if (_testOutcome != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _testOk
                              ? const Color(0xFF66BB6A)
                              : const Color(0xFFFFB74D),
                        ),
                      ),
                      child: SelectableText(
                        _testOutcome!,
                        style: const TextStyle(fontSize: 13, height: 1.45),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                FilledButton(onPressed: _save, child: const Text('Сохранить')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    String? help,
    bool mono = false,
    int lines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
          TextField(
            controller: controller,
            minLines: 1,
            maxLines: lines,
            autocorrect: false,
            enableSuggestions: false,
            style: mono
                ? const TextStyle(fontFamily: 'monospace', fontSize: 13.5)
                : null,
            decoration: InputDecoration(hintText: hint, isDense: true),
          ),
          if (help != null)
            Padding(
              padding: const EdgeInsets.only(left: 2, top: 6),
              child: Text(
                help,
                style: const TextStyle(color: kTextDim, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(text, style: const TextStyle(color: kTextDim, height: 1.4)),
    );
  }
}
