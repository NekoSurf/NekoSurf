# Notes for Claude

## Commits

- Author every commit as the maintainer, with Claude only as co-author:
  `git commit --author='wrngwrld <Marvin.Jaeckisch1@web.de>'`.
- Leave the committer as Claude (`Claude <noreply@anthropic.com>`), so
  GitHub shows the signed commit as Verified. Don't use `--reset-author`,
  which would make Claude the author.
- End the message with the `Co-Authored-By: Claude ...` line.
