/// Every 4chan address the app uses, so none are spelled out elsewhere.
///
/// Import with a prefix (`as urls`): names like [thumbnail] would clash
/// with fields of the same name.
library;

const String _api = 'https://a.4cdn.org';
const String _files = 'https://i.4cdn.org';
const String _site = 'https://boards.4chan.org';

/// Every board, with its title and limits.
final Uri boards = Uri.parse('$_api/boards.json');

/// [board]'s live threads, page by page.
Uri catalog(String board) => Uri.parse('$_api/$board/catalog.json');

/// Numbers of the threads in [board]'s archive.
Uri archive(String board) => Uri.parse('$_api/$board/archive.json');

/// Every post of [thread].
Uri thread(String board, Object thread) =>
    Uri.parse('$_api/$board/thread/$thread.json');

/// A file on [board], by its stored name: "1700000000000.webm", or a
/// thumbnail's "1700000000000s.jpg".
String boardFile(String board, String name) => '$_files/$board/$name';

/// An upload, by its time [tim] and extension [ext] (".webm").
String file(String board, int? tim, String? ext) =>
    boardFile(board, '$tim$ext');

/// The small JPEG 4chan makes of every upload, videos included.
String thumbnail(String board, int? tim) => boardFile(board, '${tim}s.jpg');

/// The thread on 4chan's website, to share or open in a browser.
String threadPage(String board, int thread) => '$_site/$board/thread/$thread';
