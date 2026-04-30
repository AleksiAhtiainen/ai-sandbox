{ pkgs, lib, claudePkgs, ... }:

let
  readOr = path: default:
    if builtins.pathExists path
    then lib.removeSuffix "\n" (builtins.readFile path)
    else default;

  username = readOr "/etc/koski-sandbox-username" "sandbox";
  homeDir = "/home/${username}";

  bootstrap = pkgs.writeShellApplication {
    name = "koski-claude-bootstrap";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      set -euo pipefail

      share="/mnt/share/claude/${username}"
      home="${homeDir}/.claude"

      install -d -o ${username} -g users -m 0755 /mnt/share/claude
      install -d -o ${username} -g users -m 0700 "$share"

      if [ -e "$home" ] && [ ! -L "$home" ]; then
        cp -an "$home"/. "$share"/ 2>/dev/null || true
        rm -rf "$home"
      fi

      ln -sfn "$share" "$home"
      chown -h ${username}:users "$home"
    '';
  };
in
{
  environment.systemPackages = [
    claudePkgs.claude-code
  ];

  systemd.services.koski-claude-bootstrap = {
    description = "Bootstrap per-VM Claude state on /mnt/share";
    after = [ "mnt-share.mount" ];
    wants = [ "mnt-share.mount" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/etc/koski-sandbox-username";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${bootstrap}/bin/koski-claude-bootstrap";
    };
  };
}
