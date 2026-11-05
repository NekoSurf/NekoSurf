# Notes for Claude

## Commits

- Author every commit as the maintainer, with Claude only as co-author:
  `git commit --author='wrngwrld <Marvin.Jaeckisch1@web.de>'`.
- Leave the committer as Claude (`Claude <noreply@anthropic.com>`), so
  GitHub shows the signed commit as Verified. Don't use `--reset-author`,
  which would make Claude the author.
- End the message with the `Co-Authored-By: Claude ...` line.
- Commit straight on `main`, without a branch, and don't push: the maintainer
  does. Only commit when asked.

### Keeping the history readable

The commits since the last push should read as a list of what changed, so each
one is a feature or fix as a user would name it, not a step in building it.
Every time you're asked to commit, first compare with what's unpushed:

```sh
git log --stat origin/main..HEAD
```

- A change that revises an unpushed feature goes into that feature's commit, so
  nothing is added and later undone. A new feature or fix gets its own commit.
- Combine or split unpushed commits when that reads better, without being asked,
  and say what you did. Never rewrite what's already been pushed.
- A commit carries its own tests, docs and release-note lines.
- Regrouping must not change the code: before starting, keep a backup ref
  (`git update-ref refs/backup/before-regroup HEAD`), and afterwards check that
  the final tree is the same as the work you started from. Each new or rewritten
  commit should pass `flutter analyze` and `flutter test` on its own.
- Update the message of a commit you change, so it's still true.

## Keeping the docs up to date

Before finishing any change, check whether it makes something in these
files untrue or incomplete, and update them in the same piece of work (or
say why they don't need it). Check each claim against the code, as with
the release notes.

- `README.md`, the front page: what the app does (in the user's words,
  short), how to get it (the TestFlight, AltSource and download links, and
  the release file names they point to, like `app-arm64-v8a-release.apk`
  and `Runner.ipa`), and how to build it (the Flutter version is
  `FLUTTER_VERSION` in `.github/workflows/checks.yml` and `_build.yml`).
- `docs/index.html`, the website: the same as the README, plus any
  version or release it names.
- The promo images in `screenshots/` and the video in `docs/demo.mp4`:
  when a change makes the app look noticeably different, say they need
  new captures, taken with `promo/capture.sh` on a Mac (see
  `promo/README.md`), and rebuild them.
- `privacy_policy.md`, a legal text: what the app keeps on the phone,
  every service it connects to, the permissions it asks for, and anything
  that sends data off the phone (analytics, crash reporting, a new SDK or
  package). Look for:
  - new hosts: `grep -rhoE "https?://[a-zA-Z0-9.-]+" lib | sort -u`
  - permission requests in `lib` (`Permission.`), and the declarations in
    `ios/Runner/Info.plist` and `android/app/src/main/AndroidManifest.xml`
  - new dependencies in `pubspec.yaml`

  When it changes, update its "Last updated" date, and say what changed
  when you report back.

## Release notes

A release is made by running the Prepare Release workflow
(`.github/workflows/prepare_release.yml`), which only asks for the version
(e.g. `0.12.2`); the build number is worked out, and the release is titled
with its tag (`v0.12.2+296`). What the release says comes from three files
in the repository root, committed to `main` before it runs. The release
commit deletes them, so after a release they don't exist: create them
again for the next one.

Keep them up to date as you go: when a change is something users notice,
add it in the same commit (or right after), creating the files if they're
gone. To check they cover everything, compare with the commits since the
last release (clones may come without tags, so fetch them first):

```sh
git fetch --tags origin
git log "$(git describe --tags --abbrev=0 --match 'v*+*' main)"..main
```

### RELEASE_NOTES.md: the GitHub release description

Markdown, for users, in this shape:

```markdown
## What's new

### 💾 A heading per feature, with an emoji
- What it does for the user, in a sentence

## What's fixed

- What works now that didn't, most noticeable first
```

- Write what the user sees, not how it's done: no class names, commits,
  or library names, and nothing about tests or refactors.
- Say only what's true: check each line against the code. Name where it
  applies when it isn't everywhere (e.g. "on iPhone", "in the Saved tab").
- Use the app's names for things consistently (the Saved tab, saving to
  Photos, the share button, the back icon).
- Something that fixes a problem made earlier in the same release isn't a
  fix for users; fold it into the feature's line instead.
- Optional for the workflow (it falls back to RELEASE_SUMMARY.txt), but
  write it for every release.

### RELEASE_SUMMARY.txt: the one-line summary

- Exactly one line; the workflow stops if it's missing or longer. It's
  AltStore's description of the version (in `source.json`), and stands in
  for the other two files when they're missing.
- One sentence naming the release's main changes, like the earlier ones in
  `source.json`, e.g. "Save and share several posts at once, with a ring
  showing how far along each is; saving is faster and more reliable, and
  going back from a thread no longer brings up the keyboard."

### WHAT_TO_TEST.txt: TestFlight's "What to Test"

- Plain text: TestFlight shows Markdown as typed. Line breaks, blank lines
  and `•` bullets are fine. At most 4000 characters (the workflow checks).
- Tell testers what to try and what they should see, as steps they can
  follow, grouped by feature, e.g. "Type in a search field, open a thread,
  tap the back icon: the keyboard should stay down".
- Include what couldn't be checked without a phone (behavior on a real
  device, in the background, on a slow connection), so testers cover it.
- The release commit writes it to `ios/TestFlight/WhatToTest.en-US.txt`,
  which Xcode Cloud reads; don't edit that file directly.
