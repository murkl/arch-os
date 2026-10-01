-- Written by the Arch OS Installer. Neovim's defaults already bring the mouse,
-- a colour scheme of its own and most of what vim needs a vimrc for, so this is
-- only what they leave out. `:help option-list` names everything that can go
-- here.
vim.o.number = true

-- Four spaces for a tab, and a search that ignores case until it holds a
-- capital letter.
vim.o.expandtab = true
vim.o.shiftwidth = 4
vim.o.softtabstop = 4
vim.o.ignorecase = true
vim.o.smartcase = true

-- An undo that survives closing the file.
vim.o.undofile = true
