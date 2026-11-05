import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/widgets/dash_dialogs.dart';
import 'package:flutter_chan/widgets/dash_header.dart';

class CupertinoMenuButton extends StatelessWidget {
  const CupertinoMenuButton({
    super.key,
    this.icon = CupertinoIcons.ellipsis_circle,
    this.label = 'More',
    required this.menuChildren,
  });

  final IconData icon;
  final String label;
  final List<DashMenuEntry> menuChildren;

  @override
  Widget build(BuildContext context) {
    return DashMenuAnchor(
      menuChildren: menuChildren,
      builder: (context, open) =>
          DashIconButton(label: label, icon: Icon(icon), onPressed: open),
    );
  }
}

DashMenuEntry buildMenuItem({
  required String title,
  required VoidCallback onPressed,
  IconData? icon,
  bool isSelected = false,
  bool isDestructive = false,
}) {
  return DashMenuEntry(
    title: title,
    icon: icon,
    isSelected: isSelected,
    isDestructive: isDestructive,
    onPressed: onPressed,
  );
}
