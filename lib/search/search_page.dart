import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/board/favorite_model.dart';
import 'package:flutter_chan/board/post_time.dart';
import 'package:flutter_chan/board/thread_views.dart';
import 'package:flutter_chan/chan/api.dart';
import 'package:flutter_chan/chan/catalog.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/chan/urls.dart' as urls;
import 'package:flutter_chan/media/post_thumbnail.dart';
import 'package:flutter_chan/search/find_4chan_browser.dart';
import 'package:flutter_chan/search/global_search.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_header.dart';
import 'package:flutter_chan/ui/dash_scaffold.dart';
import 'package:flutter_chan/ui/dash_widgets.dart';
import 'package:flutter_chan/ui/open.dart';
import 'package:flutter_chan/ui/open_url.dart';
import 'package:flutter_chan/ui/pills.dart';
import 'package:flutter_chan/ui/reload.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

enum _SearchScope { favorites, everywhere }

/// Searches thread openers on the favorite boards (live, through the
/// catalog API) or every post on 4chan (through find.4chan.org).
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _search = TextEditingController();
  late _SearchScope _scope;

  // Favorites: catalogs load once, then every keystroke filters them.
  List<Post>? _catalogs;
  bool _catalogsLoading = false;
  bool _catalogsFailed = false;

  // Everywhere: one request per submitted query, then one per page.
  String _globalQuery = '';
  final List<Post> _globalResults = <Post>[];
  int? _globalTotal;
  int? _nextOffset;
  bool _globalLoading = false;
  bool _globalFailed = false;
  int _globalRequest = 0;
  Find4chanBrowser? _browser;

  @override
  void initState() {
    super.initState();
    _scope =
        Provider.of<FavoriteProvider>(context, listen: false).boards.isEmpty
        ? _SearchScope.everywhere
        : _SearchScope.favorites;
    if (_scope == _SearchScope.favorites) {
      _loadCatalogs();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _browser?.dispose();
    super.dispose();
  }

  String get _query => _search.text.trim();

  Future<void> _loadCatalogs() async {
    setState(() {
      _catalogsLoading = true;
      _catalogsFailed = false;
    });

    final List<Post>? threads = await fetchCatalogs(
      List.of(Provider.of<FavoriteProvider>(context, listen: false).boards),
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _catalogs = threads;
      _catalogsLoading = false;
      _catalogsFailed = threads == null;
    });
  }

  Future<void> _searchEverywhere({bool more = false}) async {
    final String query = more ? _globalQuery : _query;
    if (query.isEmpty || (more && _nextOffset == null)) {
      return;
    }

    final int request = ++_globalRequest;
    setState(() {
      _browser ??= Find4chanBrowser();
      _globalQuery = query;
      _globalLoading = true;
      _globalFailed = false;
      if (!more) {
        _globalResults.clear();
        _globalTotal = null;
        _nextOffset = null;
      }
    });

    try {
      final GlobalSearchPage page = await _browser!.search(
        query,
        offset: more ? _nextOffset! : 0,
      );
      if (!mounted || request != _globalRequest) {
        return;
      }
      setState(() {
        _globalResults.addAll(page.posts);
        _globalTotal = page.totalHits ?? _globalTotal;
        _nextOffset = page.nextOffset;
        _globalLoading = false;
      });
    } catch (_) {
      if (!mounted || request != _globalRequest) {
        return;
      }
      setState(() {
        _globalLoading = false;
        _globalFailed = true;
      });
    }
  }

  void _setScope(_SearchScope scope) {
    setState(() => _scope = scope);
    if (scope == _SearchScope.favorites &&
        _catalogs == null &&
        !_catalogsLoading) {
      _loadCatalogs();
    }
    if (scope == _SearchScope.everywhere &&
        _query.isNotEmpty &&
        _query != _globalQuery) {
      _searchEverywhere();
    }
  }

  Future<void> _refresh() async {
    if (_scope == _SearchScope.favorites) {
      await _loadCatalogs();
    } else {
      await _searchEverywhere();
    }
  }

  void _openInBrowser() {
    openUrl(urls.find(query: _query).toString());
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;

    final DashScaffold page = DashScaffold(
      title: 'Search',
      onRefresh: _refresh,
      actions: [
        DashIconButton(
          label: 'Open in browser',
          icon: const Icon(CupertinoIcons.globe),
          onPressed: _openInBrowser,
        ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: CupertinoSlidingSegmentedControl<_SearchScope>(
              groupValue: _scope,
              onValueChanged: (scope) => _setScope(scope!),
              children: const {
                _SearchScope.favorites: Text('Favorite boards'),
                _SearchScope.everywhere: Text('All of 4chan'),
              },
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: CupertinoSearchTextField(
              controller: _search,
              autofocus: true,
              placeholder: _scope == _SearchScope.favorites
                  ? 'Search threads'
                  : 'Search all posts',
              backgroundColor: DashColors.card(context),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (_scope == _SearchScope.everywhere) {
                  _searchEverywhere();
                }
              },
            ),
          ),
        ),
        ...(_scope == _SearchScope.favorites
            ? _favoriteSlivers(isDark)
            : _everywhereSlivers(isDark)),
      ],
    );

    final Find4chanBrowser? browser = _browser;
    if (browser == null) {
      return page;
    }
    return Stack(
      children: [
        page,
        Positioned.fill(
          child: ListenableBuilder(
            listenable: browser,
            builder: (context, webView) =>
                _browserLayer(isDark, browser, webView!),
            child: WebViewWidget(controller: browser.controller),
          ),
        ),
      ],
    );
  }

  /// The find.4chan.org web view: a hidden pixel while it loads results, a
  /// card over the page while the user completes a Cloudflare check. The
  /// tree keeps the same shape either way, so the web view isn't recreated.
  Widget _browserLayer(bool isDark, Find4chanBrowser browser, Widget webView) {
    final bool verifying = browser.verifying;
    final EdgeInsets safe = MediaQuery.paddingOf(context);

    return Stack(
      children: [
        IgnorePointer(
          ignoring: !verifying,
          child: ColoredBox(
            color: verifying ? Colors.black54 : Colors.transparent,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: verifying ? 12 : 0,
          top: verifying ? safe.top + 60 : 0,
          right: verifying ? 12 : null,
          bottom: verifying ? safe.bottom + 24 : null,
          width: verifying ? null : 1,
          height: verifying ? null : 1,
          child: IgnorePointer(
            ignoring: !verifying,
            // Not 0: a fully transparent web view isn't painted at all, and
            // iOS then stops running its scripts.
            child: Opacity(
              opacity: verifying ? 1 : 0.01,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: ColoredBox(
                  color: DashColors.card(context),
                  child: Column(
                    children: [
                      Visibility(
                        visible: verifying,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Complete the check to search 4chan',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: DashColors.text(context),
                                  ),
                                ),
                              ),
                              CupertinoButton(
                                onPressed: browser.cancel,
                                child: const Text('Cancel'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(child: webView),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _favoriteSlivers(bool isDark) {
    final settings = Provider.of<SettingsProvider>(context);

    if (_catalogsLoading && _catalogs == null) {
      return const [
        SliverFillRemaining(child: Center(child: CupertinoActivityIndicator())),
      ];
    }
    if (_catalogsFailed) {
      return [
        SliverFillRemaining(child: ReloadWidget(onReload: _loadCatalogs)),
      ];
    }
    if (_query.isEmpty) {
      return [
        _message(
          isDark,
          'Search thread titles and openers on your '
          '${Provider.of<FavoriteProvider>(context).boards.length} '
          'favorite boards.',
        ),
      ];
    }

    final List<Post> matches = filterThreads(
      _catalogs ?? const <Post>[],
      _query,
    ).where((post) => !settings.isThreadHidden(post)).toList();
    matches.removeWhere((post) => settings.hidesBoard(post.board));

    if (matches.isEmpty) {
      return [_message(isDark, 'No threads match')];
    }
    return [ThreadsView(threads: matches, grid: false, showBoard: true)];
  }

  List<Widget> _everywhereSlivers(bool isDark) {
    final SettingsProvider settings = Provider.of<SettingsProvider>(context);
    // 4chan searches every board: those of hidden NSFW boards are left out.
    final List<Post> results = [
      for (final Post post in _globalResults)
        if (!settings.hidesBoard(post.board)) post,
    ];
    if (_globalLoading && _globalResults.isEmpty) {
      return const [
        SliverFillRemaining(child: Center(child: CupertinoActivityIndicator())),
      ];
    }
    if (_globalFailed && _globalResults.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: ReloadWidget(
            onReload: _searchEverywhere,
            icon: CupertinoIcons.search,
            title: "Couldn't search 4chan",
            message: "find.4chan.org didn't send any results back.",
            secondaryLabel: 'Open in browser',
            onSecondary: _openInBrowser,
          ),
        ),
      ];
    }
    if (_globalQuery.isEmpty) {
      return [
        _message(
          isDark,
          'Search every post on 4chan with find.4chan.org. '
          'Press search on the keyboard to start.',
        ),
      ];
    }
    if (results.isEmpty && _nextOffset == null) {
      return [_message(isDark, 'No posts match')];
    }

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(
            _globalTotal == null || results.length < _globalResults.length
                ? '${results.length} posts'
                : '$_globalTotal posts',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: DashColors.muted(context),
            ),
          ),
        ),
      ),
      SliverList.builder(
        itemCount: results.length,
        itemBuilder: (context, index) {
          final Post post = results[index];
          return _SearchResultTile(
            key: ValueKey('${post.board}-${post.no}'),
            post: post,
          );
        },
      ),
      if (_nextOffset != null || _globalFailed)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Center(
              child: _globalLoading
                  ? const CupertinoActivityIndicator()
                  : CupertinoButton(
                      onPressed: () => _searchEverywhere(more: true),
                      child: Text(_globalFailed ? 'Try again' : 'Load more'),
                    ),
            ),
          ),
        ),
    ];
  }

  Widget _message(bool isDark, String text) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: DashColors.muted(context)),
        ),
      ),
    );
  }
}

/// One post from find.4chan.org: an opening post or a reply, which opens
/// its thread scrolled to it.
class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({super.key, required this.post});

  final Post post;

  bool get _isReply => (post.resto ?? 0) != 0;

  void _open(BuildContext context) {
    final String board = post.board;
    final int thread = _isReply ? post.resto! : post.no;

    openThread(
      context,
      // Bookmarks and history describe the thread, so a reply only passes on
      // the thread number.
      _isReply ? Post(no: thread, board: board) : post,
      // Openers too, so the thread starts at the top, not the last read.
      atPost: post.no,
    );
  }

  @override
  Widget build(BuildContext context) {
    final String board = post.board;
    final String excerpt = post.commentText;
    final String? subject = post.subject;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: DashCard(
        onTap: () => _open(context),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      BoardPill(board: board),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          [
                            if (_isReply)
                              'Reply in No.${post.resto}'
                            else
                              'Thread No.${post.no}',
                            if (post.time != null) formatPostedAt(post),
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 11,
                            color: DashColors.muted(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (subject != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      subject,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: DashColors.text(context),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (excerpt.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      excerpt,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: DashColors.muted(context),
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (post.tim != null) ...[
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: PostThumbnail(post: post),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
