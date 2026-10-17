import 'package:app_settings/app_settings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_widgets.dart';
import 'package:flutter_chan/widgets/dash_dialogs.dart';

class PermissionDenied extends StatelessWidget {
  const PermissionDenied({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 32, 16, 32),
        child: DashCard(
          isDark: isDark,
          radius: 28,
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: DashColors.nsfw.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  CupertinoIcons.lock_fill,
                  color: DashColors.nsfw,
                  size: 28,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Storage access needed',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: DashColors.text(isDark),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Allow access to Photos in your device settings so saved attachments can be stored and shown here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.4,
                  color: DashColors.muted(isDark),
                ),
              ),
              const SizedBox(height: 20),
              DashDialogAction(
                isDefaultAction: true,
                onPressed: () =>
                    AppSettings.openAppSettings(type: AppSettingsType.settings),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
