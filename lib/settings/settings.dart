import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/settings/data_settings.dart';
import 'package:flutter_chan/settings/privacy_settings.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/settings/settings_widgets.dart';
import 'package:flutter_chan/settings/threads_settings.dart';
import 'package:flutter_chan/ui/back_swipe_route.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/open_url.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  late final Future<PackageInfo> _version = PackageInfo.fromPlatform();

  void _push(Widget page) {
    Navigator.of(context).push(BackSwipePageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);

    return SliverToBoxAdapter(
      child: Column(
        children: [
          _AboutCard(version: _version),
          const SizedBox(height: 22),
          SettingsGroup(
            title: 'Preferences',
            children: [
              SettingsRow(
                icon: CupertinoIcons.list_bullet,
                color: DashColors.accent2,
                title: 'Threads',
                subtitle:
                    '${settings.boardViewMode.value == ViewMode.grid ? 'Grid' : 'List'} view, sorting, ${settings.threadLayout.value == ThreadLayout.nested ? 'nested' : 'flat'} threads',
                showChevron: true,
                onTap: () => _push(const ThreadsSettings()),
              ),
              SettingsRow(
                icon: CupertinoIcons.hand_raised_fill,
                color: const Color(0xFF34D399),
                title: 'Privacy',
                subtitle: settings.allowNSFW.value
                    ? 'NSFW boards are visible'
                    : 'NSFW boards are hidden',
                showChevron: true,
                onTap: () => _push(const PrivacySettings()),
              ),
              SettingsRow(
                icon: CupertinoIcons.tray_full_fill,
                color: const Color(0xFFFBBF24),
                title: 'Data',
                subtitle: 'Watched posts, history, caches',
                showChevron: true,
                onTap: () => _push(const DataSettings()),
              ),
            ],
          ),
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
            DashColors.accent.withValues(alpha: isDark ? 0.22 : 0.35),
            DashColors.accent2.withValues(alpha: isDark ? 0.18 : 0.28),
          ],
        ),
        border: Border.all(color: DashColors.accent.withValues(alpha: 0.2)),
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
