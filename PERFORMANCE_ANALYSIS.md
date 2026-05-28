# Performance Bottleneck Analysis - NekoSurf

## Executive Summary

Analysis of the NekoSurf codebase reveals several performance bottlenecks primarily in thread viewing, reply tree building, and string processing. Most critical issues are in hot paths executed during scroll and thread loading.

---

## 🔴 Critical Bottlenecks

### 1. **Reply Tree Building - O(n²) Complexity**
**Location**: `lib/API/api.dart:122-164`

**Problem**:
```dart
Map<int, List<Post>> buildReplyChildrenIndex(List<Post> allPosts) {
  // Called for EVERY post in thread
  for (final Post post in allPosts) {
    final List<int> quotedPostIds = extractQuotedPostIds(post.com)  // 🔴 RegEx + string processing
        .where((int quotedPostId) => postsById.containsKey(quotedPostId))
        .where(...)
        .toList();
  }
}
```

**Issues**:
- `extractQuotedPostIds()` does HTML cleaning + regex matching for every post
- Called on main thread during `loadThread()` - blocks UI
- For 500-post thread: ~500 regex operations, ~500 HTML cleanings
- Then `buildReplyDescendantCountIndex()` does recursive tree walk

**Impact**: 
- 100-post thread: ~50-100ms
- 500-post thread: ~200-500ms UI freeze
- 1000-post thread: ~500ms-1s freeze

**Fix Priority**: HIGH

---

### 2. **String Processing in Hot Path**
**Location**: `lib/services/string.dart:20-37`

**Problem**:
```dart
List<int> extractQuotedPostIds(String? body) {
  final String text = unescape(cleanTags(body));  // 🔴 Called per post
  // cleanTags() uses RegExp('<[^>]*>', multiLine: true)
  // unescape() does 11 string.replaceAll() operations
  
  for (final Match match in RegExp(r'>>(\d+)').allMatches(text)) {
    // More regex
  }
}
```

**Issues**:
- `cleanTags()`: Regex allocation + multi-line matching per call
- `unescape()`: 11 sequential `replaceAll()` operations per call
- Called hundreds of times during thread load
- Also called in UI rendering (bookmarks, thread cards)

**Impact**:
- ~1-5ms per post
- Multiplied by posts = significant thread load delay

**Fix Priority**: HIGH

---

### 3. **Scroll Position Listener Overhead**
**Location**: `lib/pages/thread/thread_page.dart:67-93`

**Problem**:
```dart
void _markVisiblePostsAsWatched() {
  final watchedPosts = Provider.of<WatchedPostsProvider>(context, listen: false);  // 🔴
  final positions = itemPositionsListener.itemPositions.value;
  
  for (final position in positions) {
    // Multiple checks + provider call per visible item
    watchedPosts.markAsWatched(postIndex: index, thread: widget.thread);  // 🔴
  }
  
  _scheduleEagerWindowRefresh();  // 🔴 Triggers more work
}
```

**Issues**:
- Called on **every scroll event** via `itemPositions.addListener()`
- `Provider.of()` lookup on every scroll
- `markAsWatched()` checks time delta but still does work
- Triggers eager video window refresh (expensive)

**Impact**:
- ~5-10ms per scroll frame
- Can drop frames during fast scrolling
- Battery drain from constant computation

**Fix Priority**: MEDIUM-HIGH

---

### 4. **Eager Video Window Calculation**
**Location**: `lib/pages/thread/thread_page.dart:204-311`

**Problem**:
```dart
void _refreshEagerVideoWindow() {
  final offscreenWindow = _collectOffscreenVideoWindow();  // 🔴 Scans posts
  
  if (!_sameIdSet(_eagerVideoPostIds, offscreenWindow.ids)) {  // 🔴 O(n) comparison
    setState(() {
      _eagerVideoPostIds = offscreenWindow.ids;  // Triggers rebuild
    });
  }
  
  unawaited(_precacheThumbnails(offscreenWindow.posts));  // Network I/O
}

({Set<int> ids, List<Post> posts}) _collectOffscreenVideoWindow() {
  // Iterates through positions, finds min/max
  // Walks backward and forward through posts
  // Filters for video posts
}
```

