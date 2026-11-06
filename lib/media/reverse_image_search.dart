import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/ui/dash_menu.dart';
import 'package:flutter_chan/ui/open_url.dart';

/// Search engines that accept an image by URL. Videos are searched by their
/// thumbnail, since none of them take video links.
const List<({String name, String Function(String encodedUrl) url})>
_reverseSearchEngines = [
  (name: 'Google Lens', url: _googleLens),
  (name: 'Yandex', url: _yandex),
  (name: 'SauceNAO', url: _sauceNao),
  (name: 'Bing', url: _bing),
];

String _googleLens(String u) => 'https://lens.google.com/uploadbyurl?url=$u';
String _yandex(String u) =>
    'https://yandex.com/images/search?rpt=imageview&url=$u';
String _sauceNao(String u) => 'https://saucenao.com/search.php?url=$u';
String _bing(String u) =>
    'https://www.bing.com/images/search?view=detailv2&iss=sbi&q=imgurl:$u';

void showReverseImageSearchMenu(BuildContext anchor, String imageUrl) {
  final String encoded = Uri.encodeComponent(imageUrl);
  showDashMenu(
    anchor,
    title: 'Search image on…',
    entries: [
      for (final engine in _reverseSearchEngines)
        DashMenuEntry(
          title: engine.name,
          icon: CupertinoIcons.search,
          onPressed: () => openUrl(engine.url(encoded)),
        ),
    ],
  );
}
