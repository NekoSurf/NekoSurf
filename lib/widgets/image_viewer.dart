import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class ImageViewer extends StatelessWidget {
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

  Widget _loadingBuilder(
    BuildContext context,
    Widget child,
    ImageChunkEvent? loadingProgress,
  ) {
    if (loadingProgress == null) {
      return child;
    }

    return const Center(child: CupertinoActivityIndicator());
  }

  @override
  Widget build(BuildContext context) {
    return interactiveViewer
        ? InteractiveViewer(
            minScale: 0.5,
            maxScale: 5,
            child: Image.network(url, loadingBuilder: _loadingBuilder),
          )
        : Image.network(
            url,
            fit: fit,
            height: height,
            width: width,
            loadingBuilder: _loadingBuilder,
          );
  }
}
