import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter_chan/saved/give_media.dart';
import 'package:flutter_chan/sync/cloud_sync.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_header.dart';
import 'package:flutter_chan/ui/dash_scaffold.dart';
import 'package:flutter_chan/ui/toast.dart';
import 'package:path_provider/path_provider.dart';

/// What iCloud sync did lately, newest last, kept up to date while it's
/// open; shared as a text file, to find out why something hasn't reached
/// another device. Items are only their kind and a short code.
class SyncLogPage extends StatefulWidget {
  const SyncLogPage({super.key});

  @override
  State<SyncLogPage> createState() => _SyncLogPageState();
}

class _SyncLogPageState extends State<SyncLogPage> {
  final CloudSync _sync = CloudSync.instance;
  final ScrollController _scroll = ScrollController();
  String? _log;
  String? _failed;

  @override
  void initState() {
    super.initState();
    _sync.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _sync.removeListener(_reload);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final bool atEnd =
        !_scroll.hasClients ||
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 40;
    try {
      final String log = await _sync.log();
      if (!mounted) {
        return;
      }
      setState(() {
        _log = log;
        _failed = null;
      });
    } on SyncFailed catch (e) {
      if (mounted) {
        setState(() => _failed = '$e');
      }
      return;
    }
    // Newest last: keep it in view, unless you've scrolled up to read.
    if (atEnd) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  Future<void> _share() async {
    final String? log = _log;
    if (log == null) {
      return;
    }
    try {
      final Directory dir = await getTemporaryDirectory();
      final File file = File('${dir.path}/NekoSurf iCloud sync log.txt');
      await file.writeAsString(log);
      await shareFile(file, mimeType: 'text/plain');
    } on Exception catch (e) {
      if (mounted) {
        showToast(context, "Couldn't share the log. $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    return DashBarScaffold(
      title: 'Sync log',
      actions: [
        DashIconButton(
          label: 'Share',
          icon: const Icon(CupertinoIcons.share),
          onPressed: _log == null ? null : _share,
        ),
      ],
      body: Builder(
        builder: (context) {
          final String? text = _failed ?? _log;
          if (text == null) {
            return const Center(child: CupertinoActivityIndicator());
          }
          return SingleChildScrollView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(
              16,
              MediaQuery.paddingOf(context).top + 12,
              16,
              media.padding.bottom + 24,
            ),
            child: SelectableText(
              text,
              style: TextStyle(
                fontFamily: 'Menlo',
                fontFamilyFallback: const ['Courier'],
                fontSize: 11.5,
                height: 1.45,
                color: DashColors.text(context),
              ),
            ),
          );
        },
      ),
    );
  }
}
