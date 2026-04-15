{
  pkgs,
  inputs,
  ...
}:
let
  dblp-nvim = pkgs.vimUtils.buildVimPlugin {
    pname = "dblp-nvim";
    version = "dev";
    src = inputs.self;
  };
  wrapped = pkgs.wrapNeovimUnstable pkgs.neovim-unwrapped {
    plugins = [ dblp-nvim ];
    luaRcContent = ''
      vim.g.mapleader = " "
      vim.keymap.set("n", "<leader>p", function()
        require("dblp").search_and_insert()
      end, { desc = "DBLP: search and insert BibTeX" })
    '';
    wrapperArgs = [
      "--prefix"
      "PATH"
      ":"
      "${pkgs.lib.makeBinPath [ pkgs.curl ]}"
    ];
    withPython3 = false;
    withNodeJs = false;
    withRuby = false;
  };
in
# Remove nixpkgs' neovim passthru.tests so Blueprint doesn't expose them
# as flake checks (some are functions, not derivations, which breaks `nix flake check`).
wrapped.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    tests = { };
  };
})
