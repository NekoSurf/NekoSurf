import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/settings/appearance_settings.dart';
import 'package:flutter_chan/settings/browsing_settings.dart';
import 'package:flutter_chan/settings/storage_settings.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/open_url.dart';
import 'package:package_info_plus/package_info_plus.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  late final Future<PackageInfo> _version = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Column(
        children: [
          _AboutCard(version: _version),
          const SizedBox(height: 22),
          const AppearanceSettings(),
          const BrowsingSettings(),
          const StorageSettings(),
        ],
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.version});

  final Future<PackageInfo> version;

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            context.accent.withValues(alpha: isDark ? 0.22 : 0.35),
            context.accent2.withValues(alpha: isDark ? 0.18 : 0.28),
          ],
        ),
        border: Border.all(color: context.accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset(
              'assets/icons/icon-round.png',
              width: 64,
              height: 64,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NekoSurf',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.7,
                    color: DashColors.text(isDark),
                  ),
                ),
                FutureBuilder<PackageInfo>(
                  future: version,
                  builder: (context, snapshot) => Text(
                    snapshot.hasData
                        ? 'Version ${snapshot.data!.version} (${snapshot.data!.buildNumber})'
                        : ' ',
                    style: TextStyle(
                      fontSize: 13,
                      color: DashColors.text(isDark).withValues(alpha: 0.65),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => openUrl('https://github.com/NekoSurf/NekoSurf'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.3)
                          : Colors.white.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.chevron_left_slash_chevron_right,
                          size: 13,
                          color: DashColors.text(isDark),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'View on GitHub',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: DashColors.text(isDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
