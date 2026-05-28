# AGENTS.md - NekoSurf Development Guide

## Project Overview

**NekoSurf** is a privacy-friendly 4chan image board viewer built with Flutter for iOS and Android. The app provides a modern card-based interface for browsing boards, threads, and media with features like bookmarks, favorites, and offline media saving.

- **Language**: Dart (Flutter 3.38.1+, SDK >=3.9.2)
- **App Name**: `flutter_chan` (internal package name)
- **Version**: 0.11.4
- **Platforms**: iOS 14.0+, Android
- **Architecture**: Provider-based state management with stateful widgets

## Essential Commands

### Development

```bash
# Get dependencies
flutter pub get

# Run app (debug mode)
flutter run

# Analyze code
flutter analyze

# Run tests
flutter test

# Check Flutter setup
flutter doctor
```

### Building

```bash
# Build iOS (release, no codesign)
flutter build ios --release --no-codesign --verbose

# Build Android APKs (split per ABI)
flutter build apk --split-per-abi

# iOS requires CocoaPods
cd ios && pod install && cd ..
```

### Assets & Code Generation

```bash
# Generate launcher icons
flutter pub run flutter_launcher_icons:main

# Generate native splash screens
flutter pub run flutter_native_splash:create

# Remove splash screens
flutter pub run flutter_native_splash:remove
```

## Architecture & Code Organization

### Directory Structure

```
lib/
├── main.dart              # App entry point with MultiProvider setup
├── constants.dart         # AppColors and theme constants
├── API/                   # 4chan API client and video saving logic
│   ├── api.dart          # Thread/board fetching from 4cdn.org
│   ├── archived.dart     # Archived thread status checks
│   └── save_videos.dart  # Media download with ffmpeg & permissions
├── Models/               # Data models (Post, Board, Bookmark, etc.)
├── blocs/                # ChangeNotifier providers for state management
│   ├── bookmarks_model.dart
│   ├── favorite_model.dart
│   ├── saved_attachments_model.dart
│   ├── settings_model.dart
│   ├── theme.dart
│   └── watched_posts_model.dart
├── enums/                # Enums for Sort, ViewMode, ThreadStatus, etc.
├── pages/                # UI pages (boards, threads, settings, etc.)
│   ├── board/           # Board view (grid/list)
│   ├── boards/          # Board list & search
│   ├── thread/          # Thread viewer with video player pool
│   ├── bookmarks/       # Bookmarked threads
│   ├── savedAttachments/ # Saved media viewer
│   ├── settings/        # Settings UI
│   └── media/           # Shared media viewer
├── widgets/              # Reusable components
│   ├── feed_video_player.dart  # Video player with eager init
│   ├── feed_player_pool.dart   # Player pooling/reuse system
│   ├── floating_action_buttons.dart
│   ├── image_viewer.dart
│   └── reload.dart
├── services/             # Utility services
│   ├── cached_video.dart
│   ├── show_snackbar.dart
│   └── string.dart       # HTML cleaning utilities
└── utils/                # Additional helpers
```

### State Management

Uses **Provider** pattern with `ChangeNotifier`:

- **Global providers** initialized in `main.dart` via `MultiProvider`
- **6 core providers**:
  - `ThemeChanger` - Light/dark mode
  - `BookmarksProvider` - Thread bookmarks
  - `FavoriteProvider` - Favorite boards
  - `SettingsProvider` - User preferences (NSFW, sort, view mode)
  - `SavedAttachmentsProvider` - Saved media files
  - `WatchedPostsProvider` - Last-seen post tracking (lazy: false)

**Accessing providers**:
```dart
// Read once
final settings = Provider.of<SettingsProvider>(context, listen: false);

// React to changes
final theme = Provider.of<ThemeChanger>(context);
```

### Data Persistence

All persistence uses `SharedPreferences`:

- **Bookmarks**: Stored as JSON-encoded strings in `favoriteThreads` key
- **Favorites**: Board IDs in `favoriteBoards` key
- **Settings**: Individual keys (`allowNSFW`, `boardSort`, `boardSortDirection`, `boardViewMode`, `watchedPostsRetentionDays`, `autoScrollToLastSeen`)
- **Watched Posts**: JSON list in `watchedPosts` key with debounced saves (2s delay)

**Migration pattern**: Old keys are explicitly removed via `prefs.remove()` (e.g., `useCachingOnVideos`, `inlineMediaInThreadFeed`)

## Key Patterns & Conventions

### API Integration

**Base URLs**:
- API: `https://a.4cdn.org/{board}/catalog.json` or `/thread/{id}.json`
- Media: `https://i.4cdn.org/{board}/{tim}s.jpg` (thumbnails), `{tim}.{ext}` (full size)

