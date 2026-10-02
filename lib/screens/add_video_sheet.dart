import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../main.dart';
import '../models.dart';
import '../services/link_parser.dart';
import '../services/search.dart';
import '../theme.dart';
import 'sources_screen.dart';

/// Pick what to watch: paste a link or search through one of the sources.
/// Pops with the chosen [VideoSource].
class AddVideoSheet extends StatefulWidget {
  const AddVideoSheet({super.key});

  @override
  State<AddVideoSheet> createState() => _AddVideoSheetState();
}

class _AddVideoSheetState extends State<AddVideoSheet> {
  final _link = TextEditingController();
  final _query = TextEditingController();

  String? _sourceId;
  bool _searching = false;
  String? _error;
  List<SearchResult>? _results;

  SearchService get _search => ServicesScope.of(context).search;

  @override
  void dispose() {
    _link.dispose();
    _query.dispose();
    super.dispose();
  }

  SearchSource _current(List<SearchSource> sources) => sources.firstWhere(
    (s) => s.id == _sourceId,
    orElse: () =>
        sources.firstWhere((s) => s.usableHere, orElse: () => sources.first),
  );

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
    final source = _current(_search.sources);
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await _search.search(source, query);
      if (!mounted) return;
      setState(() => _results = results);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _results = null;
      });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _pick(SearchResult result) {
    final source = parseVideoLink(result.link, title: result.title);
    if (source == null) {
      setState(() => _error = 'Источник вернул не ссылку: ${result.link}');
      return;
    }
    Navigator.of(context).pop(source);
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
              final current = _current(sources);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text('Что смотрим?', style: text.titleLarge),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _link,
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            decoration: InputDecoration(
                              hintText: 'Ссылка на видео',
                              suffixIcon: IconButton(
                                tooltip: 'Вставить',
                                icon: const Icon(Icons.content_paste_rounded),
                                onPressed: _paste,
                              ),
                            ),
                            onChanged: (_) => setState(() => _error = null),
                            onSubmitted: (_) => _openLink(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: detected == null ? null : _openLink,
                          child: const Text('Открыть'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Text(
                      detected == null
                          ? 'YouTube, VK Видео, Rutube или прямая ссылка на '
                                'файл (.mp4, .m3u8).'
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
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Divider(),
                  ),
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        for (final s in sources)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(s.name),
                              selected: s.id == current.id,
                              showCheckmark: false,
                              onSelected: (_) => setState(() {
                                _sourceId = s.id;
                                _results = null;
                                _error = null;
                              }),
                            ),
                          ),
                        ActionChip(
                          avatar: const Icon(Icons.tune_rounded, size: 16),
                          label: const Text('Источники'),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const SourcesScreen(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: TextField(
                      controller: _query,
                      enabled: current.ready,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: current.ready
                            ? 'Поиск в «${current.name}»'
                            : 'Для «${current.name}» нужен ключ API',
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
                  if (!current.ready)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.key_rounded, size: 18),
                          label: const Text('Указать ключ'),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => SourceEditScreen(source: current),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (current.ready && !current.usableHere && _error == null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: Text(
                        '«${current.name}» не отвечает на запросы из браузера. '
                        'Поиск по нему работает в приложении для Android, а '
                        'ссылку оттуда можно вставить выше.',
                        style: text.bodySmall?.copyWith(color: kTextDim),
                      ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFFFB74D),
                          height: 1.35,
                        ),
                      ),
                    ),
                  Expanded(child: _buildResults()),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    final results = _results;
    if (results == null) return const SizedBox.shrink();
    if (results.isEmpty) {
      return const Center(
        child: Text('Ничего не нашлось', style: TextStyle(color: kTextDim)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      itemCount: results.length,
      itemBuilder: (context, i) {
        final r = results[i];
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
                  ? const ColoredBox(
                      color: kSurfaceHigh,
                      child: Icon(Icons.movie_outlined, color: kTextDim),
                    )
                  : Image.network(
                      r.poster!,
                      fit: BoxFit.cover,
                      // Posters from servers without CORS still show on web.
                      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: kSurfaceHigh,
                        child: Icon(Icons.movie_outlined, color: kTextDim),
                      ),
                    ),
            ),
          ),
          title: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: r.subtitle == null
              ? null
              : Text(
                  r.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kTextDim),
                ),
          onTap: () => _pick(r),
        );
      },
    );
  }
}
