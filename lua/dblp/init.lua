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
    local rewritten, count = bib_res:gsub("^(%s*@[%w]+%s*%{)%s*([^,]+)", "%1" .. citekey, 1)
    if count == 0 then
        return bib_res
    end
    return rewritten
end

function M.search_and_insert()
    -- Check our lock
    if is_request_ongoing then
        vim.api.nvim_err_writeln("DBLP Error: A search request is already in progress.")
        return
    end

    vim.ui.input({ prompt = 'DBLP Search Keyword: ' }, function(query)
        if not query or query == "" then return end

        is_request_ongoing = true

        local encoded_query = url_encode(query)
        local search_url = string.format("https://dblp.org/search/publ/api?q=%s&format=json", encoded_query)

        -- Execute synchronous curl with a 3-second maximum timeout (-m 3)
        -- This blocks the Neovim event loop entirely, forcing the user to wait.
        local res = vim.fn.system({ 'curl', '-s', '-m', '3', search_url })
        local exit_code = vim.v.shell_error

        if exit_code ~= 0 then
            is_request_ongoing = false
            if exit_code == 28 then -- standard curl exit code for timeout
                vim.api.nvim_err_writeln("DBLP Error: Request timed out after 3 seconds.")
            else
                vim.api.nvim_err_writeln(string.format("DBLP Error: curl failed with code %d.", exit_code))
            end
            return
        end

        local ok, parsed = pcall(vim.fn.json_decode, res)
        if not ok or not parsed.result or not parsed.result.hits or not parsed.result.hits.hit then
            is_request_ongoing = false
            vim.notify("DBLP: No results found or invalid JSON.", vim.log.levels.WARN)
            return
        end

        local hits = parsed.result.hits.hit

        -- The I/O phase is done, unlock before handing control back to the UI
        is_request_ongoing = false

        -- Spawn the selection table natively
        vim.ui.select(hits, {
            prompt = 'Select Publication:',
            format_item = function(hit)
                local title = hit.info.title or "Unknown Title"
                local first_author = get_first_author(hit)
                return string.format("[%s] %s", first_author, title)
            end
        }, function(choice)
            if not choice then return end

            if is_request_ongoing then
                vim.api.nvim_err_writeln("DBLP Error: A download request is already in progress.")
                return
            end

            is_request_ongoing = true
            local bib_url = choice.info.url .. ".bib?param=1"

            -- Synchronously fetch the BibTeX payload, also with a 3-second timeout
            local bib_res = vim.fn.system({ 'curl', '-s', '-m', '3', bib_url })
            local bib_exit_code = vim.v.shell_error

            is_request_ongoing = false

            if bib_exit_code ~= 0 then
                if bib_exit_code == 28 then
                    vim.api.nvim_err_writeln("DBLP Error: BibTeX download timed out after 3 seconds.")
                else
                    vim.api.nvim_err_writeln("DBLP Error: Failed to download BibTeX content.")
                end
                return
            end

            local citekey = get_citekey(choice)
            local rewritten_bib = rewrite_bibtex_key(bib_res, citekey)

            -- Convert binary/raw text stream into Neovim buffer lines and insert
            local lines = vim.split(rewritten_bib, '\r?\n')
            vim.api.nvim_put(lines, 'l', true, true)
            vim.notify("BibTeX successfully inserted.", vim.log.levels.INFO)
        end)

    end)
end

return M
