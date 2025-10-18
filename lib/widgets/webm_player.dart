import 'dart:io';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_chan/API/save_videos.dart';
import 'package:flutter_chan/blocs/gallery_model.dart';
import 'package:flutter_chan/blocs/saved_attachments_model.dart';
import 'package:flutter_vlc_player_16kb/flutter_vlc_player.dart';
import 'package:provider/provider.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../blocs/settings_model.dart';

class VLCPlayer extends StatefulWidget {
  const VLCPlayer({
    Key? key,
    required this.video,
    this.board,
    required this.fileName,
    this.isAsset = false,
    this.directory,
    this.ext = 'mp4',
  }) : super(key: key);

  final String video;
  final String? board;
  final String fileName;
  final bool isAsset;
  final Directory? directory;
  final String? ext;

  @override
  VLCPlayerState createState() => VLCPlayerState();
}

class VLCPlayerState extends State<VLCPlayer> {
  late VlcPlayerController _videoPlayerController;

  Directory directory = Directory('');

  bool isVisible = true;

  double sliderValue = 0.0;
  bool validPosition = false;
  String position = '';
  String duration = '';

  bool controlsVisible = true;

  Stream<FileResponse> fileStream = const Stream.empty();

  late final Future<File> cachedVideo;

  @override
  void initState() {
    super.initState();

    initVideo();
  }

