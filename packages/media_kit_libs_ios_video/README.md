# [package:media_kit_libs_ios_video](https://github.com/media-kit/media-kit)

[![](https://img.shields.io/discord/1079685977523617792?color=33cd57&label=Discord&logo=discord&logoColor=discord)](https://discord.gg/h7qf2R9n57) [![Github Actions](https://github.com/media-kit/media-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/media-kit/media-kit/actions/workflows/ci.yml)

iOS package providing video (& audio) native libraries for [`package:media_kit`](https://github.com/media-kit/media-kit).

Visit [media-kit/libmpv-darwin-build@`main`](https://github.com/media-kit/libmpv-darwin-build/tree/main) for descriptive details.

Thanks to [Julien Muret](https://github.com/birros) for libmpv & FFmpeg builds for iOS.

## License

Copyright © 2022, Hitesh Kumar Saini <<saini123hitesh@gmail.com>>

This project & the work under this repository is governed by MIT license that can be found in the [LICENSE](./LICENSE) file.

## NekoSurf's copy

This is upstream's package at media-kit/media-kit@`c533e44`, with one change:
it downloads libmpv-darwin-build v0.7.2's `ios-universal-video-encodersgpl`
frameworks instead of `ios-universal-video-default`. They have the same mpv
and FFmpeg, plus FFmpeg's encoders and `Fftools-ffi`, which NekoSurf uses to
run `ffmpeg` and `ffprobe` in-process when saving videos. The encoders include
x264, which is GPL.

To move to a newer libmpv-darwin-build release, change the version in
`ios/media_kit_libs_ios_video/Package.swift` and `ios/Makefile`, and take each
`ios-universal-video-encodersgpl` file's SHA-256 from the release.
