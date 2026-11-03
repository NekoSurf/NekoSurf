## What's new

### 💾 Save several at once
- Saving to the Saved tab, saving to Photos and removing work per post: start saving one, swipe on and save the next while the first is still going
- Each post keeps its own spinner and checkmark, and a save in progress still shows if you close and reopen the viewer
- Sharing still goes one at a time; while one is being prepared, the share button is dimmed on the others

### ⏳ See how far along it is
- Saving and sharing show a ring that fills up as the file downloads and, for webms on iPhone, as it's converted to mp4

## What's fixed

- Saving or sharing a video that's still loading uses that download instead of starting a second one, so it's much faster, and it no longer hangs on a stalled connection
- Saves that run into 4chan limiting requests try again instead of failing
- The spinner on the save and share buttons is easy to see on bright images and videos
- When saving to the Saved tab or sharing fails, the app says so instead of the spinner just stopping
- A failed save to the Saved tab no longer leaves its file behind in Files (or Download/4Chan on Android)
- Two files with the same name saved at once no longer overwrite each other
- Files with very long names, like long Japanese ones, can be saved and shared; their names are shortened to what the phone allows
- Saved files with ".webm" in the middle of their name can be shared and saved to Photos
- Sharing a saved file that's no longer there no longer leaves the share button spinning
- On iPhone, webms with an odd width or height (like 853×480) are trimmed by one row or column of pixels when converted, as H.264 needs even sizes