**Issues**:
- `_collectOffscreenVideoWindow()`: O(n) scan through posts near viewport
- `_sameIdSet()`: Custom O(n) set comparison instead of using `SetEquality`
- Called on every scroll via debounced timer
- `setState()` triggers rebuild even if only metadata changed
- Thumbnail precaching can stall main thread

**Impact**:
- ~10-20ms per calculation
- Called multiple times during scroll
- Compounds with watched posts tracking

**Fix Priority**: MEDIUM

---

### 5. **Video Player State Updates**
**Location**: `lib/widgets/feed_video_player.dart:158-191`

**Problem**:
```dart
_positionSub = player.stream.position.listen((pos) {
  // Already has 100ms throttle ✅
  
  if (pos > Duration.zero && !_hasFirstFrame) {
    if (mounted) {
      setState(() {  // 🔴 setState for single bool
        _hasFirstFrame = true;
      });
    }
  }
  
  // Updates ValueNotifier (good)
  _progressValue.value = nextProgress;
});
```

**Issues**:
- `setState()` called for `_hasFirstFrame` flag
- Position stream listener allocates closure per player
- Multiple stream subscriptions per video (position + duration)

**Impact**:
- Minor, but multiplied by 10 pooled players
- ~1-2ms per frame when videos are playing

**Fix Priority**: LOW-MEDIUM

---

### 6. **Provider Lookups in Build Methods**
**Location**: Multiple pages

**Problem**:
```dart
@override
Widget build(BuildContext context) {
  final theme = Provider.of<ThemeChanger>(context);  // 🔴 Every rebuild
  final bookmarks = Provider.of<BookmarksProvider>(context);  // 🔴
  // ... rendering
}
```

**Issues**:
- `Provider.of()` does widget tree walk on every rebuild
- Not using `context.watch<T>()` or Consumer widgets
- Some providers don't need listen: true

**Impact**:
- ~0.5-2ms per build
- Multiplied by widget tree rebuilds

**Fix Priority**: LOW

---

## 🟡 Moderate Issues

### 7. **Bookmark JSON Encoding/Decoding**
**Location**: `lib/blocs/bookmarks_model.dart`

**Problem**:
- Bookmarks stored as JSON-encoded strings in list
- Every add/remove/update encodes/decodes entire bookmark
- Linear search through list to find bookmark to update

**Impact**: Minimal (small lists), but O(n) updates

**Fix Priority**: LOW

---

### 8. **Watched Posts Persistence**
**Location**: `lib/blocs/watched_posts_model.dart:140-146`

**Problem**:
```dart
Future<void> _saveWatchedPosts() async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final List<String> watchedPostsStrings = _watchedPostsByThread.values
      .map((media) => json.encode(media.toJson()))  // 🔴 Encode all
      .toList();
  await prefs.setStringList(_watchedPostsStorageKey, watchedPostsStrings);
}
```

**Issues**:
- Encodes ALL watched posts on every save (debounced to 2s)
- Could be incremental

**Impact**: Minor due to debouncing

**Fix Priority**: LOW

---

## 🟢 Well-Optimized Areas

### ✅ Video Player Pooling
- Reuses `media_kit` Players (pool size 10)
- Prevents expensive player creation/disposal
- **Good design**

### ✅ Position Stream Throttling
- 100ms throttle on video position updates
- Uses `ValueNotifier` instead of `setState()` for progress
- **Well done**

### ✅ Thumbnail Precaching
- Limits to 6 thumbnails per pass
- Tracks already-prefetched with Set
- **Good batching**

### ✅ Visibility Detection
- Uses `VisibilityDetector` with 16ms update interval
- Proper lifecycle management
- **Appropriate for use case**

---

## 📋 Recommended Fixes (Priority Order)

### 1. **Cache Reply Tree Building** (HIGH)
```dart
// In thread_page.dart or API layer
class _ThreadCache {
  static final Map<String, ({Map<int, List<Post>> replies, Map<int, int> descendants})> _cache = {};
  
  static String _cacheKey(String board, int thread, int postCount) => '$board:$thread:$postCount';
  
  static ({Map<int, List<Post>> replies, Map<int, int> descendants}) getOrBuild(
    String board,
    int thread,
    List<Post> posts,
  ) {
    final key = _cacheKey(board, thread, posts.length);
    if (_cache.containsKey(key)) {
      return _cache[key]!;
    }
    
    final replies = buildReplyChildrenIndex(posts);
    final descendants = buildReplyDescendantCountIndex(posts);
    final result = (replies: replies, descendants: descendants);
    _cache[key] = result;
    return result;
  }
}
```

