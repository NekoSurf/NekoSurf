import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/settings/appearance_settings.dart';
import 'package:flutter_chan/settings/backup_settings.dart';
import 'package:flutter_chan/settings/browsing_settings.dart';
import 'package:flutter_chan/settings/privacy_settings.dart';
import 'package:flutter_chan/settings/settings_widgets.dart';
import 'package:flutter_chan/settings/storage_settings.dart';
import 'package:flutter_chan/settings/sync_settings.dart';
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
          const PrivacySettings(),
          const StorageSettings(),
          const CloudSyncSettings(),
          const BackupSettings(),
          const _AboutLinks(),
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
                    color: DashColors.text(context),
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
                      color: DashColors.text(context).withValues(alpha: 0.65),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _CardLink(
                      icon: CupertinoIcons.chevron_left_slash_chevron_right,
                      label: 'View on GitHub',
                      onTap: () =>
                          openUrl('https://github.com/NekoSurf/NekoSurf'),
                    ),
                    _CardLink(
                      icon: CupertinoIcons.heart_fill,
                      iconColor: const Color(0xFFF472B6),
                      label: 'Sponsor',
                      onTap: () => openUrl(_AboutLinks.sponsorUrl),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A small rounded button on the card at the top.
class _CardLink extends StatelessWidget {
  const _CardLink({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.black.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: iconColor ?? DashColors.text(context)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: DashColors.text(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Where to support the app, say what's wrong or missing, and read what the
/// app does with data.
class _AboutLinks extends StatelessWidget {
  const _AboutLinks();

  static const String sponsorUrl = 'https://github.com/sponsors/wrngwrld';
  static const String feedbackUrl =
      'https://github.com/NekoSurf/NekoSurf/issues/new';
  static const String privacyPolicyUrl =
      'https://github.com/NekoSurf/NekoSurf/blob/main/privacy_policy.md';

  @override
  Widget build(BuildContext context) {
    final Widget opensOutside = Icon(
      CupertinoIcons.arrow_up_right,
      size: 14,
      color: DashColors.muted(context),
    );

    return SettingsGroup(
      title: 'About',
      footer: 'All open on GitHub, in your browser.',
      children: [
        SettingsRow(
          icon: CupertinoIcons.heart_fill,
          color: const Color(0xFFF472B6),
          title: 'Sponsor NekoSurf',
          subtitle: 'Help keep it free, with no ads',
          trailing: opensOutside,
          onTap: () => openUrl(sponsorUrl),
        ),
        SettingsRow(
          icon: CupertinoIcons.chat_bubble_text_fill,
          color: const Color(0xFF60A5FA),
          title: 'Send feedback',
          subtitle: 'Report a bug or suggest an idea',
          trailing: opensOutside,
          onTap: () => openUrl(feedbackUrl),
        ),
        SettingsRow(
          icon: CupertinoIcons.hand_raised_fill,
          color: const Color(0xFF34D399),
          title: 'Privacy policy',
          subtitle: 'What the app keeps, and what it connects to',
          trailing: opensOutside,
          onTap: () => openUrl(privacyPolicyUrl),
        ),
      ],
    );
  }
}
