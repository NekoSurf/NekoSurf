import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/widgets/dash_dialogs.dart';
import 'package:flutter_chan/widgets/dash_header.dart';

class CupertinoMenuButton extends StatelessWidget {
  const CupertinoMenuButton({
    super.key,
    this.icon = CupertinoIcons.ellipsis_circle,
    this.glassIcon = const Icon(CupertinoIcons.ellipsis_circle),
    required this.menuChildren,
    this.isGlass = false,
  });

  final IconData icon;
  final Icon glassIcon;
  final List<DashMenuEntry> menuChildren;
  final bool isGlass;

  @override
  Widget build(BuildContext context) {
    return DashMenuAnchor(
      menuChildren: menuChildren,
      builder: (context, open) => DashIconButton(
        icon: isGlass ? glassIcon : Icon(icon),
        onPressed: open,
      ),
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
