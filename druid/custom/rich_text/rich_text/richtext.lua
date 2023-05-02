-- Source: https://github.com/britzl/defold-richtext version 5.19.0
-- Author: Britzl
-- Modified by: Insality

local helper = require("druid.helper")
local parser = require("druid.custom.rich_text.rich_text.parse")
local utf8 = require("druid.system.utf8")

local M = {}

M.ADJUST_STEPS = 10
M.ADJUST_SCALE_DELTA = 0.02

---@class rich_text.metrics
---@field width number
---@field height number
---@field offset_x number|nil
---@field offset_y number|nil
---@field node_size vector3|nil @For images only

---@class rich_text.lines_metrics
---@field text_width number
---@field text_height number
---@field lines table<number, rich_text.metrics>

---@class rich_text.word
---@field node Node
---@field relative_scale number
---@field color vector4
---@field position vector3
---@field offset vector3
---@field scale vector3
---@field size vector3
---@field metrics rich_text.metrics
---@field pivot Pivot
---@field text string
---@field shadow vector4
---@field outline vector4
---@field font string
---@field image rich_text.word.image
---@field default_animation string
---@field anchor number
---@field br boolean
---@field nobr boolean

---@class rich_text.settings
---@field parent Node
---@field size number
---@field fonts table<string, string>
---@field color vector4
---@field shadow vector4
---@field outline vector4
---@field position vector3
---@field image_pixel_grid_snap boolean
---@field combine_words boolean
---@field default_animation string
---@field node_prefab Node
---@field text_prefab Node


-- Trim spaces on string start
local function ltrim(text)
	return text:match('^%s*(.*)')
end


-- compare two words and check that they have the same size, color, font and tags
local function compare_words(one, two)
	if one == nil
	or two == nil
	or one.size ~= two.size
	or one.color ~= two.color
	or one.shadow ~= two.shadow
	or one.outline ~= two.outline
	or one.font ~= two.font then
		return false
	end
	local one_tags, two_tags = one.tags, two.tags
	if one_tags == two_tags then
		return true
	end
	if one_tags == nil or two_tags == nil then
		return false
	end
	for k, v in pairs(one_tags) do
		if two_tags[k] ~= v then
			return false
		end
	end
	for k, v in pairs(two_tags) do
		if one_tags[k] ~= v then
			return false
		end
	end
	return true
end


--- Get the length of a text ignoring any tags except image tags
-- which are treated as having a length of 1
-- @param text String with text or a list of words (from richtext.create)
-- @return Length of text
function M.length(text)
	assert(text)
	if type(text) == "string" then
		return parser.length(text)
	else
		local count = 0
		for i = 1, #text do
			local word = text[i]
			local is_text_node = not word.image
			count = count + (is_text_node and utf8.len(word.text) or 1)
		end
		return count
	end
end


---@param word rich_text.word
---@param previous_word rich_text.word|nil
---@param settings rich_text.settings
---@return rich_text.metrics
local function get_text_metrics(word, previous_word, settings)
	local text = word.text
	local font_resource = gui.get_font_resource(word.font)

	---@type rich_text.metrics
	local metrics
	local word_scale_x = word.relative_scale * settings.text_scale.x * settings.adjust_scale
	local word_scale_y = word.relative_scale * settings.text_scale.y * settings.adjust_scale

	if utf8.len(text) == 0 then
		metrics = resource.get_text_metrics(font_resource, "|")
		metrics.width = 0
		metrics.height = metrics.height * word_scale_y
	else
		metrics = resource.get_text_metrics(font_resource, text)
		metrics.width = metrics.width * word_scale_x
		metrics.height = metrics.height * word_scale_y

		if previous_word and not previous_word.image then
			local previous_word_metrics = resource.get_text_metrics(font_resource, previous_word.text)
			local union_metrics = resource.get_text_metrics(font_resource, previous_word.text .. text)

			local without_previous_width = metrics.width
			metrics.width = (union_metrics.width - previous_word_metrics.width) * word_scale_x
			-- Since the several characters can be ajusted to fit the space between the previous word and this word
			-- For example: chars: [.,?!]
			metrics.offset_x = metrics.width - without_previous_width
		end
	end

	metrics.offset_x = metrics.offset_x or 0
	metrics.offset_y = metrics.offset_y or 0

	return metrics
end


---@param word rich_text.word
---@param settings rich_text.settings
---@return rich_text.metrics
local function get_image_metrics(word, settings)
	local node_prefab = settings.node_prefab
	gui.play_flipbook(node_prefab, word.image.anim)
	local node_size = gui.get_size(node_prefab)
	local aspect = node_size.x / node_size.y
	node_size.x = word.image.width or node_size.x
	node_size.y = word.image.height or (node_size.x / aspect)

	return {
		width = node_size.x * word.relative_scale * settings.node_scale.x * settings.adjust_scale,
		height = node_size.y * word.relative_scale * settings.node_scale.y * settings.adjust_scale,
		node_size = node_size,
	}
