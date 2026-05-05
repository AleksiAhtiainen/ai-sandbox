{ pkgs, ... }:

let
  script = pkgs.writeShellApplication {
    name = "koski-firstboot";
    runtimeInputs = with pkgs; [ coreutils gnugrep systemd ];
    text = ''
      set -euo pipefail

      src=/mnt/share/.host-username
      if [ ! -f "$src" ]; then
        echo "missing $src — host must write its username there before first boot" >&2
        exit 1
      fi

      u=$(tr -d '[:space:]' < "$src")
      if ! printf '%s' "$u" | grep -Eq '^[a-z_][a-z0-9_-]{0,31}$'; then
        echo "invalid username in $src: $u" >&2
        exit 1
      fi

      printf '%s' "$u" > /etc/koski-sandbox-username
      chmod 0644 /etc/koski-sandbox-username

      arch=$(uname -m)
      case "$arch" in
        aarch64) target=sandbox-aarch64-linux ;;
        x86_64)  target=sandbox-x86_64-linux ;;
        *) echo "unsupported architecture: $arch" >&2; exit 1 ;;
      esac

      /run/current-system/sw/bin/nixos-rebuild switch --flake "/etc/nixos#$target" --impure
      systemctl reboot
    '';
  };
in
{
  systemd.services.koski-firstboot = {
    description = "Personalize VM with host username on first boot";
    after = [ "mnt-share.mount" "network-online.target" ];
    wants = [ "mnt-share.mount" "network-online.target" ];
    before = [ "getty@tty1.service" "display-manager.service" ];
    conflicts = [ "getty@tty1.service" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "!/etc/koski-sandbox-username";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${script}/bin/koski-firstboot";
      StandardOutput = "tty";
      StandardError = "tty";
      TTYPath = "/dev/tty1";
      TTYReset = true;
      TTYVHangup = true;
    };
  };
}
