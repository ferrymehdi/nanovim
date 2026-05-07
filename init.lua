---@diagnostic disable: undefined-global

-- 1. SETTINGS
local opt = vim.opt
opt.mouse, opt.number, opt.relativenumber = "i", true, true
opt.splitright, opt.splitbelow, opt.signcolumn = true, true, "yes"
opt.list, opt.listchars = true, { tab = "  ", trail = "·", nbsp = "␣" }
opt.scrolloff, opt.laststatus, opt.updatetime, opt.timeoutlen = 10, 3, 300, 300
opt.tabstop, opt.softtabstop, opt.shiftwidth, opt.expandtab = 4, 4, 4, true
opt.swapfile, opt.undofile = false, true
opt.undodir = os.getenv("HOME") .. "/.cache/nvim/undodir"
opt.path:append '**'
opt.termguicolors = true

-- Strict LSP Completion
opt.complete = ""
opt.completeopt = "menu,menuone,noselect,noinsert"

-- 2. PACKAGES (Native)
vim.pack.add {
    'https://github.com/nvim-lua/plenary.nvim',
    'https://github.com/neovim/nvim-lspconfig',
    'https://github.com/romus204/tree-sitter-manager.nvim',
    'https://github.com/ibhagwan/fzf-lua',
    'https://github.com/neogitorg/neogit',
    'https://github.com/mbbill/undotree',
    'https://github.com/catppuccin/nvim',
    'https://github.com/vyfor/cord.nvim',
}

-- 3. PLUGIN SETUP
require('tree-sitter-manager').setup({
    auto_install = true,
    highlight = true,
})

require("cord").setup({
    enabled = true,
    log_level = vim.log.levels.OFF,
    editor = {
        client = "neovim",
        tooltip = "The Superior Text Editor",
        icon = nil,
    },
    display = {
        theme = "default",
        flavor = "dark",
        swap_fields = false,
        swap_icons = false,
    },
    timestamp = {
        enabled = true,
        reset_on_idle = false,
        reset_on_change = false,
    },
    idle = {
        enabled = false,
        timeout = 300000,
        show_status = true,
        ignore_focus = true,
        unidle_on_focus = true,
        smart_idle = true,
        details = "Idling",
        state = nil,
        tooltip = "💤",
        icon = nil,
    },
    -- text = {
        --     workspace = function(opts) return 'In ' .. opts.workspace end,
        --     viewing = function(opts) return 'Viewing ' .. opts.filename end,
        --     editing = function(opts) return 'Editing ' .. opts.filename end,
        --     file_browser = function(opts) return 'Browsing files in ' .. opts.name end,
        --     plugin_manager = function(opts) return 'Managing plugins in ' .. opts.name end,
        --     lsp = function(opts) return 'Configuring LSP in ' .. opts.name end,
        --     docs = function(opts) return 'Reading ' .. opts.name end,
        --     vcs = function(opts) return 'Committing changes in ' .. opts.name end,
        --     notes = function(opts) return 'Taking notes in ' .. opts.name end,
        --     debug = function(opts) return 'Debugging in ' .. opts.name end,
        --     test = function(opts) return 'Testing in ' .. opts.name end,
        --     diagnostics = function(opts) return 'Fixing problems in ' .. opts.name end,
        --     games = function(opts) return 'Playing ' .. opts.name end,
        --     terminal = function(opts) return 'Running commands in ' .. opts.name end,
        --     dashboard = 'Home',
        -- },
        text = {
            workspace = function(opts)
                return "My shitty workspace"
            end,
            viewing = function(opts)
                return "Viewing My shit"
            end,
            file_browser = function(opts)
                return "Browsing files"
            end,
            editing = function(opts)
                return "Editing " .. opts.filename
            end,
            plugin_manager = function(opts)
                return "Managing plugins"
            end,
            lsp = function(opts)
                return "Configuring LSP"
            end,
            docs = function(opts)
                return "Reading"
            end,
            vcs = function(opts)
                return "Committing changes"
            end,
            notes = function(opts)
                return "Taking notes"
            end,
            debug = function(opts)
                return "Debugging"
            end,
            test = function(opts)
                return "Testing"
            end,
            diagnostics = function(opts)
                return "Fixing problems"
            end,
            games = function(opts)
                return "Playing"
            end,
            terminal = function(opts)
                return "Running commands"
            end,
            dashboard = "Home",
        },
        buttons = {
            {
                label = "View Repository",
                url = function(opts)
                    return opts.repo_url
                end,
            },
            {
                label = "View Config",
                url = function(opts)
                    return "https://github.com/ferrymehdi/nanovim"
                end,
            },
        },
        assets = nil,
        variables = nil,
        hooks = {
            ready = nil,
            shutdown = nil,
            pre_activity = nil,
            post_activity = nil,
            idle_enter = nil,
            idle_leave = nil,
            workspace_change = nil,
        },
        plugins = nil,
        advanced = {
            plugin = {
                autocmds = true,
                cursor_update = "on_hold",
                match_in_mappings = true,
            },
            server = {
                update = "fetch",
                pipe_path = nil,
                executable_path = nil,
                timeout = 300000,
            },
            discord = {
                reconnect = {
                    enabled = true,
                    interval = 5000,
                    initial = true,
                },
            },
        },
    })

