import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../main.dart';
import '../models.dart';
import '../services/link_parser.dart';
import '../services/search.dart';
import '../services/tmdb.dart';
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

  /// Films from the catalogue for the same query, and the one opened.
  List<Film> _films = const [];
  Film? _film;
  bool _trailerLoading = false;

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

  /// Videos from every source and, unless [films] is off, films from the
  /// catalogue, both for the text in the search field.
  Future<void> _runSearch({bool films = true}) async {
    final query = _query.text.trim();
    if (query.isEmpty || _searching) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _error = null;
      _film = null;
    });
    final tmdb = films ? _search.tmdb : null;
    String? catalogFailure;
    final videos = _search.searchAll(query);
    final catalog = tmdb == null
        ? Future.value(const <Film>[])
        : tmdb.search(query).catchError((Object e) {
            catalogFailure = e is SearchException
                ? e.message
                : 'Не удалось разобрать ответ.';
            return const <Film>[];
          });
    final found = await videos;
    final foundFilms = await catalog;
    if (!mounted) return;
    setState(() {
      _found = CombinedResults(
        results: found.results,
        searched: found.searched,
        failures: {...found.failures, 'TMDB': ?catalogFailure},
      );
      _films = foundFilms;
      _searching = false;
    });
  }

  Future<void> _watchTrailer(Film film) async {
    final tmdb = _search.tmdb;
    if (tmdb == null || _trailerLoading) return;
    setState(() {
      _trailerLoading = true;
      _error = null;
    });
    try {
      final key = await tmdb.trailerKey(film);
      if (!mounted) return;
      if (key == null) {
        setState(() => _error = 'У этого фильма в каталоге нет трейлера.');
        return;
      }
      Navigator.of(context).pop(
        parseVideoLink(
          'https://www.youtube.com/watch?v=$key',
          title: '${film.title} — трейлер',
        ),
      );
    } on SearchException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _trailerLoading = false);
    }
  }

  /// Looks for the film itself in the video sources.
  void _findFilm(Film film) {
    _query.text = film.title;
    _runSearch(films: false);
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
              final videoSources = _search.videoSources;
              final active = [
                for (final s in sources)
                  if (s.usableHere) s.name,
              ];
              final idle = [
                for (final s in sources)
                  if (!s.usableHere) s.name,
              ];
              final film = _film;
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
                    child: film != null
                        ? _FilmCard(
                            film: film,
                            trailerLoading: _trailerLoading,
                            canSearch: videoSources.isNotEmpty,
                            onTrailer: () => _watchTrailer(film),
                            onFind: () => _findFilm(film),
                            onBack: () => setState(() {
                              _film = null;
                              _error = null;
                            }),
                          )
                        : _found == null
                        ? _LinkEntry(
                            controller: _link,
                            detected: detected,
                            onChanged: () => setState(() => _error = null),
                            onPaste: _paste,
                            onOpen: _openLink,
                          )
                        : _Results(
                            found: _found!,
                            films: _films,
                            onPick: _pick,
                            onFilm: (f) => setState(() {
                              _film = f;
                              _error = null;
                            }),
                            onBack: () => setState(() {
                              _found = null;
                              _films = const [];
                            }),
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
    required this.films,
    required this.onPick,
    required this.onFilm,
    required this.onBack,
  });

  final CombinedResults found;
  final List<Film> films;
  final ValueChanged<SearchResult> onPick;
  final ValueChanged<Film> onFilm;
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
                        results.isEmpty && films.isEmpty
                            ? 'Ничего не нашлось'
                            : [
                                if (films.isNotEmpty)
                                  'Фильмов в каталоге: ${films.length}',
                                if (results.isNotEmpty)
                                  'Видео: ${results.length}',
                              ].join(' · '),
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
                if (films.isNotEmpty) ...[
                  SizedBox(
                    height: 222,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(top: 4, right: 8),
                      itemCount: films.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, i) =>
                          _FilmTile(film: films[i], onTap: onFilm),
                    ),
                  ),
                  if (results.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 10, bottom: 2),
                      child: Text(
                        'Видео',
                        style: TextStyle(color: kTextDim, fontSize: 13),
                      ),
                    ),
                ],
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

/// Poster of a catalogue film with its title underneath.
class _FilmTile extends StatelessWidget {
  const _FilmTile({required this.film, required this.onTap});

  final Film film;
  final ValueChanged<Film> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 112,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onTap(film),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Poster(url: film.poster, width: 112, height: 168),
            const SizedBox(height: 6),
            Text(
              film.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, height: 1.2),
            ),
            if (film.year != null)
              Text(
                film.year!,
                style: const TextStyle(color: kTextDim, fontSize: 11.5),
              ),
          ],
        ),
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.url, required this.width, required this.height});

  final String? url;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: width,
        height: height,
        child: url == null
            ? const _NoPoster()
            : Image.network(
                url!,
                fit: BoxFit.cover,
                webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                errorBuilder: (_, _, _) => const _NoPoster(),
              ),
      ),
    );
  }
}

/// What the catalogue knows about a film, and the two things to do with it:
/// watch the trailer together, or look for the film in the video sources.
class _FilmCard extends StatelessWidget {
  const _FilmCard({
    required this.film,
    required this.trailerLoading,
    required this.canSearch,
    required this.onTrailer,
    required this.onFind,
    required this.onBack,
  });

  final Film film;
  final bool trailerLoading;

  /// Whether any video source is connected to look the film up in.
  final bool canSearch;
  final VoidCallback onTrailer;
  final VoidCallback onFind;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final facts = [
      ?film.year,
      if (film.isSeries) 'сериал',
      if (film.rating != null) '★ ${film.rating!.toStringAsFixed(1)}',
    ].join(' · ');

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('К результатам'),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Poster(url: film.poster, width: 112, height: 168),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    film.title,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (facts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        facts,
                        style: const TextStyle(color: kTextDim, fontSize: 13),
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: trailerLoading ? null : onTrailer,
                    icon: trailerLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    label: const Text('Смотреть трейлер'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: canSearch ? onFind : null,
                    icon: const Icon(Icons.search_rounded, size: 18),
                    label: const Text('Найти в источниках'),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (!canSearch)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'Чтобы искать сам фильм, подключите источник видео на экране '
              '«Источники».',
              style: TextStyle(color: kTextDim, fontSize: 12.5, height: 1.35),
            ),
          ),
        if (film.overview.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              film.overview,
              style: const TextStyle(fontSize: 14, height: 1.45),
            ),
          ),
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Text(
            tmdbNotice,
            style: TextStyle(color: kTextDim, fontSize: 11.5, height: 1.35),
          ),
        ),
      ],
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
