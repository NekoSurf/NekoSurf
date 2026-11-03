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

2. **Build**, anywhere with Python's Pillow and ffmpeg:

   ```sh
   python3 promo/build.py
   ```

   It puts each screen in an iPhone frame on the app's cyan-to-violet
   background, and writes to `screenshots/`:

   | File | Used for |
   |---|---|
   | `banner.png` | The top of the README: three phones side by side |
   | `demo.gif` | The README: the recording, small enough to load quickly |
   | `demo.mp4` | The website: the recording, full quality |
   | `phone-<shot>.png` | The website: each screen in a phone, on a transparent background |

When the app's look changes, capture again and rebuild.
