-- sql-datasets.lua — parse dataset references out of a SQL buffer.
--
-- Pure text helpers (no side effects, no jobs). Used by the blink completion
-- source to decide which datasets' columns to offer, and by the meta schema
-- client's refresh command to know what to re-warm.
--
-- Also hosts the Hive type parser (`struct_fields`/`descend`) used to walk the
-- nested `struct<...>` schema that the `meta` CLI returns.

local M = {}

-- SQL keywords that can legally follow a `FROM <dataset>` / `JOIN <dataset>`
-- token. We use this to avoid mistaking a clause keyword for a table alias.
local KEYWORDS = {
	["as"] = true,
	["where"] = true,
	["join"] = true,
	["inner"] = true,
	["left"] = true,
	["right"] = true,
	["outer"] = true,
	["full"] = true,
	["cross"] = true,
	["on"] = true,
	["using"] = true,
	["group"] = true,
	["order"] = true,
	["having"] = true,
	["limit"] = true,
	["offset"] = true,
	["union"] = true,
	["except"] = true,
	["intersect"] = true,
	["window"] = true,
	["qualify"] = true,
	["and"] = true,
	["or"] = true,
	["select"] = true,
	["cluster"] = true,
	["tablesample"] = true,
}

-- Strip block/line comments and string literals so we don't pick up dataset
-- look-alikes inside them. Replace with a space to avoid gluing tokens.
local function sanitize(text)
	text = text:gsub("/%*.-%*/", " ") -- /* block comments */
	text = text:gsub("%-%-[^\n]*", " ") -- -- line comments
	text = text:gsub("'[^']*'", " ") -- 'string literals'
	text = text:gsub('"[^"]*"', " ") -- "quoted identifiers" (out of scope)
	return text
end

-- A valid describe target is a 2-part (schema.table) or 3-part
-- (catalog.schema.table) dotted identifier. Single identifiers are skipped,
-- which conveniently excludes CTE names and subquery aliases.
local function is_dotted_dataset(ident)
	return ident:match("^[%w_]+%.[%w_]+$") ~= nil or ident:match("^[%w_]+%.[%w_]+%.[%w_]+$") ~= nil
end

M.is_dataset = is_dotted_dataset

-- Lowercase the working copy: SQL identifiers are case-insensitive, so
-- normalizing keeps the cache key and alias lookups stable.
local function buffer_text(bufnr)
	local lines = vim.api.nvim_buf_get_lines(bufnr or 0, 0, -1, false)
	return sanitize(table.concat(lines, "\n")):lower()
end

