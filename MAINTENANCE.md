# Maintenance

This document is for contributors who update the NixOS configuration, publish
commits, or build images. For installation and user-facing testing, see
[README.md](README.md). Review [SECURITY.md](SECURITY.md) before working across
the host/VM boundary.

## Repository Topology

Maintain separate clones in the shared directory so GitHub credentials and
signing keys stay out of the VM.

First clone the repository on the host:

```sh
git clone git@github.com:AleksiAhtiainen/ai-sandbox.git \
  ~/ai-sandbox-share/ai-sandbox-host
```

After completing first boot, create the VM clone in the VM and apply the
checked-out configuration:

```sh
git -c clone.defaultRemoteName=host clone \
  /mnt/share/ai-sandbox-host /mnt/share/ai-sandbox-vm
cd /mnt/share/ai-sandbox-vm
sudo nixos-rebuild switch --flake .#sandbox-$(uname -m)-linux --impure
```

Add the VM clone as a remote on the host:

```sh
git -C ~/ai-sandbox-share/ai-sandbox-host remote add vm \
  ../ai-sandbox-vm
```

Use one designated writer per clone:

| VM path | Designated writer | Remotes |
| --- | --- | --- |
| `/mnt/share/ai-sandbox-host` | Host | `origin` and `vm` |
| `/mnt/share/ai-sandbox-vm` | VM | `host` |

The host reviews, signs, and publishes commits. The VM edits and tests the
NixOS configuration. Never write to either clone concurrently from both sides.

## Update The VM

### Get repository changes

Update the host clone on the host:

```sh
git -C ~/ai-sandbox-share/ai-sandbox-host pull --ff-only origin main
```

Then update the VM clone in the VM:

```sh
cd /mnt/share/ai-sandbox-vm
git pull --ff-only host main
```

### Update Nix inputs

Update the release-branch input approximately once a week:

```sh
nix flake update nixpkgs
```

To update only the unstable input:

```sh
nix flake update unstable
```

Review the resulting `flake.lock` changes before rebuilding.

### Apply and test changes

Run in the VM after a repository or input change:

```sh
cd /mnt/share/ai-sandbox-vm
sudo nixos-rebuild switch --flake .#sandbox-$(uname -m)-linux --impure
```

Test the affected functionality and run the smoke tests in
[README.md](README.md#test-the-installation). Then commit only intended files.
For an input update:

```sh
git status --short
git add flake.lock
git commit -m "Update Nix inputs"
```

Configure the optional VM Git identity as described in
[README.md](README.md#git-identity) if needed.

## Publish VM Commits

### Review, sign, and push

Run on the host:

```sh
cd ~/ai-sandbox-share/ai-sandbox-host
git fetch vm main
git log --patch --stat main..vm/main
git cherry-pick -S $(git rev-list --reverse main..vm/main)
git push origin main
```

Inspect every change before cherry-picking it. The cherry-pick creates signed
commits with new commit IDs.

### Reconcile the VM branch

After the push succeeds, run in the VM:

```sh
cd /mnt/share/ai-sandbox-vm
git fetch host
git status --short
```

The status command must produce no output. If it does, stop and preserve the
uncommitted work. If the tree is clean, replace the unsigned commit IDs with
the signed IDs:

```sh
git reset --hard host/main
```

## Image Architecture

`flake.nix` separates the image into two module groups:

- `seedModules` form the redistributable public seed image.
- `postSeedModules` are installed by the user's first boot.

The public seed starts at a text console. The first-boot service rebuilds the
embedded flake at `/etc/nixos`, asks for a password, and restarts into GNOME.
The private full image contains both module groups.

The image uses EFI and an ext4 root file system. It grows the root partition
automatically, creates an 8 GiB swap file, and keeps three GRUB generations.

## Build Images

### Build a seed image

Use a NixOS system with the same architecture as the target image. For example,
run in the sandbox VM:

```sh
cd /mnt/share/ai-sandbox-vm
nix build .#packages.$(uname -m)-linux.compressedImage --impure -L
cp -L result /mnt/share/ai-sandbox-$(uname -m).qcow2
```

This creates an `aarch64-linux` image on an Apple Silicon VM and an
`x86_64-linux` image on an x86_64 NixOS system.

The `--impure` option is required because `modules/user.nix` reads
`/etc/ai-sandbox-username` during evaluation. It uses `sandbox` as the fallback
username during a seed build.

### Build with GitHub Actions

`.github/workflows/build_seed_images.yml` builds both seed images weekly on
Sunday at 03:00 UTC. Start it manually from the Actions page or with:

```sh
gh workflow run "Build seed images"
```

The x86_64 job uses KVM on `ubuntu-24.04`. The aarch64 job uses
`ubuntu-24.04-arm` without KVM, so TCG software emulation can make it 10 to 50
times slower. Each job uploads an `ai-sandbox-<arch>` artifact containing an
internally compressed qcow2 file.

### Build a private full image

Use a full image when the first-boot download is impractical:

```sh
cd /mnt/share/ai-sandbox-vm
nix build .#packages.$(uname -m)-linux.compressedFullImage --impure -L
cp -L result /mnt/share/ai-sandbox-full-$(uname -m).qcow2
```

First boot still personalizes the username and runs `nixos-rebuild`. The large
package closures are already on disk.

Do not distribute the full image. It contains IntelliJ IDEA Ultimate and
Claude Code, and this project does not have redistribution rights for those
packages. GitHub Actions builds only the public seed image.

### Select a module group

Before adding a package, check its license and installed size.

- Put only redistributable packages in `seedModules`.
- Put non-redistributable packages in `postSeedModules`.
- Put large packages in `postSeedModules` to keep the public image small.
- Read the upstream license. Nix license metadata and `allowUnfree` are useful
  signals, not proof of redistribution rights.
- Use `postSeedModules` if the license is unclear.

## Maintenance Checks

Before publishing a configuration change:

1. Review `git diff` and ensure no credentials or generated VM state is added.
2. Run `nix flake check --impure`.
3. Apply the configuration with `nixos-rebuild switch` on the relevant
   architecture.
4. Test the affected tools and the README smoke tests.
5. Build the seed image when changing seed modules, first-boot behavior, disk
   layout, or image generation.
6. Confirm that public artifacts contain no post-seed proprietary packages.

Architecture-specific changes should be tested on both `aarch64-linux` and
`x86_64-linux`, using GitHub Actions when both local architectures are not
available.
