# Koski NixOS sandbox VM

Reusable, team-shareable NixOS VM image for the Koski sandbox. 

## How to start

1. **On the host**: **Setup the share and mandatory config file** for username:
 
   ```sh
   # On the host (one-time setup):
   mkdir -p ~/koski-share/shared-config
   echo "$USER" > ~/koski-share/shared-config/.host-username
   git clone git@github.com:Opetushallitus/koski-sandbox.git \
     ~/koski-share/koski-sandbox-host
   ```

2. **On the host**: **Grab koski-sandbox-<arch>.qcow2 from CI**, latest finished build's
  artifacts, https://github.com/Opetushallitus/koski-sandbox/actions/workflows/build_seed_images.yml.

3. **On the host**: **Create a VM with e.g. UTM in MacOS**:
    - use that qcow2 as the existing disk
    - add a 9p / VirtFS share named exactly **`share` → ~/koski-share**. In MacOS UTM `share` is the
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
     /mnt/share/koski-sandbox-host /mnt/share/koski-sandbox-vm
   cd /mnt/share/koski-sandbox-vm
   sudo nixos-rebuild switch --flake .#sandbox-$(uname -m)-linux --impure
   ```

7. **On the host**: **add the VM clone as a remote named `vm`**, so the host can
   pull VM-side changes (e.g. flake.lock bumps) back out:

   ```sh
   git -C ~/koski-share/koski-sandbox-host remote add vm \
     ../koski-sandbox-vm
   ```   

The share now holds two sibling clones of this repo, one per writer:

| Path (VM view)                  | Written by | Remotes                            |
| ------------------------------- | ---------- | ---------------------------------- |
| `/mnt/share/koski-sandbox-host` | host only  | GitHub + `vm` → VM dir             |
| `/mnt/share/koski-sandbox-vm`   | VM only    | `host` → host dir                  |

The idea of this split is that repos can pull or push data from each other, and
it is also possible to sign commits on the host before pushing to remote repo.

### Keeping the VM up to date

1. **On the host**: **pull the latest config from GitHub** into the host-writable
  clone (the VM has no credentials, so this can't happen in the VM):

   ```sh
   git -C ~/koski-share/koski-sandbox-host pull
   ```

2. **In the VM**: **pull from the host-writable clone**:
   
   ```sh
   cd /mnt/share/koski-sandbox-vm
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
   cd ~/koski-share/koski-sandbox-host
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
   git -C /mnt/share/koski-sandbox-vm pull host main
   ```

## What lives on the share

`~/koski-share/` on the host (= `/mnt/share/` in the VM) holds everything
the sandbox needs to persist across rebuilds and reboots, plus the
conduits between host and VM. Inventory (paths in VM view):

| Path | Writer | Purpose |
| ---- | ------ | ------- |
| `shared-config/.host-username` | host | One line with the host username. Read once by `koski-firstboot.service` to provision the VM user. Required. |
| `shared-config/.gitconfig` | host | Optional VM git identity. See [Git config](#git-config). |
| `shared-config/idea64.vmoptions` | host | Optional IDEA JVM flags; `IDEA_VM_OPTIONS` is set to this path system-wide. See [Troubleshooting](#troubleshooting) for the flags that fix UTM rendering on Apple Silicon. |
| `shared-config/claude/` | VM | Claude Code state. See [Where Claude state lives](#where-claude-state-lives). |
| `shared-config/fish_config/` | host (creates), VM (writes state) | Optional Fish config. See [Fish shell (optional)](#fish-shell-optional). |
| `koski-sandbox-host/` | host | Host-writable clone of this repo; the only side that pushes to GitHub. |
| `koski-sandbox-vm/` | VM | VM-writable clone of this repo; the side `nixos-rebuild` runs against. See the topology table above for the cross-clone remotes. |
| `koski-sandbox-<arch>.qcow2[.gz]` | maintainer | Seed image(s) staged here by `nix build` for distribution to the team. Not required on user machines. |

## ⚠ The share is the way out of the sandbox

**TL;DR:** Treat anything and especially the files the VM writes in `~/koski-share`
as untrusted on the host — don't run anything from there, and don't open it from there
in tools that auto-execute code.

`~/koski-share` is the only conduit between the VM and the host, and on
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
  — a host editor that recursively scans `~/koski-share/` is reading
  whatever the VM put there.
- Treat anything *the VM has written* as untrusted input on the host,
  even when you're the one who asked it to write it.

If a workflow needs to do anything risky (running unfamiliar code,
exercising a sketchy dependency, letting an agent loose), keep it inside
the VM. The reason this VM exists is so that those operations don't
touch the host directly; the share doesn't change that contract, but
how you treat the share on the host either preserves it or breaks it.

## Claude Code

The VM ships with [Claude Code](https://docs.claude.com/en/docs/claude-code)
preinstalled (`claude` on `PATH`).

### Where Claude state lives

`~/.claude/` is a symlink to `/mnt/share/shared-config/claude/`. Any
state Claude Code writes — settings, memories, MCP config, OAuth login,
project history, todos — survives `nixos-rebuild`, VM shutdown, and
recreating the VM from the seed image, as long as you keep using the same
`~/koski-share`. 

### Be careful running multiple VMs as the same user simultaneously

The 9p file sharing has no lock manager. Two VMs writing to the same
`/mnt/share/shared-config/claude/` give last-writer-wins on every file.

## Git config

Drop a `.gitconfig` on the share to give git an identity inside the VM:

   ```sh
   # On the host:
   cat > ~/koski-share/shared-config/.gitconfig <<'EOF'
   [user]
     name = Your Name
     email = you@example.com
   EOF
   ```

**Don't symlink your host's real `~/.gitconfig` into `~/koski-share/shared-config/`.** Use a
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
   mkdir -p ~/koski-share/shared-config/fish_config

   # In the VM: make fish your default login shell, then log out and back in.
   chsh -s "$(which fish)"
   ```