-- Return a de-duplicated, ordered list of datasets referenced by FROM/JOIN.
function M.scan(bufnr)
	local text = buffer_text(bufnr)
	local seen, list = {}, {}
	local function add(ident)
		if not is_dotted_dataset(ident) then
			return
		end
		if not seen[ident] then
			seen[ident] = true
			list[#list + 1] = ident
		end
	end
	-- `[^%w_]` (or string start) guards the keyword so we don't match inside a
	-- longer word like "transform" containing "from".
	for ident in text:gmatch("[^%w_]from%s+([%w_%.]+)") do
		add(ident)
	end
	for ident in text:gmatch("[^%w_]join%s+([%w_%.]+)") do
		add(ident)
	end
	if text:match("^from%s+") then
		add(text:match("^from%s+([%w_%.]+)"))
	end
	return list
end

-- Build an alias -> dataset map from `FROM/JOIN <dataset> [AS] <alias>`.
function M.alias_map(bufnr)
	local text = buffer_text(bufnr)
	local map = {}
	local function consider(ds, w1, w2)
		if not is_dotted_dataset(ds) then
			return
		end
		-- `AS` is optional: when present the alias is the following word.
		local alias = (w1 == "as") and w2 or w1
		if not alias or alias == "" or KEYWORDS[alias] then
			return
		end
		if alias:match("^[%w_]+$") then
			map[alias] = ds
		end
	end
	for ds, w1, w2 in text:gmatch("[^%w_]from%s+([%w_%.]+)%s+([%w_]+)%s*([%w_]*)") do
		consider(ds, w1, w2)
	end
	for ds, w1, w2 in text:gmatch("[^%w_]join%s+([%w_%.]+)%s+([%w_]+)%s*([%w_]*)") do
		consider(ds, w1, w2)
	end
	return map
end

local function slice(t, from, to)
	local r = {}
	for i = from, (to or #t) do
		r[#r + 1] = t[i]
	end
	return r
end

local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Split `s` on top-level occurrences of `delim` — i.e. delimiters that are not
-- nested inside angle brackets `< >` (struct/array/map) or parens `( )`
-- (decimal precision). Hive types nest with both, so depth must track both.
local function split_top_level(s, delim)
	local parts, buf, depth = {}, {}, 0
	for i = 1, #s do
		local c = s:sub(i, i)
		if c == "<" or c == "(" then
			depth = depth + 1
			buf[#buf + 1] = c
		elseif c == ">" or c == ")" then
			depth = depth - 1
			buf[#buf + 1] = c
		elseif c == delim and depth == 0 then
			parts[#parts + 1] = table.concat(buf)
			buf = {}
		else
			buf[#buf + 1] = c
		end
	end
	parts[#parts + 1] = table.concat(buf)
	return parts
end

-- Split a single Hive `name:type` field on its first *top-level* colon. The
-- type half may itself contain colons (nested `struct<a:int>`), so we only
-- split at depth 0. Returns name, type (or nil if there's no top-level colon).
local function split_name_type(s)
	local depth = 0
	for i = 1, #s do
		local c = s:sub(i, i)
		if c == "<" or c == "(" then
			depth = depth + 1
		elseif c == ">" or c == ")" then
			depth = depth - 1
		elseif c == ":" and depth == 0 then
			return trim(s:sub(1, i - 1)), trim(s:sub(i + 1))
		end
	end
	return nil
end

-- Peel Hive `array<...>` / `map<k,v>` wrappers until we reach a `struct<...>`,
-- then return its inner field list (the text between the outer angle brackets).
-- Returns nil for scalar types that have no addressable sub-fields.
local function unwrap_to_struct(t)
	t = trim(t)
	while true do
		local lower = t:lower()
		if lower:sub(1, 7) == "struct<" then
			return t:sub(8, -2)
		elseif lower:sub(1, 6) == "array<" then
			t = trim(t:sub(7, -2))
		elseif lower:sub(1, 4) == "map<" then
			local args = split_top_level(t:sub(5, -2), ",")
			if #args ~= 2 then
				return nil
			end
			t = trim(args[2])
		else
			return nil
		end
	end
end

-- Parse a Hive `struct<...>` type string into its named fields. Returns a list
-- of { name, type } or nil if the type isn't a struct. Also used to parse the
-- top-level schema (which `meta` returns as one outer `struct<...>`).
function M.struct_fields(type_str)
	local inner = unwrap_to_struct(type_str or "")
	if not inner then
		return nil
	end
	local fields = {}
	for _, part in ipairs(split_top_level(inner, ",")) do
		local name, rest = split_name_type(trim(part))
		if name and name ~= "" then
			fields[#fields + 1] = { name = name, type = rest }
		end
	end
	return fields
end

-- Walk a list of top-level columns into nested `struct<...>` fields following
-- `field_path` (lowercased segment names). Returns the field list available at
-- the end of the path, or nil if a segment is missing or non-struct.
function M.descend(columns, field_path)
	local current = columns
	for _, seg in ipairs(field_path or {}) do
		local found
		for _, f in ipairs(current) do
			if f.name:lower() == seg then
				found = f
				break
			end
		end
		if not found then
			return nil
		end
		local sub = M.struct_fields(found.type)
		if not sub then
			return nil
		end
		current = sub
	end
	return current
end

-- Capture the dotted "container" path immediately left of the cursor — the
-- segments before the final `.` that we're completing after. For `a.header.au`
-- (cursor after `au`) this returns { "a", "header" }; for `a.` it returns
-- { "a" }. Returns nil when the cursor isn't positioned after a `.`.
function M.path_before_cursor()
	local col = vim.api.nvim_win_get_cursor(0)[2]
	local before = vim.api.nvim_get_current_line():sub(1, col)
	local chain = before:match("([%w_]+%.[%w_%.]*)$")
	if not chain then
		return nil
	end
	local container = chain:match("^(.-)%.[%w_]*$")
	if not container or container == "" then
		return nil
	end
	local segs = {}
	for s in container:gmatch("[%w_]+") do
		segs[#segs + 1] = s:lower()
	end
	return (#segs > 0) and segs or nil
end

-- Resolve a container path to a dataset plus the remaining field path inside it.
-- The first segment(s) may be: an alias, a full referenced dataset name (2- or
-- 3-part), or the bare table component of a referenced dataset. Returns
-- `dataset, field_path` or nil if the path doesn't map to a known dataset.
function M.resolve_member(bufnr, segs)
	if not segs or #segs == 0 then
		return nil
	end
	local alias = M.alias_map(bufnr)
	local all = M.scan(bufnr)

	if alias[segs[1]] then
		return alias[segs[1]], slice(segs, 2)
	end

	for _, n in ipairs({ 3, 2 }) do
		if #segs >= n then
			local cand = table.concat(slice(segs, 1, n), ".")
			for _, ds in ipairs(all) do
				if ds == cand then
					return ds, slice(segs, n + 1)
				end
			end
		end
	end

	for _, ds in ipairs(all) do
		if ds:match("([%w_]+)$") == segs[1] then
			return ds, slice(segs, 2)
		end
	end

	return nil
end

-- SQL keywords that introduce a dataset/table name directly to their right
-- (`FROM x`, `JOIN x`, `INSERT INTO x`, `UPDATE x`, `... TABLE x`).
local TABLE_INTRO = {
	["from"] = true,
	["join"] = true,
	["into"] = true,
	["update"] = true,
	["table"] = true,
}

-- Keywords that close out a FROM/JOIN table list: once we see one of these we
-- are no longer naming tables, so a trailing comma shouldn't trigger dataset
-- completion (e.g. a comma in the SELECT list).
local FROMLIST_BREAK = {
	["select"] = true,
	["where"] = true,
	["group"] = true,
	["order"] = true,
	["having"] = true,
	["qualify"] = true,
	["window"] = true,
	["union"] = true,
	["except"] = true,
	["intersect"] = true,
	["on"] = true,
	["using"] = true,
	["set"] = true,
	["values"] = true,
	["by"] = true,
	["limit"] = true,
	["offset"] = true,
	["and"] = true,
	["or"] = true,
}

-- Heuristic: is the text `pre` (everything left of the identifier being typed)
-- in a FROM/JOIN table list? True when the nearest `from`/`join` keyword comes
-- after the nearest list-closing keyword.
local function in_from_list(pre)
	local last_from, last_break = 0, 0
	for pos, word in pre:gmatch("()([%a_]+)") do
		if word == "from" or word == "join" then
			last_from = pos
		elseif FROMLIST_BREAK[word] then
			last_break = pos
		end
	end
	return last_from > 0 and last_from > last_break
end

local function is_table_name_position(pre)
	local last = pre:match("([%a_]+)%s*$")
	if last and TABLE_INTRO[last] then
		return true
	end
	-- A continuation in a comma-separated FROM list: `from a.b t1, <here>`.
	if pre:match(",%s*$") then
		return in_from_list(pre)
	end
	return false
end

-- When the cursor sits where a dataset name is expected (after FROM/JOIN/etc.),
-- return the dotted name fragment being typed split for prefix listing:
--   typed   = the full fragment (e.g. "tracking.adcon" or "track")
--   strip   = the container up to and including the last dot ("tracking." / "")
--   partial = the segment after the last dot ("adcon" / "track")
-- Returns nil when the cursor isn't in a table-name position.
function M.name_context()
	local col = vim.api.nvim_win_get_cursor(0)[2]
	local before = vim.api.nvim_get_current_line():sub(1, col):lower()
	local typed = before:match("([%w_%.]+)$") or ""
	local pre = before:sub(1, #before - #typed)
	if not is_table_name_position(pre) then
		return nil
	end
	local strip = typed:match("^(.*%.)") or ""
	local partial = typed:sub(#strip + 1)
	return { typed = typed, strip = strip, partial = partial }
end

return M
