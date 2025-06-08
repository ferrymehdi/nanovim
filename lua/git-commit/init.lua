-- ~/.config/nvim/lua/auto-commit/init.lua
-- Interactive Git Commit Plugin for Neovim with File Selection and Diff Preview

local M = {}

-- Plugin configuration
M.config = {
	-- Auto-stage files before committing
	auto_stage = true,
	-- Ask for confirmation before committing
	confirm_commit = true,
	-- Maximum length for commit messages
	max_message_length = 50,
	-- Fallback to rule-based messages if AI fails
	use_fallback = true,
	-- Show notifications
	show_notifications = true,
	-- Keymaps
	keymaps = {
		git_commit = "<leader>gc",
		auto_commit = "<leader>gC",
		dry_run = "<leader>gd",
	},
	-- UI settings
	ui = {
		border = "rounded",
		width = 0.8,
		height = 0.8,
		preview_width = 0.5,
	},
}

-- Internal state
local api = vim.api
local fn = vim.fn
local notify = vim.notify

-- UI state
local current_files = {}
local selected_files = {}
local commit_buf = nil
local file_buf = nil
local preview_buf = nil
local commit_win = nil
local file_win = nil
local preview_win = nil

-- Utility functions
local function notify_info(msg)
	if M.config.show_notifications then
		notify(msg, vim.log.levels.INFO, { title = "GitCommit" })
	end
end

local function notify_error(msg)
	if M.config.show_notifications then
		notify(msg, vim.log.levels.ERROR, { title = "GitCommit" })
	end
end

local function notify_warn(msg)
	if M.config.show_notifications then
		notify(msg, vim.log.levels.WARN, { title = "GitCommit" })
	end
end

-- Git operations
local function run_git_command(cmd)
	local handle = io.popen("git " .. cmd .. " 2>&1")
	if not handle then
		return nil, "Failed to execute git command"
	end

	local result = handle:read("*a")
	local success = handle:close()

	if not success then
		return nil, result
	end

	return result:gsub("%s+$", ""), nil -- trim trailing whitespace
end

local function is_git_repo()
	local _, err = run_git_command("rev-parse --git-dir")
	return err == nil
end

local function get_git_status()
	return run_git_command("status --porcelain")
end

local function get_file_diff(filepath)
	-- Get diff for specific file
	local staged_diff, _ = run_git_command("diff --cached -- " .. vim.fn.shellescape(filepath))
	if staged_diff and staged_diff ~= "" then
		return staged_diff, "staged"
	end

	local unstaged_diff, _ = run_git_command("diff -- " .. vim.fn.shellescape(filepath))
	return unstaged_diff or "", "unstaged"
end

local function stage_file(filepath)
	local _, err = run_git_command("add " .. vim.fn.shellescape(filepath))
	return err == nil
end

local function unstage_file(filepath)
	local _, err = run_git_command("reset HEAD " .. vim.fn.shellescape(filepath))
	return err == nil
end

local function commit_changes(message)
	local escaped_message = message:gsub('"', '\\"')
	local _, err = run_git_command('commit -m "' .. escaped_message .. '"')
	return err == nil
end

-- File analysis functions
local function parse_git_status(status_output)
	if not status_output or status_output == "" then
		return {}
	end

	local files = {}
	for line in status_output:gmatch("[^\r\n]+") do
		if line:len() > 3 then
			local status_code = line:sub(1, 2)
			local filename = line:sub(4)

			-- Determine file status
			local status_desc = "Modified"
			local status_char = "M"

			if status_code:sub(1, 1) == "A" then
				status_desc = "Added"
				status_char = "A"
			elseif status_code:sub(1, 1) == "D" then
				status_desc = "Deleted"
				status_char = "D"
			elseif status_code:sub(1, 1) == "R" then
				status_desc = "Renamed"
				status_char = "R"
			elseif status_code:sub(1, 1) == "C" then
				status_desc = "Copied"
				status_char = "C"
			elseif status_code:sub(1, 1) == "?" then
				status_desc = "Untracked"
				status_char = "?"
			end

			table.insert(files, {
				status = status_code,
				status_char = status_char,
				status_desc = status_desc,
				filename = filename,
				display_name = string.format("[%s] %s", status_char, filename),
				is_staged = status_code:sub(1, 1):match("[AMDRC]") ~= nil,
				selected = false,
			})
		end
	end

	return files
end

