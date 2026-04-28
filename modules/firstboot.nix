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

      host_uid=$(stat -c '%u' /mnt/share)
      host_gid=$(stat -c '%g' /mnt/share)

      printf '%s' "$u"        > /etc/koski-sandbox-username
      printf '%s' "$host_uid" > /etc/koski-sandbox-uid
      printf '%s' "$host_gid" > /etc/koski-sandbox-gid
      chmod 0644 /etc/koski-sandbox-username /etc/koski-sandbox-uid /etc/koski-sandbox-gid

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
    description = "Personalize VM with host username and uid/gid on first boot";
    after = [ "mnt-share.mount" "network-online.target" ];
    wants = [ "mnt-share.mount" "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "!/etc/koski-sandbox-username";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${script}/bin/koski-firstboot";
    };
  };
}
