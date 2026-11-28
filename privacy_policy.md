# Privacy Policy

_Last updated: 28 November 2026_

NekoSurf is a free, open-source app for reading 4chan, made by wrngwrld. This policy explains what the app does with your data. In short:

- There's no account, no ads, no analytics and no tracking.
- The app sends nothing to the developer.
- What you favorite, bookmark, read and save stays on your phone, and in your own iCloud account if you turn on iCloud sync.

## What stays on your phone

NekoSurf keeps these on your phone only:

- Your settings, favorite boards, bookmarks and the filters you set to hide threads and posts
- The threads you've visited (you can turn this off in Settings → History → Track history, or keep them only while the app is open) and, for each thread, the posts you've already seen or not yet, where you left off, what you folded and what you hid (watched posts)
- A copy of the text of each thread you've bookmarked or visited, as it last loaded, so it still opens without a connection or once it's deleted. It goes when the thread leaves your bookmarks and history (or, for a thread saved for offline, when you remove it)
- The text, images and videos of threads you save for offline, in a folder only the app can see, until you remove them
- What you save to the Saved tab: on iPhone in the app's folder, which you can see in the Files app, and on Android in Download/4Chan; or, with Settings → Privacy → Keep saved files in the app turned on, in a folder only the app can see
- Images and videos you've viewed, cached so they load faster the next time
- Which of 4chan's boards are NSFW, from 4chan's board list, so they stay hidden while it loads
- A backup you make with Settings → Backup → Back up to a file goes where you choose to keep it, such as the Files app
- If you use iCloud sync, a log of what it did lately: when it sent and fetched, how many of each kind of thing (not what they are) and what iCloud answered. It leaves your phone only if you share it from Settings → iCloud sync → Sync log

## What leaves your phone

To work, the app connects to these services. Like any website you visit, they receive your IP address and basic technical details about the request:

- **4chan**, to load boards, threads, images and videos. NekoSurf only reads from 4chan; it doesn't post. 4chan's own policies apply to what it receives.
- **find.4chan.org**, only when you search all of 4chan. It's protected by Cloudflare, so the search runs in a browser view inside the app, which completes Cloudflare's check and keeps its cookie for later searches.
- **Your iCloud account**, on iPhone and iPad with NekoSurf from TestFlight, when you turn on iCloud sync in NekoSurf's Settings: NekoSurf keeps your saved media, favorite boards, bookmarks, the threads you've visited (unless you keep them only while the app is open) and your watched posts (what you've seen in each, where you left off, what you folded and hid), your thread and post filters and most of your settings in your private iCloud database (CloudKit), so they're the same on your other devices with iCloud sync on. Apple lets the app know by a silent notification when something changed on another device; nothing is shown and no permission is asked for. It goes to your own Apple account, not to the developer, counts toward your iCloud storage, and [Apple's privacy policy](https://www.apple.com/legal/privacy/) applies. It's off until you turn it on. Turning it off in NekoSurf's Settings lets you keep that data in iCloud or delete it; you can also delete it there at any time, or in your iPhone's Settings → your name → iCloud → Storage → NekoSurf.
- **GitHub**, to check whether a newer version of the app is out. This request carries nothing about you or how you use the app. [GitHub's privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement) applies.

Only when you choose them:

- **Reverse image search** opens Google Lens, Bing, Yandex or SauceNAO in your browser with the address of the image you picked. That service's privacy policy applies.
- **Links** you open go to your browser.
- **Look in archives**, on a thread 4chan has deleted, asks the archives that keep its board whether they have it, all at once: Desuarchive (desuarchive.org), b4k (arch.b4k.dev), Palanq (archive.palanq.win), Archive of Sins (archiveofsins.com), TheBArchive (thebarchive.com), 4plebs (archive.4plebs.org), warosu (warosu.org) and, last, archived.moe. They're run by others, not by 4chan or the developer. They receive the board and the thread's number, and the thread's images and videos then load from the archive's image server. archived.moe is protected by Cloudflare, so it's asked in a browser view inside the app, which completes Cloudflare's check and keeps its cookie for later, as for find.4chan.org. While looking, at most once a week, the app also asks them which boards they keep. Each can be turned off in Settings → Archives, and one that's off is never contacted. Their own policies apply.

## Permissions

- **On iPhone**, the app asks to add to your photo library when you first save something to Photos. It can only add; it can't see your photos.
- **On Android**, the app asks for storage access to keep the Saved tab's files in Download/4Chan (not if you keep them out of Download), and on Android 9 and older also to save to your gallery. If you choose a download folder for Save to Photos (Settings → Media → Download folder), Android's folder picker lets the app into that folder only, to save there, until you choose another or go back to Pictures and Movies.
- The app doesn't use your camera, microphone, contacts or location.

## How you got the app

- **TestFlight:** Apple runs TestFlight and may share crash reports, usage numbers such as installs and sessions, and any feedback you send through TestFlight with the developer. [Apple's privacy policy](https://www.apple.com/legal/privacy/) applies.
- **GitHub, AltStore, SideStore and similar:** the app and its source listing are downloaded from GitHub. [GitHub's privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement) applies.

## Deleting your data

- In **Settings → Storage**, clear the cache of images and videos, and remove threads saved for offline (also in Bookmarks → More → Saved for offline, or from the thread's menu).
- On the **History** page, clear the threads you've visited, with the copies kept of them. Watched posts are forgotten a week after you last opened the thread.
- In the **Saved tab**, delete what you've saved.
- **Uninstalling** the app deletes everything it stored, except what you saved to Photos, your gallery or your download folder, on Android the Download/4Chan folder (if you kept saved files there), any backup files you kept, and what iCloud sync keeps in your iCloud account (delete it in NekoSurf's Settings or your iPhone's iCloud settings).

## Children

NekoSurf shows 4chan, which is for adults. The app isn't meant for anyone under 18.

## Changes

When this policy changes, the new version is published here with a new date at the top. Earlier versions are in the [repository's history](https://github.com/NekoSurf/NekoSurf/commits/main/privacy_policy.md).

## Contact

Questions about this policy: [Marvin.Jaeckisch1@web.de](mailto:Marvin.Jaeckisch1@web.de), or [open an issue](https://github.com/NekoSurf/NekoSurf/issues).