-- Colorscheme
vim.cmd.colorscheme "catppuccin-nvim"

-- Custom Highlights (High Contrast Colors, No Borders)
local hl = vim.api.nvim_set_hl
-- Completion Menu (Pmenu)
hl(0, "Pmenu", { bg = "#2a273f", fg = "#e0def4" })      -- Elevated surface
hl(0, "PmenuSel", { bg = "#44415a", fg = "#ebbcba", bold = true }) -- Selection
-- Hover & Floating Windows
hl(0, "NormalFloat", { bg = "#2a273f" })               -- Same elevated surface for hover
hl(0, "FloatBorder", { fg = "#2a273f", bg = "#2a273f" }) -- Hide border by matching BG

-- 4. LSP & COMPLETION LOGIC
local au = vim.api.nvim_create_autocmd

au("LspAttach", {
    callback = function(args)
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        local opts = { buffer = args.buf, silent = true }

        -- LSP Keybinds
        vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
        vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
        vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)

        -- Manual Completion Trigger (Ctrl+Space)
        vim.keymap.set("i", "<C-Space>", "<C-x><C-o>", opts)

        -- Enable Native Completion Engine
        if client and client:supports_method('textDocument/completion') then
            vim.lsp.completion.enable(true, client.id, args.buf, { autotrigger = true })
            vim.bo[args.buf].omnifunc = "v:lua.vim.lsp.omnifunc"
        end

        -- Formatting
        vim.keymap.set("n", "gF", function()
            if client and client:supports_method('textDocument/formatting') then
                vim.lsp.buf.format({ bufnr = args.buf, id = client.id })
            else
                vim.cmd("normal! gggqG")
            end
        end, opts)
    end,
})

-- Initialize Servers using Native API
local servers = { "lua_ls", "gopls", "clangd", "rust_analyzer", "zls", "ols", "jdtls", "ts_ls", "dartls", "tailwindcss" }
for _, server in ipairs(servers) do
    vim.lsp.enable(server)
end

vim.diagnostic.config({
    virtual_text = true,
    float = { border = "none" }, -- Explicitly no borders
})

-- 5. GENERAL AUTOCOMMANDS
au("TextYankPost", { callback = function() vim.highlight.on_yank() end })

-- 6. GENERAL KEYMAPS
vim.g.mapleader = " "
local function k(mode, key, action, desc)
    vim.keymap.set(mode, key, action, { desc = desc, silent = true })
end

-- Clipboard
k({ "n", "v" }, "<leader>y", '"+y')
k({ "n", "v" }, "<leader>p", '"+p')
k("n", "<leader>yu", 'gg0vG$"+y')

-- Editor Behavior
k("n", "<Esc>", "<cmd>nohlsearch<CR>")
k("n", "-", "<cmd>Explore<CR>")
k("n", "<C-d>", "<C-d>zz")
k("n", "<C-u>", "<C-u>zz")
k("n", "<S-u>", "<C-r>")

-- Navigation
k("n", "<C-h>", "<C-w>h") k("n", "<C-l>", "<C-w>l")
k("n", "<C-j>", "<C-w>j") k("n", "<C-k>", "<C-w>k")
k("n", "<BS>", function()
    local alt = vim.fn.bufnr("#")
    if vim.fn.buflisted(alt) == 1 and vim.bo[alt].filetype ~= "netrw" then
        vim.cmd("b#")
    else vim.cmd("bn") end
end)

-- Tools
k("n", "<leader>ff", function() require("fzf-lua").files() end)
k("n", "<leader>fb", function() require("fzf-lua").buffers() end)
k("n", "<leader>fg", function() require("fzf-lua").grep() end)
k("n", "<leader>tg", "<cmd>Neogit<CR>")
k("n", "<leader>tu", "<cmd>UndotreeToggle<CR>")
k("n", "<leader>tt", "<cmd>tabnew | term<CR>")

-- Menu Navigation (Native PUM)
vim.keymap.set("i", "<Tab>", function()
    return vim.fn.pumvisible() == 1 and "<C-n>" or "<Tab>"
end, { expr = true })

vim.keymap.set("i", "<S-Tab>", function()
    return vim.fn.pumvisible() == 1 and "<C-p>" or "<S-Tab>"
end, { expr = true })

vim.keymap.set("i", "<CR>", function()
    return vim.fn.pumvisible() == 1 and "<C-y>" or "<CR>"
end, { expr = true })

-- Visual Mode & Terminal
k("v", "J", ":m '>+1<CR>gv=gv")
k("v", "K", ":m '<-2<CR>gv=gv")
k("t", "<Esc><Esc>", "<C-\\><C-n>")