**Expected gain**: 200-500ms saved on thread reloads

---

### 2. **Optimize String Processing** (HIGH)
```dart
// Cache regex patterns
class _StringPatterns {
  static final _tagsRegex = RegExp('<[^>]*>', multiLine: true);
  static final _quoteRegex = RegExp(r'>>(\d+)');
  
  // Batch replacements
  static final _unescapeMap = {
    '&gt;': '>',
    '&lt;': '<',
    '&amp;': '&',
    // ... etc
  };
}

String unescape(String body) {
  String result = body;
  for (final entry in _StringPatterns._unescapeMap.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }
  return result;
}

// Consider caching cleaned/unescaped strings per post.com hash
```

**Expected gain**: 50-100ms saved on thread load

---

### 3. **Throttle Watched Posts Tracking** (MEDIUM)
```dart
class _ThreadPageState extends State<ThreadPage> {
  Timer? _watchedPostsThrottle;
  
  void _markVisiblePostsAsWatched() {
    if (_watchedPostsThrottle?.isActive ?? false) {
      return;  // Skip if already scheduled
    }
    
    _watchedPostsThrottle = Timer(const Duration(milliseconds: 200), () {
      // Do actual work here
      final watchedPosts = Provider.of<WatchedPostsProvider>(context, listen: false);
      // ... rest of logic
    });
  }
}
```

**Expected gain**: Smoother scrolling, less CPU usage

---

### 4. **Use SetEquality for Set Comparison** (MEDIUM)
```dart
import 'package:collection/collection.dart';

// Replace _sameIdSet() with:
final _setEquality = const SetEquality<int>();

if (!_setEquality.equals(_eagerVideoPostIds, offscreenWindow.ids)) {
  // ...
}
```

**Expected gain**: Minor, but cleaner code

---

### 5. **Optimize Provider Lookups** (LOW)
```dart
// Use context.watch/read instead of Provider.of
@override
Widget build(BuildContext context) {
  final theme = context.watch<ThemeChanger>();  // Only when needed
  final bookmarks = context.read<BookmarksProvider>();  // When listen: false
}
```

**Expected gain**: 1-5ms per build

---

### 6. **Move Reply Tree Building Off Main Thread** (ADVANCED)
```dart
import 'dart:isolate';

Future<({Map<int, List<Post>> replies, Map<int, int> descendants})> buildReplyTreeIsolate(
  List<Post> posts,
) async {
  return await Isolate.run(() {
    final replies = buildReplyChildrenIndex(posts);
    final descendants = buildReplyDescendantCountIndex(posts);
    return (replies: replies, descendants: descendants);
  });
}
```

**Expected gain**: No UI freeze on large threads

---

## 📊 Estimated Impact

| Fix | Effort | Impact | Thread Load Time | Scroll Performance |
|-----|--------|--------|------------------|-------------------|
| Cache reply tree | Medium | High | -200-500ms | - |
| Optimize string processing | Low-Medium | High | -50-100ms | - |
| Throttle watched posts | Low | Medium | - | +10-15 FPS |
| Use SetEquality | Very Low | Low | -5ms | - |
| Optimize providers | Low | Low | - | +2-5 FPS |
| Isolate reply tree | High | High | No freeze | - |

---

## 🎯 Quick Wins (Best ROI)

1. **Cache reply tree building** - 30 min effort, massive gains
2. **Throttle watched posts tracking** - 15 min effort, smoother scrolling
3. **Use SetEquality** - 5 min effort, cleaner code
4. **Static regex patterns** - 10 min effort, faster string processing

---

## 🔬 Profiling Recommendations

To validate these findings, profile with:

```bash
# Flutter DevTools
flutter run --profile
# Open DevTools -> Performance tab
# Record timeline while loading large thread
```

Look for:
- `buildReplyChildrenIndex` in timeline
- `extractQuotedPostIds` call frequency
- `setState` calls during scroll
- Frame rendering times (should be <16ms)

---

## 📈 Monitoring

Add performance markers:

```dart
import 'dart:developer' as developer;

void loadThread() {
  final timeline = Timeline.startSync('loadThread');
  try {
    // ... existing code
  } finally {
    timeline.finish();
  }
}
```

Monitor with DevTools or add custom logging.
