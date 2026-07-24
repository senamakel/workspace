# Cross-host tmux and tooling parity implementation plan

## Contract

Implement the approved design in
`docs/specs/2026-07-24-cross-host-tmux-parity-design.md`. Preserve Robot1's
dirty workflow repositories and all machine-local credentials. Run the
installer only from each primary checkout.

## Task 1: Manage the shared tmux configuration

- Add `tmux.conf` with the local/master `C-b` prefix, mouse support, focus
  events, clipboard integration, passthrough, pane titles, dimmed inactive
  panes, and expanded history.
- Link `tmux.conf` to `~/.tmux.conf` from `install.sh` through the existing
  backup-aware `link` helper.
- Validate shell syntax, installer dry-run output, skill and agent generation,
  and whitespace.
- Commit `tmux.conf` and `install.sh` atomically.

## Task 2: Validate existing remote-launcher changes

- Confirm `workspace-tmux` retains `C-z` for its dedicated remote server and
  selects blue, purple, or red accents for Mac mini, Dragonfly, and Robot1.
- Confirm `super-review` launches all three remote hosts through the managed
  `~/bin/mosh-tmux` entrypoint.
- Run the focused workspace bootstrap test and shell syntax checks.

## Task 3: Deploy workspace configuration and agents

- Fast-forward the primary local checkout to the feature branch and run its
  installer.
- Transfer the exact commit to Dragonfly, Mac mini, and Robot1 without using
  GitHub as an intermediary.
- Run `install.sh` from each primary checkout and `workspace-init` where the
  managed launcher link is missing.
- Verify 15 source agents, 15 generated Claude agents, 15 generated Codex
  agents, and 15 installed links for each harness.

## Task 4: Move Robot1 CLIs to user ownership

- Install NVM and Node 24 for `droid`.
- Install current Codex and Claude npm packages through the NVM-managed npm.
- Verify the resolved commands and targets are owned by `droid` and update
  without sudo.
- Remove only the unambiguously identified root-owned npm installations through
  `/usr/bin/npm`; do not alter unrelated system packages.

## Task 5: Activate and verify live sessions

- Reload `~/.tmux.conf` into the local default server.
- Recreate the dedicated `mosh` workspace server on Mac mini, Dragonfly, and
  Robot1, then reconnect each outer `super-review` pane.
- Verify the local prefix is `C-b`; remote prefixes are `C-z`; mouse, focus,
  clipboard, passthrough, pane styling, and history match the contract.
- Verify Dragonfly is purple, Robot1 is red, and every remote workflow window
  is three columns by two rows.
- Compare Robot1's workflow status snapshot byte-for-byte with the pre-change
  snapshot.
