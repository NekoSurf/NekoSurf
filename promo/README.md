# Promo images and video

The README's banner and demo, and the website's images, are made from the
app's own screens in two steps.

1. **Capture**, on a Mac with Xcode and Flutter:

   ```sh
   promo/capture.sh
   ```

   It boots an iPhone simulator in dark mode with a clean status bar,
   installs the app, and takes the screenshots and the screen recording one
   by one, saying what to put on screen for each. They go to `promo/raw/`;
   commit them. Run it with shot names (`promo/capture.sh board demo`) to
   retake only those.

2. **Build**, anywhere with [uv](https://docs.astral.sh/uv/) and ffmpeg
   (`brew install uv ffmpeg`):

   ```sh
   uv run --project promo promo/build.py
   ```

   uv fetches the Python and Pillow versions pinned in `promo/` into
   `promo/.venv`, so nothing is installed system-wide. From inside `promo/`,
   `uv run build.py` does the same.

   It puts each screen in an iPhone frame on the app's cyan-to-violet
   background, and writes:

   | File | Used for |
   |---|---|
   | `screenshots/banner.png` | The top of the README, and link previews of the website: three phones side by side |
   | `screenshots/demo.gif` | The README: the recording, small enough to load quickly |
   | `screenshots/phone-<shot>.png` | The website: each screen in a phone, on a transparent background |
   | `docs/demo.mp4` | The website: the recording, full quality. It lives in `docs/` because GitHub Pages serves it as a video, while GitHub's raw files come as a download type Safari won't play |

When the app's look changes, capture again and rebuild.
