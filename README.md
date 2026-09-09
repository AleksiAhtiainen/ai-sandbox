# AI Sandbox NixOS VM

Reusable NixOS VM images for an AI development sandbox. Images are available
for `aarch64-linux` and `x86_64-linux`.

The VM includes GNOME, IntelliJ IDEA, Claude Code, OpenCode, Docker, and common
development tools. Read [SECURITY.md](SECURITY.md) before using untrusted code.
Repository maintainers should also read [MAINTENANCE.md](MAINTENANCE.md).

## Requirements

- UTM or another VM manager that supports qcow2 disks and 9p/VirtFS shares.
- At least 16 GiB of memory and four CPU cores for the VM.
- At least 128 GB of virtual disk space if you plan to build images.
- A macOS or Linux host.

The instructions use `~/ai-sandbox-share` on the host and `/mnt/share` in the
VM.

## Install

### 1. Prepare the host

Run these commands on the host:

```sh
mkdir -p ~/ai-sandbox-share/shared-config
printf '%s\n' "$USER" > ~/ai-sandbox-share/shared-config/.host-username
```

The username must match `^[a-z_][a-z0-9_-]{0,31}$`. If the host username
contains a period, put a valid Linux username in `.host-username` instead. For
example, use `firstname` instead of `firstname.lastname`.

### 2. Download the image

