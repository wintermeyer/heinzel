# Contributing

Bug reports, ideas and pull requests are welcome.

- Heinzel is MIT. A contribution may also end up in
  [Heinzel Pro](https://heinzel-pro.de), the commercial
  product built on these rules, under its own licence.
  Open a pull request only if that is fine with you.
- Rule files wrap at 80 characters, except code
  blocks.
- A change to `.claude/hooks/guard-taboos.sh` needs
  lines in `guard-taboos-test.sh`: one per effect
  blocked, one for the read-only form that stays
  allowed, one through a language runtime, one inside
  `ssh host "…"`. CI runs the matrix.
- A new operating system is one file in `rules/`
  with the sections `bin/heinzel-lint-rules` lists,
  one row in `rules/os-detection.md` and one in the
  README. The other rule files point to those
  sections by name: do not add a branch per OS to
  them. CI runs the lint.
- Never copy a file or text from `pro/` or from
  somebody's extension into a pull request: they are
  not MIT. CI rejects a file with Heinzel Pro's
  licence header and anything tracked under `pro/`
  or `extensions/`. A change to
  `bin/heinzel-extension` needs a case in
  `bin/heinzel-extension-test`.
- In the guard, a rule is either a safety rule
  (`deny`) or Heinzel Pro's work (`deny_pro
  <feature>`). The test matrix counts both; a new
  rule changes one of the two numbers there.
- A rule names the effect it guards against, never a
  list of binaries. See the head of the hook for why.
