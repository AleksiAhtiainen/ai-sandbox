{ pkgs, lib, claudePkgs, ... }:

let
  readOr = path: default:
    if builtins.pathExists path
    then lib.removeSuffix "\n" (builtins.readFile path)
    else default;

  username = readOr "/etc/koski-sandbox-username" "sandbox";
  homeDir = "/home/${username}";

  updateClaude = pkgs.writeShellApplication {
    name = "update-claude";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      set -euo pipefail

      flake=/mnt/share/koski-sandbox

      #sudo
      nix flake update claude-pkgs --flake "$flake"

      arch=$(uname -m)
      case "$arch" in
        aarch64) target=sandbox-aarch64-linux ;;
        x86_64)  target=sandbox-x86_64-linux ;;
        *) echo "unsupported architecture: $arch" >&2; exit 1 ;;
      esac

      sudo nixos-rebuild switch --flake "$flake#$target" --impure
    '';
  };

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
    updateClaude
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
