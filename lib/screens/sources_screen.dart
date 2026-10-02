import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../services/detect.dart';
import '../services/link_parser.dart';
import '../services/search.dart';
import '../services/tmdb.dart';
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
        label: const Text('Добавить API'),
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
                        'Поиск идёт сразу по всем источникам из этого списка. '
                        'Добавить можно любой API, который отвечает в JSON.',
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
      status = 'Не участвует в поиске: нужен ключ API';
    } else if (kIsWeb && source.webBlocked) {
      status = 'Работает в приложении для Android, в браузере — нет';
    } else if (source.catalog) {
      status = 'Каталог фильмов: описания, постеры, трейлеры';
    } else {
      status = source.builtIn ? 'Встроенный' : 'Свой API';
    }
    return ListTile(
      leading: Icon(
        source.builtIn ? Icons.verified_outlined : Icons.api_rounded,
        color: source.usableHere ? null : const Color(0xFFFFB74D),
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
///
/// A new API needs just its address: where the title, the link and the
/// poster are in the answer is worked out from a trial search. The paths can
/// still be corrected by hand under «Дополнительно».
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

  bool _busy = false;
  String? _outcome;
  bool _ok = false;

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

  /// `…?q=` pasted without the placeholder gets one.
  String _address() {
    final url = _url.text.trim();
    return !url.contains('{query}') && url.endsWith('=') ? '$url{query}' : url;
  }

  SearchSource _build() {
    final initial = _initial;
    if (initial != null && initial.builtIn) {
      return initial.copyWith(apiKey: _key.text.trim());
    }
    final address = _address();
    final name = _name.text.trim();
    return SearchSource(
      id: initial?.id ?? newId(),
      name: name.isNotEmpty
          ? name
          : (Uri.tryParse(address)?.host.replaceFirst('www.', '') ?? '')
                .ifEmpty('Мой источник'),
      urlTemplate: address,
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

  String? _problemWith(SearchSource s) {
    if (s.builtIn) return null;
    if (!s.urlTemplate.startsWith('http')) {
      return 'Укажите адрес API, он начинается с https://';
    }
    if (!s.urlTemplate.contains('{query}')) {
      return 'Поставьте в адресе {query} там, где должен быть текст поиска. '
          'Например: https://site.com/api/search?q={query}';
    }
    if (s.needsKey && s.apiKey.isEmpty) {
      return 'В адресе есть {key} — укажите ключ API.';
    }
    return null;
  }

  void _show(String text, {bool ok = false}) {
    if (!mounted) return;
    setState(() {
      _outcome = text;
      _ok = ok;
    });
  }

  /// Runs a trial search, works out the fields if they are not set yet and
  /// reports what was found. Returns whether the source is usable.
  Future<bool> _check() async {
    var source = _build();
    final problem = _problemWith(source);
    if (problem != null) {
      _show(problem);
      return false;
    }
    final query = _testQuery.text.trim().ifEmpty('кино');
    final search = ServicesScope.of(context).search;
    setState(() {
      _busy = true;
      _outcome = null;
    });
    try {
      if (source.catalog) {
        final films = await Tmdb(source.apiKey).search(query);
        if (films.isEmpty) {
          _show(
            'Ключ принят, но по запросу «$query» в каталоге ничего нет. '
            'Попробуйте другой запрос для проверки.',
          );
          return false;
        }
        final first = films.first;
        _show(
          'Работает, найдено: ${films.length}\n'
          '${first.title}${first.year == null ? '' : ' (${first.year})'}',
          ok: true,
        );
        return true;
      }

      final json = await search.fetch(source, query);
      if (!mounted) return false;

      if (!source.builtIn && source.linkPath.isEmpty) {
        final found = detectPaths(json);
        if (found == null) {
          _show(
            'Сервис ответил, но ссылок на видео в ответе не нашлось. '
            'Попробуйте другой запрос для проверки или укажите поля вручную '
            'в «Дополнительно».',
          );
          return false;
        }
        _list.text = found.listPath;
        _title.text = found.titlePath;
        _link.text = found.linkPath;
        _poster.text = found.posterPath;
        _subtitle.text = found.subtitlePath;
        source = _build();
      }

      final results = parseResults(source, json);
      if (results.isEmpty) {
        _show(
          'Сервис ответил, но по запросу «$query» ничего нет. '
          'Попробуйте другой запрос для проверки.',
        );
        return false;
      }
      final first = results.first;
      final parsed = parseVideoLink(first.link);
      if (parsed == null) {
        _show(
          'В поле ссылки оказалась не ссылка: ${first.link}\n'
          'Поправьте поля в «Дополнительно».',
        );
        return false;
      }
      _show(
        'Работает, найдено: ${results.length}\n'
        '${first.title}\n'
        '${parsed.syncable ? '${parsed.label} — будет идти у всех одновременно' : 'Обычная страница — откроется без синхронизации'}',
        ok: true,
      );
      return true;
    } on SearchException catch (e) {
      _show(e.message);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _redetect() async {
    for (final c in [_list, _title, _link, _linkTemplate, _poster, _subtitle]) {
      c.clear();
    }
    await _check();
  }

  Future<void> _save() async {
    final search = ServicesScope.of(context).search;
    // A source without fields is not usable yet: check it first.
    if (!_builtIn && _link.text.trim().isEmpty && !await _check()) return;
    final source = _build();
    final problem = _problemWith(source);
    if (problem != null) {
      _show(problem);
      return;
    }
    await search.save(source);
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
              ? 'Новый API'
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
                    _field(_key, 'Ключ API', mono: true, lines: 4),
                    if (initial.catalog) const _Note(tmdbNotice),
                  ] else
                    const _Note('Ключ не нужен, источник готов к работе.'),
                ] else ...[
                  _field(
                    _url,
                    'Адрес поиска',
                    hint: 'https://site.com/api/search?q={query}',
                    help:
                        '{query} — место для текста поиска. Если нужен ключ, '
                        'поставьте в адресе {key} и впишите ключ ниже.',
                    mono: true,
                    lines: 3,
                  ),
                  _field(_key, 'Ключ API (если нужен)', mono: true),
                  _field(
                    _name,
                    'Название (не обязательно)',
                    hint: 'Например: Мой каталог',
                  ),
                ],
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
                      onPressed: _busy ? null : _check,
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Проверить'),
                    ),
                  ],
                ),
                if (_outcome != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _ok
                              ? const Color(0xFF66BB6A)
                              : const Color(0xFFFFB74D),
                        ),
                      ),
                      child: Text(
                        _outcome!,
                        style: const TextStyle(fontSize: 13, height: 1.45),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: const Text('Сохранить'),
                ),
                if (!_builtIn) ...[const SizedBox(height: 12), _advanced()],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Manual control over what detection fills in.
  Widget _advanced() {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        title: const Text('Дополнительно', style: TextStyle(fontSize: 14)),
        subtitle: const Text(
          'Поля ответа и заголовки. Заполняются сами при проверке.',
          style: TextStyle(color: kTextDim, fontSize: 12),
        ),
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 12),
            child: Text(
              'Путь — названия полей через точку, например data.items или '
              'snippet.title. Число — номер элемента в списке (0 — первый, '
              '-1 — последний).',
              style: TextStyle(color: kTextDim, fontSize: 13, height: 1.4),
            ),
          ),
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
                'Прямая ссылка на файл либо ссылка YouTube, VK Видео или '
                'Rutube — тогда будет синхронизация.',
            mono: true,
          ),
          _field(
            _linkTemplate,
            'Шаблон ссылки (если в поле только id)',
            hint: 'https://site.com/video/{value}.mp4',
            mono: true,
          ),
          _field(_poster, 'Постер', hint: 'poster.url', mono: true),
          _field(_subtitle, 'Подпись', hint: 'year', mono: true),
          _field(
            _headers,
            'Заголовки запроса',
            hint: 'Authorization: Bearer {key}',
            help: 'По одному на строку: Имя: значение.',
            mono: true,
            lines: 3,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : _redetect,
              icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
              label: const Text('Определить поля заново'),
            ),
          ),
        ],
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

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
