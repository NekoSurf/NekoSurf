import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/home/app_shell.dart';
import 'package:flutter_chan/main.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/ui/app_restart.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_dialogs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('restarting from a dialog builds the app again from what is '
      'stored', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'themeColor': 'cyan'});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      AppRoot(prefs: prefs, settings: SettingsProvider(prefs)),
    );
    await tester.pump(const Duration(seconds: 1));

    final BuildContext context = tester.element(find.byType(AppShell));
    final AppRestart app = AppRestart.of(context);
    Future<void> confirmThenRestart() async {
      final bool? restore = await showDashDialog<bool>(
        context: context,
        builder: (dialogContext) => DashDialog(
          title: const Text('Restore?'),
          actions: [
            DashDialogAction(
              child: const Text('Restore'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
      );
      if (restore ?? false) {
        await app.restart(() => prefs.setString('themeColor', 'violet'));
      }
    }

    confirmThenRestart();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Restore'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.byType(AppShell), findsOneWidget);
    expect(
      Provider.of<SettingsProvider>(
        tester.element(find.byType(AppShell)),
        listen: false,
      ).themeColor.value,
      ThemeColor.violet,
    );
  });
}
