{ pkgs, lib, unstablePkgs, ... }:

let
  readOr = path: default:
    if builtins.pathExists path
    then lib.removeSuffix "\n" (builtins.readFile path)
    else default;

  username = readOr "/etc/koski-sandbox-username" "sandbox";
  homeDir = "/home/${username}";

  # Seeded into the user-scope MCP config (~/.claude.json) so Claude Code
  # can drive the system Chromium out of the box. User scope (not
  # /etc/claude-code/managed-mcp.json) because the managed file takes
  # exclusive control and would disable all other MCP servers (IDEA,
  # claude.ai connectors).
  chromeDevtoolsMcp = builtins.toJSON {
    type = "stdio";
    command = "npx";
    args = [
      "-y"
      "chrome-devtools-mcp@latest"
      "--executablePath"
      "/run/current-system/sw/bin/chromium"
      "--isolated"
    ];
  };

  bootstrap = pkgs.writeShellApplication {
    name = "koski-claude-bootstrap";
    runtimeInputs = with pkgs; [ coreutils jq ];
    text = ''
      set -euo pipefail

      share="/mnt/share/shared-config/claude"
      home="${homeDir}/.claude"

      install -d -o ${username} -g users -m 0755 /mnt/share/shared-config
      install -d -o ${username} -g users -m 0700 "$share"

      if [ -e "$home" ] && [ ! -L "$home" ]; then
        cp -an "$home"/. "$share"/ 2>/dev/null || true
        rm -rf "$home"
      fi

      ln -sfn "$share" "$home"
      chown -h ${username}:users "$home"

      # Seed the chrome-devtools MCP server into Claude Code's user scope
      # if absent (re-added on every boot; remove it here to drop it).
      cfg="${homeDir}/.claude.json"
      server='${chromeDevtoolsMcp}'
      tmp="$(mktemp)"
      if [ -s "$cfg" ]; then
        jq --argjson server "$server" \
          '.mcpServers["chrome-devtools"] //= $server' "$cfg" > "$tmp"
      else
        jq -n --argjson server "$server" \
          '{ mcpServers: { "chrome-devtools": $server } }' > "$tmp"
      fi
      install -o ${username} -g users -m 0600 "$tmp" "$cfg"
      rm -f "$tmp"
    '';
  };
in
{
  environment.systemPackages = [
    unstablePkgs.claude-code
  ];

  systemd.services.koski-claude-bootstrap = {
    description = "Bootstrap per-VM Claude state on /mnt/share/shared-config";
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