**Fetching pattern** (see `lib/API/api.dart`):
```dart
Future<List<Post>> _fetchAllThreadsFromBoard;

void loadBoard() {
  setState(() {
    _fetchAllThreadsFromBoard = fetchAllThreadsFromBoard(sort, board)
      .then((value) => filteredBoards = value);
  });
}
```

### Video Player Pooling

**Critical non-obvious system**: Thread pages use `FeedPlayerPool` to reuse `media_kit` Player instances (pool size = 10).

- **Why**: Creating/destroying Players is expensive; reuse prevents stutter
- **Eager initialization**: Videos near viewport are initialized early (`eagerInitialize: true`)
- **Visibility-based**: Uses `VisibilityDetector` to play/pause on scroll
- **Warmup window**: `_offscreenVideoWarmupEachSide = 3` posts above/below viewport

**Implementation** (see `lib/pages/thread/thread_page.dart:140-220`):
```dart
FeedPlayerPool _playerPool = FeedPlayerPool(poolSize: 10);

// Mark posts for eager init based on visible positions
Set<int> _eagerVideoPostIds = computeEagerWindow();

// Pass pool to video widgets
FeedVideoPlayer(
  videoUrl: url,
  eagerInitialize: _eagerVideoPostIds.contains(post.no),
  pool: _playerPool,
)
```

### Watched Posts & Auto-Scroll

Non-obvious feature: Tracks which posts user has seen, auto-scrolls to last unseen post.

- **Tracking**: `WatchedPostsProvider.markAsWatched()` called from `ItemPositionsListener`
- **Auto-scroll**: On thread load, if `autoScrollToLastSeen` enabled, scrolls to first unwatched post index
- **Retention**: Cleaned up based on `watchedPostsRetentionDays` setting (default: 7 days)
- **Debounced saves**: Writes to disk 2s after last change to avoid thrashing

### Media Saving & Permissions

**Platform-specific permission handling** (see `lib/API/save_videos.dart`):

- **Android**:
  - SDK 30+: Requires `manageExternalStorage`
  - SDK 29: No permission needed (scoped storage)
  - SDK <29: Requires `storage` permission
  - Save path: `/Download/4Chan/`
  
- **iOS**:
  - Requires `photosAddOnly` permission
  - Shows custom `PermissionDenied` modal on denial
  - Uses `saver_gallery` package to save to Photos

**Video conversion**: Uses `ffmpeg_kit_flutter_new` to convert WebM to MP4 for iOS compatibility

### Linting & Code Style

**Strict analysis** enabled (`analysis_options.yaml`):
- `strict-casts: true`
- `strict-raw-types: true`
- Follows Flutter framework lint rules (see file for full list)
- Uses `lint` package (style: lint badge in README)
- Ignores: `todo`, `argument_type_not_assignable`, `unnecessary_import`

**Common patterns**:
- Prefer `const` constructors
- Prefer `final` locals
- Prefer single quotes for strings
- Always declare return types
- Use trailing commas for multi-line parameter lists

## Gotchas & Non-Obvious Behavior

### 1. Provider Initialization Order

`WatchedPostsProvider` has `lazy: false` in main.dart — it starts cleanup timer immediately. Other providers are lazy-loaded.

### 2. Thread Sorting Direction

**Important**: All sorts are done ascending first, then reversed if `direction == SortDirection.desc`. This is different from typical "sort with comparator" pattern.

```dart
// Sort ascending
ops.sort((a, b) => (a.replies ?? 0).compareTo(b.replies ?? 0));

// Then reverse for descending
if (direction == SortDirection.desc) {
  ops = ops.reversed.toList();
}
```

### 3. Bookmark vs Favorite

- **Bookmarks**: Individual threads (stored per-thread)
- **Favorites**: Entire boards (for quick access on home)

Both use similar `ChangeNotifier` pattern but store different data shapes.

### 4. Media Kit Initialization

`MediaKit.ensureInitialized()` MUST be called in `main()` before `runApp()`. Missing this causes video playback to fail silently.

### 5. Visibility Detector Update Interval

Set to 16ms (60fps) in main.dart:
```dart
VisibilityDetectorController.instance.updateInterval = 
  const Duration(milliseconds: 16);
```

Higher values reduce CPU but make scroll-based video play/pause laggy.

### 6. Platform-Specific UI

Uses `CupertinoApp` as root, not `MaterialApp`. Mix of Cupertino and Material widgets throughout. Settings page uses `CupertinoListSection` for iOS-native feel.

### 7. Image/Video URL Construction

