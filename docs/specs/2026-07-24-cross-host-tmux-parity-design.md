# Cross-host tmux and tooling parity

## Goal

Manage the common tmux experience from the workspace repository and align the
Dragonfly and Robot1 cloud hosts with the existing workstation setup. The
deployment must preserve machine-local credentials and dirty workflow
checkouts.

## tmux configuration

The repository will contain one canonical `tmux.conf`. `install.sh` will link
it to `~/.tmux.conf`, using the installer's existing backup behavior for a
conflicting file.

The shared configuration will enable:

- mouse-based window and pane selection, resizing, and scrolling;
- focus events and terminal clipboard integration;
- passthrough for nested terminal applications;
- a dark inactive-pane background and terminal-native active-pane background;
- pane titles; and
- a large scrollback history.

The local default tmux server, which hosts the master `super-review` session,
will retain tmux's `Ctrl-b` prefix. The dedicated remote `mosh` tmux servers on
Mac mini, Dragonfly, and Robot1 will override the prefix to `Ctrl-z` through
`workspace-tmux`. This avoids a prefix collision between the outer and inner
sessions.

Terminal-window transparency is outside tmux's control and remains a setting of
the terminal application. The shared inactive-pane styling provides the tmux
equivalent of visual dimming.

## Host identity

`workspace-tmux` will retain a distinct accent per remote host:

- Mac mini and unspecified hosts: blue;
- Dragonfly: purple; and
- Robot1 cloud: red.

All hosts otherwise use the same five six-pane workflow windows, `btop` window,
shell window, mouse behavior, pane styling, and `Ctrl-z` remote prefix.

## Workspace and agent deployment

The current workspace commit will be transferred directly to Dragonfly and
Robot1 without publishing it to GitHub. On each host, `install.sh` will render
the canonical `agents/<name>` sources into native Claude and Codex agent files
and link them into both harnesses. Verification will compare source, generated,
and installed agent counts and confirm that the links resolve.

Robot1's existing workflow repositories will not be pulled, reset, cleaned, or
otherwise normalized. In particular, modified submodule pointers in its
workflow checkouts are user state and must remain untouched.

## User-owned command-line tools

Dragonfly's existing NVM, Node 24, Codex, and Claude installations are already
user-owned and will only be verified.

Robot1 will receive NVM and Node 24 under the `droid` account. Codex and Claude
will be installed as NVM-managed global packages, and the shell will resolve
those user-owned installations before the existing root-owned `/usr/bin`
copies. After both user-owned commands are verified, the two root-owned npm
packages will be uninstalled explicitly through `/usr/bin/npm`. Successful
future updates must not require sudo.

Ollama and model downloads are excluded from Robot1 parity because the host has
no GPU. They can be installed separately if CPU inference is wanted.

## Activation and verification

The installer will be run from each primary workspace checkout. Existing tmux
servers will reload the shared configuration where possible. Dedicated remote
workspace servers will be recreated so layout, prefix, and host colors take
effect.

Verification will cover:

- shell syntax and installer dry-run behavior;
- generated Claude and Codex agent validation;
- local master prefix `C-b`;
- remote prefixes `C-z`;
- mouse, focus, clipboard, passthrough, and pane-style option values;
- Dragonfly purple and Robot1 red status and border colors;
- three-column by two-row geometry in every remote workflow window;
- user-owned Node 24, Codex, and Claude resolution on Robot1; and
- unchanged dirty-state output for Robot1's workflow repositories.