end


---@param word rich_text.word
---@param settings rich_text.settings
---@param previous_word rich_text.word|nil
---@return rich_text.metrics
local function measure_node(word, settings, previous_word)
	local metrics = word.image and get_image_metrics(word, settings) or get_text_metrics(word, previous_word, settings)
	return metrics
end


--- Create rich text gui nodes from text
-- @param text The text to create rich text nodes from
-- @param settings Optional settings table (refer to documentation for details)
-- @return words
-- @return metrics
function M.create(text, settings)
	assert(text, "You must provide a text")

	-- default settings for a word
	-- will be assigned to each word unless tags override the values
	local font = gui.get_font(settings.text_prefab)
	local word_params = {
		node = nil, -- Autofill on node creation
		relative_scale = 1,
		color = nil,
		position = nil, -- Autofill later
		scale = nil, -- Autofill later
		size = nil, -- Autofill later
		pivot = nil, -- Autofill later
		offset = nil, -- Autofill later
		metrics = {},
		-- text params
		source_text = nil,
		text = nil, -- Autofill later in parse.lua
		text_color = gui.get_color(settings.text_prefab),
		shadow = settings.shadow,
		outline = settings.outline,
		font = font,
		-- Image params
		---@type rich_text.word.image
		image = nil,
		image_color = gui.get_color(settings.node_prefab),
		default_animation = nil,
		-- Tags
		anchor = nil,
		br = nil,
		nobr = nil,
	}

	local parsed_words = parser.parse(text, word_params)
	local lines = M._split_on_lines(parsed_words, settings)
	local lines_metrics = M._position_lines(lines, settings)
	M._update_nodes(lines, settings)

	local words = {}
	for index = 1, #lines do
		for jindex = 1, #lines[index] do
			table.insert(words, lines[index][jindex])
		end
	end

	return words, settings, lines_metrics
end


---@param words rich_text.word
---@param metrics rich_text.metrics
---@param settings rich_text.settings
function M._fill_properties(word, metrics, settings)
	word.metrics = metrics
	word.position = vmath.vector3(0)

	if word.image then
		word.scale = gui.get_scale(settings.node_prefab) * word.relative_scale * settings.adjust_scale
		word.pivot = gui.get_pivot(settings.node_prefab)
		word.size = metrics.node_size
		word.offset = vmath.vector3(0, 0, 0)
		if word.image.width then
			word.size.y = word.image.height or (word.size.y * word.image.width / word.size.x)
			word.size.x = word.image.width
		end
	else
		word.scale = gui.get_scale(settings.text_prefab) * word.relative_scale * settings.adjust_scale
		word.pivot = gui.get_pivot(settings.text_prefab)
		word.size = vmath.vector3(metrics.width, metrics.height, 0)
		word.offset = vmath.vector3(metrics.offset_x, metrics.offset_y, 0)
	end
end