-- AI commit message generation
local function generate_commit_message_with_codeium(diff_content, files_info)
	-- Simple integration with Codeium - in real implementation,
	-- you'd integrate with Codeium's chat API
	local codeium_ok, _ = pcall(require, "codeium")
	if not codeium_ok then
		return nil, "Codeium not available"
	end

	-- For now, return nil to use fallback
	-- In future, integrate with Codeium's completion API
	return nil, "Using fallback generation"
end

-- Fallback commit message generation
local function generate_fallback_commit_message(files_info)
	if #files_info == 0 then
		return "chore: update files"
	end

	-- Analyze file types and changes
	local added_files = {}
	local modified_files = {}
	local deleted_files = {}

	for _, file in ipairs(files_info) do
		if file.status_char == "A" then
			table.insert(added_files, file)
		elseif file.status_char == "M" then
			table.insert(modified_files, file)
		elseif file.status_char == "D" then
			table.insert(deleted_files, file)
		end
	end

	-- Generate message based on file changes
	if #added_files > 0 and #modified_files == 0 and #deleted_files == 0 then
		if #added_files == 1 then
			local filename = fn.fnamemodify(added_files[1].filename, ":t")
			return "feat: add " .. filename
		else
			return "feat: add " .. #added_files .. " new files"
		end
	elseif #deleted_files > 0 and #added_files == 0 and #modified_files == 0 then
		if #deleted_files == 1 then
			local filename = fn.fnamemodify(deleted_files[1].filename, ":t")
			return "remove: delete " .. filename
		else
			return "remove: delete " .. #deleted_files .. " files"
		end
	elseif #modified_files > 0 then
		if #modified_files == 1 then
			local filename = fn.fnamemodify(modified_files[1].filename, ":t")
			local ext = fn.fnamemodify(filename, ":e")

			if ext:match("md") or ext:match("txt") or ext:match("rst") then
				return "docs: update " .. filename
			elseif ext:match("py") or ext:match("js") or ext:match("lua") or ext:match("java") then
				return "fix: update " .. filename
			else
				return "chore: update " .. filename
			end
		else
			return "chore: update " .. #modified_files .. " files"
		end
	else
		return "chore: update repository"
	end
end

-- Main commit message generation
local function generate_commit_message(files_info)
	-- Get diff for selected files
	local diff_content = ""
	for _, file in ipairs(files_info) do
		if file.selected then
			local file_diff, _ = get_file_diff(file.filename)
			diff_content = diff_content .. file_diff .. "\n"
		end
	end

	-- Try Codeium first
	local message, err = generate_commit_message_with_codeium(diff_content, files_info)

	if message and message ~= "" then
		return message
	end

	-- Use fallback
	if M.config.use_fallback then
		return generate_fallback_commit_message(files_info)
	end

	return nil, err or "Failed to generate commit message"
end

-- UI Functions
local function close_git_commit_ui()
	if commit_win and api.nvim_win_is_valid(commit_win) then
		api.nvim_win_close(commit_win, true)
	end
	if file_win and api.nvim_win_is_valid(file_win) then
		api.nvim_win_close(file_win, true)
	end
	if preview_win and api.nvim_win_is_valid(preview_win) then
		api.nvim_win_close(preview_win, true)
	end

	if commit_buf and api.nvim_buf_is_valid(commit_buf) then
		api.nvim_buf_delete(commit_buf, { force = true })
	end
	if file_buf and api.nvim_buf_is_valid(file_buf) then
		api.nvim_buf_delete(file_buf, { force = true })
	end
	if preview_buf and api.nvim_buf_is_valid(preview_buf) then
		api.nvim_buf_delete(preview_buf, { force = true })
	end

	commit_win, file_win, preview_win = nil, nil, nil
	commit_buf, file_buf, preview_buf = nil, nil, nil
	current_files = {}
	selected_files = {}
end