  Future<void> initVideo() async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);

    final File file;

    if (widget.isAsset) {
      file = File(
          '${widget.directory!.path}/savedAttachments/${getNameWithoutExtension(widget.fileName)}${widget.ext}');

      _videoPlayerController = VlcPlayerController.file(
        file,
        hwAcc: HwAcc.auto,
        autoPlay: true,
      );

      _videoPlayerController.addListener(listener);
    } else if (settings.getUseCachingOnVideos()) {
      cachedVideo = getCachedVideo();
    } else {
      _videoPlayerController = VlcPlayerController.network(
        'https://i.4cdn.org/${widget.board}/${widget.video}',
        hwAcc: HwAcc.full,
        autoPlay: true,
        options: VlcPlayerOptions(
          advanced: VlcAdvancedOptions([
            VlcAdvancedOptions.networkCaching(2000),
          ]),
        ),
      );
    }
  }

  Future<File> getCachedVideo() async {
    final File file = await DefaultCacheManager().getSingleFile(
      'https://i.4cdn.org/${widget.board}/${widget.video}',
    );

    _videoPlayerController = VlcPlayerController.file(
      file,
      hwAcc: HwAcc.auto,
      autoPlay: true,
    );

    _videoPlayerController.addListener(listener);

    return file;
  }

  Future<void> listener() async {
    try {
      if (!mounted) {
        return;
      }

      if (!isVisible) {
        _videoPlayerController.pause();
      }

      if (_videoPlayerController.value.isInitialized && isVisible) {
        final oPosition = _videoPlayerController.value.position;
        final oDuration = _videoPlayerController.value.duration;
        if (oPosition != null && oDuration != null) {
          if (oDuration.inHours == 0) {
            final strPosition = oPosition.toString().split('.')[0];
            final strDuration = oDuration.toString().split('.')[0];
            position =
                "${strPosition.split(':')[1]}:${strPosition.split(':')[2]}";
            duration =
                "${strDuration.split(':')[1]}:${strDuration.split(':')[2]}";
          } else {
            position = oPosition.toString().split('.')[0];
            duration = oDuration.toString().split('.')[0];
          }
          validPosition = oDuration.compareTo(oPosition) >= 0;
          sliderValue = validPosition ? oPosition.inSeconds.toDouble() : 0;
        }
        setState(() {});
      }

      if (_videoPlayerController.value.isEnded) {
        _videoPlayerController.stop();
        _videoPlayerController.play();
      }
    } catch (e) {
      print(e);
    }
  }

  void _onScrubbing(DragUpdateDetails details) {
    try {
      setState(() {
        final double screenWidth = MediaQuery.of(context).size.width;

        final int videoDurationInSeconds =
            _videoPlayerController.value.duration.inSeconds;

        double scrubSensitivity;

        if (videoDurationInSeconds <= 15) {
          scrubSensitivity = 70.0 / videoDurationInSeconds;
        } else if (videoDurationInSeconds <= 30) {
          scrubSensitivity = 100.0 / videoDurationInSeconds;
        } else if (videoDurationInSeconds <= 300) {
          scrubSensitivity = 200.0 / videoDurationInSeconds;
        } else {
          scrubSensitivity = 300.0 / videoDurationInSeconds;
        }

        final double delta = (details.delta.dx / screenWidth) *
            scrubSensitivity *
            videoDurationInSeconds;

        int newSliderValue = (sliderValue + delta).round();

        newSliderValue = newSliderValue.clamp(0, videoDurationInSeconds);

        if ((newSliderValue - sliderValue).abs() >= 1) {
          sliderValue = newSliderValue.toDouble();

          if (_videoPlayerController.value.isInitialized) {
            _videoPlayerController.setTime(sliderValue.toInt() * 1000);
          }
        }
      });
    } catch (e) {
      print('Error during scrubbing: $e');
    }
  }

  void _onSliderPositionChanged(double progress) {
    try {
      setState(() {
        sliderValue = progress.floor().toDouble();
        _videoPlayerController.setTime(sliderValue.toInt() * 1000);
      });
    } catch (e) {
      print(e);
    }
  }

  Future<void> _togglePlaying() async {
    try {
      setState(() {
        _videoPlayerController.value.isPlaying
            ? _videoPlayerController.pause()
            : _videoPlayerController.play();

        isVisible ? isVisible = false : isVisible = true;
      });
    } catch (e) {
      print(e);
    }
  }

  @override
  void dispose() {
    try {
      _videoPlayerController.stop();
    } catch (e) {
      print(e);
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SavedAttachmentsProvider savedAttachmentsProvider =
        Provider.of<SavedAttachmentsProvider>(context);
    final SettingsProvider settings = Provider.of<SettingsProvider>(context);
    final GalleryProvider galleryProvider =
        Provider.of<GalleryProvider>(context, listen: false);

    if (widget.isAsset || !settings.getUseCachingOnVideos()) {
      _videoPlayerController.addListener(listener);
      return videoWidget(savedAttachmentsProvider, galleryProvider);
    } else {
      return FutureBuilder<File>(
        future: cachedVideo,
        builder: (context, AsyncSnapshot<File> snapshot) {
          return snapshot.hasData
              ? videoWidget(savedAttachmentsProvider, galleryProvider)
              : const CupertinoActivityIndicator();
        },
      );
    }
  }

  Stack videoWidget(SavedAttachmentsProvider savedAttachmentsProvider,
      GalleryProvider galleryProvider) {
    try {
      if (_videoPlayerController.value.isInitialized && mounted) {
        if (savedAttachmentsProvider.playing) {
          _videoPlayerController.play();
        } else {
          _videoPlayerController.pause();
        }
      }
    } catch (e) {
      print(e);
    }
    return Stack(
      children: [
        const Center(
          child: CupertinoActivityIndicator(),
        ),
        GestureDetector(
          onTap: () {
            setState(() {
              galleryProvider
                  .setControlsVisible(!galleryProvider.getControlsVisible());
            });
          },
          onHorizontalDragUpdate: (details) {
            _onScrubbing(details);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() {
                galleryProvider
                    .setControlsVisible(!galleryProvider.getControlsVisible());
              });
            },
            onHorizontalDragUpdate: (details) {
              _onScrubbing(details);
            },
            child: VisibilityDetector(
              key: ObjectKey(widget.video),
              onVisibilityChanged: (visibility) {
                if (visibility.visibleFraction < 0.5 &&
                    mounted &&
                    _videoPlayerController.value.isInitialized) {
                  _videoPlayerController.pause();

                  setState(() {
                    isVisible = false;
                  });
                }
                if (visibility.visibleFraction > 0.5 &&
                    mounted &&
                    _videoPlayerController.value.isInitialized) {
                  _videoPlayerController.play();

                  setState(() {
                    isVisible = true;
                  });
                }
              },
              child: Stack(
                children: [
                  Center(
                    child: AbsorbPointer(
                      child: VlcPlayer(
                        controller: _videoPlayerController,
                        aspectRatio: _videoPlayerController.value.aspectRatio,
                        placeholder:
                            const Center(child: CupertinoActivityIndicator()),
                      ),
                    ),
                  ),
                  Opacity(
                    opacity: galleryProvider.getControlsVisible() ? 1 : 0,
                    child: SafeArea(
                      child: Column(
                        children: [
                          Expanded(
                            child: Container(),
                          ),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 5),
                            height: 45,
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(15),
                                  // The BackdropFilter is currently bugged in flutter, it will not cut the border radius
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(
                                        sigmaX: 10.0, sigmaY: 10.0),
                                    child: Container(
                                      decoration: const BoxDecoration(
                                          color:
                                              Color.fromRGBO(50, 50, 50, 0.50),
                                          borderRadius: BorderRadius.all(
                                              Radius.circular(15))),
                                    ),
                                  ),
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      color: Colors.white,
                                      icon:
                                          _videoPlayerController.value.isPlaying
                                              ? const Icon(Icons.pause)
                                              : const Icon(Icons.play_arrow),
                                      onPressed: _togglePlaying,
                                    ),
                                    Expanded(
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        mainAxisSize: MainAxisSize.max,
                                        children: [
                                          Text(
                                            position,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                            ),
                                          ),
                                          Expanded(
                                            child: Slider(
                                              activeColor:
                                                  CupertinoColors.systemGrey,
                                              inactiveColor:
                                                  CupertinoColors.systemFill,
                                              thumbColor: CupertinoColors.white,
                                              value: sliderValue.clamp(
                                                  0.0,
                                                  (!validPosition &&
                                                          _videoPlayerController
                                                                  .value
                                                                  .duration ==
                                                              null)
                                                      ? 1.0
                                                      : _videoPlayerController
                                                          .value
                                                          .duration
                                                          .inSeconds
                                                          .toDouble()),
                                              min: 0.0,
                                              max: (!validPosition &&
                                                      _videoPlayerController
                                                              .value.duration ==
                                                          null)
                                                  ? 1.0
                                                  : _videoPlayerController
                                                      .value.duration.inSeconds
                                                      .toDouble(),
                                              onChanged: validPosition
                                                  ? _onSliderPositionChanged
                                                  : null,
                                            ),
                                          ),
                                          Text(
                                            duration,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(
                                            width: 15,
                                          )
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