If `~/koski-share/shared-config/fish_config` doesn't exist, the symlink isn't created
and any local `~/.config/fish` is left untouched. Fish state lives on the
share, so it survives `nixos-rebuild` and recreating the VM — the same
single-writer caveat as `/mnt/share/shared-config/claude/` applies.

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
   cd ~/koski-share/koski-sandbox-host   # or wherever you have it cloned
   arch=$(uname -m)
   nix build .#packages.$arch-linux.compressedImage --impure -L
   cp -L result /mnt/share/koski-sandbox-$arch.qcow2
   ```

`--impure` is needed because `modules/user.nix` reads
`/etc/koski-sandbox-username` at evaluation time (with a safe fallback to
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
`koski-sandbox-<arch>`, which you then download and stage on the share.

The `x86_64` build runs on `ubuntu-24.04` with KVM. The `aarch64` build
runs on `ubuntu-24.04-arm`, which doesn't expose `/dev/kvm`; the inner
`nixos-install` VM falls back to TCG and is roughly 10–50× slower than
the x86_64 job.

### Building a "full" image (private use)

For machines where the long first-boot download is inconvenient, build
a full image that bakes `postSeedModules` (GUI stack, IntelliJ IDEA,
Claude Code, dev tools) into the qcow2:

   ```sh
   cd ~/koski-share/koski-sandbox-host
   nix build .#packages.$(uname -m)-linux.compressedFullImage --impure -L
   cp -L result /mnt/share/koski-sandbox-full-image-$(uname -m).qcow2
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
   console, runs `koski-firstboot`, and fetches all of it from the
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
  `~/koski-share/` safely under concurrent access. Today we run 9p
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
- Investigate, if there is a way to get IntelliJ IDEA working with HW acceleration in MacOS
  UTM hosted VM
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
  today you'd have to save the image to `~/koski-share/` on the host and
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

- **`koski-firstboot.service` failed**: most likely `/mnt/share/shared-config/.host-username`
  was missing or contained whitespace/invalid characters.
  `journalctl -u koski-firstboot` shows the exact reason. Fix the file on
  the host, then `sudo systemctl restart koski-firstboot`.
- **9p share didn't mount**: confirm the share name is exactly `share`
  in your VM runtime's settings. UTM "VirtFS" name must match
  `fileSystems."/mnt/share".device`.
- **Wrong username in VM after first boot** (e.g. `.host-username` had the
  wrong value): re-trigger first-boot:
  `sudo rm /etc/koski-sandbox-username && sudo systemctl start koski-firstboot`.
- **`/mnt/share` writes fail with permission denied**: check that the
  bindfs layer mounted — `mount | grep fuse.bindfs` should show
  `/mnt/share`. If only `/run/koskishare` is mounted, the bindfs unit
  failed; `journalctl -u mnt-share.mount` shows why.
- **IntelliJ IDEA shows a corrupted splash / EULA
  dialog**: the default UTM display device on Apple Silicon
  (`virtio-gpu-gl-pci`) mangles the framebuffer for JetBrains'
  Skia/JBR renderer. Two workarounds, lighter first:

  1. Disable HW acceleration **only inside the IDE**. Drop these lines
     into `/mnt/share/shared-config/idea64.vmoptions` on the host (the VM sets
     `IDEA_VM_OPTIONS` to that path system-wide, so every VM picks it up
     and you skip the per-version `~/.config/JetBrains/IntelliJIdea<version>/`
     dance):

     ```
     -Dide.ui.hw.acceleration=false
     -Dsun.java2d.opengl=false
     -Dsun.java2d.d3d=false
     -Dsun.java2d.metal=false
     -Dsun.java2d.xrender=false
     -Dsun.java2d.pmoffscreen=false
     ```

     Restart IDEA. Other apps keep host-side GL; IDEA renders correctly
     but its own UI is slower.

  2. Disable host-side GL globally for the VM. In UTM → Settings →
     Display, switch the **Display Device** to `virtio-gpu-pci` (no
     `-gl`). All apps lose host GL acceleration — noticeably slower
     overall — but rendering everywhere becomes correct. Use this if
     other Java/Skia apps misrender too.
- **IntelliJ IDEA Markdown preview pane (e.g. opening `README.md`) shows a black
  screen** even after the splash/EULA workaround above: the preview is
  rendered by JCEF (embedded Chromium), which has its own GPU pipeline
  not covered by the Java2D flags. Append to the same
  `/mnt/share/shared-config/idea64.vmoptions` as above:

  ```
  -Dide.browser.jcef.gpu.disable=true
  -Dide.browser.jcef.gpu.infoCollection.disabled=true
  ```

  Restart IDEA. JCEF then software-rasterizes the preview — slightly
  slower but renders correctly.
