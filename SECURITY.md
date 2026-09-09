# Security

## Security Model

The VM reduces direct access to the host. It is not a complete security
boundary: the shared directory, network, and clipboard remain data paths
between the VM and host. The image also does not eliminate software
supply-chain risks in NixOS packages, binary caches, or upstream downloads.

Keep untrusted code and dependencies in the VM. Do not give them access to host
services or shared data they do not need.

## Shared Files

Treat every file written by the VM as untrusted on the host.

- Do not run scripts or binaries from the share on the host.
- Do not open shared projects in host tools that can run code.
- This includes IDE plug-ins, language servers, Git hooks, `direnv`, `mise`,
  and package installation hooks.
- Do not let host tools automatically index the complete share.
- Review VM commits on the host before signing and publishing them.

The host and VM can write to every path in the share. Documented writer roles
are a convention, not access control. The 9p file system has no lock manager.
Never let the host and VM, or two VMs, write to the same directory at the same
time.

The share can contain credentials and private project data. In particular,
`shared-config/claude/` contains persistent Claude Code state and login data.
Do not use the same state directory from two VMs simultaneously.

## Network And Clipboard

UTM Shared Network gives the VM Internet access and lets it connect to services
on the host vmnet interface.

- Bind host services to the vmnet IP when only the VM needs them.
- Do not bind a host service to `0.0.0.0` unless LAN access is necessary.
- Authenticate sensitive host services even when they only listen on vmnet.
- Treat the SPICE clipboard as another data path between the VM and host.
- Transfer images through the share when clipboard image transfer is
  unavailable, and treat them as untrusted on the host.

## Privileged Tools

- The VM user belongs to `wheel` and can use `sudo`.
- The VM user belongs to `docker`; Docker access is root-equivalent inside the
  VM.
- OpenCode permits tool use by default. Session sharing and automatic updates
  are disabled.
- The IntelliJ IDEA MCP server uses brave mode and does not request approval
  for each tool call.
- GNOME screen locking is disabled.
- The VM has no SSH server.

Do not leave an unlocked VM accessible to people who should not have access to
its data or tools.

## Software Supply Chain

The system uses a NixOS release branch and the faster-moving
`nixos-unstable-small` branch. Unstable-small receives less stabilization than
a release branch, so updates can introduce newer defects or compromised
upstream software sooner.

Review `flake.lock` updates, package sources, and build results. Nix hashes and
binary caches improve reproducibility but do not establish that upstream code
is trustworthy.

Public seed images contain only packages intended for redistribution. Private
full images contain IntelliJ IDEA Ultimate and Claude Code, for which this
project does not have redistribution rights. Never publish or distribute a
full image.

## Git And Publishing

The VM intentionally has no GitHub credentials or signing key. Use the
two-clone workflow in [MAINTENANCE.md](MAINTENANCE.md) to review VM commits on
the host, create signed commits, and publish them.

Do not expose the host Git configuration to the VM. Credential helpers,
signing keys, include paths, hooks, and host-only tools may otherwise cross the
trust boundary.

## Reporting A Vulnerability

Do not include secrets, credentials, or private project data in a public
report. Report vulnerabilities through the repository's GitHub security
advisory interface when available; otherwise contact the repository owner
privately before opening a public issue.
