# Koski NixOS sandbox VM

Reusable, team-shareable NixOS VM image for the Koski sandbox. One generic
qcow2 per architecture is built and distributed; each teammate's VM
personalizes itself on first boot to match the host username (required for
licensing). The VM user is always uid `1000` / gid `100` (`users`); the
`/mnt/share` mount is a `bindfs` layer over the raw 9p mount that remaps
ownership, so files appear as the VM user regardless of host uid/gid (501
/ 20 on macOS, 1000 / 100 on Linux, etc.) — no `chown` needed.

## Quick start

The short version — see the detailed sections below for context and gotchas.

```sh
# On the host (one-time setup):
mkdir -p ~/koski-share
echo "$USER" > ~/koski-share/.host-username
git clone git@github.com:Opetushallitus/koski-sandbox.git \
  ~/koski-share/koski-sandbox-host

# Grab koski-sandbox-<arch>.qcow2 from team storage. Create a VM with it:
#   - use that qcow2 as the existing disk
#   - add a 9p / VirtFS share named exactly `share` → ~/koski-share
#   - ≥ 16 GB RAM (more is better in practice), ≥ 4 cores
# Boot, wait ~1–2 min for first-boot personalization, log in as your host
# username (password: changeme), then run `passwd`.

# Inside the VM (one-time, after first boot): make a VM-writable clone
# from the host-writable one, with the cross-clone remote named `host`:
git -c clone.defaultRemoteName=host clone \
  /mnt/share/koski-sandbox-host /mnt/share/koski-sandbox-vm
cd /mnt/share/koski-sandbox-vm
sudo nixos-rebuild switch --flake .#sandbox-$(uname -m)-linux --impure

# Optional, on the host: add the VM clone as a remote named `vm`, so the
# host can pull VM-side changes (e.g. flake.lock bumps) back out:
git -C ~/koski-share/koski-sandbox-host remote add vm \
  ../koski-sandbox-vm
```

The share now holds two sibling clones of this repo, one per writer:

| Path (VM view)                  | Written by | Remotes                            |
| ------------------------------- | ---------- | ---------------------------------- |
| `/mnt/share/koski-sandbox-host` | host only  | GitHub + `vm` → VM dir             |
| `/mnt/share/koski-sandbox-vm`   | VM only    | `host` → host dir                  |

Each side only ever **pulls** from the other; neither side ever pushes
into the other dir. That keeps the "single writer per file" invariant
that the 9p `cache=loose` share needs (no lock manager → concurrent
writers corrupt refs and the index). Pushing to GitHub is fine — but do
it only from the host, since the VM has no credentials.

### Keeping the VM up to date

```sh
# On the host: pull the latest config from GitHub into the host-writable
# clone (the VM has no credentials, so this can't happen in the VM):
git -C ~/koski-share/koski-sandbox-host pull

# In the VM: pull from the host-writable clone:
cd /mnt/share/koski-sandbox-vm
git pull host main

# Bump pinned nixpkgs package versions yourself (weekly-ish). This writes
# the new flake.lock into the VM dir — see "Sharing flake.lock bumps with
# the team" below for how to push it back out via the host.
nix flake update nixpkgs

# To update only the unstable input (claude-code, IntelliJ IDEA, …):
nix flake update unstable

# Commit the resulting flake.lock changes, if required
git add ...
git commit ...

# Apply changes — run after any of the above:
sudo nixos-rebuild switch --flake .#sandbox-$(uname -m)-linux --impure
```

## Claude Code

