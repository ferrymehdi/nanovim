----------------------------------------------------------
--                                                      --
--      ultra minimalistic and powerful nvim config     --
--                                                      --
----------------------------------------------------------

--  leader key
vim.g.mapleader = " "
local jdk = "/usr/lib/jvm/java-21-openjdk" -- your path
vim.env.JAVA_HOME = jdk
vim.env.PATH = jdk .. "/bin:" .. (vim.env.PATH or "")
-- load the plugins
require("settings.lazy")

-- load the options
require("settings.options")
-- load the global funcs
require("settings.globals")
-- load Autocommands
require("settings.autoCommands")
-- load the keybinds
require("settings.keybinds")

require('lspconfig').jdtls.setup {}
