# [package:media_kit_libs_android_video](https://github.com/media-kit/media-kit)

[![](https://img.shields.io/discord/1079685977523617792?color=33cd57&label=Discord&logo=discord&logoColor=discord)](https://discord.gg/h7qf2R9n57) [![Github Actions](https://github.com/media-kit/media-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/media-kit/media-kit/actions/workflows/ci.yml)

Android package providing video (& audio) native libraries for [`package:media_kit`](https://github.com/media-kit/media-kit).

## License

Copyright © 2021 & onwards, Hitesh Kumar Saini <<saini123hitesh@gmail.com>>

This project & the work under this repository is governed by MIT license that can be found in the [LICENSE](./LICENSE) file.

## NekoSurf's copy

This is upstream's package at media-kit/media-kit@`c533e44`, with one change:
`android/build.gradle` downloads libmpv-android-video-build v1.1.11's
`encoders-gpl` libraries instead of v1.1.7's `default` ones (v1.1.7 has no
encoder build). They have the same mpv and FFmpeg, plus FFmpeg's encoders and
fftools, linked into `libmpv.so`, which NekoSurf uses to run `ffmpeg` and
`ffprobe` in-process when saving videos. The encoders include x264, which is
GPL.

The release lists only SHA-256s; the MD5s in `build.gradle` are of the
downloaded files, checked against those.
