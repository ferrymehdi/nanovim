return {
	{
		"local/git-commit",
		dir = vim.fn.stdpath("config") .. "/lua/git-commit",
		dependencies = { "Exafunction/codeium.nvim" },
		event = "VeryLazy",
		cond = function()
			return vim.fn.isdirectory(".git") == 1
		end,
		config = function()
			require("git-commit").setup({
				keymaps = {
					git_commit = "<leader>gc",
					auto_commit = "<leader>gC",
					dry_run = "<leader>gd",
				},
			})
		end,
		keys = {
			{ "<leader>gc", "<cmd>GitCommit<cr>", desc = "🎯 Interactive Git Commit" },
			{ "<leader>gC", "<cmd>AutoCommit<cr>", desc = "🚀 Auto Commit" },
			{ "<leader>gd", "<cmd>AutoCommitDry<cr>", desc = "👁️ Preview Message" },
		},
	},
}
