import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class ImageViewer extends StatefulWidget {
  const ImageViewer({
    Key? key,
    required this.url,
    this.interactiveViewer = false,
    this.fit = BoxFit.contain,
    this.height,
    this.width,
  }) : super(key: key);

  final String url;
  final bool interactiveViewer;
  final BoxFit fit;
  final double? height;
  final double? width;

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  late Future<File> _getImage;

  @override
  void initState() {
    super.initState();
    _getImage = getImage();
  }

  @override
  void didUpdateWidget(ImageViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _getImage = getImage();
    }
  }

  Future<File> getImage() async {
    final File file = await DefaultCacheManager().getSingleFile(widget.url);

    return file;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File>(
      future: _getImage,
      builder: (context, AsyncSnapshot<File> snapshot) {
        switch (snapshot.connectionState) {
          case ConnectionState.waiting:
            return const Center(child: CupertinoActivityIndicator());
          default:
            return widget.interactiveViewer
                ? InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 5,
                    child: Image.file(snapshot.data ?? File('')),
                  )
                : Image.file(
                    snapshot.data ?? File(''),
                    fit: widget.fit,
                    height: widget.height,
                    width: widget.width,
                  );
        }
      },
    );
  }
}
