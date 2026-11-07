#!/usr/bin/env python3
"""Turns the simulator captures in promo/raw/ into the promo images and video.

Run with uv, which installs what it needs into promo/.venv (ffmpeg is needed too):

    uv run --project promo promo/build.py             # everything
    uv run --project promo promo/build.py board demo  # only what these show in

Name shots (home, board, thread, gallery, search), demo or banner to remake
only what uses them: a shot in the banner remakes the banner too.

It writes to screenshots/:

- banner.png: three phones side by side, for the top of the README
- phone-<shot>.png: each screenshot in a phone, on a transparent
  background, for the website
- demo.gif: the recording in a phone on the background, small enough for
  the README

and to docs/, the website, which GitHub Pages serves (GitHub's raw files
come as a download type Safari won't play):

- demo.mp4: the same recording, full quality

The phone is drawn here (a generic modern iPhone: rounded body, thin rim,
Dynamic Island), so no device artwork needs licensing.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import imagequant
from PIL import Image, ImageChops, ImageDraw, ImageFilter

# The app's accent colors (DashColors.accent and accent2).
CYAN = (0x6D, 0xD4, 0xEC)
VIOLET = (0xA7, 0x8B, 0xFA)
BODY = (12, 12, 16)
RIM = (58, 61, 74)

# promo/, so the defaults work from any directory.
PROMO = Path(__file__).resolve().parent

# Which screenshots go where; promo/capture.sh takes them under these names.
BANNER_SHOTS = ("home", "board", "thread")
SHOTS = ("home", "board", "thread", "gallery", "search")
RECORDING = "demo"
BANNER = "banner"

# The README's GIF: GitHub shows it at most ~440 px wide, and it should load
# quickly on a phone.
GIF_WIDTH = 420
GIF_FPS = 12
GIF_MAX_SECONDS = 16

# Drawn larger and scaled down, for smooth edges.
SUPERSAMPLE = 3


def gradient(size: tuple[int, int]) -> Image.Image:
    """The background: cyan in the top left to violet in the bottom right,
    with a soft light in the top left."""
    w, h = size
    # Diagonal: the average of a left-to-right and a top-to-bottom ramp.
    down = Image.linear_gradient("L").resize((w, h), Image.BILINEAR)
    across = Image.linear_gradient("L").rotate(90).resize((w, h), Image.BILINEAR)
    ramp = ImageChops.add(down.point(lambda v: v // 2), across.point(lambda v: v // 2))
    bg = Image.composite(Image.new("RGB", size, VIOLET), Image.new("RGB", size, CYAN), ramp)
    # A blurred ellipse fades out by itself, with no edge to show.
    mask = Image.new("L", size, 0)
    r = max(w, h) * 0.42
    ImageDraw.Draw(mask).ellipse((-r * 0.6, -r * 0.8, r * 1.2, r * 0.8), fill=90)
    mask = mask.filter(ImageFilter.GaussianBlur(max(w, h) * 0.12))
    return Image.composite(Image.new("RGB", size, (255, 255, 255)), bg, mask)


def rounded_mask(size: tuple[int, int], radius: float) -> Image.Image:
    """An anti-aliased rounded rectangle, white on black."""
    w, h = size
    big = Image.new("L", (w * SUPERSAMPLE, h * SUPERSAMPLE), 0)
    ImageDraw.Draw(big).rounded_rectangle(
        (0, 0, w * SUPERSAMPLE - 1, h * SUPERSAMPLE - 1),
        radius=radius * SUPERSAMPLE,
        fill=255,
    )
    return big.resize((w, h), Image.LANCZOS)


class Phone:
    """The frame's geometry for a screen of a given size, in pixels."""

    def __init__(self, screen: tuple[int, int]):
        sw, sh = screen
        self.screen = screen
        self.bezel = round(sw * 0.035)
        self.radius = sw * 0.137
        self.size = (sw + 2 * self.bezel, sh + 2 * self.bezel)
        self.island = (round(sw * 0.31), round(sw * 0.092))
        self.island_top = round(sw * 0.027)

    def body(self) -> Image.Image:
        """The phone without its screen: body, rim and Dynamic Island, with
        the screen area transparent."""
        w, h = self.size
        b = self.bezel
        outer = rounded_mask(self.size, self.radius + b)
        rim_inner = rounded_mask(
            (w - 2 * max(1, b // 6), h - 2 * max(1, b // 6)),
            self.radius + b - max(1, b // 6),
        )
        frame = Image.new("RGBA", self.size, RIM + (0,))
        frame.putalpha(outer)
        inner = Image.new("RGBA", self.size, BODY + (0,))
        inner_alpha = Image.new("L", self.size, 0)
        inner_alpha.paste(rim_inner, (max(1, b // 6), max(1, b // 6)))
        inner.putalpha(inner_alpha)
        frame = Image.alpha_composite(frame, inner)
        # Cut the screen out.
        hole = Image.new("L", self.size, 0)
        hole.paste(rounded_mask(self.screen, self.radius), (b, b))
        frame.putalpha(ImageChops.subtract(frame.getchannel("A"), hole))
        # The Dynamic Island, over the screen.
        iw, ih = self.island
        island = Image.new("RGBA", self.size, BODY + (0,))
        island_alpha = Image.new("L", self.size, 0)
        island_alpha.paste(rounded_mask(self.island, ih / 2), ((w - iw) // 2, b + self.island_top))
        island.putalpha(island_alpha)
        return Image.alpha_composite(frame, island)

    def screen_mask(self) -> Image.Image:
        return rounded_mask(self.screen, self.radius)


def framed(shot: Image.Image) -> Image.Image:
    """[shot] in a phone, on a transparent background."""
    phone = Phone(shot.size)
    out = Image.new("RGBA", phone.size, (0, 0, 0, 0))
    screen = shot.convert("RGBA")
    screen.putalpha(phone.screen_mask())
    out.paste(screen, (phone.bezel, phone.bezel), screen)
    return Image.alpha_composite(out, phone.body())


def shadow(phone: Image.Image, blur: int, opacity: float) -> Image.Image:
    alpha = phone.getchannel("A").point(lambda v: v * opacity)
    pad = blur * 3
    canvas = Image.new("L", (phone.width + 2 * pad, phone.height + 2 * pad), 0)
    canvas.paste(alpha, (pad, pad))
    return canvas.filter(ImageFilter.GaussianBlur(blur))


def place(canvas: Image.Image, phone: Image.Image, center_x: int, top: int) -> None:
    """Pastes [phone] with a soft shadow below it."""
    blur = max(8, phone.width // 14)
    sh = shadow(phone, blur, 0.45)
    pad = blur * 3
    x = center_x - phone.width // 2
    canvas.paste((10, 10, 30), (x - pad, top - pad + blur), sh)
    canvas.alpha_composite(phone, (x, top))


def save_small(image: Image.Image, out: Path) -> None:
    """Saves with a palette of 256 colors, between half and a third of the size,
    which the eye barely notices. libimagequant keeps small vivid details like a red
    heart, and its dithering keeps gradients from showing bands; Pillow's own
    palettes lose both."""
    imagequant.quantize_pil_image(image.convert("RGBA"), dithering_level=1.0, max_colors=256).save(out, optimize=True)


def banner(shots: list[Image.Image], out: Path) -> None:
    """Three phones side by side, the middle one larger and in front."""
    w, h = 2400, 1260
    canvas = gradient((w, h)).convert("RGBA")
    phones = [framed(s) for s in shots]
    side_h, middle_h = round(h * 0.80), round(h * 0.90)

    def scaled(p: Image.Image, height: int) -> Image.Image:
        return p.resize((round(p.width * height / p.height), height), Image.LANCZOS)

    left, middle, right = scaled(phones[0], side_h), scaled(phones[1], middle_h), scaled(phones[2], side_h)
    gap = round(middle.width * 0.62)
    place(canvas, left, w // 2 - gap - middle.width // 2, round(h * 0.12))
    place(canvas, right, w // 2 + gap + middle.width // 2, round(h * 0.12))
    place(canvas, middle, w // 2, round(h * 0.05))
    save_small(canvas.convert("RGB"), out)


def single(shot: Image.Image, out: Path, height: int = 1600) -> None:
    phone = framed(shot)
    phone = phone.resize((round(phone.width * height / phone.height), height), Image.LANCZOS)
    save_small(phone, out)


def run(args: list[str]) -> None:
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)


def probe(path: Path) -> tuple[int, int, float]:
    """[path]'s width, height and length in seconds."""
    def ask(entries: str, stream: bool) -> str:
        return subprocess.run(
            ["ffprobe", "-v", "error", *(["-select_streams", "v:0"] if stream else []),
             "-show_entries", entries, "-of", "csv=p=0", str(path)],
            check=True, capture_output=True, text=True,
        ).stdout.strip()

    w, h = ask("stream=width,height", True).split(",")[:2]
    return int(w), int(h), float(ask("format=duration", False))


def demo(recording: Path, out_mp4: Path, out_gif: Path) -> None:
    """The recording in a phone on the background: an MP4, and a GIF from it."""
    rw, rh, seconds = probe(recording)
    # 4:5, the phone filling most of the height.
    cw, ch = 1080, 1350
    screen_h = round(ch * 0.86) - 2 * round(ch * 0.86 * 0.035 * rw / rh)
    screen = (round(screen_h * rw / rh) // 2 * 2, screen_h // 2 * 2)
    phone = Phone(screen)
    x, y = (cw - phone.size[0]) // 2, (ch - phone.size[1]) // 2

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        bg = gradient((cw, ch)).convert("RGBA")
        blur = max(8, phone.size[0] // 14)
        pad = blur * 3
        silhouette = Image.new("RGBA", phone.size, (0, 0, 0, 255))
        silhouette.putalpha(rounded_mask(phone.size, phone.radius + phone.bezel))
        bg.paste((10, 10, 30), (x - pad, y - pad + blur), shadow(silhouette, blur, 0.45))
        bg.convert("RGB").save(tmp / "bg.png")
        phone.screen_mask().save(tmp / "mask.png")
        body = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
        body.alpha_composite(phone.body(), (x, y))
        body.save(tmp / "body.png")

        sx, sy = x + phone.bezel, y + phone.bezel
        graph = (
            f"[1:v]fps=30,scale={screen[0]}:{screen[1]}:flags=lanczos,format=rgba[rec];"
            "[2:v]format=gray[m];[rec][m]alphamerge[screen];"
            f"[0:v][screen]overlay={sx}:{sy}:shortest=1[withscreen];"
            "[withscreen][3:v]overlay=0:0,format=yuv420p[out]"
        )
        # Each still repeats only as long as the recording, or the graph would
        # wait for more of them forever.
        still = ["-loop", "1", "-framerate", "30", "-t", f"{seconds:.3f}", "-i"]
        run(["ffmpeg", "-y", *still, str(tmp / "bg.png"), "-i", str(recording),
             *still, str(tmp / "mask.png"), *still, str(tmp / "body.png"),
             "-filter_complex", graph, "-map", "[out]", "-an",
             "-c:v", "libx264", "-preset", "slow", "-crf", "20", "-movflags", "+faststart",
             str(out_mp4)])

        gif = (
            f"fps={GIF_FPS},scale={GIF_WIDTH}:-2:flags=lanczos,split[a][b];"
            "[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle"
        )
        run(["ffmpeg", "-y", "-t", str(GIF_MAX_SECONDS), "-i", str(out_mp4), "-vf", gif, str(out_gif)])


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__.splitlines()[0],
        epilog="With no names, makes everything.",
    )
    parser.add_argument(
        "names",
        nargs="*",
        metavar="name",
        help=f"what to remake: {', '.join((*SHOTS, RECORDING, BANNER))}",
    )
    parser.add_argument("--raw", type=Path, default=PROMO / "raw")
    parser.add_argument("--out", type=Path, default=PROMO.parent / "screenshots")
    parser.add_argument("--site", type=Path, default=PROMO.parent / "docs")
    args = parser.parse_args()

    unknown = sorted(set(args.names) - {*SHOTS, RECORDING, BANNER})
    if unknown:
        parser.error(f"unknown: {', '.join(unknown)}. Choose from {', '.join((*SHOTS, RECORDING, BANNER))}.")

    wanted = set(args.names) or {*SHOTS, RECORDING, BANNER}
    singles = [s for s in SHOTS if s in wanted]
    make_banner = BANNER in wanted or bool(wanted & set(BANNER_SHOTS))
    make_demo = RECORDING in wanted

    # Only what's being made has to be there.
    needed = {*singles, *(BANNER_SHOTS if make_banner else ())}
    missing = [f"{s}.png" for s in SHOTS if s in needed and not (args.raw / f"{s}.png").exists()]
    recording = None
    if make_demo:
        recording = next((p for p in args.raw.glob(f"{RECORDING}.*") if p.suffix.lower() in (".mp4", ".mov")), None)
        if recording is None:
            missing.append(f"{RECORDING}.mp4")
    if missing:
        print(f"Missing in {args.raw}: {', '.join(missing)}. Take them with promo/capture.sh.", file=sys.stderr)
        return 1
    if make_demo and not shutil.which("ffmpeg"):
        print("ffmpeg is needed for the video.", file=sys.stderr)
        return 1

    args.out.mkdir(parents=True, exist_ok=True)
    args.site.mkdir(parents=True, exist_ok=True)
    shots = {s: Image.open(args.raw / f"{s}.png") for s in needed}
    made = []
    if make_banner:
        banner([shots[s] for s in BANNER_SHOTS], args.out / "banner.png")
        made.append(args.out / "banner.png")
    for name in singles:
        single(shots[name], args.out / f"phone-{name}.png")
        made.append(args.out / f"phone-{name}.png")
    if make_demo:
        demo(recording, args.site / "demo.mp4", args.out / "demo.gif")
        made += [args.out / "demo.gif", args.site / "demo.mp4"]

    for f in made:
        print(f"{f}  {f.stat().st_size / 1e6:.1f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
