-- blink-sources/meta_columns.lua — a blink.cmp completion source for .sql files
-- that offers both:
--   * dataset *names* (in FROM/JOIN positions), listed by prefix from the
--     `gridTable` platform via `meta dataset list`, and
--   * the column / nested struct field names of a referenced dataset.
--
-- Both are fetched lazily (and cached) by helpers.meta-schema, which shells out
-- to the `meta` CLI. This module is the glue: it decides what the cursor is on,
-- turns meta's output into blink items, and streams fresh results in as the
-- async fetches resolve.

local datasets = require("helpers.sql-datasets")
local schema = require("helpers.meta-schema")

local Kind = require("blink.cmp.types").CompletionItemKind
local PlainText = vim.lsp.protocol.InsertTextFormat.PlainText
local NameKind = Kind.Struct or Kind.Class or Kind.Module

--- @class blink.cmp.Source
local Source = {}

function Source.new(opts, _)
	local self = setmetatable({}, { __index = Source })
	-- Apply platform (and any tuning) to the shared schema client.
	schema.setup(opts or {})
	return self
end

function Source:enabled()
	return vim.bo.filetype == "sql"
end

-- Retrigger after `.` so `alias.`/`schema.table.`/nested `col.` narrows down.
function Source:get_trigger_characters()
	return { "." }
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
			-- Show the column's type (not the dataset) next to the label.
			labelDetails = { description = (f.type ~= "" and f.type) or nil },
		}
	end
	return items
end

-- Turn a list of full dataset names into completion items. `strip` is the
-- already-typed container (e.g. "tracking."); we insert only the remainder so
-- the item slots in after the dot, matching how blink treats `.` as a boundary.
-- Names that don't share the exact typed prefix are dropped before blink sees
-- them. This avoids fuzzy matches like `prod_conv` -> `prod_virtual_...`.
local function names_to_items(names, nctx)
	local items = {}
	local typed = nctx.typed or ""
	local strip = nctx.strip or ""
	for _, full in ipairs(names or {}) do
		local insert
		if typed == "" or full:sub(1, #typed):lower() == typed:lower() then
			if strip ~= "" then
				insert = full:sub(#strip + 1)
			else
				insert = full
			end
		end
		if insert and insert ~= "" then
			items[#items + 1] = {
				label = insert,
				kind = NameKind,
				insertText = insert,
				insertTextFormat = PlainText,
				filterText = insert,
				-- Show the full dataset name next to the (possibly partial) label.
				detail = full,
				labelDetails = { description = "dataset" },
			}
		end
	end
	return items
end

-- Two kinds of completion, chosen by cursor position:
--   1. Member columns — when the cursor is after a dotted path whose head
--      resolves to a dataset referenced in the buffer (alias `a.`, full name
--      `schema.table.`, or bare `table.`); trailing segments drill into nested
--      `struct<...>` types. Columns show their type, not the dataset.
--   2. Dataset names — when the cursor is in a FROM/JOIN table-name position;
--      we list matching `gridTable` datasets by prefix via `meta dataset list`.
-- Anywhere else we return nothing, so general typing isn't polluted.
function Source:get_completions(_, callback)
	local bufnr = vim.api.nvim_get_current_buf()
	local empty = { is_incomplete_forward = false, is_incomplete_backward = false, items = {} }

	-- 1) Column completion takes priority when the path resolves to a dataset.
	local segs = datasets.path_before_cursor()
	if segs then
		local dataset, field_path = datasets.resolve_member(bufnr, segs)
		if dataset then
			local function deliver(entry, complete)
				local fields = datasets.descend(entry.columns, field_path)
				callback({
					is_incomplete_forward = not complete,
					is_incomplete_backward = not complete,
					items = fields and fields_to_items(fields) or {},
				})
			end

			local entry = schema.get(dataset)
			if entry.state == "ready" then
				deliver(entry, true)
				return
			end

			local cancelled = false
			callback({ is_incomplete_forward = true, is_incomplete_backward = true, items = {} })
			schema.fetch(dataset, function(resolved)
				if not cancelled and resolved.state == "ready" then
					deliver(resolved, true)
				end
			end)
			return function()
				cancelled = true
			end
		end
	end

	-- 2) Dataset-name completion when naming a FROM/JOIN table.
	local nctx = datasets.name_context()
	if not nctx then
		callback(empty)
		return
	end

	-- meta does a prefix match, so list by the container (constant while typing
	-- after the last dot) and let blink filter; for the first segment there's no
	-- container yet, so list by the fragment itself.
	local prefix = (nctx.strip ~= "" and nctx.strip) or nctx.typed
	local function deliver_names(entry, complete)
		callback({
			is_incomplete_forward = not complete,
			is_incomplete_backward = not complete,
			items = names_to_items(entry.names, nctx),
		})
	end

	local cached = schema.list_get(prefix)
	if cached.state == "ready" then
		deliver_names(cached, true)
		return
	end

	local cancelled = false
	callback({ is_incomplete_forward = true, is_incomplete_backward = true, items = {} })
	schema.list(prefix, function(resolved)
		if not cancelled and resolved.state == "ready" then
			deliver_names(resolved, true)
		end
	end)

	-- Returned to blink as the cancellation hook for this completion context.
	return function()
		cancelled = true
	end
end

return Source
