{ pkgs, lib, unstablePkgs, ... }:

let
  readOr = path: default:
    if builtins.pathExists path
    then lib.removeSuffix "\n" (builtins.readFile path)
    else default;

  username = readOr "/etc/ai-sandbox-username" "sandbox";
  homeDir = "/home/${username}";

  shareDir = "/mnt/share/shared-config/opencode";
  homeConfig = "${homeDir}/.config/opencode";

  opencodeDefaultConfig = ./opencode-default-config.json;

  bootstrap = pkgs.writeShellApplication {
    name = "ai-sandbox-opencode-bootstrap";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      set -euo pipefail

      install -d -o ${username} -g users -m 0755 /mnt/share/shared-config
      install -d -o ${username} -g users -m 0700 "${shareDir}"

      if [ -e "${homeConfig}" ] && [ ! -L "${homeConfig}" ]; then
        mkdir -p "${shareDir}"
        cp -an "${homeConfig}"/. "${shareDir}"/ 2>/dev/null || true
        rm -rf "${homeConfig}"
      fi

      ln -sfn "${shareDir}" "${homeConfig}"
      chown -h ${username}:users "${homeConfig}"

      if [ ! -e "${shareDir}/opencode.json" ]; then
        mkdir -p "${shareDir}"
        cp "${opencodeDefaultConfig}" "${shareDir}/opencode.json"
        chown ${username}:users "${shareDir}/opencode.json"
        chmod 0600 "${shareDir}/opencode.json"
      fi
    '';
  };
in
{
  environment.systemPackages = [
    unstablePkgs.opencode
  ];

  systemd.services.ai-sandbox-opencode-bootstrap = {
    description = "Bootstrap opencode config on /mnt/share/shared-config";
    after = [ "mnt-share.mount" ];
    wants = [ "mnt-share.mount" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/etc/ai-sandbox-username";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${bootstrap}/bin/ai-sandbox-opencode-bootstrap";
    };
  };
}