---@param words rich_text.word[]
---@param settings rich_text.settings
---@return rich_text.word[][]
function M._split_on_lines(words, settings)
	local i = 1
	local lines = {}
	local current_line = {}
	local word_count = #words
	local current_line_width = 0
	local current_line_height = 0

	repeat
		local word = words[i]
		if word.image then
			word.default_animation = settings.default_animation
		end

		-- Reset texts to start measure again
		word.text = word.source_text

		-- get the previous word, so we can combine
		local previous_word = current_line[#current_line]
		if settings.combine_words then
			if not compare_words(previous_word, word) then
				previous_word = nil
			end
		end

		local word_metrics = measure_node(word, settings)

		local next_words_width = word_metrics.width
		-- Collect width of nobr words from current to next words with nobr
		if word.nobr then
			for index = i + 1, word_count do
				if words[index].nobr then
					local next_word_measure = measure_node(words[index], settings, words[index-1])
					next_words_width = next_words_width + next_word_measure.width
				else
					break
				end
			end
		end
		local overflow = (current_line_width + next_words_width) > settings.width
		local is_new_line = (overflow or word.br) and settings.is_multiline

		-- We recalculate metrics with previous_word if it follow for word on current line
		if not is_new_line and previous_word then
			word_metrics = measure_node(word, settings, previous_word)
		end

		-- Trim first word of the line
		if is_new_line or not previous_word then
			word.text = ltrim(word.text)
			word_metrics = measure_node(word, settings, nil)
		end
		M._fill_properties(word, word_metrics, settings)

		-- check if the line overflows due to this word
		if not is_new_line then
			-- the word fits on the line, add it and update text metrics
			current_line_width = current_line_width + word.metrics.width
			current_line_height = math.max(current_line_height, word.metrics.height)
			current_line[#current_line + 1] = word
		else
			-- overflow, position the words that fit on the line
			lines[#lines + 1] = current_line

			word.text = ltrim(word.text)
			current_line = { word }
			current_line_height = word.metrics.height
			current_line_width = word.metrics.width
		end

		i = i + 1
	until i > word_count

	if #current_line > 0 then
		lines[#lines + 1] = current_line
	end

	return lines
end


---@param lines rich_text.word[][]
---@param settings rich_text.settings
---@return rich_text.lines_metrics
function M._position_lines(lines, settings)
	local lines_metrics = M._get_lines_metrics(lines, settings)
	-- current x-y is left top point of text spawn

	local parent_size = gui.get_size(settings.parent)
	local pivot = helper.get_pivot_offset(gui.get_pivot(settings.parent))
	local offset_y = (parent_size.y - lines_metrics.text_height) * (pivot.y - 0.5) - (parent_size.y * (pivot.y - 0.5))

	local current_y = offset_y
	for line_index = 1, #lines do
		local line = lines[line_index]
		local line_metrics = lines_metrics.lines[line_index]
		local current_x = (parent_size.x - line_metrics.width) * (pivot.x + 0.5) - (parent_size.x * (pivot.x + 0.5))
		local max_height = 0
		for word_index = 1, #line do
			local word = line[word_index]
			local pivot_offset = helper.get_pivot_offset(word.pivot)
			local word_width = word.metrics.width
			word.position.x = current_x + word_width * (pivot_offset.x + 0.5) + word.offset.x
			word.position.y = current_y + word.metrics.height * (pivot_offset.y - 0.5) + word.offset.y

			-- Align item on text line depends on anchor
			word.position.y = word.position.y - (word.metrics.height - line_metrics.height) * (pivot_offset.y - 0.5)

			current_x = current_x + word_width

			-- TODO: check if we need to calculate images
			if not word.image then
				max_height = math.max(max_height, word.metrics.height)
			end

			if settings.image_pixel_grid_snap and word.image then
				word.position.x = helper.round(word.position.x)
				word.position.y = helper.round(word.position.y)
			end
		end

		current_y = current_y - line_metrics.height
	end

	return lines_metrics
end


---@param lines rich_text.word[][]
---@param settings rich_text.settings
---@return rich_text.lines_metrics
function M._get_lines_metrics(lines, settings)
	local metrics = {}
	local text_width = 0
	local text_height = 0
	for line_index = 1, #lines do
		local line = lines[line_index]
		local width = 0
		local height = 0
		for word_index = 1, #line do
			local word = line[word_index]
			local word_width = word.metrics.width
			width = width + word_width
			-- TODO: Here too
			if not word.image then
				height = math.max(height, word.metrics.height)
			end
		end

		if line_index > 1 then
			height = height * settings.text_leading
		end

		text_width = math.max(text_width, width)
		text_height = text_height + height

		metrics[#metrics + 1] = {
			width = width,
			height = height,
		}
	end

	---@type rich_text.lines_metrics
	local lines_metrics = {
		text_width = text_width,
		text_height = text_height,
		lines = metrics,
	}

	return lines_metrics
end


---@param lines rich_text.word[][]
---@param settings rich_text.settings
function M._update_nodes(lines, settings)
	for line_index = 1, #lines do
		local line = lines[line_index]
		for word_index = 1, #line do
			local word = line[word_index]
			local node
			if word.image then
				node = word.node or gui.clone(settings.node_prefab)
				gui.set_size_mode(node, gui.SIZE_MODE_MANUAL)
				gui.play_flipbook(node, hash(word.image.anim or word.default_animation))
				gui.set_color(node, word.color or word.image_color)
			else
				node = word.node or gui.clone(settings.text_prefab)
				gui.set_outline(node, word.outline)
				gui.set_shadow(node, word.shadow)
				gui.set_text(node, word.text)
				gui.set_color(node, word.color or word.text_color)
			end
			word.node = node
			gui.set_enabled(node, true)
			gui.set_parent(node, settings.parent)
			gui.set_size(node, word.size)
			gui.set_scale(node, word.scale)
			gui.set_position(node, word.position)
		end
	end
end


---@param words rich_text.word[]
---@param settings rich_text.settings
---@param scale number
---@return rich_text.lines_metrics
function M.set_text_scale(words, settings, scale)
	settings.adjust_scale = scale

	local lines = M._split_on_lines(words, settings)
	local line_metrics = M._position_lines(lines, settings)
	M._update_nodes(lines, settings)

	return line_metrics
end


---@param words rich_text.word[]
---@param settings rich_text.settings
---@param lines_metrics rich_text.lines_metrics
function M.adjust_to_area(words, settings, lines_metrics)
	local last_line_metrics = lines_metrics

	if not settings.is_multiline then
		if lines_metrics.text_width > settings.width then
			last_line_metrics = M.set_text_scale(words, settings, settings.width / lines_metrics.text_width)
		end
	else
		-- Multiline adjusting is very tricky stuff...
		-- It's do a lot of calculations, beware!
		if lines_metrics.text_width > settings.width or lines_metrics.text_height > settings.height then
			local scale_koef = math.sqrt(settings.height / lines_metrics.text_height)
			if lines_metrics.text_width * scale_koef > settings.width then
				scale_koef = math.sqrt(settings.width / lines_metrics.text_width)
			end
			local adjust_scale = math.min(scale_koef, 1)

			local lines = M.apply_scale_without_update(words, settings, adjust_scale)
			local is_fit = M.is_fit_info_area(lines, settings)
			local step = is_fit and M.ADJUST_SCALE_DELTA or -M.ADJUST_SCALE_DELTA

			for i = 1, M.ADJUST_STEPS do
				-- Grow down to check if we fit
				if step < 0 and is_fit then
					last_line_metrics = M.set_text_scale(words, settings, adjust_scale)
					break
				end
				-- Grow up to check if we still fit
				if step > 0 and not is_fit then
					last_line_metrics = M.set_text_scale(words, settings, adjust_scale - step)
					break
				end

				adjust_scale = adjust_scale + step
				local lines = M.apply_scale_without_update(words, settings, adjust_scale)
				is_fit = M.is_fit_info_area(lines, settings)

				if i == M.ADJUST_STEPS then
					last_line_metrics = M.set_text_scale(words, settings, adjust_scale)
				end
			end
		end
	end

	return last_line_metrics
end


---@return boolean @If we fit into area size
function M.apply_scale_without_update(words, settings, scale)
	settings.adjust_scale = scale
	return M._split_on_lines(words, settings)
end


---@param lines rich_text.word[][]
---@param settings rich_text.settings
function M.is_fit_info_area(lines, settings)
	local lines_metrics = M._get_lines_metrics(lines, settings)
	local area_size = gui.get_size(settings.parent)
	return lines_metrics.text_width <= area_size.x and lines_metrics.text_height <= area_size.y
end


--- Detected click/touch events on words with an anchor tag
-- These words act as "hyperlinks" and will generate a message when clicked
-- @param words Words to search for anchor tags
-- @param action The action table from on_input
-- @return true if a word was clicked, otherwise false
function M.on_click(words, action)
	for i = 1, #words do
		local word = words[i]
		if word.anchor and gui.pick_node(word.node, action.x, action.y) then
			if word.tags and word.tags.a then
				local message = {
					node_id = gui.get_id(word.node),
					text = word.text,
					x = action.x, y = action.y,
					screen_x = action.screen_x, screen_y = action.screen_y
				}
				msg.post("#", word.tags.a, message)
				return true
			end
		end
	end

	return false
end


--- Get all words with a specific tag
-- @param words The words to search (as received from richtext.create)
-- @param tag The tag to search for. Nil to search for words without a tag
-- @return Words matching the tag
function M.tagged(words, tag)
	local tagged = {}
	for i = 1, #words do
		local word = words[i]
		if not tag and not word.tags then
			tagged[#tagged + 1] = word
		elseif word.tags and word.tags[tag] then
			tagged[#tagged + 1] = word
		end
	end
	return tagged
end


--- Split a word into it's characters
-- @param word The word to split
-- @return The individual characters
function M.characters(word)
	assert(word)

	local parent = gui.get_parent(word.node)
	local font = gui.get_font(word.node)
	local layer = gui.get_layer(word.node)
	local pivot = gui.get_pivot(word.node)

	local word_length = utf8.len(word.text)

	-- exit early if word is a single character or empty
	if word_length <= 1 then
		local char = helper.deepcopy(word)
		char.node, char.metrics = create_node(char, parent, font)
		gui.set_pivot(char.node, pivot)
		gui.set_position(char.node, gui.get_position(word.node))
		gui.set_layer(char.node, layer)
		return { char }
	end

	-- split word into characters
	local chars = {}
	local position = gui.get_position(word.node)
	local position_x = position.x

	for i = 1, word_length do
		local char = helper.deepcopy(word)
		chars[#chars + 1] = char
		char.text = utf8.sub(word.text, i, i)
		char.node, char.metrics = create_node(char, parent, font)
		gui.set_layer(char.node, layer)
		gui.set_pivot(char.node, pivot)

		local sub_metrics = get_text_metrics(word, font, utf8.sub(word.text, 1, i))
		position.x = position_x + sub_metrics.width - char.metrics.width
		char.position = vmath.vector3(position)
		gui.set_position(char.node, char.position)
	end

	return chars
end


---Removes the gui nodes created by rich text
function M.remove(words)
	assert(words)

	for i = 1, #words do
		gui.delete_node(words[i].node)
	end
end


return M
