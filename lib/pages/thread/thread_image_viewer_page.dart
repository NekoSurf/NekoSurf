import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/save_videos.dart';
import 'package:flutter_chan/blocs/saved_attachments_model.dart';
import 'package:provider/provider.dart';

class ThreadImageViewerPage extends StatefulWidget {
  const ThreadImageViewerPage({
    Key? key,
    required this.imageUrl,
    this.title,
    this.board,
    this.fileName,
  }) : super(key: key);

  final String imageUrl;
  final String? title;
  final String? board;
  final String? fileName;

  @override
  State<ThreadImageViewerPage> createState() => _ThreadImageViewerPageState();
}

class _ThreadImageViewerPageState extends State<ThreadImageViewerPage> {
  bool _isSaving = false;
  bool _isRemoving = false;
  bool _didSaveAttachment = false;
  Timer? _saveSuccessTimer;
  bool _isDownloading = false;
  bool _didDownload = false;
  Timer? _downloadSuccessTimer;
  bool _isSharing = false;

  @override
  void dispose() {
    _saveSuccessTimer?.cancel();
    _downloadSuccessTimer?.cancel();
    super.dispose();
  }

  Future<void> _downloadToGallery() async {
    if (_isDownloading || widget.imageUrl.isEmpty || widget.fileName == null) {
      return;
    }
    setState(() {
      _isDownloading = true;
    });
    await saveVideo(widget.imageUrl, widget.fileName!, context, isSaved: false);
    if (!mounted) {
      return;
    }
    setState(() {
      _isDownloading = false;
      _didDownload = true;
    });
    _downloadSuccessTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _didDownload = false;
      });
    });
  }

  Future<void> _shareCurrentMedia() async {
    if (_isSharing || widget.imageUrl.isEmpty || widget.fileName == null) {
      return;
    }
    setState(() {
      _isSharing = true;
    });
    await shareMedia(
      widget.imageUrl,
      widget.fileName!,
      context,
      isSaved: false,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isSharing = false;
    });
  }

  Future<void> _saveToAttachments() async {
    if (_isSaving || widget.board == null || widget.fileName == null) {
      return;
    }

    final savedAttachments = context.read<SavedAttachmentsProvider>();
    final alreadySaved = savedAttachments.getSavedAttachments().any(
      (attachment) =>
          attachment.fileName?.split('/').last.split('.').first ==
          widget.fileName?.split('.').first,
    );

    if (alreadySaved) {
      _showSaveConfirmation();
      return;
    }

    setState(() {
      _isSaving = true;
    });

    await savedAttachments.addSavedAttachments(
      context,
      widget.board!,
      widget.fileName!,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isSaving = false;
    });

    final saveSucceeded = savedAttachments.getSavedAttachments().any(
      (attachment) => attachment.fileName?.split('/').last == widget.fileName,
    );

    if (saveSucceeded) {
      _showSaveConfirmation();
    }
  }

  Future<void> _removeFromAttachments() async {
    if (_isRemoving || widget.board == null || widget.fileName == null) {
      return;
    }
    setState(() {
      _isRemoving = true;
    });
    await context.read<SavedAttachmentsProvider>().removeSavedAttachments(
      widget.fileName!,
      context,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isRemoving = false;
    });
  }

  void _showSaveConfirmation() {
    _saveSuccessTimer?.cancel();
    setState(() {
      _didSaveAttachment = true;
    });
    _saveSuccessTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _didSaveAttachment = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Center(
              child: Image.network(
                widget.imageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) {
                    return child;
                  }

                  return const Center(
                    child: CupertinoActivityIndicator(radius: 14),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return const Text(
                    'Unable to load image',
                    style: TextStyle(color: Colors.white),
                  );
                },
              ),
            ),
          ),
          Positioned(
            top: topInset + 8,
            left: 8,
            child: CupertinoButton(
              minimumSize: const Size(36, 36),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(999),
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Icon(
                CupertinoIcons.back,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
          Positioned(
            top: topInset + 10,
            right: 12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.board != null && widget.fileName != null)
                  Builder(
                    builder: (context) {
                      final savedAttachments = context
                          .watch<SavedAttachmentsProvider>();
                      final isSaved = savedAttachments
                          .getSavedAttachments()
                          .any(
                            (a) =>
                                a.fileName?.split('/').last.split('.').first ==
                                widget.fileName?.split('.').first,
                          );
                      if (isSaved) {
                        return CupertinoButton(
                          minimumSize: const Size(36, 36),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          color: Colors.black.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(999),
                          onPressed: _isRemoving
                              ? null
                              : _removeFromAttachments,
                          child: _isRemoving
                              ? const CupertinoActivityIndicator(radius: 9)
                              : const Icon(
                                  CupertinoIcons.trash,
                                  color: Colors.white,
                                  size: 18,
                                ),
                        );
                      }
                      return CupertinoButton(
                        minimumSize: const Size(36, 36),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        color: Colors.black.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(999),
                        onPressed: _isSaving || _didSaveAttachment
                            ? null
                            : _saveToAttachments,
                        child: _isSaving
                            ? const CupertinoActivityIndicator(radius: 9)
                            : Icon(
                                _didSaveAttachment
                                    ? CupertinoIcons.check_mark_circled_solid
                                    : CupertinoIcons.add_circled,
                                color: Colors.white,
                                size: 18,
                              ),
                      );
                    },
                  ),
                const SizedBox(width: 8),
                CupertinoButton(
                  minimumSize: const Size(36, 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(999),
                  onPressed: _isDownloading || _didDownload
                      ? null
                      : _downloadToGallery,
                  child: _isDownloading
                      ? const CupertinoActivityIndicator(radius: 9)
                      : Icon(
                          _didDownload
                              ? CupertinoIcons.check_mark_circled_solid
                              : CupertinoIcons.arrow_down_to_line,
                          color: Colors.white,
                          size: 18,
                        ),
                ),
                const SizedBox(width: 8),
                CupertinoButton(
                  minimumSize: const Size(36, 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(999),
                  onPressed: _isSharing ? null : _shareCurrentMedia,
                  child: _isSharing
                      ? const CupertinoActivityIndicator(radius: 9)
                      : const Icon(
                          CupertinoIcons.share,
                          color: Colors.white,
                          size: 18,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
