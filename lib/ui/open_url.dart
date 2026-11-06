import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] outside the app.
Future<void> openUrl(String url) async {
  final bool launched = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.platformDefault,
  ).catchError((_) => false);
  if (!launched) {
    debugPrint('Could not launch $url');
  }
}
