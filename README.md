# AI Sandbox NixOS VM

Reusable, team-shareable NixOS VM image for the AI sandbox. 

## How to start

1. **On the host**: **Setup the share and mandatory config file** for username:
 
   ```sh
   # On the host (one-time setup):
   mkdir -p ~/ai-sandbox-share/shared-config
   echo "$USER" > ~/ai-sandbox-share/shared-config/.host-username
   git clone git@github.com:AleksiAhtiainen/ai-sandbox.git \
     ~/ai-sandbox-share/ai-sandbox-host
   ```

2. **On the host**: **Grab ai-sandbox-<arch>.qcow2 from CI**, latest finished build's
  artifacts, https://github.com/AleksiAhtiainen/ai-sandbox/actions/workflows/build_seed_images.yml.

3. **On the host**: **Create a VM with e.g. UTM in MacOS**:
    - use that qcow2 as the existing disk
    - add a 9p / VirtFS share named exactly **`share` → ~/ai-sandbox-share**. In MacOS UTM `share` is the
      name by default.
    - ≥ 16 GB RAM (more is better in practice), ≥ 4 cores
    - Resize to large enough disk. At least 128 GBish, if planning to build
    the NixOS images in the VM

4. **Boot and wait for first-boot personalization to finish**. The seed
   comes up to a text console on tty1, sets the host username, then runs
   nixos-rebuild to fetch the GUI stack, IDEA, Claude Code, and the dev
   tools (kept out of the seed for licensing and size reasons). Once the
   rebuild completes it prompts on tty1 for a login password for your
   user, then reboots into GNOME.

   **Inside the VM**: The first boot is bandwidth-bound: there is
   over 10GB of data to download. Stay near the console so you can type
   the password when the prompt appears.

   No default password ships in the seed — the user account is locked
   until you set the password at the prompt, and that password is what
   you'll use at the GDM login screen after the reboot.

6. **Inside the VM** (one-time, after first boot): **make a VM-writable clone
   from the host-writable one**, with the cross-clone remote named `host`:

   ```sh
   git -c clone.defaultRemoteName=host clone \
     /mnt/share/ai-sandbox-host /mnt/share/ai-sandbox-vm
   cd /mnt/share/ai-sandbox-vm
   sudo nixos-rebuild switch --flake .#sandbox-$(uname -m)-linux --impure
   ```

7. **On the host**: **add the VM clone as a remote named `vm`**, so the host can
   pull VM-side changes (e.g. flake.lock bumps) back out:

   ```sh
   git -C ~/ai-sandbox-share/ai-sandbox-host remote add vm \
     ../ai-sandbox-vm
   ```   

The share now holds two sibling clones of this repo, one per writer:

| Path (VM view)                  | Written by | Remotes                            |
| ------------------------------- | ---------- | ---------------------------------- |
| `/mnt/share/ai-sandbox-host` | host only  | GitHub + `vm` → VM dir             |
| `/mnt/share/ai-sandbox-vm`   | VM only    | `host` → host dir                  |

The idea of this split is that repos can pull or push data from each other, and
it is also possible to sign commits on the host before pushing to remote repo.

### Keeping the VM up to date

