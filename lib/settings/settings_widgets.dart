import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chan/ui/colors.dart';

/// What's typed in Settings' search field, for the rows to show only what
/// matches it; empty when not searching.
class SettingsSearch extends InheritedWidget {
  const SettingsSearch({super.key, required this.query, required super.child});

  /// In lower case.
  final String query;

  static String queryOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsSearch>()?.query ?? '';

  @override
  bool updateShouldNotify(SettingsSearch oldWidget) => query != oldWidget.query;
}

/// Whether a search finds [row]: by its title, what it says under that, or
/// the value it shows.
bool settingsRowMatches(SettingsRow row, String query) => [
  row.title,
  row.subtitle,
  row.value,
].any((String? text) => text?.toLowerCase().contains(query) ?? false);

/// A group's title was searched for, so all of it shows.
class _GroupFound extends InheritedWidget {
  const _GroupFound({required this.found, required super.child});

  final bool found;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GroupFound>()?.found ?? false;

  @override
  bool updateShouldNotify(_GroupFound oldWidget) => found != oldWidget.found;
}

class SettingsGroup extends StatefulWidget {
  const SettingsGroup({
    super.key,
    required this.children,
    this.title,
    this.footer,
  });

  final String? title;
  final String? footer;
  final List<Widget> children;

  @override
  State<SettingsGroup> createState() => _SettingsGroupState();
}

class _SettingsGroupState extends State<SettingsGroup> {
  /// While searching, whether a row in it matches, as last looked.
  bool _found = true;

  /// Looks through the rows built in it, after they're built, wherever
  /// they're wrapped, and hides it while none matches.
  void _look(String query) {
    if (!mounted || query != SettingsSearch.queryOf(context)) {
      return;
    }
    bool found = false;
    void visit(Element element) {
      if (found) {
        return;
      }
      final Widget widget = element.widget;
      if (widget is SettingsRow && settingsRowMatches(widget, query)) {
        found = true;
        return;
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    if (found != _found) {
      setState(() => _found = found);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? title = widget.title;
    final String? footer = widget.footer;
    final List<Widget> children = widget.children;
    final String query = SettingsSearch.queryOf(context);
    final bool searching = query.isNotEmpty;
    final bool titleFound =
        searching && (title?.toLowerCase().contains(query) ?? false);
    if (searching && !titleFound) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _look(query));
    }
    // Still built while hidden, so its rows can be looked through.
    return Offstage(
      offstage: searching && !titleFound && !_found,
      child: _GroupFound(
        found: titleFound,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                  child: Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: DashColors.muted(context),
                    ),
                  ),
                ),
              Container(
                decoration: BoxDecoration(
                  color: DashColors.card(context),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: DashColors.border(context)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (int i = 0; i < children.length; i++) ...[
                      // Not while searching: rows between may be hidden.
                      if (i > 0 && !searching)
                        Divider(
                          height: 1,
                          indent: 58,
                          color: DashColors.border(context),
                        ),
                      children[i],
                    ],
                  ],
                ),
              ),
              if (footer != null && !searching)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                  child: Text(
                    footer,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: DashColors.muted(context),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final String query = SettingsSearch.queryOf(context);
    if (query.isNotEmpty &&
        !_GroupFound.of(context) &&
        !settingsRowMatches(this, query)) {
      return const SizedBox.shrink();
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 17, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: destructive
                          ? DashColors.danger
                          : DashColors.text(context),
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.3,
                          color: DashColors.muted(context),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (value != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  value!,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.accent,
                  ),
                ),
              ),
            if (trailing != null)
              Padding(padding: const EdgeInsets.only(left: 8), child: trailing),
          ],
        ),
      ),
    );
  }
}

class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CupertinoSwitch(
      value: value,
      activeTrackColor: context.accent,
      onChanged: (bool on) {
        // It ticks by itself on iPhone, but not on Android.
        if (defaultTargetPlatform != TargetPlatform.iOS) {
          HapticFeedback.selectionClick();
        }
        onChanged(on);
      },
    );
  }
}

/// A choice between a few options, all in view.
class SettingsSegments<T extends Object> extends StatelessWidget {
  const SettingsSegments({
    super.key,
    required this.value,
    required this.onChanged,
    required this.segments,
  });

  final T value;
  final ValueChanged<T> onChanged;
  final Map<T, String> segments;

  @override
  Widget build(BuildContext context) {
    return CupertinoSlidingSegmentedControl<T>(
      groupValue: value,
      backgroundColor: DashColors.page(context),
      thumbColor: context.accent,
      padding: const EdgeInsets.all(3),
      onValueChanged: (T? chosen) {
        if (chosen != null) {
          HapticFeedback.selectionClick();
          onChanged(chosen);
        }
      },
      children: {
        for (final MapEntry<T, String> segment in segments.entries)
          segment.key: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              segment.value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: segment.key == value
                    ? CupertinoColors.black
                    : DashColors.text(context),
              ),
            ),
          ),
      },
    );
  }
}
