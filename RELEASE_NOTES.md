## What's new

### 💾 Save several at once
- Saving, saving to Photos and removing now work per post: start saving one, swipe on and save the next while the first is still going
- Each post keeps its own spinner and checkmark, and a save in progress still shows if you close and reopen the viewer
- While saving, downloading or sharing, the button shows a ring filling up as the file downloads and, for webms on iPhone, as it's converted to mp4
- Sharing still goes one at a time; while one is being prepared, the share button is dimmed on the others

## What's fixed

- Saving or sharing a video that's still loading waits for that download instead of starting a second one, so it's much faster, and it no longer hangs on a stalled connection
- Saves that run into 4chan limiting requests try again instead of failing
- Two files with the same name saved at once no longer overwrite each other
- When saving to the Saved tab or sharing fails, the app says so instead of the spinner just stopping
- A failed save no longer leaves its file behind in Files (or Download/4Chan on Android)
- The spinner on the save, download and share buttons is easy to see on bright images and videos
- On iPhone, webms with an odd width or height (like 853×480) lose one row or column of pixels when converted, since H.264 can't store odd sizes
- Saved files with ".webm" in the middle of their name can be shared and saved to Photos
- Sharing a saved file that's no longer there no longer leaves the share button spinning
