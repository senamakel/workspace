# Workspace Bootstrap and Tmux Design

## Purpose

This repository will become the source of truth for:

- initializing the TinyHumans workflow checkout set on a Mac;
- launching the persistent remote tmux workspace used through
  `enamakel@mac-mini`; and
- launching the existing local `super-review` tmux dashboard.

The bootstrap is intentionally conservative. It creates missing repositories
but never updates, resets, or otherwise modifies an existing destination.

## Components

### `bin/workspace-init`

`workspace-init` runs locally on the machine being initialized. It does not SSH
to another host.

The command accepts:

```text
workspace-init [--dry-run] [--workspace <path>]
```

The default workspace is `$HOME/work`. The command creates the workspace and
`$HOME/bin`, then ensures these repositories exist:

| Destination | SSH remote |
|---|---|
| `workflow-openhuman` | `git@github.com:tinyhumansai/workflow-openhuman.git` |
| `workflow-medulla` | `git@github.com:tinyhumansai/workflow-medulla.git` |
| `workflow-tinyplace` | `git@github.com:tinyhumansai/workflow-tinyplace.git` |
| `workflow-opencompany` | `git@github.com:tinyhumansai/workflow-opencompany.git` |
| `workflow-dashboard` | `git@github.com:tinyhumansai/workflow-dashboard.git` |

Each missing repository is created with `git clone --recurse-submodules`.
Any existing destination, whether a file or directory, is reported and left
completely untouched. The command never fetches, pulls, resets, or initializes
submodules inside an existing destination.

After the clone pass, the command installs `$HOME/bin/mosh-tmux` as a symlink to
the checkout's `bin/workspace-tmux`. A different existing file or symlink is
moved into a timestamped directory under `$HOME/.config-backups/` before the
new link is created. An already-correct link is left alone.

`--dry-run` describes directory creation, clone, backup, and link actions
without changing the filesystem or contacting GitHub. Unknown, repeated, or
incomplete arguments fail with usage text.

If a clone fails, the command exits immediately. Re-running it safely resumes
at the first destination that does not already exist.

### `bin/workspace-tmux`

`workspace-tmux` is the Mac mini launcher installed as `~/bin/mosh-tmux`.
It uses tmux from `PATH`, a dedicated server named `mosh`, and a session named
`workspace`. `MOSH_TMUX_SERVER` and `MOSH_TMUX_SESSION` may override those
names.

When the session does not exist, the launcher requires all five workflow
directories and creates these windows:

1. `openhuman` — six panes rooted at `workflow-openhuman`;
2. `medulla` — six panes rooted at `workflow-medulla`;
3. `tinyplace` — six panes rooted at `workflow-tinyplace`;
4. `dashboard` — six panes rooted at `workflow-dashboard`;
5. `opencompany` — six panes rooted at `workflow-opencompany`;
6. `btop` — one pane running `btop`; and
7. `shell` — one pane rooted at `$HOME`.

Each workflow window is a fixed two-row by three-column layout. The session is
created detached at a generous size so the layout does not depend on the first
client's dimensions.

On every invocation, including when the session already exists, the launcher
reapplies the blue remote theme, mouse and passthrough settings, inactive-pane
dimming, and the `C-z` prefix. It refuses to attach from inside another tmux
client and otherwise replaces itself with the tmux attach command.

### `bin/super-review`

`super-review` is the canonical local master launcher. It preserves the current
home-level script's session recreation behavior and layout:

1. five two-by-two workflow windows for `workflow-openhuman`,
   `workflow-medulla`, `workflow-tinyplace`, `workflow-dashboard`, and
   `workflow-opencompany`;
2. a mixed two-by-two `libraries` window rooted at `tinycortex`, `tinyagents`,
   `tinychannels`, and `tinyjuice`;
3. `btop`;
4. `cloud`, which runs the existing Robot1 `mosh` and remote tmux command;
5. `macmini`, which runs the existing Mac mini `mosh` and
   `~/bin/mosh-tmux` command;
6. `dragonfly`, which runs
   `mosh enamakel@dragonfly -- zsh -lc '~/bin/mosh-tmux'`; and
7. `shell`.

The launcher uses `$HOME/work/tinyhumansai` as its default repository root,
preserves the `super-review` session name, and resolves `tmux`, `btop`, and
`mosh` through `PATH`. It recreates the session, applies pane titles and border
settings, selects the first window, and attaches.

### Shared tmux helper

A non-executable Bash helper under `bin/` provides only reusable tmux
primitives:

- create a session or window and return its first pane;
- construct a two-by-two window;
- construct a two-by-three window; and
- construct a mixed two-by-two window.

The helper receives the tmux command, server/session target, names, and
directories from each launcher. Repository lists, window order, remote
commands, themes, and attach behavior remain explicit in the launchers.

### Installer integration

`install.sh` manages `$HOME/super-review.sh` as a symlink to
`bin/super-review`. It uses the installer's existing backup and idempotent-link
behavior. The Mac mini's `~/bin/mosh-tmux` link remains the responsibility of
`workspace-init`, so bootstrapping the workflow checkout set does not require
installing every personal agent configuration.

The README documents the bootstrap command, both tmux launchers, the installed
links, the five-repository set, and the destructive session-recreation behavior
of the local master launcher.

## Safety and error handling

- Existing workspace destinations are never inspected or changed.
- Clone destinations and symlink targets are fully quoted.
- A missing `git`, `tmux`, `btop`, or `mosh` dependency produces a clear error
  at the point where that command is required.
- A missing workflow directory prevents creation of a new remote tmux session;
  it does not kill or alter an existing session.
- Tests and validation never launch or replace the user's live tmux sessions.
- The local master launcher retains its deliberate session replacement
  behavior and documents it in `--help` output and the README.

## Verification

A dependency-free shell integration suite uses temporary homes and fake
executables to verify:

- all five exact SSH clone commands include `--recurse-submodules`;
- existing destinations are skipped without Git calls;
- dry-run mode performs no writes or Git calls;
- `mosh-tmux` linking is idempotent and backs up a conflicting file;
- invalid arguments fail;
- the remote launcher produces five two-by-three workflow windows plus `btop`
  and `shell`;
- the remote launcher reuses an existing session without rebuilding windows;
- the remote prefix and theme are applied;
- the master launcher produces the preserved five workflow, libraries,
  system, cloud, Mac mini, Dragonfly, and shell windows;
- pane working directories and remote commands are exact; and
- the `dragonfly` remote window follows `macmini` and precedes `shell`.

Final validation includes the integration suite, Bash syntax for all managed
scripts, Zsh syntax, agent and skill validation, installer dry-run, and
`git diff --check`. Runtime execution against live tmux sessions is excluded
because both launchers can attach to or replace interactive state.
