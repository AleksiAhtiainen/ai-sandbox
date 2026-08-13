{ pkgs, lib, unstablePkgs, ... }:

let
  readOr = path: default:
    if builtins.pathExists path
    then lib.removeSuffix "\n" (builtins.readFile path)
    else default;

  username = readOr "/etc/ai-sandbox-username" "sandbox";
  homeDir = "/home/${username}";

  # Seeded into the user-scope MCP config (~/.claude.json) so Claude Code
  # finds these servers on a fresh VM without manual `claude mcp add`.
  # User scope (not /etc/claude-code/managed-mcp.json) because the
  # managed file takes exclusive control and would disable all other MCP
  # servers (e.g. claude.ai connectors). Entries already present in
  # ~/.claude.json win over these seeds.
  seededMcpServers = builtins.toJSON {
    "chrome-devtools" = {
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
    # IntelliJ IDEA's built-in MCP server. 64342 is IDEA's default port;
    # if it's taken IDEA picks the next free one and this entry needs a
    # manual fix (`claude mcp add`).
    idea = {
      type = "sse";
      url = "http://127.0.0.1:64342/sse";
    };
  };

  bootstrap = pkgs.writeShellApplication {
    name = "ai-sandbox-claude-bootstrap";
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

      # Seed MCP servers into Claude Code's user scope (re-added on
      # every boot if missing; existing entries are left untouched).
      cfg="${homeDir}/.claude.json"
      seed='${seededMcpServers}'
      tmp="$(mktemp)"
      if [ -s "$cfg" ]; then
        jq --argjson seed "$seed" \
          '.mcpServers = $seed + (.mcpServers // {})' "$cfg" > "$tmp"
      else
        jq -n --argjson seed "$seed" '{ mcpServers: $seed }' > "$tmp"
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

  systemd.services.ai-sandbox-claude-bootstrap = {
    description = "Bootstrap per-VM Claude state on /mnt/share/shared-config";
    after = [ "mnt-share.mount" ];
    wants = [ "mnt-share.mount" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/etc/ai-sandbox-username";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${bootstrap}/bin/ai-sandbox-claude-bootstrap";
    };
  };
}
