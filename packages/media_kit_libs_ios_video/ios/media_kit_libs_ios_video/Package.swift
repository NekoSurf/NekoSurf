// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

// NekoSurf: upstream media_kit_libs_ios_video 1.1.5 (media-kit/media-kit at
// c533e44), switched from libmpv-darwin-build's playback-only "video-default"
// frameworks to the "video-encodersgpl" ones of the same release (v0.7.2): the
// same mpv and FFmpeg, plus FFmpeg's encoders and Fftools-ffi, which runs
// ffmpeg and ffprobe commands in-process for saving videos. The encoders bring
// X264, Vpx, Ogg and Vorbis with them.

import PackageDescription

let libmpvTargets = [
    "Ass",
    "Avcodec",
    "Avfilter",
    "Avformat",
    "Avutil",
    "Dav1d",
    "Fftools-ffi",
    "Freetype",
    "Fribidi",
    "Harfbuzz",
    "Mbedcrypto",
    "Mbedtls",
    "Mbedx509",
    "Mpv",
    "Ogg",
    "Png16",
    "Swresample",
    "Swscale",
    "Uchardet",
    "Vorbis",
    "Vorbisenc",
    "Vorbisfile",
    "Vpx",
    "X264",
    "Xml2"
]

let libmpvArtifactBase = "https://github.com/media-kit/libmpv-darwin-build/releases/download/v0.7.2/libmpv-xcframeworks_v0.7.2_ios-universal-video-encodersgpl"
let libmpvChecksums = [
    "Ass": "136c56521897238cbd7ea58d8a507f42ff725c043ed5681554cfecd60faae115",
    "Avcodec": "0df630b0d91c915d42752b42ab026c0e3d2e17e0119aa0181f233d2effeb32f1",
    "Avfilter": "b97ef16cc7bc6cc3a11d95c2392bd71f1f19b8a383ba43cb4f3d40112c93854e",
    "Avformat": "4c3be33c45c3d4cfd9ea5328877d2d45855449ea72c524a2d5310507523777bd",
    "Avutil": "ec455537c7bca205b8854aa7c246dd2884f3d4a72f90532a3ce7592d88b6a925",
    "Dav1d": "928a46eaff12ac082ce98f379691d96c030a22db18f63c3c14bb46e724afb27e",
    "Fftools-ffi": "82524fbc441e5ecbba2572f9195f8e51f8152e332a165a4f2e17e2947f2e80c6",
    "Freetype": "7c5344f6df51a0dc10c04c6ad13fdeb2b38fe458eccf4a133c01f77c7cfca748",
    "Fribidi": "89b38c81c609d1bbb08c28c1dfbaf8b793a5be83e025f88af131aa01fb867998",
    "Harfbuzz": "8ad65b1de0b1a8120d8c6ac3d192ac8a0a8e383a28bcc4610fe1823881dfb58f",
    "Mbedcrypto": "00ca2faa18c8bd7b4cb49f40775a3a9305545371a9cf65ea0cf359ab13aeb50e",
    "Mbedtls": "377c63ae8bb23309d4116ad0492850e0cd488a63ae44ae9192111af1719a910f",
    "Mbedx509": "b8eb0ab6dfb096fa75c38f763d990160db5bdf485e023351faa13b95ad58fe2e",
    "Mpv": "8f1023ae3cd4371fa6356e42de9b2aefb9398a7a45ad8e27954ffc2430ca3bfb",
    "Ogg": "6dd28cbfcaa3a5e089321788e03440fa47e1eb02aa9b58f44947c85a29dfde07",
    "Png16": "8601b5f9b65ce0abb8e7639fadfd93781dfd81f0c50e1c941a0b7dbd7ed6d497",
    "Swresample": "0d4e83ef70da4b7b2524b22be3884093ae7998b6ef963829ff1f2260e2be6649",
    "Swscale": "ba1e31253fc61abebb2df41f5d296030dbbf9e4294201b58b23266817451f407",
    "Uchardet": "f2a4279b2e32d1d3262f9087968e9fa835b10659ba37340e370ba8156696c4ab",
    "Vorbis": "269b0e2b1c1bfee2ba96d8cfbe9cec4014dabc73bcd8a08210c582a4cfa962b7",
    "Vorbisenc": "7035a930649d0552d0c1b8b85f642d7ddb32415113f8fa9f85740cb1e2f8aaba",
    "Vorbisfile": "7a52e25f6b7c6ee69241c75c8ffbdacf6d9b70869f68c53fd5f958759543bc03",
    "Vpx": "178e7daeb7ecc5e58386743e1b63f4ad18c7ac965fcc442209b942023dc115b8",
    "X264": "37ee953d263c41e5487b6010f87a7b87b2eb692931eb4f213e31b09a0f894504",
    "Xml2": "df6af001a7f6933e2ccabe26c49a3ed073e692c1bf5b5bbe01c1aaa122201314"
]
let libmpvProductTargets: [String] = ["media_kit_libs_ios_video"] + libmpvTargets

let package = Package(
    name: "media_kit_libs_ios_video",
    platforms: [
        .iOS("9.0")
    ],
    products: [
        .library(name: "media-kit-libs-ios-video", targets: libmpvProductTargets),
        .library(name: "Mpv", targets: ["Mpv"])
    ],
    dependencies: [],
    targets: libmpvTargets.map { framework in
        .binaryTarget(
            name: framework,
            url: "\(libmpvArtifactBase)_\(framework).zip",
            checksum: libmpvChecksums[framework]!
        )
    } + [
        .target(
            name: "media_kit_libs_ios_video",
            dependencies: libmpvTargets.map { framework in .target(name: framework) },
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
