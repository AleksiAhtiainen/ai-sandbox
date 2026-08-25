# AI Sandbox NixOS VM

This project provides reusable NixOS VM images for an AI development sandbox.
It supports `aarch64-linux` and `x86_64-linux`.

## Terms

| Term | Meaning |
| --- | --- |
| Host | The macOS or Linux system that runs the VM. |
| VM | The NixOS guest system. |
| Share | `~/ai-sandbox-share` on the host and `/mnt/share` in the VM. |
| Seed image | Public image with first-boot downloads. |
| Full image | Private image with all packages. Do not distribute it. |

## Security limits

The VM reduces direct access to the host. The share, network, and clipboard are
still data paths between the VM and the host.

### Shared files

Treat all files that the VM writes as untrusted files on the host.

- Do not run scripts or binaries from the share on the host.
- Do not open projects from the share in a host tool that can run code.
- This restriction includes IDE plug-ins, language servers, Git hooks,
  `direnv`, `mise`, and package installation hooks.
- Do not let host tools automatically index the complete share.
- Review VM commits on the host before you sign and publish them.

The host and the VM can write to all paths in the share. The writer roles in
this document are a convention, not an access control. The 9p file system has
no lock manager. Never let the host and the VM, or two VMs, write to the same
directory at the same time.

### Network and tools

UTM Shared Network gives the VM Internet access. It also lets the VM connect to
services on the host vmnet interface.

- Bind host services to the vmnet IP when only the VM must use them.
- Do not bind a host service to `0.0.0.0` unless LAN access is necessary.
- Treat the SPICE clipboard as another data path between the VM and the host.
- The VM user is in the `wheel` and `docker` groups. Docker access is
  root-equivalent inside the VM.
- OpenCode permits tool use by default. Session sharing and automatic updates
  are disabled.
- The IntelliJ IDEA MCP server uses brave mode. It does not ask for approval
  for each tool call.
- GNOME screen locking is disabled.

Keep untrusted code and dependencies in the VM. Do not give them access to
host services or shared data that they do not need.

## Start the VM

### 1. Prepare the host

Run these commands on the host:

```sh
mkdir -p ~/ai-sandbox-share/shared-config
printf '%s\n' "$USER" > ~/ai-sandbox-share/shared-config/.host-username
git clone git@github.com:AleksiAhtiainen/ai-sandbox.git \
  ~/ai-sandbox-share/ai-sandbox-host
```

The username must match this expression:

```text
^[a-z_][a-z0-9_-]{0,31}$
```

If the host username contains a period, select a valid Linux username and put
it in `.host-username`. For example, use `firstname` instead of
`firstname.lastname`.

### 2. Download the seed image

