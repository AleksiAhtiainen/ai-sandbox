# Koski NixOS sandbox VM

Reusable, team-shareable NixOS VM image for the Koski sandbox. One generic
qcow2 per architecture is built and distributed; each teammate's VM
personalizes itself on first boot to match the host username (required for
licensing) and the host uid/gid (so files in `/mnt/share` Just Work without
`chown`).

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

After ~1–2 minutes the VM personalizes itself with your host username +
uid/gid and reboots. Log in as `<your-host-username>` (password
`changeme`); run `passwd` immediately.

### 5. Verify

```sh
whoami            # → your host username
id -u             # → your host uid (e.g. 501 on macOS, 1000 on Linux)
ls -la /mnt/share # files appear owned by your VM user, no chown needed
```

## Maintainer setup (building the seed)

This is the one-time bootstrap. Run inside any NixOS environment matching
the target architecture — your existing UTM NixOS VM works for the
aarch64 seed.

```sh
cd ~/koski-nixos-sandbox-config   # or wherever you have it cloned
nix build .#packages.aarch64-linux.image --impure -L
cp -L result/nixos.qcow2 /mnt/share/koski-sandbox-aarch64.qcow2
```

`--impure` is needed because `modules/user.nix` reads `/etc/koski-sandbox-*`
files at evaluation time (with safe fallbacks during the seed build, so
the seed gets the placeholder user `sandbox` / uid 1000 / gid 100). The
fallback values are overwritten on each teammate's first boot.

For x86_64 the same command on an Intel-Linux NixOS environment, with
`packages.x86_64-linux.image`.

Distribute the resulting qcow2 to the team via shared storage. CI builds
+ Releases are out of scope for now (planned follow-up).

## Updating the configuration after first boot

Inside the VM, the build-time flake source is at `/etc/nixos` (read-only,
in the Nix store). To make changes:

```sh
# Clone a writable copy
git clone <repo-url> ~/koski-nixos-sandbox-config
cd ~/koski-nixos-sandbox-config

# Edit, then rebuild
sudo nixos-rebuild switch --flake .#sandbox-$(uname -m)-linux --impure
```

(Replace `sandbox-aarch64-linux` / `sandbox-x86_64-linux` as appropriate.)

## Troubleshooting

- **`koski-firstboot.service` failed**: most likely `/mnt/share/.host-username`
  was missing or contained whitespace/invalid characters.
  `journalctl -u koski-firstboot` shows the exact reason. Fix the file on
  the host, then `sudo systemctl restart koski-firstboot`.
- **9p share didn't mount**: confirm the share name is exactly `share`
  in your VM runtime's settings. UTM "VirtFS" name must match
  `fileSystems."/mnt/share".device`.
- **Wrong uid in `/mnt/share` after first boot**: re-trigger first-boot:
  `sudo rm /etc/koski-sandbox-username && sudo systemctl start koski-firstboot`.
