{ pkgs, lib, ... }:

let
  readOr = path: default:
    if builtins.pathExists path
    then lib.removeSuffix "\n" (builtins.readFile path)
    else default;

  username = readOr "/etc/koski-sandbox-username" "sandbox";
  homeDir = "/home/${username}";

  bootstrap = pkgs.writeShellApplication {
    name = "koski-git-bootstrap";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      set -euo pipefail

      src="/mnt/share/shared-config/.gitconfig"
      dest="${homeDir}/.gitconfig"

      if [ ! -e "$src" ]; then
        exit 0
      fi

      if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
        exit 0
      fi

      if [ -e "$dest" ] || [ -L "$dest" ]; then
        mv "$dest" "$dest.bak.$(date +%s)"
      fi

      ln -sfn "$src" "$dest"
      chown -h ${username}:users "$dest"
    '';
  };
in
{
  systemd.services.koski-git-bootstrap = {
    description = "Link host-provided .gitconfig from /mnt/share/shared-config into the VM user home";
    after = [ "mnt-share.mount" ];
    wants = [ "mnt-share.mount" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/etc/koski-sandbox-username";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${bootstrap}/bin/koski-git-bootstrap";
    };
  };
}