Open the latest successful
[Build seed images](https://github.com/AleksiAhtiainen/ai-sandbox/actions/workflows/build_seed_images.yml)
run. Download the `ai-sandbox-<arch>` artifact for the VM architecture. The
artifact contains `ai-sandbox-<arch>.qcow2`.

### 3. Create the VM

Create a VM in UTM or a compatible VM manager.

1. Use the qcow2 file as an existing disk.
2. Add a 9p or VirtFS share with the tag `share`.
3. Map the share to `~/ai-sandbox-share` on the host.
4. Assign at least 16 GiB of memory and four CPU cores.
5. Increase the virtual disk to at least 128 GB if you will build images in
   the VM.

The share tag must be exactly `share`. UTM uses this tag by default. The root
partition and file system grow automatically when the virtual disk is larger.

### 4. Complete the first boot

Boot the VM and keep the text console open.

The seed image does these operations on `tty1`:

1. It reads `shared-config/.host-username` from the share.
2. It creates the VM user.
3. It downloads and installs GNOME, IntelliJ IDEA, Claude Code, OpenCode, and
   the development tools.
4. It asks you to set a login password.
5. It restarts the VM and opens GDM.

The download is more than 10 GB. The first boot is usually limited by network
speed. No default password is in the seed image. The account stays locked
until you set a password.

### 5. Create the VM clone

After the first boot, run these commands in the VM:

```sh
git -c clone.defaultRemoteName=host clone \
  /mnt/share/ai-sandbox-host /mnt/share/ai-sandbox-vm
cd /mnt/share/ai-sandbox-vm
sudo nixos-rebuild switch --flake .#sandbox-$(uname -m)-linux --impure
```

The remote for this clone is named `host`.

### 6. Add the VM remote

Run this command on the host:

```sh
git -C ~/ai-sandbox-share/ai-sandbox-host remote add vm \
  ../ai-sandbox-vm
```

Use one designated writer for each clone:

| VM path | Designated writer | Remotes |
| --- | --- | --- |
| `/mnt/share/ai-sandbox-host` | Host | `origin` and `vm` |
| `/mnt/share/ai-sandbox-vm` | VM | `host` |

This topology prevents normal workflows from using concurrent writers. It
also lets the host review, sign, and publish commits without putting GitHub
credentials in the VM.

## Update the VM

### Get repository changes

First, update the host clone on the host:

```sh
git -C ~/ai-sandbox-share/ai-sandbox-host pull --ff-only origin main
```

Then update the VM clone in the VM:

```sh
cd /mnt/share/ai-sandbox-vm
git pull --ff-only host main
```

### Update Nix inputs

Update `nixpkgs` approximately once a week:

```sh
nix flake update nixpkgs
```

To update only the unstable input, run:

```sh
nix flake update unstable
```

The unstable input supplies Claude Code and IntelliJ IDEA.

### Apply changes

Run this command in the VM after a repository or input change:

```sh
cd /mnt/share/ai-sandbox-vm
sudo nixos-rebuild switch --flake .#sandbox-$(uname -m)-linux --impure
```

Test the new configuration. Then commit the intended files in the VM. For an
input update, use this example:

```sh
git status --short
git add flake.lock
git commit -m "Update Nix inputs"
```

See [Git identity](#git-identity) if Git does not have your name and email
address.

## Publish VM commits

The VM has no GitHub credentials or signing key. Publish its commits from the
host.

### 1. Review and sign

Run these commands on the host:

```sh
cd ~/ai-sandbox-share/ai-sandbox-host
git fetch vm main
git log --patch --stat main..vm/main
git cherry-pick -S $(git rev-list --reverse main..vm/main)
git push origin main
```

The `cherry-pick` command creates signed commits with new commit IDs.

### 2. Reconcile the VM branch

After the push succeeds, run these commands in the VM:

```sh
cd /mnt/share/ai-sandbox-vm
git fetch host
git status --short
```

The `git status --short` command must show no output. If it shows output, stop.
Otherwise, replace the unsigned commit IDs with the signed commit IDs:

```sh
git reset --hard host/main
```

## Shared state

The share keeps configuration and work across rebuilds, restarts, and VM
replacement. These paths are shown from the VM:

| Path | Designated writer | Purpose |
| --- | --- | --- |
| `shared-config/.host-username` | Host | Required VM username. |
| `shared-config/.gitconfig` | Host | Optional Git identity for the VM. |
| `shared-config/claude/` | VM | Claude Code state and login data. |
| `shared-config/opencode/` | VM | OpenCode configuration and state. |
| `shared-config/tmux/` | VM | Tmux configuration. |
| `shared-config/nvim/` | VM | Neovim configuration. |
| `shared-config/fish_config/` | VM | Optional Fish configuration. |
| `shared-config/.fish` | VM | Fish login-shell state: `on` or `off`. |
| `shared-config/.pop-shell` | VM | Pop Shell state: `on` or `off`. |
| `ai-sandbox-host/` | Host | Clone that pulls from and pushes to GitHub. |
| `ai-sandbox-vm/` | VM | Clone used by `nixos-rebuild`. |
| `ai-sandbox-<arch>.qcow2` | Maintainer | Optional staged seed image. |

The raw 9p mount is `/run/ai-sandbox-share`. A `bindfs` layer exposes it as
`/mnt/share`. The layer maps file ownership to VM user ID `1000` and group ID
`100`.

## Host AI model

OpenCode can use a `muse-glimmer-local` model from a llama.cpp server on the
macOS host. This configuration keeps the model files out of the VM.

### Start llama.cpp

Build llama.cpp and download the model files. Then find the host vmnet IP:

```sh
ifconfig bridge* | grep inet
```

The usual UTM address is `192.168.64.1`. Check the address after a major UTM
or macOS change.

Start the server on the vmnet address:

```sh
./build/bin/llama-server \
  -m custom-models/muse-glimmer-30B-kquant-17gb.gguf \
  --mmproj custom-models/mmproj-kquant.gguf \
  -a muse-glimmer-local \
  -ngl 99 -c 131072 -np 1 \
  --host 192.168.64.1 --port 8080 \
  --jinja \
  --temp 1.0 --top-p 0.95 --top-k 64
```

Do not use `--host 0.0.0.0` unless you need LAN access.

### Configure UTM

Use **Settings > Devices > Network > Network Mode > Shared Network**. The VM
usually gets an address in `192.168.64.0/24`.

Test the server from the VM:

```sh
curl http://192.168.64.1:8080/v1/models
```

### Configure OpenCode

On the first boot, `modules/opencode.nix` creates this file if it does not
exist:

```text
/mnt/share/shared-config/opencode/opencode.json
```

The default configuration uses these values:

| Setting | Value |
| --- | --- |
| Provider | `llama.cpp` |
| Model | `llama.cpp/muse-glimmer-local` |
| Base URL | `http://192.168.64.1:8080/v1` |
| Context limit | `131072` |
| Output limit | `8192` |

Edit `baseURL` if the vmnet IP is different. OpenCode does not overwrite an
existing configuration file.

## Claude Code and MCP

[Claude Code](https://docs.claude.com/en/docs/claude-code) is available as
`claude` after first-boot installation.

`~/.claude/` links to `/mnt/share/shared-config/claude/`. Its contents survive
VM replacement. This directory can contain credentials and private project
data. Do not use the same directory from two VMs at the same time.

`~/.claude.json` stays on the VM disk. It does not survive VM replacement.
The `ai-sandbox-claude-bootstrap` service adds these MCP entries on each boot:

| Name | Function |
| --- | --- |
| `chrome-devtools` | Runs the MCP server in isolated Chromium. |
| `idea` | Connects to IntelliJ IDEA at `http://127.0.0.1:64342/sse`. |

Existing entries are not changed. If you remove a seeded entry, it returns on
the next boot. Add `--headless` to the Chrome entry if you do not want a
visible browser window.

The `ai-sandbox-idea-bootstrap` service enables the IDEA MCP server and brave
mode on a new VM. IDEA owns the setting after the service creates it. A change
in IDEA persists across restarts, but not across VM replacement. If IDEA uses
a port other than `64342`, update the `idea` entry in `~/.claude.json`.

## Optional configuration

### Git identity

Create a minimal Git configuration on the host:

```sh
cat > ~/ai-sandbox-share/shared-config/.gitconfig <<'EOF'
[user]
  name = Your Name
  email = you@example.com
EOF
```

Do not link the host `~/.gitconfig` to the share. It can expose credential
helpers, signing keys, include paths, hooks, and host-only tools. Use a
separate configuration for the VM.

### Fish shell

[Fish](https://fishshell.com/) is installed, but Bash is the default login
shell. Run these commands in the VM to use Fish:

```sh
mkdir -p /mnt/share/shared-config/fish_config
sudo systemctl restart ai-sandbox-fish-bootstrap
fish-on
```

Log out and log in. Use `fish-off` to restore Bash. The `.fish` marker and
Fish configuration survive rebuilds and VM replacement.

The bootstrap service does not replace a nonempty local `~/.config/fish`
directory.

### Pop Shell

[Pop Shell](https://github.com/pop-os/shell) is installed but disabled. Run
this command in the VM to enable it:

```sh
pop-shell-on
```

On Wayland, log out and log in after the first enable operation. Run
`pop-shell-off` to disable it.

Key bindings:

| Keys | Action |
| --- | --- |
| `Super+Y` | Toggle tiling. |
| `Super+-` | Open the launcher. |
| `Super+Return` | Enter window-adjustment mode. |
| `Super+Arrow` | Move focus. |
| `Super+Shift+Arrow` | Swap windows. |

### Java SDK

Use `/etc/jdks/jdk17` as the JDK path in IntelliJ IDEA. This path stays stable
when a Nix rebuild changes the Nix store path.

## Image architecture

`flake.nix` separates the image into two module groups.

- `seedModules` contains `base`, `share`, `user`, `firstboot`, `vm`, `git`,
  and `fish`. These modules form the public seed image.
- `postSeedModules` contains `desktop`, `spice`, `claude`, `idea`,
  `dev-tools`, `opencode`, `tmux-neovim`, and `yed`. First boot installs these
  modules.

The public seed starts at a text console. The first-boot service rebuilds the
embedded flake at `/etc/nixos`, sets the password, and restarts into GNOME.
The private full image contains both module groups.

The image uses EFI and an ext4 root file system. It grows the root partition
automatically, creates an 8 GiB swap file, and keeps three GRUB generations.

## Build images

### Build a seed image

Use a NixOS system with the same architecture as the target image. For
example, run these commands in the sandbox VM:

```sh
cd /mnt/share/ai-sandbox-vm
nix build .#packages.$(uname -m)-linux.compressedImage --impure -L
cp -L result /mnt/share/ai-sandbox-$(uname -m).qcow2
```

The build creates an `aarch64-linux` image on an Apple Silicon VM and an
`x86_64-linux` image on an x86_64 NixOS system.

The `--impure` option is required. `modules/user.nix` reads
`/etc/ai-sandbox-username` during evaluation. It uses `sandbox` as the fallback
username during a seed build.

### Build with GitHub Actions

`.github/workflows/build_seed_images.yml` builds both seed images each day at
03:00 UTC. You can also start it manually from the Actions page or with this
command:

```sh
gh workflow run "Build seed images"
```

The x86_64 job uses KVM on `ubuntu-24.04`. The aarch64 job uses
`ubuntu-24.04-arm` without KVM. The aarch64 build uses TCG software emulation
and can be 10 to 50 times slower.

Each job uploads an `ai-sandbox-<arch>` artifact that contains an internally
compressed qcow2 file.

### Build a private full image

Use a full image when the first-boot download is not practical:

```sh
cd /mnt/share/ai-sandbox-vm
nix build .#packages.$(uname -m)-linux.compressedFullImage --impure -L
cp -L result /mnt/share/ai-sandbox-full-image$(uname -m)-.qcow2
```

First boot still personalizes the username and runs `nixos-rebuild`. The large
package closures are already on the disk, so the rebuild does not require the
normal large download.

Do not distribute the full image. It contains IntelliJ IDEA Ultimate and
Claude Code. This project does not have redistribution rights for those
packages. GitHub Actions builds only the public seed image.

### Select a module group

Before you add a package, check its license and its installed size.

- Put only redistributable packages in `seedModules`.
- Put non-redistributable packages in `postSeedModules`.
- Put large packages in `postSeedModules` to keep the public image small.
- Read the upstream license terms. Nix license metadata and `allowUnfree` are
  useful signals, but they are not proof of redistribution rights.
- If the license is not clear, use `postSeedModules`.

## Known limitations

- The VM has no SSH server.
- The desktop uses Finnish Mac keyboard settings and the `Europe/Helsinki`
  time zone.
- 9p has no lock manager and is slower than a locked virtiofs setup.
- Signing and GitHub push operations require the host workflow in this
  document.
- SPICE clipboard integration usually transfers text, not images. To transfer
  an image, save it in the share and treat it as untrusted on the host.
- The broad share is the primary file transfer path and a major trust
  boundary.

## Troubleshooting

### First boot waits for a username

The service waits when `.host-username` is missing or invalid. Fix this file on
the host:

```text
~/ai-sandbox-share/shared-config/.host-username
```

Use a value that matches `^[a-z_][a-z0-9_-]{0,31}$`. Then press Enter in the
VM console. Use this command to inspect the service:

```sh
journalctl -u ai-sandbox-firstboot
```

### First boot stopped after it accepted the username

The service writes `/etc/ai-sandbox-username` before it runs the rebuild and
password prompt. If the process stops after this point, remove the marker and
start the service again:

```sh
sudo rm /etc/ai-sandbox-username
sudo systemctl start ai-sandbox-firstboot
```

### The share does not mount

Confirm that the UTM VirtFS tag is `share`. It must match the device in
`fileSystems."/mnt/share"`.

### Writes to `/mnt/share` fail

Check the `bindfs` mount:

```sh
mount | grep fuse.bindfs
journalctl -u mnt-share.mount
```

`/mnt/share` must be a `fuse.bindfs` mount. If only
`/run/ai-sandbox-share` is mounted, the `bindfs` mount failed.

### The VM has the wrong username

Correct `.host-username` on the host. Then repeat first boot:

```sh
sudo rm /etc/ai-sandbox-username
sudo systemctl start ai-sandbox-firstboot
```

### IntelliJ IDEA license activation fails

JetBrains can associate an activation with the operating-system username. If
the VM username is different from the host username, override the Java user
name:

```sh
idea -Duser.name=firstname.lastname
```
