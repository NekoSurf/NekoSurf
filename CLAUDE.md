# Notes for Claude

## Commits

- Author every commit as the maintainer, with Claude only as co-author:
  `git commit --author='wrngwrld <Marvin.Jaeckisch1@web.de>'`.
- Leave the committer as Claude (`Claude <noreply@anthropic.com>`), so
  GitHub shows the signed commit as Verified. Don't use `--reset-author`,
  which would make Claude the author.
- End the message with the `Co-Authored-By: Claude ...` line.

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