1. **On the host**: **pull the latest config from GitHub** into the host-writable
  clone (the VM has no credentials, so this can't happen in the VM):

   ```sh
   git -C ~/ai-sandbox-share/ai-sandbox-host pull
   ```

2. **In the VM**: **pull from the host-writable clone**:
   
   ```sh
   cd /mnt/share/ai-sandbox-vm
   git pull host main
   ```

3. **In the VM**: **Bump pinned nixpkgs package versions** yourself (weekly-ish). This writes
  the new flake.lock into the VM dir — publish it back to GitHub via the
  host with the steps below.

   ```sh
   nix flake update nixpkgs
   ```

   To update only the unstable input (claude-code, IntelliJ IDEA, …):
   
   ```sh
   nix flake update unstable
   ```

4. **In the VM**: Commit the resulting flake.lock changes, if required

   ```sh
   git add ...
   git commit ...
   ```

5. **In the VM**: **Apply changes** — run after any of the above:

   ```sh
   sudo nixos-rebuild switch --flake .#sandbox-$(uname -m)-linux --impure
   ```

6. **On the host:** **Publish VM-side commits** (flake.lock bumps, config tweaks) back to GitHub. The VM has no
  GitHub credentials and no signing key, so re-signing and pushing must happen on the host:

   Fetch the VM's commits and review them before re-signing.

   ```sh
   cd ~/ai-sandbox-share/ai-sandbox-host
   git fetch vm main
   git log -p --stat main..vm/main
   ```

   Then re-sign each commit with the host's key and push to GitHub:

   ```sh
   git cherry-pick -S main..vm/main
   git push origin
   ```

7. **Back in the VM**: pull so the VM tracks the now-signed published history
   (and so its `main` matches `origin/main`):

   ```sh
   git -C /mnt/share/ai-sandbox-vm pull host main
   ```

## What lives on the share

`~/ai-sandbox-share/` on the host (= `/mnt/share/` in the VM) holds everything
the sandbox needs to persist across rebuilds and reboots, plus the
conduits between host and VM. Inventory (paths in VM view):

| Path | Writer | Purpose |
| ---- | ------ | ------- |
| `shared-config/.host-username` | host | One line with the host username. Read once by `ai-sandbox-firstboot.service` to provision the VM user. Required. |
| `shared-config/.gitconfig` | host | Optional VM git identity. See [Git config](#git-config). |
| `shared-config/claude/` | VM | Claude Code state. See [Where Claude state lives](#where-claude-state-lives). |
| `shared-config/fish_config/` | host (creates), VM (writes state) | Optional Fish config. See [Fish shell (optional)](#fish-shell-optional). |
| `shared-config/.fish` | VM | One line (`on`/`off`) selecting fish as the login shell. See [Fish shell (optional)](#fish-shell-optional). |
| `shared-config/.pop-shell` | VM | One line (`on`/`off`) toggling the Pop Shell tiling extension. See [Pop Shell tiling (optional)](#pop-shell-tiling-optional). |
| `ai-sandbox-host/` | host | Host-writable clone of this repo; the only side that pushes to GitHub. |
| `ai-sandbox-vm/` | VM | VM-writable clone of this repo; the side `nixos-rebuild` runs against. See the topology table above for the cross-clone remotes. |
| `ai-sandbox-<arch>.qcow2[.gz]` | maintainer | Seed image(s) staged here by `nix build` for distribution to the team. Not required on user machines. |

## Host AI Model – muse-glimmer-local

The sandbox can access a llama.cpp hosted `muse-glimmer-local` model running on the macOS host via the UTM vmnet. This keeps the large model off the VM and lets OpenCode in the VM use it.

### Prerequisites on the host

- llama.cpp built, models downloaded to e.g. `custom-models/`.
- The model is referenced in Hugging Face muse-glimmer documentation for installation and running.

### Run the model on the host

Find the vmnet bridge IP used by UTM:

```sh
ifconfig bridge* | grep inet
```

Typical output is `192.168.64.1`. The IP is stable for the current UTM installation; verify after major macOS/UTM changes.

Run llama-server bound to the vmnet IP only:

```sh
./build/bin/llama-server \
  -m custom-models/muse-glimmer-30B-kquant-17gb.gguf \
  --mmproj custom-models/mmproj-kquant.gguf \
  -a muse-glimmer-30B \
  -ngl 99 -c 131072 -np 1 \
  --host 192.168.64.1 --port 8080 \
  --jinja \
  --temp 1.0 --top-p 0.95 --top-k 64
```

Binding to the vmnet IP limits exposure to the VM subnet. Do not use `--host 0.0.0.0` unless you intend LAN exposure.

### UTM network

UTM Settings → Devices → Network → Network Mode → Shared Network is the default. The VM receives DHCP in `192.168.64.0/24` and can reach `192.168.64.1:8080`.

From inside the VM:

```sh
curl http://192.168.64.1:8080
```

### OpenCode default config

`modules/opencode.nix` bootstraps `~/.config/opencode` to `/mnt/share/shared-config/opencode`. On first boot, if no config exists, it seeds `opencode-default-config.json` from the repo.

The default config points OpenCode at the host model:

```json
{
  "model": "llama.cpp/muse-glimmer-local",
  "provider": {
    "llama.cpp": {
      "options": { "baseURL": "http://192.168.64.1:8080/v1" }
    }
  }
}
```

Edit `/mnt/share/shared-config/opencode/opencode.json` on the host to change `baseURL` to your actual vmnet IP. The config survives `nixos-rebuild` and VM recreation as long as the share is kept.

## ⚠ The share is the way out of the sandbox

**TL;DR:** Treat anything and especially the files the VM writes in `~/ai-sandbox-share`
as untrusted on the host — don't run anything from there, and don't open it from there
in tools that auto-execute code.

`~/ai-sandbox-share` is the only conduit between the VM and the host, and on
the host it's a normal directory with full host privileges. Anything the
VM writes there — directly, or via a compromised tool, dependency, or
agent — is sitting in your home directory ready to be picked up by host
processes. The sandbox stops protecting you the moment you naively walk
share contents back out to the host.

Concretely, on the host side:

- Don't run scripts or binaries from the share unless you'd run them
  with no sandbox at all. The VM can plant them there.
- Don't open share-resident projects in host tools that auto-execute
  code: IDE plugins, LSP servers, `npm install` postinstall hooks,
  `direnv`/`mise` autoloaders, git hooks (`pre-commit`, `post-checkout`,
  `…`). Open them from inside the VM instead.
- Be deliberate about which directories under the share host tools index
  — a host editor that recursively scans `~/ai-sandbox-share/` is reading
  whatever the VM put there.
- Treat anything *the VM has written* as untrusted input on the host,
  even when you're the one who asked it to write it.

If a workflow needs to do anything risky (running unfamiliar code,
exercising a sketchy dependency, letting an agent loose), keep it inside
the VM. The reason this VM exists is so that those operations don't
touch the host directly; the share doesn't change that contract, but
how you treat the share on the host either preserves it or breaks it.

## ⚠ The network is a way out of the sandbox

**TL;DR:** With UTM Shared Network the VM is a network peer of the host. Treat network reachability from the VM to the host as an additional escape vector, separate from the 9p share.

`Shared Network` routes VM traffic directly through the host OS on the vmnet bridge, typically `192.168.64.0/24`. The VM can reach the host’s vmnet IP, scan host services, and, because Shared Network provides Internet access, it can also reach the Internet via the host.

Concretely:

- Any service listening on the vmnet interface is reachable from the VM. If you bind a host service to `0.0.0.0`, it is reachable from LAN/Wi-Fi and from the VM.
- The VM can perform port scans and attempt exploitation of host services. An untrusted AI agent running in the VM can use the host as a pivot to your internal network.
- Internet access is available in Shared Network, so an agent can exfiltrate data, download code, or beacon out.
- This is distinct from the 9p share: the share gives filesystem write access; the network gives service access and outbound connectivity.

## Claude Code

The VM ships with [Claude Code](https://docs.claude.com/en/docs/claude-code)
preinstalled (`claude` on `PATH`).

### Where Claude state lives

`~/.claude/` is a symlink to `/mnt/share/shared-config/claude/`. Any
state Claude Code writes — settings, memories, MCP config, OAuth login,
project history, todos — survives `nixos-rebuild`, VM shutdown, and
recreating the VM from the seed image, as long as you keep using the same
`~/ai-sandbox-share`. 

### Seeded MCP servers

`ai-sandbox-claude-bootstrap` seeds MCP servers into Claude Code's user
scope (`~/.claude.json`) on every boot, so they work on a fresh VM
without a manual `claude mcp add`. Entries already present in
`~/.claude.json` are left untouched; removing one with
`claude mcp remove` only lasts until the next boot. The definitions
live in `modules/claude.nix`:

- `chrome-devtools` — drives the system Chromium, e.g. to verify UI
  changes in a locally running app. The browser opens as a visible
  window in the GNOME session (with an isolated profile); add
  `--headless` to hide it.
- `idea` — IntelliJ IDEA's built-in MCP server at
  `http://127.0.0.1:64342/sse` (IDEA's default port; if IDEA ends up
  on another port, fix the entry manually).

On the IDEA side, `ai-sandbox-idea-bootstrap` (`modules/idea.nix`) seeds
`options/mcpServer.xml` into IDEA's config dir so the built-in MCP
server is enabled (with brave mode, i.e. no per-tool-call confirmation
dialogs) without visiting *Settings | Tools | MCP Server* on a fresh
VM. The file is seeded only if missing — IDEA owns it afterwards, so
turning the server off in the IDE sticks across reboots.

### Be careful running multiple VMs as the same user simultaneously

The 9p file sharing has no lock manager. Two VMs writing to the same
`/mnt/share/shared-config/claude/` give last-writer-wins on every file.

## Git config

Drop a `.gitconfig` on the share to give git an identity inside the VM:

   ```sh
   # On the host:
   cat > ~/ai-sandbox-share/shared-config/.gitconfig <<'EOF'
   [user]
     name = Your Name
     email = you@example.com
   EOF
   ```

**Don't symlink your host's real `~/.gitconfig` into `~/ai-sandbox-share/shared-config/`.** Use a
VM-specific copy. The host config typically references things that don't make
sense in the sandbox (signing key paths, `gpg.program`, credential helpers,
`includeIf` paths, custom diff/merge tools), and sharing it weakens the
isolation the VM is meant to provide. A minimal `[user]` block is usually
enough — add VM-only aliases and tooling on top as needed.

### Working with git on the share

Set up your git repos and remotes so that the same directory is never
written concurrently by the host and/or multiple VMs — 9p has no lock
manager, so concurrent writers will corrupt refs and the index. Sign
and push to GitHub from the host, since the VM has no credentials or
signing key.

## Fish shell (optional)

[Fish](https://fishshell.com/) is installed but not the default login
shell. To opt in:

   ```sh
   # On the host (one-time): create the shared fish config dir. The VM
   # symlinks ~/.config/fish to it on next boot, so anything you drop in
   # here (config.fish, functions/, completions/, conf.d/) is picked up.
   mkdir -p ~/ai-sandbox-share/shared-config/fish_config

   # In the VM: switch the login shell to fish, then log out and back in.
   fish-on
   ```

This writes `on` to `/mnt/share/shared-config/.fish` and chshes the
configured user (prompting for sudo). A systemd one-shot re-applies
the marker at every later boot, and an activation hook re-applies it
at the end of each `nixos-rebuild switch` — both needed because
NixOS's user activation otherwise rewrites the shell field in
`/etc/passwd` back to bash. The state survives `nixos-rebuild`,
reboots, and recreating the VM from the seed. Because the marker
lives on the share, the same single-writer caveat as `claude/` and
`fish_config/` applies.

If `~/ai-sandbox-share/shared-config/fish_config` doesn't exist, the symlink isn't created
and any local `~/.config/fish` is left untouched. Fish state lives on the
share, so it survives `nixos-rebuild` and recreating the VM.

To revert:

   ```sh
   fish-off
   ```

## Pop Shell tiling (optional)

[Pop Shell](https://github.com/pop-os/shell) is installed but disabled.
To opt in, run inside the VM:

   ```sh
   pop-shell-on
   ```

This writes `on` to `/mnt/share/shared-config/.pop-shell`, applies the
change to the current GNOME session, and re-applies it at every later
login via an XDG autostart entry — so the state persists across
`nixos-rebuild`, reboots, and recreating the VM from the seed. Because
the marker lives on the share, the same caveat as `claude/` and
`fish_config/` applies: single writer only.

`pop-shell-on` also clears GNOME's `Super+Left/Right/Up/Down`
keybindings (`toggle-tiled-left/right`, `maximize`, `unmaximize`)
so Pop Shell's focus-navigation bindings come through. On Wayland,
log out and back in the first time you flip it on so GNOME Shell
loads the extension.

To revert:

   ```sh
   pop-shell-off
   ```

Keys once enabled: `Super+Y` toggles tiling, `Super+-` opens the
launcher (remapped from the upstream `Super+/`, which needs Shift on a
Finnish keyboard), `Super+Return` enters window-adjustment mode,
`Super+Arrows` move focus, `Super+Shift+Arrows` swap windows.

## Development tools

Stable symlinks to JDK installs live under `/etc/jdks/` (e.g.
`/etc/jdks/jdk17`), so IDEA's *File → Project Structure → SDKs* can
point at a path that survives `nixos-rebuild` — the underlying Nix
store path changes on every rebuild.

## Maintainer setup (building the seed)

This is the one-time bootstrap. Run inside any NixOS environment matching
the target architecture — your existing UTM NixOS VM works for the
aarch64 seed.

   ```sh
   cd ~/ai-sandbox-share/ai-sandbox-host   # or wherever you have it cloned
   arch=$(uname -m)
   nix build .#packages.$arch-linux.compressedImage --impure -L
   cp -L result /mnt/share/ai-sandbox-$arch.qcow2
   ```

`--impure` is needed because `modules/user.nix` reads
`/etc/ai-sandbox-username` at evaluation time (with a safe fallback to
`sandbox` during the seed build). The username file is written on each
teammate's first boot from `/mnt/share/shared-config/.host-username`.

The build runs on whichever architecture the NixOS environment matches —
aarch64 on an Apple Silicon UTM VM, x86_64 on an Intel-Linux NixOS
environment.

Distribute the resulting qcow2 to the team via shared storage.

### Building via GitHub Actions

`.github/workflows/build_seed_images.yml` builds both seed images on
GitHub-hosted runners. It's `workflow_dispatch` only — trigger it from the
Actions tab (or `gh workflow run "Build seed images"`). The job runs the
same `nix build .#packages.<arch>-linux.compressedImage` as the local
recipe above and uploads the resulting qcow2 as a workflow artifact named
`ai-sandbox-<arch>`, which you then download and stage on the share.

The `x86_64` build runs on `ubuntu-24.04` with KVM. The `aarch64` build
runs on `ubuntu-24.04-arm`, which doesn't expose `/dev/kvm`; the inner
`nixos-install` VM falls back to TCG and is roughly 10–50× slower than
the x86_64 job.

### Building a "full" image (private use)

For machines where the long first-boot download is inconvenient, build
a full image that bakes `postSeedModules` (GUI stack, IntelliJ IDEA,
Claude Code, dev tools) into the qcow2:

   ```sh
   cd ~/ai-sandbox-share/ai-sandbox-host
   nix build .#packages.$(uname -m)-linux.compressedFullImage --impure -L
   cp -L result /mnt/share/ai-sandbox-full-image-$(uname -m).qcow2
   ```

Use the resulting qcow2 the same way as the public seed (see
[How to start](#how-to-start)). First boot still personalizes the
username and runs `nixos-rebuild switch`, but the full closure is
already on disk so nothing is downloaded — the VM comes up to GNOME
without a bandwidth-bound wait.

**Don't redistribute the full qcow2.** It bundles IntelliJ IDEA
Ultimate and Claude Code, which we don't have the right to redistribute
— that's why the default seed leaves them in `postSeedModules` and
lets each user pull them from the nixpkgs binary cache on first boot.
The GitHub Actions workflow only builds the redistributable seed.

### Adding packages — what goes in the seed

`flake.nix` splits modules into `seedModules` (baked into the public
qcow2) and `postSeedModules` (added by the user's first-boot
`nixos-rebuild`). Two reasons to keep something out of the seed:

1. **Licensing**: anything in `seedModules` is being publicly
   redistributed via the seed, so non-redistributable packages must not
   go there. `modules/idea.nix` (IntelliJ IDEA Ultimate) and
   `modules/claude.nix` (Claude Code) live in `postSeedModules` for this
   reason — the user's machine fetches them from the nixpkgs binary
   cache on first boot, so the redistribution relationship is between
   the user and the upstream vendor.
2. **Size**: every package in the seed inflates the qcow2 we distribute
   and the time it takes to build (manually or in CI) and download.
   The GUI stack (`modules/desktop.nix` — GNOME/GDM/Firefox — plus its
   `modules/spice.nix` autostart) and heavy dev tooling (JDK, Maven,
   Node, Chromium, docker-compose, … in `modules/dev-tools.nix`) live
   in `postSeedModules` for this reason: the seed boots to a text
   console, runs `ai-sandbox-firstboot`, and fetches all of it from the
   nixpkgs binary cache on first boot.

Quick check when adding a new package: if it builds without
`nixpkgs.config.allowUnfree = true`, it's licensing-safe for
`seedModules`. If it needs `allowUnfree`, query its license metadata
(`nix eval --json nixpkgs#<pkg>.meta.license`) and read the actual
upstream terms — SPDX-level `redistributable = true` doesn't catch
contractual restrictions like JetBrains' subscription agreement (§3.5(d)
prohibits providing the IDE Product to third parties). For
licensing-safe but heavy packages, put them in `dev-tools.nix`. When
unsure, put the package in `postSeedModules`.

## (Possible) TODOs

- Consider running an SSH server in the VM so users can `ssh` in from a
  host terminal (better paste/scrollback/tmux story than the UTM console).
  Password auth on a network-reachable service is the wrong default —
  prefer key-only auth (e.g. a key dropped on the share) or a
  vsock/loopback-only listener that isn't exposed beyond the host.
- There are now GUI settings specific to Macs, think how to modularize (e.g. keyboard type)
- Investigate replacing the 9p share with virtiofs (and POSIX-lock
  pass-through), which would let host + multiple VMs share
  `~/ai-sandbox-share/` safely under concurrent access. Today we run 9p
  with `cache=none` for cross-side coherence, which is correct but
  slower than a properly locked virtiofs setup would be.
- Reduce reliance on the broad host↔VM share. Today every outbound flow
  from the VM (commits, file edits, build artifacts) goes through the
  same wide-open share, which is also the sandbox-escape vector
  described in the warning above. Replace as many of those flows as
  possible with narrower, explicit, time-limited mechanisms — scoped
  tokens for specific operations, an RPC bridge over vsock that
  authorizes individual requests, or an outbound proxy that handles
  signing-and-push without exposing the host filesystem. Goal: the
  share is for genuinely shared dev state, not for "the VM needs to do
  anything outside itself."
- Figure out the recommended way to create signed commits and push to GitHub
  from inside the VM (e.g. forwarding the host's 1Password SSH agent over a
  vsock/TCP bridge, or a per-VM signing key registered with GitHub). Until
  then, sign and push from the host as described above.
- Bootstrap path for users who don't yet have any NixOS VM and need to build a seed from
  scratch on macOS (would bring back something like nix-darwin linux-builder, or a temporary
  Lima/Tart VM, or CI).
- Figure out the easiest way to paste images from the host clipboard into the
  Claude Code shell running in the VM (Claude Code accepts image paste in the
  terminal, but SPICE/UTM clipboard sharing typically only forwards text, so
  today you'd have to save the image to `~/ai-sandbox-share/` on the host and
  reference it by path from inside the VM).

## Technical notes

One generic qcow2 per architecture is built and distributed; each teammate's VM
personalizes itself on first boot to match the host username (required for
licensing).

The VM user is always uid `1000` / gid `100` (`users`); the
`/mnt/share` mount is a `bindfs` layer over the raw 9p mount that remaps
ownership, so files appear as the VM user regardless of host uid/gid (501
/ 20 on macOS, 1000 / 100 on Linux, etc.).

## Troubleshooting

- **`ai-sandbox-firstboot.service` failed**: most likely `/mnt/share/shared-config/.host-username`
  was missing or contained whitespace/invalid characters. The common
  macOS gotcha is a dotted username (e.g. `firstname.lastname`) — Linux
  `useradd` only accepts lowercase letters, digits, underscore, and
  hyphen, so the `echo "$USER" > .host-username` step in the setup
  recipe silently produces an invalid file for these users. Pick a
  dot-free name (e.g. `firstname`).
  `journalctl -u ai-sandbox-firstboot` shows the exact reason. Fix the file on
  the host, then `sudo systemctl restart ai-sandbox-firstboot`.
- **9p share didn't mount**: confirm the share name is exactly `share`
  in your VM runtime's settings. UTM "VirtFS" name must match
  `fileSystems."/mnt/share".device`.
- **Wrong username in VM after first boot** (e.g. `.host-username` had the
  wrong value): re-trigger first-boot:
  `sudo rm /etc/ai-sandbox-username && sudo systemctl start ai-sandbox-firstboot`.
- **`/mnt/share` writes fail with permission denied**: check that the
  bindfs layer mounted — `mount | grep fuse.bindfs` should show
  `/mnt/share`. If only `/run/ai-sandbox-share` is mounted, the bindfs unit
  failed; `journalctl -u mnt-share.mount` shows why.
- **IntelliJ IDEA license activation fails because the VM username
  differs from your host**: JetBrains ties activations to the OS
  username, so a host like `firstname.lastname` and a VM forced to
  `firstname` (see the dotted-username gotcha above) won't share the
  same license. Launch IDEA with `-Duser.name=<host-username>` to
  override, e.g. `idea -Duser.name=firstname.lastname`.
