{ pkgs, lib, unstablePkgs, ... }:

let
  readOr = path: default:
    if builtins.pathExists path
    then lib.removeSuffix "\n" (builtins.readFile path)
    else default;

  username = readOr "/etc/ai-sandbox-username" "sandbox";
  homeDir = "/home/${username}";

  # IDEA keeps per-version settings under
  # ~/.config/JetBrains/IntelliJIdea<year>.<major>; derive the dir from
  # the installed package so the seed follows IDEA upgrades.
  ideaConfigDir = "IntelliJIdea"
    + lib.concatStringsSep "." (lib.take 2 (lib.splitVersion unstablePkgs.jetbrains.idea.version));

  # Enables IDEA's built-in MCP server (Settings | Tools | MCP Server) so
  # the idea MCP entry seeded into Claude Code (see claude.nix) works on
  # a fresh VM without flipping it on in the IDE. Brave mode lets MCP
  # tool calls run without per-call confirmation dialogs in IDEA.
  mcpServerXml = pkgs.writeText "idea-mcpServer.xml" ''
    <application>
      <component name="McpServerSettings">
        <option name="enableBraveMode" value="true" />
        <option name="enableMcpServer" value="true" />
      </component>
    </application>
  '';

  bootstrap = pkgs.writeShellApplication {
    name = "ai-sandbox-idea-bootstrap";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      set -euo pipefail

      options="${homeDir}/.config/JetBrains/${ideaConfigDir}/options"
      target="$options/mcpServer.xml"

      # Seed only if the file doesn't exist: IDEA owns it afterwards, so
      # disabling the server from the IDE sticks (unlike the MCP entries
      # in claude.nix, which are re-added on every boot).
      if [ ! -e "$target" ]; then
        dir="${homeDir}"
        for part in .config JetBrains ${ideaConfigDir} options; do
          dir="$dir/$part"
          [ -d "$dir" ] || install -d -o ${username} -g users -m 0755 "$dir"
        done
        install -o ${username} -g users -m 0600 ${mcpServerXml} "$target"
      fi
    '';
  };
in
{
  environment.systemPackages = [
    unstablePkgs.jetbrains.idea
    # jetbrains-toolbox
  ];

  systemd.services.ai-sandbox-idea-bootstrap = {
    description = "Seed IDEA settings that enable the built-in MCP server";
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/etc/ai-sandbox-username";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${bootstrap}/bin/ai-sandbox-idea-bootstrap";
    };
  };
}
