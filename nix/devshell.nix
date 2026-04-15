{ pkgs, perSystem, ... }:
pkgs.mkShell {
  packages = [
    perSystem.self.nvim-plugin-dev
    pkgs.lua
    pkgs.lua-language-server
    pkgs.stylua
    pkgs.selene
  ];

  shellHook = ''
    echo "dblp.nvim dev shell"
    echo "  nvim      – Neovim with dblp.nvim loaded (leader=Space, <leader>p to search)"
    echo "  stylua    – Lua formatter"
    echo "  selene    – Lua linter"
  '';
}
