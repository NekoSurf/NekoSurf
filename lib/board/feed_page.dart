import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/board/favorite_model.dart';
import 'package:flutter_chan/board/thread_order.dart';
import 'package:flutter_chan/board/thread_views.dart';
import 'package:flutter_chan/chan/api.dart';
import 'package:flutter_chan/chan/catalog.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_scaffold.dart';
import 'package:flutter_chan/ui/dash_widgets.dart';
import 'package:flutter_chan/ui/reload.dart';
import 'package:provider/provider.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> with ThreadOrder<FeedPage> {
  List<Post> _threads = [];
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadFeed();
  }

  @override
  void onOrderChanged() {
    _threads = sortThreads(_threads, sort, sortDirection);
  }

  Future<void> _loadFeed() async {
    final List<String> boards = Provider.of<FavoriteProvider>(
      context,
      listen: false,
    ).boards;

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    final List<Post>? threads = await fetchCatalogs(boards);

    if (!mounted) {
      return;
    }

    setState(() {
      _threads = sortThreads(threads ?? <Post>[], sort, sortDirection);
      _isLoading = false;
      _hasError = threads == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final int boardCount = Provider.of<FavoriteProvider>(context).boards.length;
    final List<Post> visibleThreads = _threads
        .where(settings.isThreadListed)
        .toList();

    return DashScaffold(
      title: 'Feed',
      onRefresh: _loadFeed,
      actions: [const ViewModeButton(), sortMenu(settings)],
      slivers: [
        SliverToBoxAdapter(
          child: DashPageHeader(
            color: DashColors.feed,
            badge: const Icon(
              CupertinoIcons.rectangle_stack_fill,
              color: DashColors.feed,
            ),
            title: _isLoading && _threads.isEmpty
                ? 'Loading...'
                : '${visibleThreads.length} threads',
            subtitle: 'From $boardCount favorite boards',
          ),
        ),
        if (_isLoading && _threads.isEmpty)
          const SliverFillRemaining(
            child: Center(child: CupertinoActivityIndicator()),
          )
        else if (_hasError)
          SliverFillRemaining(child: ReloadWidget(onReload: _loadFeed))
        else
          ThreadsView(
            threads: visibleThreads,
            grid: settings.boardViewMode.value == ViewMode.grid,
            showBoard: true,
          ),
      ],
    );
  }
}
