import 'package:flutter/cupertino.dart';

class CupertinoMenuButton extends StatelessWidget {
  const CupertinoMenuButton({
    super.key,
    required this.icon,
    required this.menuChildren,
  });

  final IconData icon;
  final List<Widget> menuChildren;

  @override
  Widget build(BuildContext context) {
    return CupertinoMenuAnchor(
      menuChildren: menuChildren,
      builder: (context, controller, _) => CupertinoIconButton(
        icon: icon,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

CupertinoMenuItem buildMenuItem({
  required String title,
  required VoidCallback onPressed,
  IconData? icon,
  bool isSelected = false,
  bool isDestructive = false,
}) {
  return CupertinoMenuItem(
    leading: isSelected ? const Icon(CupertinoIcons.check_mark) : null,
    trailing: icon == null ? null : Icon(icon),
    isDestructiveAction: isDestructive,
    onPressed: onPressed,
    child: Text(title),
  );
}

class CupertinoIconButton extends StatelessWidget {
  const CupertinoIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(40, 40),
      onPressed: onPressed,
      child: Icon(icon, size: 22, color: color),
    );
  }
}
