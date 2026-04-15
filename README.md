# DBLP Neovim

A simple Neovim Lua plugin for academic writers to fetch bib entries from DBLP.
Funny how we don't have anyone did this before.

To install this plugin, use the built-in neovim package manager:

```lua
vim.pack.add({"https://github.com/whexy/dblp.nvim"})
```

DBLP provides free API for searching the paper, just trigger the command to
search, then select which paper entry you want, and the bib entry is inserted.

```lua
-- Map <leader>p in normal mode to trigger the search
vim.keymap.set('n', '<leader>p', function()
    require('dblp').search_and_insert()
end, { desc = 'Search DBLP and insert BibTeX', noremap = true, silent = true })
```
