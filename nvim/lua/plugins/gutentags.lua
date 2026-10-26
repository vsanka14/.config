-- Background ctags indexer for the no-LSP flow. Indexes only git-tracked files,
-- caches tags outside the repo, and regenerates on-demand rather than on save.
return {
	"ludovicchabant/vim-gutentags",
	event = { "BufReadPost", "BufNewFile" },
	init = function()
		-- /usr/bin/ctags is the macOS BSD stub and shadows Homebrew's
		-- universal-ctags in PATH, so point at the real binary explicitly.
		local brew_ctags = "/opt/homebrew/bin/ctags"
		vim.g.gutentags_ctags_executable = vim.fn.executable(brew_ctags) == 1 and brew_ctags or "ctags"

		vim.g.gutentags_modules = { "ctags" }
		vim.g.gutentags_cache_dir = vim.fn.expand("~/.cache/gutentags")
		vim.g.gutentags_ctags_tagfile = "tags"

		vim.g.gutentags_add_default_project_roots = 0
		vim.g.gutentags_project_root = { ".git" }
		vim.g.gutentags_file_list_command = {
			markers = {
				[".git"] = "git ls-files",
			},
		}

		vim.g.gutentags_ctags_extra_args = {
			-- Absolute paths: the tagfile lives in the cache dir, so relative
			-- paths would resolve against it and break jumps.
			"--tag-relative=never",
			-- Skip data/markup languages that flood the index with noise.
			"--languages=-JavaProperties,-Iniconf,-Json,-Yaml,-Markdown,-XML,-SVG,-HTML,-Pod,-reStructuredText",
			"--fields=+ailmn",
		}

		-- On first open only, never on save: reindexing big repos is slow and the
		-- AI agent edits files outside nvim. Refresh manually with <Leader>ft.
		vim.g.gutentags_generate_on_new = 1
		vim.g.gutentags_generate_on_missing = 1
		vim.g.gutentags_generate_on_write = 0
		vim.g.gutentags_generate_on_empty_buffer = 0
	end,
}