local function update_file_list()
	if not file_buf or not api.nvim_buf_is_valid(file_buf) then
		return
	end

	-- Make buffer modifiable temporarily
	api.nvim_buf_set_option(file_buf, "modifiable", true)

	local lines = {}
	table.insert(lines, "📁 Select files to commit (Space to toggle, Enter to preview):")
	table.insert(lines, "")

	for i, file in ipairs(current_files) do
		local prefix = file.selected and "✓ " or "  "
		local staged_indicator = file.is_staged and "●" or "○"
		local line = string.format("%s%s %s %s", prefix, staged_indicator, file.status_char, file.filename)
		table.insert(lines, line)
	end

	table.insert(lines, "")
	table.insert(lines, "Usage:")
	table.insert(lines, "  <Space>   Toggle file selection")
	table.insert(lines, "  <Enter>   Preview file diff")
	table.insert(lines, "  s         Stage/unstage file")
	table.insert(lines, "  <Tab>     Generate commit message")
	table.insert(lines, "  q         Quit")

	api.nvim_buf_set_lines(file_buf, 0, -1, false, lines)

	-- Set buffer back to non-modifiable
	api.nvim_buf_set_option(file_buf, "modifiable", false)

	-- Set highlighting
	local ns_id = api.nvim_create_namespace("git_commit_files")
	api.nvim_buf_clear_namespace(file_buf, ns_id, 0, -1)

	for i, file in ipairs(current_files) do
		local line_nr = i + 1 -- +2 for header, -1 for 0-indexed
		if file.selected then
			api.nvim_buf_add_highlight(file_buf, ns_id, "DiffAdd", line_nr, 0, -1)
		elseif file.is_staged then
			api.nvim_buf_add_highlight(file_buf, ns_id, "DiffChange", line_nr, 0, -1)
		end
	end
end

local function update_preview(file_index)
	if not preview_buf or not api.nvim_buf_is_valid(preview_buf) then
		return
	end

	-- Make buffer modifiable temporarily
	api.nvim_buf_set_option(preview_buf, "modifiable", true)

	if not file_index or file_index > #current_files then
		api.nvim_buf_set_lines(preview_buf, 0, -1, false, { "Select a file to preview changes" })
		api.nvim_buf_set_option(preview_buf, "modifiable", false)
		return
	end

	local file = current_files[file_index]
	local diff_content, diff_type = get_file_diff(file.filename)

	if not diff_content or diff_content == "" then
		api.nvim_buf_set_lines(preview_buf, 0, -1, false, {
			"No changes to preview for: " .. file.filename,
			"",
			"File status: " .. file.status_desc,
		})
		api.nvim_buf_set_option(preview_buf, "modifiable", false)
		return
	end

	local lines = vim.split(diff_content, "\n")
	local header = {
		"📄 " .. file.filename .. " (" .. diff_type .. ")",
		"Status: " .. file.status_desc,
		"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
		"",
	}

	-- Combine header and diff
	local final_lines = {}
	for _, line in ipairs(header) do
		table.insert(final_lines, line)
	end
	for _, line in ipairs(lines) do
		table.insert(final_lines, line)
	end

	api.nvim_buf_set_lines(preview_buf, 0, -1, false, final_lines)

	-- Apply diff highlighting and set back to non-modifiable
	api.nvim_buf_set_option(preview_buf, "filetype", "diff")
	api.nvim_buf_set_option(preview_buf, "modifiable", false)
end

local function setup_file_buffer_keymaps()
	if not file_buf then
		return
	end

	local opts = { buffer = file_buf, noremap = true, silent = true }

	-- Toggle file selection
	vim.keymap.set("n", "<Space>", function()
		local cursor_line = api.nvim_win_get_cursor(file_win)[1]
		local file_index = cursor_line - 2 -- Adjust for header

		if file_index >= 1 and file_index <= #current_files then
			current_files[file_index].selected = not current_files[file_index].selected
			update_file_list()
		end
	end, opts)

	-- Preview file
	vim.keymap.set("n", "<CR>", function()
		local cursor_line = api.nvim_win_get_cursor(file_win)[1]
		local file_index = cursor_line - 2 -- Adjust for header
		update_preview(file_index)
	end, opts)

	-- Stage/unstage file
	vim.keymap.set("n", "s", function()
		local cursor_line = api.nvim_win_get_cursor(file_win)[1]
		local file_index = cursor_line - 2 -- Adjust for header

		if file_index >= 1 and file_index <= #current_files then
			local file = current_files[file_index]
			if file.is_staged then
				if unstage_file(file.filename) then
					file.is_staged = false
					notify_info("Unstaged: " .. file.filename)
				else
					notify_error("Failed to unstage: " .. file.filename)
				end
			else
				if stage_file(file.filename) then
					file.is_staged = true
					notify_info("Staged: " .. file.filename)
				else
					notify_error("Failed to stage: " .. file.filename)
				end
			end
			update_file_list()
		end
	end, opts)

	-- Generate commit message
	vim.keymap.set("n", "<Tab>", function()
		M.generate_and_show_commit_message()
	end, opts)

	-- Quit
	vim.keymap.set("n", "q", close_git_commit_ui, opts)
	vim.keymap.set("n", "<Esc>", close_git_commit_ui, opts)
end

