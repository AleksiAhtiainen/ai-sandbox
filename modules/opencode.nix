{ pkgs, lib, unstablePkgs, ... }:

let
  readOr = path: default:
    if builtins.pathExists path
    then lib.removeSuffix "\n" (builtins.readFile path)
    else default;

  username = readOr "/etc/ai-sandbox-username" "sandbox";
  homeDir = "/home/${username}";

  shareDir = "/mnt/share/shared-config/opencode";
  homeConfigDir = "${homeDir}/.config/opencode";
  homeConfig = "${homeConfigDir}/opencode.json";

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

      if [ -L "${homeConfigDir}" ]; then
        if [ "$(readlink "${homeConfigDir}")" != "${shareDir}" ]; then
          echo "Refusing to replace unexpected symlink: ${homeConfigDir}" >&2
          exit 1
        fi
        rm "${homeConfigDir}"
      fi
      install -d -o ${username} -g users -m 0700 "${homeConfigDir}"

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

      if [ -e "${homeConfig}" ] && ! cmp -s "${homeConfig}" "$cfg"; then
        backup="$(mktemp "${homeConfig}.vm-local-backup.XXXXXX")"
        install -o ${username} -g users -m 0600 "${homeConfig}" "$backup"
      fi
      rm -f "${homeConfig}"
      ln -s "$cfg" "${homeConfig}"
      chown -h ${username}:users "${homeConfig}"
    '';
  };
in
{
  environment.systemPackages = [
    unstablePkgs.opencode
  ];

  systemd.services.ai-sandbox-opencode-bootstrap = {
    description = "Bootstrap shared OpenCode configuration";
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
