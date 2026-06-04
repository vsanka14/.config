-- helpers/gridtable.lua - blink.cmp SQL dataset + field completion from SQLite.
--
-- Neovim is read-only in this flow. The DB is built outside Neovim by:
--   python3 ~/code/meta-gridtable-index/build_index.py
--
-- The source never calls live `meta`; missing SQLite data means no Meta items.

local Kind = require("blink.cmp.types").CompletionItemKind
local PlainText = vim.lsp.protocol.InsertTextFormat.PlainText
local NameKind = Kind.Struct or Kind.Class or Kind.Module

--- @class blink.cmp.Source
local Source = {}

local config = {
	db_path = vim.fn.expand("~/.cache/meta-gridtable-index/index.sqlite3"),
	sqlite_bin = "sqlite3",
	list_limit = 500,
}

local list_cache = {}
local fields_cache = {}
local warned_missing = false

local KEYWORDS = {
	["and"] = true,
	["as"] = true,
	["cluster"] = true,
	["cross"] = true,
	["except"] = true,
	["full"] = true,
	["group"] = true,
	["having"] = true,
	["inner"] = true,
	["intersect"] = true,
	["join"] = true,
	["left"] = true,
	["limit"] = true,
	["offset"] = true,
	["on"] = true,
	["or"] = true,
	["order"] = true,
	["outer"] = true,
	["qualify"] = true,
	["right"] = true,
	["select"] = true,
	["tablesample"] = true,
	["union"] = true,
	["using"] = true,
	["where"] = true,
	["window"] = true,
}

local TABLE_INTRO = {
	["from"] = true,
	["into"] = true,
	["join"] = true,
	["table"] = true,
	["update"] = true,
}

local FROMLIST_BREAK = {
	["and"] = true,
	["by"] = true,
	["except"] = true,
	["group"] = true,
	["having"] = true,
	["intersect"] = true,
	["limit"] = true,
	["offset"] = true,
	["on"] = true,
	["or"] = true,
	["order"] = true,
	["qualify"] = true,
	["select"] = true,
	["set"] = true,
	["union"] = true,
	["using"] = true,
	["values"] = true,
	["where"] = true,
	["window"] = true,
}

function Source.new(opts, _)
	local self = setmetatable({}, { __index = Source })
	opts = opts or {}
	if type(opts.db_path) == "string" and opts.db_path ~= "" then
		config.db_path = opts.db_path
	end
	if type(opts.sqlite_bin) == "string" and opts.sqlite_bin ~= "" then
		config.sqlite_bin = opts.sqlite_bin
	end
	local list_limit = tonumber(opts.list_limit)
	if list_limit then
		config.list_limit = list_limit
	end
	return self
end

function Source:enabled()
	return vim.bo.filetype == "sql"
end

function Source:get_trigger_characters()
	return { "." }
end

local function sql_quote(value)
	return "'" .. tostring(value or ""):gsub("'", "''") .. "'"
end

local function valid_ident(value)
	return type(value) == "string" and value:match("^[%w_%.]*$") ~= nil
end

local function sqlite_lines(sql)
	if vim.fn.filereadable(config.db_path) ~= 1 then
		if not warned_missing then
			warned_missing = true
			vim.notify_once(
				"Meta SQLite DB not found: " .. config.db_path .. " (run python3 ~/code/meta-gridtable-index/build_index.py)",
				vim.log.levels.WARN,
				{ title = "Meta" }
			)
		end
		return nil
	end

	local lines = vim.fn.systemlist({
		config.sqlite_bin,
		"-readonly",
		"-batch",
		"-noheader",
		"-separator",
		"\t",
		config.db_path,
		sql,
	})
	if vim.v.shell_error ~= 0 then
		return nil
	end
	return lines
end

