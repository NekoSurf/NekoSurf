import 'package:app_settings/app_settings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:provider/provider.dart';

class PermissionDenied extends StatelessWidget {
  const PermissionDenied({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeChanger>(context);
    final bool isDark = theme.getTheme() == ThemeData.dark();
    final Color cardColor = isDark
        ? const Color(0xFF13161B)
        : const Color(0xFFFFFFFF);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16.0, 32.0, 16.0, 32.0),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark
                  ? CupertinoColors.systemGrey.withValues(alpha: 0.25)
                  : const Color(0x14000000),
            ),
            boxShadow: isDark
                ? []
                : const [
                    BoxShadow(
                      color: Color(0x12000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Permission denied!',
                style: TextStyle(
                  fontSize: 26,
                  color: theme.getTheme() == ThemeData.dark()
                      ? Colors.white
                      : Colors.black,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 30),
              Text(
                'To use this feature, you need to grant the app permission to access your storage.',
                style: TextStyle(
                  fontSize: 16,
                  color: theme.getTheme() == ThemeData.dark()
                      ? Colors.white
                      : Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Go to your device settings and enable the Full Access permission to the Photos for this app.',
                style: TextStyle(
                  fontSize: 16,
                  color: theme.getTheme() == ThemeData.dark()
                      ? Colors.white
                      : Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              CupertinoButton(
                color: CupertinoColors.activeBlue,
                child: const Text(
                  'Open System Settings',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: () {
                  AppSettings.openAppSettings(type: AppSettingsType.settings);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
