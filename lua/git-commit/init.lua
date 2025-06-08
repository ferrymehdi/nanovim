-- ~/.config/nvim/lua/git-commit/init.lua
-- Simple 3-Panel Git Commit Interface

local M = {}

-- Plugin configuration
M.config = {
	show_notifications = true,
	keymaps = {
		git_commit = "<leader>gc",
	},
	ui = {
		border = "rounded",
		width = 0.95,
		height = 0.85,
	},
}

-- Internal state
local api = vim.api
local fn = vim.fn
local notify = vim.notify

-- UI state
local staged_files = {}
local all_files = {}
local commit_buf = nil
local files_buf = nil
local diff_buf = nil
local commit_win = nil
local files_win = nil
local diff_win = nil
local current_commit_message = ""
local focused_file_index = nil

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

	return result:gsub("%s+$", ""), nil
end

local function is_git_repo()
	local _, err = run_git_command("rev-parse --git-dir")
	return err == nil
end

local function get_all_files()
	local output, err = run_git_command("status --porcelain")
	if err or not output or output == "" then
		return {}
	end

	local files = {}
	for line in output:gmatch("[^\r\n]+") do
		if line:len() > 3 then
			local status_code = line:sub(1, 2)
			local filename = line:sub(4)

			local staged_status = status_code:sub(1, 1)
			local unstaged_status = status_code:sub(2, 2)

			local status_desc = "Modified"
			local color = "Normal"
			local is_staged = staged_status ~= " " and staged_status ~= "?"

			if staged_status == "A" or unstaged_status == "A" then
				status_desc = "Added"
				color = "DiffAdd"
			elseif staged_status == "D" or unstaged_status == "D" then
				status_desc = "Deleted"
				color = "DiffDelete"
			elseif staged_status == "M" or unstaged_status == "M" then
				status_desc = "Modified"
				color = "Normal"
			elseif staged_status == "R" then
				status_desc = "Renamed"
				color = "DiffChange"
			elseif staged_status == "?" then
				status_desc = "Untracked"
				color = "Comment"
				is_staged = false
			end

			table.insert(files, {
				status = staged_status,
				status_desc = status_desc,
				filename = filename,
				color = color,
				is_staged = is_staged,
				display_name = (is_staged and "●" or "○") .. " " .. staged_status .. " " .. filename,
			})
		end
	end

	return files
end

local function get_staged_files()
	local files = {}
	for _, file in ipairs(all_files) do
		if file.is_staged then
			table.insert(files, file)
		end
	end
	return files
end

local function stage_file(filepath)
	local _, err = run_git_command("add " .. vim.fn.shellescape(filepath))
	return err == nil
end

local function unstage_file(filepath)
	local _, err = run_git_command("reset HEAD " .. vim.fn.shellescape(filepath))
	return err == nil
end

local function get_file_diff(filepath, staged_only)
	if not filepath then
		return "", "No file selected"
	end

	local diff_cmd = staged_only and "diff --cached" or "diff"
	local diff, err = run_git_command(diff_cmd .. " -- " .. vim.fn.shellescape(filepath))
	if err then
		return "", err
	end

	return diff or "", nil
end