local function setup_commit_buffer_keymaps()
	if not commit_buf then
		return
	end

	local opts = { buffer = commit_buf, noremap = true, silent = true }

	-- Commit
	vim.keymap.set("n", "<CR>", function()
		M.execute_commit()
	end, opts)

	-- Generate new message
	vim.keymap.set("n", "r", function()
		M.generate_and_show_commit_message()
	end, opts)

	-- Edit message
	vim.keymap.set("n", "e", function()
		api.nvim_buf_set_option(commit_buf, "modifiable", true)
		api.nvim_set_current_win(commit_win)
		vim.cmd("startinsert")
	end, opts)

	-- Quit
	vim.keymap.set("n", "q", close_git_commit_ui, opts)
	vim.keymap.set("n", "<Esc>", close_git_commit_ui, opts)
end

function M.generate_and_show_commit_message()
	local selected_files = {}
	for _, file in ipairs(current_files) do
		if file.selected then
			table.insert(selected_files, file)
		end
	end

	if #selected_files == 0 then
		notify_warn("No files selected")
		return
	end

	notify_info("🤖 Generating commit message...")
	local commit_message = generate_commit_message(selected_files)

	if not commit_message then
		notify_error("Failed to generate commit message")
		return
	end

	-- Update commit buffer
	if commit_buf and api.nvim_buf_is_valid(commit_buf) then
		-- Make buffer modifiable temporarily
		api.nvim_buf_set_option(commit_buf, "modifiable", true)

		local lines = {
			"💬 Generated Commit Message:",
			"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
			"",
			commit_message,
			"",
			"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
			"",
			"Selected files (" .. #selected_files .. "):",
		}

		for _, file in ipairs(selected_files) do
			table.insert(lines, "  " .. file.display_name)
		end

		table.insert(lines, "")
		table.insert(lines, "Commands:")
		table.insert(lines, "  <Enter>  Commit with this message")
		table.insert(lines, "  e        Edit message")
		table.insert(lines, "  r        Regenerate message")
		table.insert(lines, "  q        Cancel")

		api.nvim_buf_set_lines(commit_buf, 0, -1, false, lines)
		api.nvim_buf_set_option(commit_buf, "modifiable", false)

		-- Highlight the commit message
		local ns_id = api.nvim_create_namespace("git_commit_message")
		api.nvim_buf_clear_namespace(commit_buf, ns_id, 0, -1)
		api.nvim_buf_add_highlight(commit_buf, ns_id, "String", 3, 0, -1)

		-- Focus commit window
		api.nvim_set_current_win(commit_win)
	end
end

