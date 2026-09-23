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

  # Entries already present in opencode.json win over these seeds.
  seededMcpServers = {
    "chrome-devtools" = {
      type = "local";
      command = [
        "npx"
        "-y"
        "chrome-devtools-mcp@latest"
        "--executablePath"
        "/run/current-system/sw/bin/chromium"
        "--isolated"
      ];
    };
    # IntelliJ IDEA's built-in MCP server. If the default port is taken,
    # IDEA picks the next free one and this URL needs a manual update.
    idea = {
      type = "remote";
      url = "http://127.0.0.1:64342/sse";
    };
  };

  opencodeDefaultConfig = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    default_agent = "plan";
    model = "llama.cpp/muse-glimmer-local";
    small_model = "llama.cpp/muse-glimmer-local";
    autoupdate = false;
    share = "disabled";
    enabled_providers = [ "llama.cpp" ];
    mcp = seededMcpServers;
    provider = {
      "llama.cpp" = {
        npm = "@ai-sdk/openai-compatible";
        name = "Local llama.cpp";
        options = {
          baseURL = "http://192.168.64.1:8080/v1";
        };
        models = {
          "muse-glimmer-local" = {
            name = "Muse Glimmer (local)";
            limit = {
              context = 131072;
              output = 8192;
            };
          };
        };
      };
    };
    permission = "allow";
    compaction = {
      auto = true;
      prune = true;
      reserved = 8192;
    };
  };

  bootstrap = pkgs.writeShellApplication {
    name = "ai-sandbox-opencode-bootstrap";
    runtimeInputs = with pkgs; [ coreutils jq ];
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

      cfg="${shareDir}/opencode.json"
      seed='${builtins.toJSON seededMcpServers}'
      tmp="$(mktemp)"
      if [ -s "$cfg" ]; then
        jq --argjson seed "$seed" \
          '.mcp = $seed + (.mcp // {})' "$cfg" > "$tmp"
      else
        # shellcheck disable=SC2016
        config='${opencodeDefaultConfig}'
        printf '%s' "$config" > "$tmp"
      fi
      install -o ${username} -g users -m 0600 "$tmp" "$cfg"
      rm -f "$tmp"
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
