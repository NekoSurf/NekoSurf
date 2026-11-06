import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/chan/api.dart';
import 'package:flutter_chan/chan/board_link.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_dialogs.dart';
import 'package:flutter_chan/ui/open.dart';

void showOpenLinkDialog(BuildContext context) {
  showDashDialog<void>(
    context: context,
    builder: (_) => const _OpenLinkDialog(),
  );
}

class _OpenLinkDialog extends StatefulWidget {
  const _OpenLinkDialog();

  @override
  State<_OpenLinkDialog> createState() => _OpenLinkDialogState();
}

class _OpenLinkDialogState extends State<_OpenLinkDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _warning;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final String text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _warning = 'Please enter a link');
      return;
    }

    final link = parseBoardLink(text);
    final int? thread = link?.thread;
    if (link == null || thread == null) {
      setState(() => _warning = 'This link is not supported');
      return;
    }

    final List<Post> posts;
    try {
      posts = await fetchThread(link.board, thread);
    } catch (e) {
      if (mounted) {
        setState(() => _warning = e.toString());
      }
      return;
    }
    if (mounted) {
      Navigator.of(context).pop();
      openThread(context, posts.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DashDialog(
      title: const Text('Open Link'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          if (_warning != null) ...[
            Text(_warning!, style: const TextStyle(color: DashColors.danger)),
            const SizedBox(height: 5),
          ],
          DashDialogField(
            controller: _controller,
            placeholder: 'Insert Thread URL',
          ),
        ],
      ),
      actions: [
        DashDialogAction(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context),
        ),
        DashDialogAction(
          isDefaultAction: true,
          onPressed: _open,
          child: const Text('Open'),
        ),
      ],
    );
  }
}