local function list_datasets(prefix, limit)
	prefix = prefix or ""
	if not valid_ident(prefix) then
		return {}
	end
	limit = tonumber(limit) or config.list_limit
	local key = prefix .. "\0" .. tostring(limit)
	if list_cache[key] then
		return list_cache[key]
	end

	local sql = table.concat({
		"select name from datasets",
		"where name glob " .. sql_quote(prefix .. "*"),
		"order by name",
		"limit " .. tostring(limit),
	}, " ") .. ";"

	local rows = sqlite_lines(sql) or {}
	local names = {}
	for _, row in ipairs(rows) do
		if row ~= "" then
			names[#names + 1] = row
		end
	end
	list_cache[key] = names
	return names
end

local function list_fields(dataset, parent_path)
	parent_path = parent_path or ""
	if not valid_ident(dataset) or not valid_ident(parent_path) then
		return {}
	end
	local key = dataset .. "\0" .. parent_path
	if fields_cache[key] then
		return fields_cache[key]
	end

	local sql = table.concat({
		"select name, native_type from fields",
		"where dataset_name = " .. sql_quote(dataset),
		"and parent_path = " .. sql_quote(parent_path),
		"order by ordinal",
	}, " ") .. ";"

	local rows = sqlite_lines(sql) or {}
	local fields = {}
	for _, row in ipairs(rows) do
		local name, native_type = row:match("^([^\t]*)\t(.*)$")
		if name and name ~= "" then
			fields[#fields + 1] = { name = name, type = native_type or "" }
		end
	end
	fields_cache[key] = fields
	return fields
end

local function sanitize(text)
	text = text:gsub("/%*.-%*/", " ")
	text = text:gsub("%-%-[^\n]*", " ")
	text = text:gsub("'[^']*'", " ")
	text = text:gsub('"[^"]*"', " ")
	return text
end

local function is_dotted_dataset(ident)
	return ident:match("^[%w_]+%.[%w_]+$") ~= nil or ident:match("^[%w_]+%.[%w_]+%.[%w_]+$") ~= nil
end

local function buffer_text(bufnr)
	local lines = vim.api.nvim_buf_get_lines(bufnr or 0, 0, -1, false)
	return sanitize(table.concat(lines, "\n")):lower()
end

local function scan_datasets(bufnr)
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

local function alias_map(bufnr)
	local text = buffer_text(bufnr)
	local map = {}
	local function consider(ds, w1, w2)
		if not is_dotted_dataset(ds) then
			return
		end
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

local function path_before_cursor()
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

local function resolve_member(bufnr, segs)
	if not segs or #segs == 0 then
		return nil
	end
	local aliases = alias_map(bufnr)
	local all = scan_datasets(bufnr)

	if aliases[segs[1]] then
		return aliases[segs[1]], slice(segs, 2)
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
	if pre:match(",%s*$") then
		return in_from_list(pre)
	end
	return false
end

local function name_context()
	local col = vim.api.nvim_win_get_cursor(0)[2]
	local before = vim.api.nvim_get_current_line():sub(1, col):lower()
	local typed = before:match("([%w_%.]+)$") or ""
	local pre = before:sub(1, #before - #typed)
	if not is_table_name_position(pre) then
		return nil
	end
	local strip = typed:match("^(.*%.)") or ""
	return { typed = typed, strip = strip }
end

local function fields_to_items(fields)
	local items = {}
	for _, f in ipairs(fields or {}) do
		items[#items + 1] = {
			label = f.name,
			kind = Kind.Field,
			insertText = f.name,
			insertTextFormat = PlainText,
			detail = (f.type ~= "" and f.type) or nil,
			labelDetails = { description = (f.type ~= "" and f.type) or nil },
		}
	end
	return items
end

local function names_to_items(names, nctx)
	local items = {}
	local typed = nctx.typed or ""
	local strip = nctx.strip or ""
	for _, full in ipairs(names or {}) do
		local insert
		if typed == "" or full:sub(1, #typed):lower() == typed:lower() then
			insert = (strip ~= "") and full:sub(#strip + 1) or full
		end
		if insert and insert ~= "" then
			items[#items + 1] = {
				label = insert,
				kind = NameKind,
				insertText = insert,
				insertTextFormat = PlainText,
				filterText = insert,
				detail = full,
				labelDetails = { description = "dataset" },
			}
		end
	end
	return items
end

function Source:get_completions(_, callback)
	local bufnr = vim.api.nvim_get_current_buf()
	local empty = { is_incomplete_forward = false, is_incomplete_backward = false, items = {} }

	local segs = path_before_cursor()
	if segs then
		local dataset, field_path = resolve_member(bufnr, segs)
		if dataset then
			local parent_path = table.concat(field_path or {}, ".")
			callback({
				is_incomplete_forward = false,
				is_incomplete_backward = false,
				items = fields_to_items(list_fields(dataset, parent_path)),
			})
			return
		end
	end

	local nctx = name_context()
	if not nctx then
		callback(empty)
		return
	end

	local prefix = (nctx.strip ~= "" and nctx.strip) or nctx.typed
	callback({
		is_incomplete_forward = false,
		is_incomplete_backward = false,
		items = names_to_items(list_datasets(prefix), nctx),
	})
end

return Source
