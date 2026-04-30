# Koski NixOS sandbox VM

Reusable, team-shareable NixOS VM image for the Koski sandbox. One generic
qcow2 per architecture is built and distributed; each teammate's VM
personalizes itself on first boot to match the host username (required for
licensing). The VM user is always uid `1000` / gid `100` (`users`); the
`/mnt/share` mount is a `bindfs` layer over the raw 9p mount that remaps
ownership, so files appear as the VM user regardless of host uid/gid (501
/ 20 on macOS, 1000 / 100 on Linux, etc.) — no `chown` needed.

## End-user setup (each teammate)

You don't need Nix on your host. You need a VM runtime that supports a 9p
share named `share`:

- **Apple Silicon Mac**: [UTM](https://mac.getutm.app/), VirtFS share.
- **Intel Linux**: virt-manager with a Filesystem device.

### 1. Get the seed image

Download the qcow2 for your architecture from the team's shared storage
(name to be decided once the first seed is built):

- `koski-sandbox-aarch64.qcow2` — Apple Silicon Mac.
- `koski-sandbox-x86_64.qcow2` — Intel Linux.

### 2. Prepare the host share

```sh
mkdir -p ~/koski-share
echo "$USER" > ~/koski-share/.host-username
```

`.host-username` is read once at first boot to set the VM's user account.

### 3. Create the VM

#### UTM (Apple Silicon Mac)

1. Create a New Virtual Machine → **Virtualize** → Linux → **Use existing**
   → select the qcow2.
2. Memory ≥ 4 GB, CPU ≥ 4 cores, UEFI on (default).
3. Settings → **Sharing** → Directory Share Mode = **VirtFS**, Path =
   `~/koski-share`. **Share name must be exactly `share`** (matches
   `fileSystems."/mnt/share".device`).
4. Save.

#### virt-manager (Intel Linux)

1. New VM → **Import existing disk image** → select qcow2.
2. Q35 chipset, UEFI firmware, virtio disk + virtio NIC.
3. Add Hardware → **Filesystem**: Driver `path`, Source = host share dir,
   Target path = **`share`**.
4. Display = SPICE; Channel = `org.spice-space.webdav.0` and `spicevmc`
   (default in modern virt-manager).

### 4. First boot

Start the VM. GDM appears. The VM runs `koski-firstboot.service` in the
background — you can watch it:

```sh
# Log in to the throwaway "sandbox" account (password: changeme)
journalctl -u koski-firstboot -f
```

After ~1–2 minutes the VM personalizes itself with your host username and
reboots. Log in as `<your-host-username>` (password `changeme`); run
`passwd` immediately.

### 5. Verify

```sh
whoami            # → your host username
id                # → uid=1000 gid=100(users)
ls -la /mnt/share # files appear as <you>:users via bindfs, no chown needed
mount | grep share
# /run/koskishare on 9p
# /mnt/share on fuse.bindfs (layered on top)
```

## Updating the configuration after first boot

Inside the VM, the build-time flake source is at `/etc/nixos` (read-only,
in the Nix store). For changes, keep a writable copy of this repo on the
host's share directory and rebuild from `/mnt/share` inside the VM:

```sh
# On the host, once:
mv /path/to/your/koski-sandbox ~/koski-share/

# In the VM, after every edit:
sudo nixos-rebuild switch \
  --flake /mnt/share/koski-sandbox#sandbox-$(uname -m)-linux \
  --impure
```

This way you edit on the host with your normal tools, and the VM rebuilds
from the same files via 9p + bindfs.

Note: the 9p share is mounted with `cache=loose`, and bindfs adds its own
caching on top. The guest does not revalidate against the host, so any
structural change you make on the host while the VM is running — renaming
or moving the share directory, deleting files, swapping a file for a
symlink — can leave the VM with stale dentries that survive even an
`umount` + `mount`. Symptoms include `ls` showing files that `open()`
then can't find, and `?` in the ACL column of `ls -l`. Plain in-place
edits (saving a file from your editor) are fine; for anything more
invasive, shut the VM down first, or be prepared to reboot it.

## Claude Code

The VM ships with [Claude Code](https://docs.claude.com/en/docs/claude-code)
preinstalled (`claude` on `PATH`) and an `update-claude` command for pulling
the latest release on demand.

### Where Claude state lives

`~/.claude/` is a symlink to `/mnt/share/claude/<username>/`. Any
state Claude Code writes — settings, memories, MCP config, OAuth login,
project history, todos — survives `nixos-rebuild`, VM shutdown, and
recreating the VM from the seed image, as long as you keep using the same
`~/koski-share`. If a previous version of this VM had a real `~/.claude`
directory, it is migrated onto the share once on the next boot and replaced
with the symlink.

Note: This does not keep multiple VMs using same username sandboxed from each
other, only from the HOST. E.g. a pormpt-injection compromise in one VM could
plant a hook in the common settings that another VM ends up using. This is also
why `~/.claude/` is **not** a symlink to your host's own
`~/.claude/`: the VM is supposed to be a sandbox, so the host's own
credentials, hooks, and history stay outside the VM's reach.

### Be careful running multiple VMs as the same user simultaneously

The 9p file sharing has no lock manager and uses `cache=loose`. Two VMs
writing to the same `/mnt/share/claude/<user>/` give last-writer-wins on
every file, with stale-cache reads on top.

### Updating Claude Code

`claude-code` is pinned via a dedicated `claude-pkgs` flake input that
tracks `nixos-unstable`, separately from the rest of the system (which
stays on `nixos-25.11`). To pull the newest release:

```sh
update-claude
```

This runs `nix flake update claude-pkgs` against
`/mnt/share/koski-sandbox` and rebuilds. To bump everything
else, use the whole-system rebuild command in the section above.

## Maintainer setup (building the seed)

This is the one-time bootstrap. Run inside any NixOS environment matching
the target architecture — your existing UTM NixOS VM works for the
aarch64 seed.

```sh
cd ~/koski-sandbox   # or wherever you have it cloned
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

On the next boot (or after `sudo systemctl restart koski-git-bootstrap`),
`~/.gitconfig` inside the VM becomes a symlink to `/mnt/share/.gitconfig`.
Edits on either side are visible to the other, so `git config --global ...`
inside the VM writes back to the share. If `~/.gitconfig` already exists as a
real file, it is moved to `~/.gitconfig.bak.<timestamp>` before the symlink
replaces it.

**Don't symlink your host's real `~/.gitconfig` into `~/koski-share/`.** Use a
VM-specific copy. The host config typically references things that don't make
sense in the sandbox (signing key paths, `gpg.program`, credential helpers,
`includeIf` paths, custom diff/merge tools), and sharing it weakens the
isolation the VM is meant to provide. A minimal `[user]` block is usually
enough — add VM-only aliases and tooling on top as needed.

### Signed commits and pushing to GitHub

For now, **do signing and pushing to GitHub on the host**, not inside the VM.
Keep the working tree on `~/koski-share/` (so the VM and host see the same
checkout via `/mnt/share`), do unsigned commits inside the VM if you like,
and when you're ready to publish, sign-and-push from the host where your
1Password SSH agent / signing key already lives. Don't have both sides
touching the same `.git/` at the same time — 9p has no lock manager and uses
`cache=loose`, so concurrent writers will corrupt refs and the index.

## (Possible) TODOs

- Figure out the recommended way to create signed commits and push to GitHub
  from inside the VM (e.g. forwarding the host's 1Password SSH agent over a
  vsock/TCP bridge, or a per-VM signing key registered with GitHub). Until
  then, sign and push from the host as described above.
- GitHub Actions matrix building qcow2 for both arches and uploading to Releases (replaces
the manual seed handoff).
- Bootstrap path for users who don't yet have any NixOS VM and need to build a seed from
scratch on macOS (would bring back something like nix-darwin linux-builder, or a temporary
Lima/Tart VM, or CI).

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
