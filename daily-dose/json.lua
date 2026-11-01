-- Minimal JSON codec (encode/decode) with no dependencies.
-- Scope: the extension's API payloads and persisted state. Objects are encoded with
-- sorted keys so output is stable; arrays are tables with a positive integer `[1]`
-- (or empty tables). `null` decodes to nil.

local Json = {}

local escapes = {
	['"'] = '\\"',
	['\\'] = '\\\\',
	['\b'] = '\\b',
	['\f'] = '\\f',
	['\n'] = '\\n',
	['\r'] = '\\r',
	['\t'] = '\\t',
}

local function escapeChar(c)
	return escapes[c] or string.format('\\u%04x', string.byte(c))
end

local function encodeString(s)
	return '"' .. s:gsub('[%z\1-\31\\"]', escapeChar) .. '"'
end

local function isArray(t)
	local count = 0
	for k, _ in pairs(t) do
		if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
			return false
		end
		count = count + 1
	end
	if count == 0 then
		return true
	end
	return t[1] ~= nil and t[count] ~= nil
end

local function encodeValue(v, out)
	local tv = type(v)
	if v == nil then
		out[#out + 1] = "null"
	elseif tv == "boolean" then
		out[#out + 1] = v and "true" or "false"
	elseif tv == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			out[#out + 1] = "null"
		elseif math.floor(v) == v and math.abs(v) < 1e15 then
			out[#out + 1] = string.format("%d", v)
		else
			out[#out + 1] = string.format("%.14g", v)
		end
	elseif tv == "string" then
		out[#out + 1] = encodeString(v)
	elseif tv == "table" then
		if isArray(v) then
			out[#out + 1] = "["
			for i = 1, #v do
				if i > 1 then
					out[#out + 1] = ","
				end
				encodeValue(v[i], out)
			end
			out[#out + 1] = "]"
		else
			local keys = {}
			for k in pairs(v) do
				if type(k) ~= "string" then
					error("json.encode: object keys must be strings, got " .. type(k))
				end
				keys[#keys + 1] = k
			end
			table.sort(keys)
			out[#out + 1] = "{"
			for i, k in ipairs(keys) do
				if i > 1 then
					out[#out + 1] = ","
				end
				out[#out + 1] = encodeString(k)
				out[#out + 1] = ":"
				encodeValue(v[k], out)
			end
			out[#out + 1] = "}"
		end
	else
		error("json.encode: unsupported type " .. tv)
	end
end

function Json.encode(value)
	local out = {}
	encodeValue(value, out)
	return table.concat(out)
end

-- Decoder -------------------------------------------------------------------

local Parser = {}
Parser.__index = Parser

local function newParser(text)
	return setmetatable({ text = text, pos = 1, len = #text }, Parser)
end

function Parser:skipWhitespace()
	local _, last = self.text:find("^[ \t\r\n]*", self.pos)
	self.pos = (last or self.pos - 1) + 1
end

function Parser:peek()
	return self.text:sub(self.pos, self.pos)
end

function Parser:error(msg)
	error(string.format("json.decode: %s at byte %d", msg, self.pos), 0)
end

function Parser:parseValue()
	self:skipWhitespace()
	local c = self:peek()
	if c == "{" then
		return self:parseObject()
	elseif c == "[" then
		return self:parseArray()
	elseif c == '"' then
		return self:parseString()
	elseif c == "t" then
		return self:literal("true", true)
	elseif c == "f" then
		return self:literal("false", false)
	elseif c == "n" then
		return self:literal("null", nil)
	elseif c == "-" or c:match("%d") then
		return self:parseNumber()
	end
	self:error("unexpected character '" .. c .. "'")
end

function Parser:literal(word, value)
	if self.text:sub(self.pos, self.pos + #word - 1) ~= word then
		self:error("invalid literal")
	end
	self.pos = self.pos + #word
	return value
end

function Parser:parseString()
	self.pos = self.pos + 1 -- opening quote
	local out = {}
	while true do
		local c = self:peek()
		if c == "" then
			self:error("unterminated string")
		elseif c == '"' then
			self.pos = self.pos + 1
			return table.concat(out)
		elseif c == "\\" then
			local esc = self.text:sub(self.pos + 1, self.pos + 1)
			self.pos = self.pos + 2
			if esc == "u" then
				local hex = self.text:sub(self.pos, self.pos + 3)
				if not hex:match("^%x%x%x%x$") then
					self:error("invalid unicode escape")
				end
				local code = tonumber(hex, 16)
				self.pos = self.pos + 4
				if code < 128 then
					out[#out + 1] = string.char(code)
				elseif code < 2048 then
					out[#out + 1] = string.char(192 + math.floor(code / 64), 128 + code % 64)
				else
					out[#out + 1] = string.char(
						224 + math.floor(code / 4096),
						128 + math.floor(code / 64) % 64,
						128 + code % 64
					)
				end
			else
				local map = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
				if map[esc] == nil then
					self:error("invalid escape '" .. esc .. "'")
				end
				out[#out + 1] = map[esc]
			end
		else
			local plain = self.text:match('^[^"\\]+', self.pos)
			out[#out + 1] = plain
			self.pos = self.pos + #plain
		end
	end
end

function Parser:parseNumber()
	local num = self.text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", self.pos)
	if not num or num == "" then
		self:error("invalid number")
	end
	local value = tonumber(num)
	if value == nil then
		self:error("invalid number")
	end
	self.pos = self.pos + #num
	return value
end

function Parser:parseArray()
	self.pos = self.pos + 1
	local result = {}
	self:skipWhitespace()
	if self:peek() == "]" then
		self.pos = self.pos + 1
		return result
	end
	while true do
		result[#result + 1] = self:parseValue()
		self:skipWhitespace()
		local c = self:peek()
		if c == "," then
			self.pos = self.pos + 1
		elseif c == "]" then
			self.pos = self.pos + 1
			return result
		else
			self:error("expected ',' or ']'")
		end
	end
end

function Parser:parseObject()
	self.pos = self.pos + 1
	local result = {}
	self:skipWhitespace()
	if self:peek() == "}" then
		self.pos = self.pos + 1
		return result
	end
	while true do
		self:skipWhitespace()
		if self:peek() ~= '"' then
			self:error("expected object key")
		end
		local key = self:parseString()
		self:skipWhitespace()
		if self:peek() ~= ":" then
			self:error("expected ':'")
		end
		self.pos = self.pos + 1
		result[key] = self:parseValue()
		self:skipWhitespace()
		local c = self:peek()
		if c == "," then
			self.pos = self.pos + 1
		elseif c == "}" then
			self.pos = self.pos + 1
			return result
		else
			self:error("expected ',' or '}'")
		end
	end
end

function Json.decode(text)
	if type(text) ~= "string" or text == "" then
		return nil, "empty input"
	end
	local parser = newParser(text)
	local ok, value = pcall(function()
		return parser:parseValue()
	end)
	if not ok then
		return nil, tostring(value)
	end
	return value
end

return Json
