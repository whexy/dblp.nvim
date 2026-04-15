local M = {}

-- Mutex lock to prevent concurrent executions
local is_request_ongoing = false

local function url_encode(str)
	if str then
		str = string.gsub(str, "\n", "\r\n")
		str = string.gsub(str, "([^%w %-%_%.%~])", function(c)
			return string.format("%%%02X", string.byte(c))
		end)
		str = string.gsub(str, " ", "+")
	end
	return str
end

local function get_first_author(hit)
	if not (hit.info and hit.info.authors and hit.info.authors.author) then
		return "Unknown Author"
	end
	local author_data = hit.info.authors.author
	if author_data.text then
		return author_data.text
	end
	if type(author_data) == "table" and author_data[1] and author_data[1].text then
		return author_data[1].text
	end
	return "Unknown Author"
end

local function get_first_word(text, fallback)
	if type(text) ~= "string" then
		return fallback
	end

	local word = text:match("%w+")
	if not word or word == "" then
		return fallback
	end

	return word:lower()
end

local function get_citekey(hit)
	local first_author = get_first_author(hit)
	local author_part = get_first_word(first_author, "unknown")

	local year = tostring((hit.info and hit.info.year) or ""):match("%d%d%d%d") or "0000"
	local year_num = tonumber(year)
	if not year_num or year_num < 1900 or year_num > 2100 then
		year = "0000"
	end

	local title = (hit.info and hit.info.title) or ""
	local title_part = get_first_word(title, "untitled")

	return string.format("%s%s%s", author_part, year, title_part)
end

local function rewrite_bibtex_key(bib_res, citekey)
	local rewritten, count = bib_res:gsub("^(%s*@[%w]+%s*%{)%s*[^,]+", "%1" .. citekey, 1)
	if count == 0 then
		return bib_res
	end
	return rewritten
end

-- Default request timeout in milliseconds
local REQUEST_TIMEOUT_MS = 10000

--- Makes an async HTTP GET request with timeout via vim.net.request().
--- Requires Neovim >= 0.12.
---@param url string
---@param timeout_ms integer timeout in milliseconds
---@param callback fun(err: string?, body: string?)
local function async_get(url, timeout_ms, callback)
	local done = false
	local timer = nil

	local job = vim.net.request(url, {}, function(err, response)
		if done then
			return
		end
		done = true
		if timer then
			timer:stop()
			timer:close()
		end
		if err then
			callback(err, nil)
		else
			callback(nil, response.body)
		end
	end)

	-- Arm a timeout that cancels the request
	timer = vim.uv.new_timer()
	timer:start(timeout_ms, 0, function()
		if done then
			return
		end
		done = true
		timer:stop()
		timer:close()
		job:close()
		callback(string.format("Request timed out after %d seconds.", timeout_ms / 1000), nil)
	end)
end

function M.search_and_insert()
	-- Check our lock
	if is_request_ongoing then
		vim.notify("DBLP Error: A search request is already in progress.", vim.log.levels.ERROR)
		return
	end

	vim.ui.input({ prompt = "DBLP Search Keyword: " }, function(query)
		if not query or query == "" then
			return
		end

		is_request_ongoing = true

		local encoded_query = url_encode(query)
		local search_url = string.format("https://dblp.org/search/publ/api?q=%s&format=json", encoded_query)

		-- Async search request — does not block the editor
		async_get(search_url, REQUEST_TIMEOUT_MS, function(err, body)
			if err then
				is_request_ongoing = false
				vim.schedule(function()
					vim.notify("DBLP Error: " .. err, vim.log.levels.ERROR)
				end)
				return
			end

			local ok, parsed = pcall(vim.json.decode, body)
			if not ok or not parsed.result or not parsed.result.hits or not parsed.result.hits.hit then
				is_request_ongoing = false
				vim.schedule(function()
					vim.notify("DBLP: No results found or invalid JSON.", vim.log.levels.WARN)
				end)
				return
			end

			local hits = parsed.result.hits.hit

			-- The I/O phase is done, unlock before handing control back to the UI
			is_request_ongoing = false

			-- Spawn the selection UI (must be on the main thread)
			vim.schedule(function()
				vim.ui.select(hits, {
					prompt = "Select Publication:",
					format_item = function(hit)
						local title = hit.info.title or "Unknown Title"
						local first_author = get_first_author(hit)
						return string.format("[%s] %s", first_author, title)
					end,
				}, function(choice)
					if not choice then
						return
					end

					if is_request_ongoing then
						vim.notify("DBLP Error: A download request is already in progress.", vim.log.levels.ERROR)
						return
					end

					is_request_ongoing = true
					local bib_url = choice.info.url .. ".bib?param=1"

					-- Async BibTeX download — does not block the editor
					async_get(bib_url, REQUEST_TIMEOUT_MS, function(bib_err, bib_body)
						is_request_ongoing = false

						if bib_err then
							vim.schedule(function()
								vim.notify("DBLP Error: " .. bib_err, vim.log.levels.ERROR)
							end)
							return
						end

						local citekey = get_citekey(choice)
						local rewritten_bib = rewrite_bibtex_key(bib_body, citekey)

						-- Insert into buffer (must be on the main thread)
						vim.schedule(function()
							local lines = vim.split(rewritten_bib, "\r?\n")
							vim.api.nvim_put(lines, "l", true, true)
							vim.notify("BibTeX successfully inserted.", vim.log.levels.INFO)
						end)
					end)
				end)
			end)
		end)
	end)
end

return M
