import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

Future<Uri?> checkForAppUpdate() async {
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    final response = await http
        .get(
          Uri.parse(
            'https://api.github.com/repos/NekoSurf/NekoSurf/releases/latest',
          ),
          headers: const {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      return null;
    }

    final release = jsonDecode(response.body) as Map<String, dynamic>;
    if (release['draft'] == true || release['prerelease'] == true) {
      return null;
    }

    final latestVersion = _versionParts(release['tag_name'] as String?);
    final installedVersion = _versionParts(
      '${packageInfo.version}+${packageInfo.buildNumber}',
    );
    final releaseUrl = Uri.tryParse(release['html_url'] as String? ?? '');
    final updateUrl = Platform.isIOS
        ? Uri.parse('https://testflight.apple.com/join/ky5bRwMY')
        : releaseUrl;

    if (latestVersion == null ||
        installedVersion == null ||
        updateUrl == null) {
      return null;
    }

    print(
      'Latest version: $latestVersion, Installed version: $installedVersion',
    );

    for (var index = 0; index < latestVersion.length; index++) {
      if (latestVersion[index] > installedVersion[index]) {
        return updateUrl;
      }
      if (latestVersion[index] < installedVersion[index]) {
        return null;
      }
    }

    return null;
  } on Exception {
    return null;
  }
}

List<int>? _versionParts(String? version) {
  if (version == null) {
    return null;
  }
  // Tags look like v0.11.5+290; legacy tags (v0.11.5-6) have no build number.
  final match = RegExp(
    r'^v?(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?(?:-.*)?$',
  ).firstMatch(version.trim());
  if (match == null) {
    return null;
  }

  return [
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4) ?? '0'),
  ];
}
