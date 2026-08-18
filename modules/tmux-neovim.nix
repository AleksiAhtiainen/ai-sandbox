{ pkgs, lib, ... }:

let
  readOr = path: default:
    if builtins.pathExists path
    then lib.removeSuffix "\n" (builtins.readFile path)
    else default;

  username = readOr "/etc/ai-sandbox-username" "sandbox";
  homeDir = "/home/${username}";

  tmuxBootstrap = pkgs.writeShellApplication {
    name = "ai-sandbox-tmux-bootstrap";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      set -euo pipefail

      share="/mnt/share/shared-config/tmux"
      target="${homeDir}/.config/tmux"

      install -d -o ${username} -g users -m 0755 /mnt/share/shared-config
      install -d -o ${username} -g users -m 0755 "$share"
      install -d -o ${username} -g users -m 0755 "${homeDir}/.config"

      if [ -e "$target" ] && [ ! -L "$target" ]; then
        if [ -d "$target" ]; then
          cp -an "$target"/. "$share"/ 2>/dev/null || true
        else
          cp -an "$target" "$share"/ 2>/dev/null || true
        fi
        rm -rf "$target"
      fi

      ln -sfn "$share" "$target"
      chown -h ${username}:users "$target"
    '';
  };

  nvimBootstrap = pkgs.writeShellApplication {
    name = "ai-sandbox-neovim-bootstrap";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      set -euo pipefail

      share="/mnt/share/shared-config/nvim"
      target="${homeDir}/.config/nvim"

      install -d -o ${username} -g users -m 0755 /mnt/share/shared-config
      install -d -o ${username} -g users -m 0755 "$share"
      install -d -o ${username} -g users -m 0755 "${homeDir}/.config"

      if [ -e "$target" ] && [ ! -L "$target" ]; then
        if [ -d "$target" ]; then
          cp -an "$target"/. "$share"/ 2>/dev/null || true
        else
          cp -an "$target" "$share"/ 2>/dev/null || true
        fi
        rm -rf "$target"
      fi

      ln -sfn "$share" "$target"
      chown -h ${username}:users "$target"
    '';
  };
in
{
  environment.systemPackages = with pkgs; [
    tmux
  ];

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    configure = {
      customLuaRC = ''
        local user_init = vim.fn.stdpath("config") .. "/init.lua"
        if vim.fn.filereadable(user_init) == 1 then
          dofile(user_init)
        end
      '';
      packages.ai-sandbox.start = with pkgs.vimPlugins; [
        fzf-lua
        gitsigns-nvim
        mini-completion
        nvim-lspconfig
        quicker-nvim
      ];
    };
  };

  systemd.services.ai-sandbox-tmux-bootstrap = {
    description = "Symlink ~/.config/tmux to /mnt/share/shared-config/tmux";
    after = [ "mnt-share.mount" ];
    wants = [ "mnt-share.mount" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/etc/ai-sandbox-username";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${tmuxBootstrap}/bin/ai-sandbox-tmux-bootstrap";
    };
  };

  systemd.services.ai-sandbox-neovim-bootstrap = {
    description = "Symlink ~/.config/nvim to /mnt/share/shared-config/nvim";
    after = [ "mnt-share.mount" ];
    wants = [ "mnt-share.mount" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/etc/ai-sandbox-username";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${nvimBootstrap}/bin/ai-sandbox-neovim-bootstrap";
    };
  };
}
