{ pkgs, lib, ... }:

let
  readOr = path: default:
    if builtins.pathExists path
    then lib.removeSuffix "\n" (builtins.readFile path)
    else default;

  username = readOr "/etc/ai-sandbox-username" "sandbox";
  homeDir = "/home/${username}";

  bootstrap = pkgs.writeShellApplication {
    name = "ai-sandbox-fish-bootstrap";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      set -euo pipefail

      share="/mnt/share/shared-config/fish_config"
      target="${homeDir}/.config/fish"

      # Source of truth lives on the share. If it isn't there, leave the
      # user's local fish config (if any) untouched.
      if [ ! -d "$share" ]; then
        exit 0
      fi

      install -d -o ${username} -g users -m 0755 "${homeDir}/.config"

      # Don't clobber a real, non-empty config dir the user set up locally.
      if [ -e "$target" ] && [ ! -L "$target" ]; then
        if [ -n "$(ls -A "$target" 2>/dev/null)" ]; then
          echo "Refusing to replace existing $target — directory non-empty" >&2
          exit 0
        fi
        rmdir "$target"
      fi

      ln -sfn "$share" "$target"
      chown -h ${username}:users "$target"
    '';
  };

  shellApply = pkgs.writeShellApplication {
    name = "ai-sandbox-fish-shell-apply";
    runtimeInputs = with pkgs; [ coreutils shadow ];
    text = ''
      set -euo pipefail

      state=off
      if [ -r /mnt/share/shared-config/.fish ]; then
        state=$(tr -d '[:space:]' < /mnt/share/shared-config/.fish)
      fi
      if [ "$state" = on ]; then
        target=/run/current-system/sw/bin/fish
      else
        target=/run/current-system/sw/bin/bash
      fi
      current=""
      while IFS=: read -r u _ _ _ _ _ s; do
        if [ "$u" = "${username}" ]; then
          current="$s"
          break
        fi
      done < /etc/passwd
      if [ "$current" != "$target" ]; then
        chsh -s "$target" "${username}"
      fi
    '';
  };
in
{
  # Fish is installed and registered in /etc/shells. The user's login
  # shell is controlled by a marker file on the share (`.fish` = `on`
  # / `off`), flipped via fish-on / fish-off. NixOS's activation script
  # re-pins the shell field in /etc/passwd on every boot from the
  # declared user record, so a one-shot chsh would not stick; the
  # activation hook and systemd unit below re-apply the marker after
  # each rebuild and boot.
  programs.fish.enable = true;

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "fish-on" ''
      set -e
      install -d /mnt/share/shared-config
      echo on > /mnt/share/shared-config/.fish
      sudo ${shellApply}/bin/ai-sandbox-fish-shell-apply
      echo "Log out and back in for fish to take effect."
    '')
    (pkgs.writeShellScriptBin "fish-off" ''
      set -e
      install -d /mnt/share/shared-config
      echo off > /mnt/share/shared-config/.fish
      sudo ${shellApply}/bin/ai-sandbox-fish-shell-apply
      echo "Log out and back in for bash to take effect."
    '')
  ];

  systemd.services.ai-sandbox-fish-bootstrap = {
    description = "Symlink ~/.config/fish to /mnt/share/shared-config/fish_config when available";
    after = [ "mnt-share.mount" ];
    wants = [ "mnt-share.mount" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/etc/ai-sandbox-username";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${bootstrap}/bin/ai-sandbox-fish-bootstrap";
    };
  };

  # Boot path: activation runs before mnt-share is mounted, so re-apply
  # the marker once the share is up.
  systemd.services.ai-sandbox-fish-shell-apply = {
    description = "Re-apply login shell from /mnt/share/shared-config/.fish";
    after = [ "mnt-share.mount" ];
    wants = [ "mnt-share.mount" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/etc/ai-sandbox-username";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${shellApply}/bin/ai-sandbox-fish-shell-apply";
    };
  };

  # Rebuild path: re-apply the marker at the end of `nixos-rebuild
  # switch`, after NixOS's `users` activation has reset /etc/passwd.
  # The share is already mounted in a running session, so this takes
  # effect immediately without waiting for a reboot.
  system.activationScripts.ai-sandbox-fish-shell-apply = lib.stringAfter [ "users" ] ''
    ${shellApply}/bin/ai-sandbox-fish-shell-apply || true
  '';
}