function M.execute_commit()
	if not commit_buf or not api.nvim_buf_is_valid(commit_buf) then
		return
	end

	-- Make buffer temporarily modifiable to read content
	local was_modifiable = api.nvim_buf_get_option(commit_buf, "modifiable")
	if not was_modifiable then
		api.nvim_buf_set_option(commit_buf, "modifiable", true)
	end

	-- Get commit message from buffer
	local lines = api.nvim_buf_get_lines(commit_buf, 0, -1, false)
	local commit_message = ""

	-- Find the commit message (should be on line 4, index 3)
	if #lines >= 4 then
		commit_message = lines[4]:gsub("^%s*", ""):gsub("%s*$", "")
	end

	-- Restore modifiable state
	if not was_modifiable then
		api.nvim_buf_set_option(commit_buf, "modifiable", false)
	end

	if commit_message == "" then
		notify_error("No commit message provided")
		return
	end

	-- Stage selected files
	local selected_files = {}
	for _, file in ipairs(current_files) do
		if file.selected then
			table.insert(selected_files, file)
			if not file.is_staged then
				stage_file(file.filename)
			end
		end
	end

	if #selected_files == 0 then
		notify_error("No files selected")
		return
	end

	-- Execute commit
	notify_info("🚀 Committing changes...")
	if commit_changes(commit_message) then
		notify_info("✅ Successfully committed " .. #selected_files .. " files!")
		close_git_commit_ui()
	else
		notify_error("❌ Failed to commit changes")
	end
end

-- Main UI function
function M.show_git_commit_ui()
	-- Check if we're in a git repository
	if not is_git_repo() then
		notify_error("Not in a git repository")
		return
	end

	-- Get git status
	local status_output, err = get_git_status()
	if err then
		notify_error("Failed to get git status: " .. err)
		return
	end

	current_files = parse_git_status(status_output)
	if #current_files == 0 then
		notify_info("No changes to commit")
		return
	end

	-- Calculate window dimensions
	local screen_width = api.nvim_get_option("columns")
	local screen_height = api.nvim_get_option("lines")
	local width = math.floor(screen_width * M.config.ui.width)
	local height = math.floor(screen_height * M.config.ui.height)
	local row = math.floor((screen_height - height) / 2)
	local col = math.floor((screen_width - width) / 2)

	local file_width = math.floor(width * (1 - M.config.ui.preview_width))
	local preview_width = width - file_width - 1
	local commit_height = 12
	local file_height = height - commit_height - 1

	-- Create buffers
	commit_buf = api.nvim_create_buf(false, true)
	file_buf = api.nvim_create_buf(false, true)
	preview_buf = api.nvim_create_buf(false, true)

	-- Create windows
	commit_win = api.nvim_open_win(commit_buf, true, {
		relative = "editor",
		width = width,
		height = commit_height,
		row = row,
		col = col,
		border = M.config.ui.border,
		title = " Git Commit ",
		title_pos = "center",
	})

	file_win = api.nvim_open_win(file_buf, false, {
		relative = "editor",
		width = file_width,
		height = file_height,
		row = row + commit_height + 1,
		col = col,
		border = M.config.ui.border,
		title = " Files ",
		title_pos = "center",
	})

	preview_win = api.nvim_open_win(preview_buf, false, {
		relative = "editor",
		width = preview_width,
		height = file_height,
		row = row + commit_height + 1,
		col = col + file_width + 1,
		border = M.config.ui.border,
		title = " Preview ",
		title_pos = "center",
	})

	-- Set buffer options
	for _, buf in ipairs({ commit_buf, file_buf, preview_buf }) do
		api.nvim_buf_set_option(buf, "bufhidden", "wipe")
		api.nvim_buf_set_option(buf, "buftype", "nofile")
		api.nvim_buf_set_option(buf, "swapfile", false)
	end

	-- Initial content (set modifiable first)
	api.nvim_buf_set_option(commit_buf, "modifiable", true)
	api.nvim_buf_set_lines(commit_buf, 0, -1, false, {
		"🎯 Git Commit Interface",
		"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
		"",
		"Select files in the left panel, then press <Tab> to generate commit message",
		"",
		"Commands:",
		"  <Tab>     Generate commit message",
		"  q         Quit",
	})
	api.nvim_buf_set_option(commit_buf, "modifiable", false)

	-- Set up keymaps
	setup_file_buffer_keymaps()
	setup_commit_buffer_keymaps()

	-- Update file list and focus file window
	update_file_list()
	api.nvim_set_current_win(file_win)

	notify_info("Git Commit UI opened - Select files with <Space>")
end

-- Legacy auto-commit function (for backward compatibility)
function M.auto_commit(opts)
	opts = opts or {}
	local dry_run = opts.dry_run or false

	if dry_run then
		-- For dry run, just show what would be committed
		local status_output, err = get_git_status()
		if err then
			notify_error("Failed to get git status: " .. err)
			return false
		end

		local files_info = parse_git_status(status_output)
		if #files_info == 0 then
			notify_info("No changes to commit")
			return true
		end

		local commit_message = generate_commit_message(files_info)
		notify_info("Would commit with message: " .. (commit_message or "Unable to generate message"))
		return true
	else
		-- Open the interactive UI
		M.show_git_commit_ui()
	end
end

-- Setup function
function M.setup(opts)
	-- Merge user config with defaults
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	-- Create user commands
	api.nvim_create_user_command("GitCommit", function()
		M.show_git_commit_ui()
	end, { desc = "Open interactive git commit interface" })

	api.nvim_create_user_command("AutoCommit", function()
		M.auto_commit()
	end, { desc = "Open git commit interface (alias)" })

	api.nvim_create_user_command("AutoCommitDry", function()
		M.auto_commit({ dry_run = true })
	end, { desc = "Preview commit message without UI" })

	-- Set up keymaps if enabled
	if M.config.keymaps then
		for action, keymap in pairs(M.config.keymaps) do
			if keymap then
				if action == "git_commit" then
					vim.keymap.set("n", keymap, function()
						M.show_git_commit_ui()
					end, { desc = "Open Git Commit UI", silent = true })
				elseif action == "auto_commit" then
					vim.keymap.set("n", keymap, function()
						M.auto_commit()
					end, { desc = "Git Commit Interface", silent = true })
				elseif action == "dry_run" then
					vim.keymap.set("n", keymap, function()
						M.auto_commit({ dry_run = true })
					end, { desc = "Preview commit message", silent = true })
				end
			end
		end
	end

	notify_info("Git Commit plugin loaded! Use :GitCommit to get started")
end

return M