local function get_all_staged_diffs()
	if #staged_files == 0 then
		return {
			"No files staged for commit",
			"",
			"Stage files with 's' key or use: git add <file>",
			"",
			"Available files are shown in the left panel.",
			"● = staged, ○ = unstaged",
		}
	end

	local all_diffs = {}
	table.insert(all_diffs, "=== ALL STAGED FILES DIFF ===")
	table.insert(all_diffs, "")
	table.insert(all_diffs, "Files to be committed (" .. #staged_files .. "):")

	for _, file in ipairs(staged_files) do
		table.insert(all_diffs, "  " .. file.display_name)
	end

	table.insert(all_diffs, "")
	table.insert(
		all_diffs,
		"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	)
	table.insert(all_diffs, "")

	for i, file in ipairs(staged_files) do
		table.insert(all_diffs, "")
		table.insert(all_diffs, "=== FILE " .. i .. "/" .. #staged_files .. ": " .. file.filename .. " ===")
		table.insert(all_diffs, "Status: " .. file.status_desc)
		table.insert(all_diffs, "")

		local diff_content, err = get_file_diff(file.filename, true)
		if err or not diff_content or diff_content == "" then
			if file.status == "D" then
				table.insert(all_diffs, "File deleted - no diff content")
			elseif file.status == "A" then
				table.insert(all_diffs, "New file added - content not shown in diff")
			else
				table.insert(all_diffs, "No diff content available")
			end
		else
			local diff_lines = vim.split(diff_content, "\n")
			for _, line in ipairs(diff_lines) do
				table.insert(all_diffs, line)
			end
		end

		table.insert(all_diffs, "")
		table.insert(
			all_diffs,
			"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
		)
	end

	return all_diffs
end

local function generate_commit_message_from_staged()
	if #staged_files == 0 then
		return "chore: update files"
	end

	local added_files = {}
	local modified_files = {}
	local deleted_files = {}

	for _, file in ipairs(staged_files) do
		if file.status == "A" then
			table.insert(added_files, file)
		elseif file.status == "M" then
			table.insert(modified_files, file)
		elseif file.status == "D" then
			table.insert(deleted_files, file)
		end
	end

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
		local parts = {}
		if #added_files > 0 then
			table.insert(parts, "add " .. #added_files .. " files")
		end
		if #modified_files > 0 then
			table.insert(parts, "update " .. #modified_files .. " files")
		end
		if #deleted_files > 0 then
			table.insert(parts, "remove " .. #deleted_files .. " files")
		end
		return "chore: " .. table.concat(parts, ", ")
	end
end

-- UI Functions
function M.close_git_commit_ui()
	local windows = { commit_win, files_win, diff_win }
	local buffers = { commit_buf, files_buf, diff_buf }

	for _, win in ipairs(windows) do
		if win and api.nvim_win_is_valid(win) then
			api.nvim_win_close(win, true)
		end
	end

	for _, buf in ipairs(buffers) do
		if buf and api.nvim_buf_is_valid(buf) then
			api.nvim_buf_delete(buf, { force = true })
		end
	end

	commit_win, files_win, diff_win = nil, nil, nil
	commit_buf, files_buf, diff_buf = nil, nil, nil
	staged_files = {}
	all_files = {}
	current_commit_message = ""
	focused_file_index = nil
end

local function update_commit_message()
	if not commit_buf or not api.nvim_buf_is_valid(commit_buf) then
		return
	end

	api.nvim_buf_set_option(commit_buf, "modifiable", true)

	local lines = {
		current_commit_message,
		"",
		"-- Auto-generated from staged files --",
		"-- Edit above, then press <Enter> to commit --",
		"-- Press 'r' to regenerate message --",
		"-- Press 'q' to quit --",
	}

	api.nvim_buf_set_lines(commit_buf, 0, -1, false, lines)

	if api.nvim_get_current_win() == commit_win then
		api.nvim_win_set_cursor(commit_win, { 1, 0 })
	end
end

local function update_files_list()
	if not files_buf or not api.nvim_buf_is_valid(files_buf) then
		return
	end

	api.nvim_buf_set_option(files_buf, "modifiable", true)

	local lines = {}
	table.insert(lines, "Files (" .. #staged_files .. " staged):")
	table.insert(lines, "")

	for i, file in ipairs(all_files) do
		table.insert(lines, file.display_name)
	end

	if #all_files == 0 then
		table.insert(lines, "No files modified")
	end

	table.insert(lines, "")
	table.insert(lines, "Legend: ● staged, ○ unstaged")
	table.insert(lines, "")
	table.insert(lines, "Navigation:")
	table.insert(lines, "  j/k      Move up/down")
	table.insert(lines, "  s        Stage/unstage file")
	table.insert(lines, "  <Enter>  View file diff")
	table.insert(lines, "  <Tab>    Focus diff preview")
	table.insert(lines, "  <S-Tab>  Focus commit message")
	table.insert(lines, "  <C-c>    Commit")
	table.insert(lines, "  q        Quit")

	api.nvim_buf_set_lines(files_buf, 0, -1, false, lines)
	api.nvim_buf_set_option(files_buf, "modifiable", false)

	local ns_id = api.nvim_create_namespace("git_files")
	api.nvim_buf_clear_namespace(files_buf, ns_id, 0, -1)

	for i, file in ipairs(all_files) do
		local line_nr = i + 1
		api.nvim_buf_add_highlight(files_buf, ns_id, file.color, line_nr, 0, -1)
	end
end

local function refresh_files()
	all_files = get_all_files()
	staged_files = get_staged_files()

	current_commit_message = generate_commit_message_from_staged()
	update_commit_message()
	update_files_list()
end

local function commit_staged_files()
	if #staged_files == 0 then
		notify_error("No staged files to commit")
		return
	end

	if current_commit_message == "" then
		notify_error("No commit message provided")
		return
	end

	local escaped_message = current_commit_message:gsub('"', '\\"')
	local _, err = run_git_command('commit -m "' .. escaped_message .. '"')

	if err then
		notify_error("Failed to commit: " .. err)
	else
		notify_info("✅ Successfully committed " .. #staged_files .. " files!")
		M.close_git_commit_ui()
	end
end

local function update_diff_preview(file_index)
	if not diff_buf or not api.nvim_buf_is_valid(diff_buf) then
		return
	end

	api.nvim_buf_set_option(diff_buf, "modifiable", true)

	if not file_index or file_index < 1 or file_index > #all_files then
		focused_file_index = nil
		local all_diffs = get_all_staged_diffs()
		api.nvim_buf_set_lines(diff_buf, 0, -1, false, all_diffs)
		api.nvim_buf_set_option(diff_buf, "filetype", "diff")
		api.nvim_buf_set_option(diff_buf, "modifiable", false)
		return
	end

	focused_file_index = file_index
	local file = all_files[file_index]

	local diff_content, err = get_file_diff(file.filename, file.is_staged)

	if err or not diff_content or diff_content == "" then
		local status_info = {
			"📄 " .. file.filename,
			"Status: " .. file.status_desc,
			"Staged: " .. (file.is_staged and "Yes" or "No"),
			"",
		}

		if file.status == "D" then
			table.insert(status_info, "This file was deleted")
			table.insert(status_info, "No diff content to show")
		elseif file.status == "A" then
			table.insert(status_info, "This file was added")
			if not diff_content or diff_content == "" then
				table.insert(status_info, "File is empty or binary")
			end
		else
			table.insert(status_info, "No diff content available")
			table.insert(status_info, "File might be binary or unchanged")
		end

		api.nvim_buf_set_lines(diff_buf, 0, -1, false, status_info)
		api.nvim_buf_set_option(diff_buf, "modifiable", false)
		return
	end

	local lines = vim.split(diff_content, "\n")
	local header = {
		"📄 " .. file.filename,
		"Status: " .. file.status_desc,
		"Staged: " .. (file.is_staged and "Yes" or "No"),
		"",
		"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
		"",
	}

	local final_lines = {}
	for _, line in ipairs(header) do
		table.insert(final_lines, line)
	end
	for _, line in ipairs(lines) do
		table.insert(final_lines, line)
	end

	api.nvim_buf_set_lines(diff_buf, 0, -1, false, final_lines)
	api.nvim_buf_set_option(diff_buf, "filetype", "diff")
	api.nvim_buf_set_option(diff_buf, "modifiable", false)
end

-- Keymaps
local function setup_commit_buffer_keymaps()
	if not commit_buf then
		return
	end

	local opts = { buffer = commit_buf, noremap = true, silent = true }

	vim.keymap.set("n", "<CR>", function()
		local lines = api.nvim_buf_get_lines(commit_buf, 0, 1, false)
		if #lines > 0 then
			current_commit_message = lines[1]:gsub("^%s*", ""):gsub("%s*$", "")
			commit_staged_files()
		end
	end, opts)

	vim.keymap.set("i", "<C-c>", function()
		vim.cmd("stopinsert")
		local lines = api.nvim_buf_get_lines(commit_buf, 0, 1, false)
		if #lines > 0 then
			current_commit_message = lines[1]:gsub("^%s*", ""):gsub("%s*$", "")
			commit_staged_files()
		end
	end, opts)

	vim.keymap.set("n", "r", function()
		current_commit_message = generate_commit_message_from_staged()
		update_commit_message()
	end, opts)

	vim.keymap.set("n", "<Tab>", function()
		api.nvim_set_current_win(files_win)
	end, opts)

	-- Navigate to diff with Shift+Tab
	vim.keymap.set("n", "<S-Tab>", function()
		api.nvim_set_current_win(diff_win)
	end, opts)

	-- Navigate to commit with Shift+Tab
	vim.keymap.set("n", "<S-Tab>", function()
		api.nvim_set_current_win(commit_win)
	end, opts)

	vim.keymap.set("n", "q", M.close_git_commit_ui, opts)
	vim.keymap.set("n", "<Esc>", M.close_git_commit_ui, opts)
end

local function setup_diff_buffer_keymaps()
	if not diff_buf then
		return
	end

	local opts = { buffer = diff_buf, noremap = true, silent = true }

	-- Navigate back to files panel
	vim.keymap.set("n", "<Tab>", function()
		api.nvim_set_current_win(files_win)
	end, opts)

	-- Navigate to commit message
	vim.keymap.set("n", "<S-Tab>", function()
		api.nvim_set_current_win(commit_win)
	end, opts)

	-- Navigate to files with h
	vim.keymap.set("n", "h", function()
		api.nvim_set_current_win(files_win)
	end, opts)

	-- Navigate to commit message with H
	vim.keymap.set("n", "H", function()
		api.nvim_set_current_win(commit_win)
	end, opts)

	-- Allow normal vim navigation in diff
	-- j/k/g/G work normally for scrolling

	-- Quick commit
	vim.keymap.set("n", "<C-c>", function()
		if current_commit_message ~= "" then
			commit_staged_files()
		else
			notify_error("No commit message. Focus commit panel and add message.")
		end
	end, opts)

	-- Quit
	vim.keymap.set("n", "q", M.close_git_commit_ui, opts)
	vim.keymap.set("n", "<Esc>", M.close_git_commit_ui, opts)
end

local function setup_files_buffer_keymaps()
	if not files_buf then
		return
	end

	local opts = { buffer = files_buf, noremap = true, silent = true }

	vim.keymap.set("n", "j", function()
		vim.cmd("normal! j")
		local cursor_line = api.nvim_win_get_cursor(files_win)[1]
		local file_index = cursor_line - 2
		update_diff_preview(file_index)
	end, opts)

	vim.keymap.set("n", "k", function()
		vim.cmd("normal! k")
		local cursor_line = api.nvim_win_get_cursor(files_win)[1]
		local file_index = cursor_line - 2
		update_diff_preview(file_index)
	end, opts)

	vim.keymap.set("n", "s", function()
		local cursor_line = api.nvim_win_get_cursor(files_win)[1]
		local file_index = cursor_line - 2

		if file_index >= 1 and file_index <= #all_files then
			local file = all_files[file_index]

			if file.is_staged then
				if unstage_file(file.filename) then
					notify_info("Unstaged: " .. file.filename)
					refresh_files()
					api.nvim_win_set_cursor(files_win, { cursor_line, 0 })
					update_diff_preview(file_index)
				end
			else
				if stage_file(file.filename) then
					notify_info("Staged: " .. file.filename)
					refresh_files()
					api.nvim_win_set_cursor(files_win, { cursor_line, 0 })
					update_diff_preview(file_index)
				end
			end
		end
	end, opts)

	vim.keymap.set("n", "<CR>", function()
		local cursor_line = api.nvim_win_get_cursor(files_win)[1]
		local file_index = cursor_line - 2
		update_diff_preview(file_index)
	end, opts)

	vim.keymap.set("n", "<Tab>", function()
		api.nvim_set_current_win(diff_win)
	end, opts)

	vim.keymap.set("n", "<C-c>", function()
		if current_commit_message ~= "" then
			commit_staged_files()
		else
			notify_error("No commit message. Focus commit panel and add message.")
		end
	end, opts)

	vim.keymap.set("n", "q", M.close_git_commit_ui, opts)
	vim.keymap.set("n", "<Esc>", M.close_git_commit_ui, opts)
end

-- Main UI function
function M.show_git_commit_ui()
	if not is_git_repo() then
		notify_error("Not in a git repository")
		return
	end

	refresh_files()

	if #all_files == 0 then
		notify_error("No files modified. Make some changes first.")
		return
	end

	current_commit_message = generate_commit_message_from_staged()

	local screen_width = api.nvim_get_option("columns")
	local screen_height = api.nvim_get_option("lines")
	local width = math.floor(screen_width * M.config.ui.width)
	local height = math.floor(screen_height * M.config.ui.height)
	local row = math.floor((screen_height - height) / 2)
	local col = math.floor((screen_width - width) / 2)

	local left_width = math.floor(width * 0.4)
	local right_width = width - left_width - 1

	local commit_height = math.floor(height * 0.3)
	local files_height = height - commit_height - 1

	commit_buf = api.nvim_create_buf(false, true)
	files_buf = api.nvim_create_buf(false, true)
	diff_buf = api.nvim_create_buf(false, true)

	commit_win = api.nvim_open_win(commit_buf, true, {
		relative = "editor",
		width = left_width,
		height = commit_height,
		row = row,
		col = col,
		border = M.config.ui.border,
		title = " Commit Message ",
		title_pos = "center",
	})

	files_win = api.nvim_open_win(files_buf, false, {
		relative = "editor",
		width = left_width,
		height = files_height,
		row = row + commit_height + 1,
		col = col,
		border = M.config.ui.border,
		title = " Files ",
		title_pos = "center",
	})

	diff_win = api.nvim_open_win(diff_buf, false, {
		relative = "editor",
		width = right_width,
		height = height,
		row = row,
		col = col + left_width + 1,
		border = M.config.ui.border,
		title = " Diff Preview ",
		title_pos = "center",
	})

	for _, buf in ipairs({ commit_buf, files_buf, diff_buf }) do
		api.nvim_buf_set_option(buf, "bufhidden", "wipe")
		api.nvim_buf_set_option(buf, "buftype", "nofile")
		api.nvim_buf_set_option(buf, "swapfile", false)
	end

	api.nvim_buf_set_option(commit_buf, "modifiable", true)
	api.nvim_buf_set_option(diff_buf, "modifiable", false)

	setup_commit_buffer_keymaps()
	setup_files_buffer_keymaps()
	setup_diff_buffer_keymaps()

	update_commit_message()
	update_files_list()
	update_diff_preview(nil)

	api.nvim_set_current_win(files_win)
	if #all_files > 0 then
		api.nvim_win_set_cursor(files_win, { 3, 0 })
		update_diff_preview(1)
	end

	notify_info("Git UI: " .. #staged_files .. " staged, " .. (#all_files - #staged_files) .. " unstaged files")
end

-- Setup function
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	api.nvim_create_user_command("GitCommit", function()
		M.show_git_commit_ui()
	end, { desc = "Open git commit interface" })

	if M.config.keymaps and M.config.keymaps.git_commit then
		vim.keymap.set("n", M.config.keymaps.git_commit, function()
			M.show_git_commit_ui()
		end, { desc = "Open Git Commit UI", silent = true })
	end

	notify_info("Git Commit plugin loaded! Use :GitCommit")
end

return M
