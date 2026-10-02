import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../main.dart';
import '../models.dart';
import '../services/link_parser.dart';
import '../services/search.dart';
import '../theme.dart';
import 'sources_screen.dart';

/// Pick what to watch: paste a link, or search — one query goes to every
/// connected source and the answers come back as a single list.
/// Pops with the chosen [VideoSource].
class AddVideoSheet extends StatefulWidget {
  const AddVideoSheet({super.key});

  @override
  State<AddVideoSheet> createState() => _AddVideoSheetState();
}

class _AddVideoSheetState extends State<AddVideoSheet> {
  final _link = TextEditingController();
  final _query = TextEditingController();

  bool _searching = false;
  String? _error;
  CombinedResults? _found;

  SearchService get _search => ServicesScope.of(context).search;

  @override
  void dispose() {
    _link.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      setState(() => _link.text = text);
    }
  }

  void _openLink() {
    final source = parseVideoLink(_link.text);
    if (source == null) {
      setState(() => _error = 'Это не похоже на ссылку.');
      return;
    }
    Navigator.of(context).pop(source);
  }

  Future<void> _runSearch() async {
    final query = _query.text.trim();
    if (query.isEmpty || _searching) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _error = null;
    });
    final found = await _search.searchAll(query);
    if (!mounted) return;
    setState(() {
      _found = found;
      _searching = false;
    });
  }

  void _pick(SearchResult result) {
    final source = parseVideoLink(result.link, title: result.title);
    if (source == null) {
      setState(() => _error = 'Источник вернул не ссылку: ${result.link}');
      return;
    }
    Navigator.of(context).pop(source);
  }

  void _openSources() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SourcesScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final detected = parseVideoLink(_link.text);

    return PointerInterceptor(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.88,
          child: ListenableBuilder(
            listenable: _search,
            builder: (context, _) {
              final sources = _search.sources;
              final active = [
                for (final s in sources)
                  if (s.usableHere) s.name,
              ];
              final idle = [
                for (final s in sources)
                  if (!s.usableHere) s.name,
              ];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text('Что смотрим?', style: text.titleLarge),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TextField(
                      controller: _query,
                      enabled: active.isNotEmpty,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: active.isEmpty
                            ? 'Нет подключённых источников'
                            : 'Название фильма или видео',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searching
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      onSubmitted: (_) => _runSearch(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 8, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            [
                              if (active.isNotEmpty)
                                'Ищем в: ${active.join(', ')}',
                              if (idle.isNotEmpty)
                                'Не подключены: ${idle.join(', ')}',
                            ].join('\n'),
                            style: text.bodySmall?.copyWith(
                              color: kTextDim,
                              height: 1.4,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _openSources,
                          icon: const Icon(Icons.tune_rounded, size: 16),
                          label: const Text('Источники'),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFFFB74D),
                          height: 1.35,
                        ),
                      ),
                    ),
                  Expanded(
                    child: _found == null
                        ? _LinkEntry(
                            controller: _link,
                            detected: detected,
                            onChanged: () => setState(() => _error = null),
                            onPaste: _paste,
                            onOpen: _openLink,
                          )
                        : _Results(
                            found: _found!,
                            onPick: _pick,
                            onBack: () => setState(() => _found = null),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Shown until a search is made: the field for a direct link.
class _LinkEntry extends StatelessWidget {
  const _LinkEntry({
    required this.controller,
    required this.detected,
    required this.onChanged,
    required this.onPaste,
    required this.onOpen,
  });

  final TextEditingController controller;
  final VideoSource? detected;
  final VoidCallback onChanged;
  final VoidCallback onPaste;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final detected = this.detected;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'или по ссылке',
                  style: TextStyle(color: kTextDim, fontSize: 12),
                ),
              ),
              Expanded(child: Divider()),
            ],
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: 'Ссылка на видео',
                  suffixIcon: IconButton(
                    tooltip: 'Вставить',
                    icon: const Icon(Icons.content_paste_rounded),
                    onPressed: onPaste,
                  ),
                ),
                onChanged: (_) => onChanged(),
                onSubmitted: (_) => onOpen(),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: detected == null ? null : onOpen,
              child: const Text('Открыть'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          detected == null
              ? 'YouTube, VK Видео, Rutube или прямая ссылка на файл '
                    '(.mp4, .m3u8).'
              : detected.syncable
              ? '${detected.label} · будет идти у всех одновременно'
              : 'Обычная страница · откроется рядом с чатом, без '
                    'синхронизации',
          style: text.bodySmall?.copyWith(
            color: detected == null || detected.syncable
                ? kTextDim
                : const Color(0xFFFFB74D),
          ),
        ),
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.found,
    required this.onPick,
    required this.onBack,
  });

  final CombinedResults found;
  final ValueChanged<SearchResult> onPick;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final results = found.results;
    final failures = found.failures;
    // Say where each result came from only when there is a choice.
    final showSource = found.searched.length > 1;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
      itemCount: results.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 4, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        results.isEmpty
                            ? 'Ничего не нашлось'
                            : 'Найдено: ${results.length}',
                        style: const TextStyle(color: kTextDim, fontSize: 13),
                      ),
                    ),
                    TextButton(
                      onPressed: onBack,
                      child: const Text('Вставить ссылку'),
                    ),
                  ],
                ),
                for (final f in failures.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6, right: 8),
                    child: Text(
                      '${f.key}: ${f.value}',
                      style: const TextStyle(
                        color: Color(0xFFFFB74D),
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }
        final r = results[i - 1];
        final caption = [
          if (showSource) r.source,
          if (r.subtitle != null && r.subtitle!.isNotEmpty) r.subtitle!,
        ].join(' · ');
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 4,
          ),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 96,
              height: 54,
              child: r.poster == null
                  ? const _NoPoster()
                  : Image.network(
                      r.poster!,
                      fit: BoxFit.cover,
                      // Posters from servers without CORS still show on web.
                      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                      errorBuilder: (_, _, _) => const _NoPoster(),
                    ),
            ),
          ),
          title: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: caption.isEmpty
              ? null
              : Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kTextDim),
                ),
          onTap: () => onPick(r),
        );
      },
    );
  }
}

class _NoPoster extends StatelessWidget {
  const _NoPoster();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: kSurfaceHigh,
      child: Icon(Icons.movie_outlined, color: kTextDim),
    );
  }
}