Thumbnails: `https://i.4cdn.org/{board}/{tim}s.jpg`
Full media: `https://i.4cdn.org/{board}/{tim}.{ext}`

Note the `s` suffix on thumbnail URLs. Missing this breaks image loading.

### 8. Error Handling in main.dart

Custom `FlutterError.onError` handler logs to console but doesn't crash the app. This is for debugging only — don't rely on it for production error tracking.

## Testing Approach

Currently minimal test coverage (only `flutter_test` in dev_dependencies, no test files observed). When adding tests:

- Unit test providers (bookmark add/remove, settings persistence)
- Widget test critical UI flows (thread loading, video player initialization)
- Integration test permission flows (platform-specific)

## CI/CD

**GitHub Actions** (`.github/workflows/release_build.yml`):

- **Triggers**: On release published
- **iOS Job**: Builds IPA on macOS, uploads to release
  - Xcode 26.1, Flutter 3.38.1, Ruby 3.3
  - CocoaPods install required
  - No code signing (for TestFlight, manual signing elsewhere)
- **Android Job**: Builds split APKs (arm64-v8a, armeabi-v7a, x86_64)
  - Java 17, Flutter 3.38.1
  - Gradle heap: 2GB

## Common Tasks

### Adding a New Setting

1. Add field to `SettingsProvider` (lib/blocs/settings_model.dart)
2. Add getter/setter methods
3. Update `loadPreferences()` to read from SharedPreferences
4. Add UI control in settings page (lib/pages/settings/)
5. Use enum if multiple values (add to lib/enums/enums.dart)

### Adding a New Page

1. Create widget in `lib/pages/{category}/`
2. Extend `StatefulWidget` if needs state
3. Access providers via `Provider.of<T>(context)`
4. Use `CupertinoPageScaffold` for iOS-native look
5. Navigate via `Navigator.push()` or `CupertinoPageRoute`

### Working with the Video Player

1. Don't create `Player()` directly in feed contexts — use `FeedPlayerPool`
2. Set `eagerInitialize: true` for videos near viewport
3. Always dispose pool when leaving thread page
4. Use `allowHiddenWarmup: true` only for offscreen preloading
5. Monitor `_hasFirstFrame` before showing controls

### Handling Permissions

1. Import `lib/API/save_videos.dart` for helpers
2. Use `checkAndRequestPermissions()` before media operations
3. On iOS, catch permission denial and show `PermissionDenied` modal
4. On Android, check SDK version for correct permission type
5. Always use `await` — permission dialogs are async

## Dependencies Notes

### Core Dependencies

- `provider: ^6.1.5` - State management
- `shared_preferences: ^2.5.5` - Persistence
- `http: ^1.6.0` - API calls (simple GET requests)
- `dio: ^5.9.2` - File downloads (used in save_videos.dart)
- `flutter_html: ^3.0.0` - Render 4chan HTML comments

### Media

- `media_kit: ^1.2.6` - Video playback engine
- `media_kit_video: ^2.0.1` - Video UI widgets
- `media_kit_libs_video: ^1.0.7` - Native libraries
- `ffmpeg_kit_flutter_new: ^4.1.0` - Video conversion
- `flutter_cache_manager: ^3.4.1` - Image caching
- `visibility_detector: ^0.4.0+2` - Scroll-based visibility

### UI/UX

- `modal_bottom_sheet: ^3.0.0` - Cupertino modals
- `scrollable_positioned_list: ^0.3.8` - Jump to index in thread
- `flutter_slidable: ^4.0.3` - Swipe actions on bookmarks

### Platform Integration

- `permission_handler: ^12.0.1` - Runtime permissions
- `path_provider: ^2.1.5` - App directories
- `saver_gallery: ^4.0.0` - Save to Photos/Gallery
- `share_plus: ^13.1.0` - Share media
- `package_info_plus: ^10.1.0` - App version info
- `device_info_plus: ^13.1.0` - SDK version checks

## Debugging Tips

1. **Video not playing**: Check MediaKit initialization, pool lease acquisition, visibility state
2. **Settings not persisting**: Ensure `notifyListeners()` called after `prefs.setX()`
3. **Bookmarks not loading**: Check JSON encoding/decoding in BookmarksProvider
4. **Permission denied**: Check platform-specific SDK version logic
5. **Images not loading**: Verify URL construction (tim + 's.jpg' for thumbnails)
6. **Auto-scroll not working**: Check `autoScrollToLastSeen` setting, watched posts retention

## Resources

- 4chan API docs: https://github.com/4chan/4chan-API
- Flutter docs: https://docs.flutter.dev/
- media_kit: https://github.com/media-kit/media-kit
- TestFlight: https://testflight.apple.com/join/ky5bRwMY
