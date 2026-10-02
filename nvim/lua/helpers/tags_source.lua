-- helpers/tags_source.lua - blink.cmp completion from the ctags index.
--
-- Fills the gap LSP leaves while typing: inline completion of symbols defined in
-- other files. Backed by the same on-disk tags index gutentags builds, so it
-- costs no resident memory. Kept cheap: fires only after a few characters and
-- prefix-matches via taglist (binary search over the sorted tags file), skipping
-- qualified Foo.bar tags so it inserts plain identifiers.

local Kind = require("blink.cmp.types").CompletionItemKind
local PlainText = vim.lsp.protocol.InsertTextFormat.PlainText

-- ctags kind letter -> blink completion kind (for the menu icon).
local KIND_MAP = {
	f = Kind.Function,
	F = Kind.Function,
	m = Kind.Method,
	c = Kind.Class,
	C = Kind.Constant,
	v = Kind.Variable,
	p = Kind.Property,
	t = Kind.Struct,
	i = Kind.Interface,
	g = Kind.Enum,
	e = Kind.EnumMember,
	s = Kind.Struct,
}

--- @class blink.cmp.Source
local Source = {}

local config = {
	min_keyword = 3,
	list_limit = 200,
}

-- Prose filetypes where symbol completion is just noise.
local DISABLED = {
	markdown = true,
	mdx = true,
	text = true,
	help = true,
	gitcommit = true,
	gitrebase = true,
	sql = true,
}

function Source.new(opts, _)
	local self = setmetatable({}, { __index = Source })
	opts = opts or {}
	local min_keyword = tonumber(opts.min_keyword)
	if min_keyword then
		config.min_keyword = min_keyword
	end
	local list_limit = tonumber(opts.list_limit)
	if list_limit then
		config.list_limit = list_limit
	end
	return self
end

function Source:enabled()
	return not DISABLED[vim.bo.filetype]
end

function Source:get_completions(_, callback)
	local empty = { is_incomplete_forward = false, is_incomplete_backward = false, items = {} }

	local col = vim.api.nvim_win_get_cursor(0)[2]
	local before = vim.api.nvim_get_current_line():sub(1, col)
	local prefix = before:match("[%w_]+$")
	if not prefix or #prefix < config.min_keyword then
		callback(empty)
		return
	end

	local ok, tags = pcall(vim.fn.taglist, "^" .. vim.fn.escape(prefix, "\\/.*$^~[]"))
	if not ok or type(tags) ~= "table" then
		callback(empty)
		return
	end

	local items, seen = {}, {}
	for _, t in ipairs(tags) do
		local name = t.name
		-- Skip qualified tags (Foo.bar) so completion inserts plain identifiers.
		if name and name:match("^[%w_]+$") and not seen[name] then
			seen[name] = true
			items[#items + 1] = {
				label = name,
				kind = KIND_MAP[t.kind] or Kind.Text,
				insertText = name,
				insertTextFormat = PlainText,
				labelDetails = { description = "tag" },
			}
			if #items >= config.list_limit then
				break
			end
		end
	end

	callback({ is_incomplete_forward = true, is_incomplete_backward = true, items = items })
end

return Source