The VM ships with [Claude Code](https://docs.claude.com/en/docs/claude-code)
preinstalled (`claude` on `PATH`).

### Where Claude state lives

`~/.claude/` is a symlink to `/mnt/share/claude/<username>/`. Any
state Claude Code writes — settings, memories, MCP config, OAuth login,
project history, todos — survives `nixos-rebuild`, VM shutdown, and
recreating the VM from the seed image, as long as you keep using the same
`~/koski-share`. 

### Be careful running multiple VMs as the same user simultaneously

The 9p file sharing has no lock manager and uses `cache=loose`. Two VMs
writing to the same `/mnt/share/claude/<user>/` give last-writer-wins on
every file, with stale-cache reads on top.

## Maintainer setup (building the seed)

This is the one-time bootstrap. Run inside any NixOS environment matching
the target architecture — your existing UTM NixOS VM works for the
aarch64 seed.

```sh
cd ~/koski-share/koski-sandbox-host   # or wherever you have it cloned
nix build .#packages.aarch64-linux.image --impure -L
cp -L result/nixos.qcow2 /mnt/share/koski-sandbox-aarch64.qcow2
```

`--impure` is needed because `modules/user.nix` reads
`/etc/koski-sandbox-username` at evaluation time (with a safe fallback to
`sandbox` during the seed build). The username file is written on each
teammate's first boot from `/mnt/share/.host-username`.

For x86_64 the same command on an Intel-Linux NixOS environment, with
`packages.x86_64-linux.image`.

Distribute the resulting qcow2 to the team via shared storage. CI builds
are out of scope for now (planned follow-up).

## Git config

Drop a `.gitconfig` on the share to give git an identity inside the VM:

```sh
# On the host:
cat > ~/koski-share/.gitconfig <<'EOF'
[user]
  name = Your Name
  email = you@example.com
EOF
```

**Don't symlink your host's real `~/.gitconfig` into `~/koski-share/`.** Use a
VM-specific copy. The host config typically references things that don't make
sense in the sandbox (signing key paths, `gpg.program`, credential helpers,
`includeIf` paths, custom diff/merge tools), and sharing it weakens the
isolation the VM is meant to provide. A minimal `[user]` block is usually
enough — add VM-only aliases and tooling on top as needed.

### Working with git on the share

Set up your git repos and remotes so that the same directory is never
written concurrently by the host and/or multiple VMs — 9p `cache=loose` has
no lock manager, so concurrent writers will corrupt refs and the index. Sign
and push to GitHub from the host, since the VM has no credentials or
signing key.

## (Possible) TODOs

- Add swap file/partition by default
- There are now GUI settings specific to Macs, think how to modularize (e.g. keyboard type)
- Clean up unnecessary services from the modules: currently there is probably added fluff
- Investigate replacing the 9p `cache=loose` share with virtiofs (and
  POSIX-lock pass-through), which would give host + multiple VMs a coherent
  view of `~/koski-share/` and make concurrent access safer.
- Investigate, if there is a way to get IntelliJ IDEA working with HW acceleration in MacOS
UTM hosted VM
- Figure out the recommended way to create signed commits and push to GitHub
  from inside the VM (e.g. forwarding the host's 1Password SSH agent over a
  vsock/TCP bridge, or a per-VM signing key registered with GitHub). Until
  then, sign and push from the host as described above.
- GitHub Actions matrix building qcow2 for both arches and uploading to Releases (replaces
the manual seed handoff).
- Bootstrap path for users who don't yet have any NixOS VM and need to build a seed from
scratch on macOS (would bring back something like nix-darwin linux-builder, or a temporary
Lima/Tart VM, or CI).
- Figure out the easiest way to paste images from the host clipboard into the
  Claude Code shell running in the VM (Claude Code accepts image paste in the
  terminal, but SPICE/UTM clipboard sharing typically only forwards text, so
  today you'd have to save the image to `~/koski-share/` on the host and
  reference it by path from inside the VM).

## Troubleshooting

- **`koski-firstboot.service` failed**: most likely `/mnt/share/.host-username`
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
- **VM sees stale content under `/mnt/share` after host-side edits**:
  the 9p share uses `cache=loose` and bindfs caches on top, so the
  guest doesn't revalidate against the host. For content-only edits,
  drop the guest caches:
  `sync && sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'`. Structural
  changes (rename, delete, swap to symlink) can leave stale dentries
  that survive this — reboot the VM in that case.
- **JetBrains IDE (IDEA, Toolbox, …) shows a corrupted splash / EULA
  dialog**: the default UTM display device on Apple Silicon
  (`virtio-gpu-gl-pci`) mangles the framebuffer for JetBrains'
  Skia/JBR renderer. Two workarounds, lighter first:

  1. Disable HW acceleration **only inside the IDE**. Add to
     `~/.config/JetBrains/IntelliJIdea<version>/idea64.vmoptions`
     (create the file if missing):

     ```
     -Dide.ui.hw.acceleration=false
     -Dsun.java2d.opengl=false
     -Dsun.java2d.d3d=false
     -Dsun.java2d.metal=false
     -Dsun.java2d.xrender=false
     -Dsun.java2d.pmoffscreen=false
     ```

     Restart IDEA. Other apps keep host-side GL; IDEA renders correctly
     but its own UI is slower. Adjust `<version>` (e.g. `2026.1`) per
     installed IDEA.

  2. Disable host-side GL globally for the VM. In UTM → Settings →
     Display, switch the **Display Device** to `virtio-gpu-pci` (no
     `-gl`). All apps lose host GL acceleration — noticeably slower
     overall — but rendering everywhere becomes correct. Use this if
     other Java/Skia apps misrender too.
- **"The password you use to log in to your computer no longer matches
  that of your login keyring"** (e.g. when launching Chromium): GDM
  auto-creates the GNOME login keyring on first login, encrypted with
  the seed password (`changeme`). Running `passwd` afterwards doesn't
  rekey the keyring, so PAM can no longer auto-unlock it. Either nuke
  it (loses saved Chromium cookies/passwords) — `rm -rf
  ~/.local/share/keyrings`, then log out and back in — or open Seahorse
  (`seahorse`), right-click the "Login" keyring → Change Password, with
  old = `changeme` and new = your current login password.