Open the latest successful
[Build seed images](https://github.com/AleksiAhtiainen/ai-sandbox/actions/workflows/build_seed_images.yml)
run. Download the `ai-sandbox-<arch>` artifact for the VM architecture. The
artifact contains `ai-sandbox-<arch>.qcow2`.

Use `aarch64` on Apple Silicon and `x86_64` on an Intel or AMD host.

### 3. Create the VM

Create a VM in UTM or a compatible VM manager:

1. Use the qcow2 file as an existing disk.
2. Add a 9p or VirtFS share with the tag `share`.
3. Map the share to `~/ai-sandbox-share` on the host.
4. Assign at least 16 GiB of memory and four CPU cores.
5. Increase the virtual disk to at least 128 GB if you will build images.

The share tag must be exactly `share`. UTM uses this tag by default. The root
partition and file system grow automatically when the virtual disk is larger.

### 4. Complete the first boot

Boot the VM and keep the text console open. The seed image:

1. Reads `shared-config/.host-username` from the share.
2. Creates the VM user.
3. Downloads and installs the desktop and development tools.
4. Asks you to set a login password.
5. Restarts the VM and opens GDM.

The download is more than 10 GB and is usually limited by network speed. No
default password is in the seed image. The account stays locked until you set
a password.

## Test The Installation

After signing in, open a terminal in the VM and run:

```sh
test -w /mnt/share
touch /mnt/share/ai-sandbox-smoke-test
nixos-version
docker run --rm hello-world
claude --version
opencode --version
```

Also verify that:

- GNOME starts and the VM can access the Internet.
- `ai-sandbox-smoke-test` appears in `~/ai-sandbox-share` on the host.
- IntelliJ IDEA starts.
- `curl http://192.168.64.1:8080/v1/models` succeeds if you configured the
  optional host AI model.

Delete the test file from the VM with
`rm /mnt/share/ai-sandbox-smoke-test`. Do not let the host and VM write to the
same shared directory simultaneously.

## Shared State

The share keeps configuration and work across rebuilds, restarts, and VM
replacement. Paths below are shown from the VM:

| Path | Writer | Purpose |
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

The raw 9p mount is `/run/ai-sandbox-share`. A `bindfs` layer exposes it as
`/mnt/share` and maps ownership to VM user ID `1000` and group ID `100`.

## Host AI Model

OpenCode can use a `muse-glimmer-local` model from a llama.cpp server on the
macOS host. This keeps the model files out of the VM.

### Start llama.cpp

Build llama.cpp and download the model files. Find the host vmnet IP:

```sh
ifconfig bridge* | grep inet
```

The usual UTM address is `192.168.64.1`. Start the server on that address:

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

In UTM, select **Settings > Devices > Network > Network Mode > Shared
Network**. Test the server from the VM:

```sh
curl http://192.168.64.1:8080/v1/models
```

### Configure OpenCode

On first boot, `modules/opencode.nix` creates
`/mnt/share/shared-config/opencode/opencode.json` if it does not exist. Its
defaults are:

| Setting | Value |
| --- | --- |
| Provider | `llama.cpp` |
| Model | `llama.cpp/muse-glimmer-local` |
| Base URL | `http://192.168.64.1:8080/v1` |
| Context limit | `131072` |
| Output limit | `8192` |

Edit `baseURL` if the vmnet IP differs. OpenCode does not overwrite an existing
configuration file.

## Claude Code And MCP

[Claude Code](https://docs.claude.com/en/docs/claude-code) is available as
`claude` after first boot.

`~/.claude/` links to `/mnt/share/shared-config/claude/`, so its contents
survive VM replacement. `~/.claude.json` stays on the VM disk and does not.
The `ai-sandbox-claude-bootstrap` service adds these MCP entries on each boot:

| Name | Function |
| --- | --- |
| `chrome-devtools` | Runs the MCP server in isolated Chromium. |
| `idea` | Connects to IntelliJ IDEA at `http://127.0.0.1:64342/sse`. |

Existing entries are not changed. If you remove a seeded entry, it returns on
the next boot. Add `--headless` to the Chrome entry to hide its browser window.

The `ai-sandbox-idea-bootstrap` service enables the IDEA MCP server and brave
mode on a new VM. Later changes in IDEA persist across restarts but not VM
replacement. If IDEA uses a port other than `64342`, update the `idea` entry in
`~/.claude.json`.

## Optional Configuration

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
helpers, signing keys, include paths, hooks, and host-only tools.

### Fish shell

Fish is installed, but Bash is the default login shell. Run in the VM:

```sh
mkdir -p /mnt/share/shared-config/fish_config
sudo systemctl restart ai-sandbox-fish-bootstrap
fish-on
```

Log out and back in. Use `fish-off` to restore Bash. The bootstrap service does
not replace a nonempty local `~/.config/fish` directory.

### Pop Shell

Pop Shell is installed but disabled. Run `pop-shell-on`, then log out and back
in. Run `pop-shell-off` to disable it.

| Keys | Action |
| --- | --- |
| `Super+Y` | Toggle tiling. |
| `Super+-` | Open the launcher. |
| `Super+Return` | Enter window-adjustment mode. |
| `Super+Arrow` | Move focus. |
| `Super+Shift+Arrow` | Swap windows. |

### Java SDK

Use `/etc/jdks/jdk17` as the JDK path in IntelliJ IDEA. It remains stable when
a Nix rebuild changes the Nix store path.

## Known Limitations

- The VM has no SSH server.
- The desktop uses Finnish Mac keyboard settings and the `Europe/Helsinki`
  time zone.
- 9p has no lock manager and is slower than a locked virtiofs setup.
- SPICE clipboard integration usually transfers text, not images.

See [SECURITY.md](SECURITY.md) for the security implications of the share,
network, clipboard, and installed tools.

## Troubleshooting

### First boot waits for a username

Fix `~/ai-sandbox-share/shared-config/.host-username` on the host. It must match
`^[a-z_][a-z0-9_-]{0,31}$`. Press Enter in the VM console, or inspect the
service:

```sh
journalctl -u ai-sandbox-firstboot
```

### First boot stopped after accepting the username

Remove the marker and restart the service:

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

`/mnt/share` must be a `fuse.bindfs` mount. If only `/run/ai-sandbox-share` is
mounted, the `bindfs` mount failed.

### The VM has the wrong username

Correct `.host-username` on the host, then repeat first boot:

```sh
sudo rm /etc/ai-sandbox-username
sudo systemctl start ai-sandbox-firstboot
```

### IntelliJ IDEA license activation fails

JetBrains can associate activation with the operating-system username. If the
VM username differs from the host username, override the Java user name:

```sh
idea -Duser.name=firstname.lastname
```
