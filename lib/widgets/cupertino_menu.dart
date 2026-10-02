import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_widgets/widgets/interactive/glass_icon_button.dart';

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
  final List<Widget> menuChildren;
  final bool isGlass;

  @override
  Widget build(BuildContext context) {
    return CupertinoMenuAnchor(
      menuChildren: menuChildren,
      builder: (context, controller, _) => isGlass
          ? GlassIconButton(
              icon: glassIcon,
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
            )
          : CupertinoIconButton(
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
