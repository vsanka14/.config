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
	M = Kind.Field,
	G = Kind.Property,
}

-- ctags kinds that are noise for cross-file completion: import aliases (dupes of
-- the real definition elsewhere), batch labels, and preprocessor/style locals.
local DROP_KINDS = {
	a = true,
	l = true,
	z = true,
}

-- A name is often tagged in many places with different kinds (e.g. the real
-- `const` plus field re-assignments/imports). When deduping, keep the most
-- meaningful kind so the icon reflects the actual definition, not whichever
-- tag happened to sort first.
local KIND_PRIORITY = {
	c = 9,
	C = 8,
	f = 7,
	F = 7,
	m = 6,
	i = 6,
	g = 5,
	t = 5,
	s = 5,
	G = 5,
	e = 4,
	p = 3,
	M = 2,
	v = 1,
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
	-- Mark the "nothing yet" result incomplete so blink keeps re-querying as the
	-- keyword grows past min_keyword; a complete empty list would be cached and
	-- never refreshed, so completions would never appear.
	local empty = { is_incomplete_forward = true, is_incomplete_backward = true, items = {} }

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

	-- First pass: collect unique names in first-seen order, upgrading each to
	-- the highest-priority kind seen across all of its tags.
	local order, best = {}, {}
	for _, t in ipairs(tags) do
		local name = t.name
		-- Skip qualified tags (Foo.bar) so completion inserts plain identifiers,
		-- and low-value kinds (imports, labels, style locals).
		if name and name:match("^[%w_]+$") and not DROP_KINDS[t.kind] then
			local prio = KIND_PRIORITY[t.kind] or 0
			local cur = best[name]
			if not cur then
				order[#order + 1] = name
				best[name] = { kind = KIND_MAP[t.kind] or Kind.Text, prio = prio }
			elseif prio > cur.prio then
				cur.kind = KIND_MAP[t.kind] or Kind.Text
				cur.prio = prio
			end
		end
	end

	local items = {}
	for _, name in ipairs(order) do
		items[#items + 1] = {
			label = name,
			kind = best[name].kind,
			insertText = name,
			insertTextFormat = PlainText,
			labelDetails = { description = "tag" },
		}
		if #items >= config.list_limit then
			break
		end
	end

	callback({ is_incomplete_forward = true, is_incomplete_backward = true, items = items })
end

return Source
