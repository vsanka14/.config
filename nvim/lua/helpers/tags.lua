-- Go-to-definition for the no-LSP flow. Resolves Ember component invocations by
-- path convention first (see helpers/ember.lua) since ctags can't follow them,
-- then falls back to ctags (jump on one match, fuzzy-pick on several) and finally
-- a ripgrep search. The origin is pushed onto the tag stack so <C-t> returns.

local ember = require("helpers.ember")

local M = {}

-- Definition-like kinds, surfaced first in the picker.
local kind_priority = {
	f = 1,
	c = 2,
	m = 3,
	C = 4,
	v = 5,
	t = 6,
	i = 7,
	g = 8,
	s = 9,
}

local function push_tagstack(tagname)
	local winid = vim.api.nvim_get_current_win()
	local pos = vim.api.nvim_win_get_cursor(0)
	local item = {
		tagname = tagname,
		from = { vim.api.nvim_get_current_buf(), pos[1], pos[2] + 1, 0 },
	}
	pcall(vim.fn.settagstack, winid, { items = { item } }, "a")
end

local function jump_to(tag, tagname)
	push_tagstack(tagname)
	vim.cmd("edit " .. vim.fn.fnameescape(tag.filename))
	local lnum = tonumber(tag.line)
	if lnum then
		pcall(vim.api.nvim_win_set_cursor, 0, { lnum, 0 })
	elseif type(tag.cmd) == "string" and tag.cmd:sub(1, 1) == "/" then
		local pat = tag.cmd:gsub("^/", ""):gsub("/$", "")
		vim.fn.search(pat, "cw")
	end
	vim.cmd("normal! zz")
end

local function pick(name, items, on_choose)
	require("mini.pick").start({
		source = {
			name = name,
			items = items,
			choose = function(item)
				if item then
					vim.schedule(function()
						on_choose(item)
					end)
				end
			end,
		},
	})
end

function M.goto_definition()
	local files, token = ember.resolve_component()
	if #files == 1 then
		jump_to({ filename = files[1] }, token)
		return
	elseif #files > 1 then
		local items = {}
		for _, f in ipairs(files) do
			table.insert(items, { text = vim.fn.fnamemodify(f, ":~:."), path = f })
		end
		pick("Component: " .. token, items, function(item)
			jump_to({ filename = item.path }, token)
		end)
		return
	end

	local word = vim.fn.expand("<cword>")
	if word == "" then
		return
	end

	local tags = vim.fn.taglist("^" .. vim.fn.escape(word, "\\/.*$^~[]") .. "$")
	if #tags == 0 then
		require("mini.pick").builtin.grep({ pattern = word })
		return
	end
	if #tags == 1 then
		jump_to(tags[1], word)
		return
	end

	table.sort(tags, function(a, b)
		return (kind_priority[a.kind] or 99) < (kind_priority[b.kind] or 99)
	end)

	local items = {}
	for _, t in ipairs(tags) do
		local fname = vim.fn.fnamemodify(t.filename, ":~:.")
		local kind = (t.kind and t.kind ~= "") and ("[" .. t.kind .. "] ") or ""
		local loc = t.line and (":" .. t.line) or ""
		table.insert(items, { text = kind .. fname .. loc, tag = t })
	end

	pick("Definitions: " .. word, items, function(item)
		jump_to(item.tag, word)
	end)
end

return M
