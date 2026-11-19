-- Berburu Museng headless harness -- STRICT mocks edition.
--
-- Run:  lune run harness/harness.luau        (from the repo root)
--
-- Why strict: the previous harness's mocks tolerated member accesses
-- that real Roblox rejects, so two live-place killers passed every
-- headless check and only showed up in Studio:
--   * BrainrotFactory wrote model.PivotOffset. PivotOffset is not a
--     scriptable member of Model; the write throws in Roblox and
--     killed CatchService's start AND every egg hatch.
--   * HUD's shop-toggle call passed its arguments shifted by one,
--     landing the string "Hide shop" in makeButton's color slot;
--     button.BackgroundColor3 = "Hide shop" threw, the HUD script
--     died mid-construction, and the state wiring below the crash
--     never ran (server had cash 150, HUD showed $0 forever).
-- These mocks therefore behave like Roblox where it matters:
--   * Accessing or assigning a member a class does not have ERRORS
--     ("X is not a valid member of Class \"Name\"") -- in particular
--     a Model has NO PivotOffset, CFrame or Position.
--   * Assigning a value of the wrong type to a typed property
--     ERRORS ("Unable to assign property P. Color3 expected, got
--     string").
-- A static lint (below) adds defence in depth for the same classes.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

-- ------------------------------------------------------------------
-- Test framework
-- ------------------------------------------------------------------

local results = {}
local function check(name, ok, detail)
	table.insert(results, { Name = name, Ok = ok and true or false, Detail = detail })
	if ok then
		print("PASS  " .. name)
	else
		print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or ""))
	end
end

local SRC_FILES = {
	"src/shared/Config.luau",
	"src/shared/BrainrotData.luau",
	"src/server/BrainrotFactory.luau",
	"src/server/GameState.luau",
	"src/server/EconomyService.luau",
	"src/server/CatchService.luau",
	"src/server/StealService.luau",
	"src/server/WorldBuilder.luau",
	"src/server/Main.server.luau",
	"src/client/HUD.client.luau",
	"src/client/Effects.client.luau",
}

local function readSrc(path)
	return fs.readFile(path)
end

-- Naive comment stripper for the lint: removes -- to end of line.
-- Safe for this codebase: no string literal in src/ contains "--".
local function stripComments(source)
	local out = {}
	for line in (source .. "\n"):gmatch("(.-)\n") do
		local cut = line:find("--", 1, true)
		if cut then
			line = line:sub(1, cut - 1)
		end
		table.insert(out, line)
	end
	return table.concat(out, "\n")
end

-- ------------------------------------------------------------------
-- Static lint
-- ------------------------------------------------------------------

local function lintPivotOffset()
	-- Every .PivotOffset in src/ must be on a variable in this
	-- allowlist of proven BaseParts. (Post-fix there are no hits at
	-- all; the allowlist exists so a future legitimate BasePart use
	-- is a deliberate, reviewed exception.)
	local ALLOW = { root = true, part = true }
	local bad = {}
	for _, path in ipairs(SRC_FILES) do
		local src = stripComments(readSrc(path))
		for chain in src:gmatch("([%w_%.]*)%.PivotOffset") do
			local var = chain:match("([%w_]+)$") or ""
			if not ALLOW[var] then
				table.insert(bad, path .. ": ." .. chain .. ".PivotOffset")
			end
		end
	end
	check("LINT PivotOffset only on allowlisted BaseParts", #bad == 0, table.concat(bad, "; "))
end

local function lintStringColors()
	local bad = {}
	for _, path in ipairs(SRC_FILES) do
		local src = stripComments(readSrc(path))
		for lineno, line in ipairs(string.split(src, "\n")) do
			if line:find("BackgroundColor3%s*=%s*\"") or line:find("TextColor3%s*=%s*\"") then
				table.insert(bad, path .. ":" .. lineno)
			end
		end
	end
	check("LINT no string-literal BackgroundColor3/TextColor3 assignments", #bad == 0, table.concat(bad, "; "))
end

local function lintModelPivotProps()
	local bad = {}
	for _, path in ipairs(SRC_FILES) do
		local src = stripComments(readSrc(path))
		for chain in src:gmatch("([%w_%.]*[Mm]odel)%.CFrame") do
			table.insert(bad, path .. ": " .. chain .. ".CFrame")
		end
		for chain in src:gmatch("([%w_%.]*[Mm]odel)%.Position") do
			table.insert(bad, path .. ": " .. chain .. ".Position")
		end
	end
	check("LINT no .CFrame/.Position on Model receivers", #bad == 0, table.concat(bad, "; "))
end

local function compileAll()
	local compile = luau.compile or function(source)
		return luau.load(source, {})
	end
	local bad = {}
	for _, path in ipairs(SRC_FILES) do
		local ok, err = pcall(compile, readSrc(path))
		if not ok then
			table.insert(bad, path .. ": " .. tostring(err))
		end
	end
	check("COMPILE all src files parse as Luau", #bad == 0, table.concat(bad, "; "))
end

-- ------------------------------------------------------------------
-- Datatypes (mock Roblox types, tagged tables)
-- ------------------------------------------------------------------

local Vector3 = {}
Vector3.__index = function(self, key)
	if key == "X" then
		return self._x
	elseif key == "Y" then
		return self._y
	elseif key == "Z" then
		return self._z
	elseif key == "Magnitude" then
		return math.sqrt(self._x ^ 2 + self._y ^ 2 + self._z ^ 2)
	elseif key == "Unit" then
		local m = math.sqrt(self._x ^ 2 + self._y ^ 2 + self._z ^ 2)
		if m == 0 then
			return Vector3.new(0, 0, 0)
		end
		return Vector3.new(self._x / m, self._y / m, self._z / m)
	end
	return nil
end
function Vector3.new(x, y, z)
	return setmetatable({ _tag = "Vector3", _x = x or 0, _y = y or 0, _z = z or 0 }, Vector3)
end
Vector3.__add = function(a, b)
	return Vector3.new(a._x + b._x, a._y + b._y, a._z + b._z)
end
Vector3.__sub = function(a, b)
	return Vector3.new(a._x - b._x, a._y - b._y, a._z - b._z)
end
Vector3.__mul = function(a, b)
	if type(a) == "number" then
		return Vector3.new(a * b._x, a * b._y, a * b._z)
	end
	return Vector3.new(a._x * b, a._y * b, a._z * b)
end
Vector3.__div = function(a, b)
	return Vector3.new(a._x / b, a._y / b, a._z / b)
end
Vector3.__unm = function(a)
	return Vector3.new(-a._x, -a._y, -a._z)
end
Vector3.__eq = function(a, b)
	return a._x == b._x and a._y == b._y and a._z == b._z
end
Vector3.__tostring = function(a)
	return string.format("%f, %f, %f", a._x, a._y, a._z)
end

local Vector2 = {}
Vector2.__index = function(self, key)
	if key == "X" then
		return self._x
	elseif key == "Y" then
		return self._y
	elseif key == "Magnitude" then
		return math.sqrt(self._x ^ 2 + self._y ^ 2)
	end
	return nil
end
function Vector2.new(x, y)
	return setmetatable({ _tag = "Vector2", _x = x or 0, _y = y or 0 }, Vector2)
end
Vector2.__add = function(a, b)
	return Vector2.new(a._x + b._x, a._y + b._y)
end
Vector2.__sub = function(a, b)
	return Vector2.new(a._x - b._x, a._y - b._y)
end
Vector2.__mul = function(a, b)
	if type(a) == "number" then
		return Vector2.new(a * b._x, a * b._y)
	end
	return Vector2.new(a._x * b, a._y * b)
end
Vector2.__tostring = function(a)
	return string.format("%f, %f", a._x, a._y)
end

-- CFrame: position + row-major rotation matrix. Columns of the
-- matrix are the axis vectors (XVector = (r00, r10, r20), etc.).
local CFrame = {}
local function cframeRaw(px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22)
	return setmetatable({
		_tag = "CFrame",
		_px = px, _py = py, _pz = pz,
		_r00 = r00, _r01 = r01, _r02 = r02,
		_r10 = r10, _r11 = r11, _r12 = r12,
		_r20 = r20, _r21 = r21, _r22 = r22,
	}, CFrame)
end
function CFrame.new(...)
	local args = { ... }
	if #args == 0 then
		return cframeRaw(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	elseif #args == 1 and type(args[1]) == "table" then
		local v = args[1]
		return cframeRaw(v._x, v._y, v._z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	elseif #args == 3 then
		return cframeRaw(args[1], args[2], args[3], 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	error("harness CFrame.new: unsupported argument count " .. #args)
end
function CFrame.Angles(rx, ry, rz)
	local cx, sx = math.cos(rx), math.sin(rx)
	local cy, sy = math.cos(ry), math.sin(ry)
	local cz, sz = math.cos(rz), math.sin(rz)
	-- R = RotY * RotX * RotZ
	local r00 = cy * cz + sy * sx * sz
	local r01 = -cy * sz + sy * sx * cz
	local r02 = sy * cx
	local r10 = cx * sz
	local r11 = cx * cz
	local r12 = -sx
	local r20 = -sy * cz + cy * sx * sz
	local r21 = sy * sz + cy * sx * cz
	local r22 = cy * cx
	return cframeRaw(0, 0, 0, r00, r01, r02, r10, r11, r12, r20, r21, r22)
end
function CFrame.lookAt(eye, target)
	local forward = (target - eye).Unit
	local zaxis = -forward
	local up = Vector3.new(0, 1, 0)
	local xaxis = Vector3.new(
		up._y * zaxis._z - up._z * zaxis._y,
		up._z * zaxis._x - up._x * zaxis._z,
		up._x * zaxis._y - up._y * zaxis._x
	)
	if xaxis.Magnitude < 1e-6 then
		xaxis = Vector3.new(1, 0, 0)
	else
		xaxis = xaxis.Unit
	end
	local yaxis = Vector3.new(
		zaxis._y * xaxis._z - zaxis._z * xaxis._y,
		zaxis._z * xaxis._x - zaxis._x * xaxis._z,
		zaxis._x * xaxis._y - zaxis._y * xaxis._x
	)
	return cframeRaw(eye._x, eye._y, eye._z,
		xaxis._x, yaxis._x, zaxis._x,
		xaxis._y, yaxis._y, zaxis._y,
		xaxis._z, yaxis._z, zaxis._z)
end
CFrame.__index = function(self, key)
	if key == "Position" then
		return Vector3.new(self._px, self._py, self._pz)
	elseif key == "X" then
		return self._px
	elseif key == "Y" then
		return self._py
	elseif key == "Z" then
		return self._pz
	elseif key == "LookVector" then
		return Vector3.new(-self._r02, -self._r12, -self._r22)
	elseif key == "XVector" then
		return Vector3.new(self._r00, self._r10, self._r20)
	elseif key == "YVector" then
		return Vector3.new(self._r01, self._r11, self._r21)
	elseif key == "ZVector" then
		return Vector3.new(self._r02, self._r12, self._r22)
	elseif key == "Inverse" then
		return function(cf)
			local r00, r01, r02 = cf._r00, cf._r10, cf._r20
			local r10, r11, r12 = cf._r01, cf._r11, cf._r21
			local r20, r21, r22 = cf._r02, cf._r12, cf._r22
			local px = -(r00 * cf._px + r01 * cf._py + r02 * cf._pz)
			local py = -(r10 * cf._px + r11 * cf._py + r12 * cf._pz)
			local pz = -(r20 * cf._px + r21 * cf._py + r22 * cf._pz)
			return cframeRaw(px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22)
		end
	end
	return nil
end
CFrame.__mul = function(a, b)
	if type(b) == "table" and b._tag == "Vector3" then
		return Vector3.new(
			a._px + a._r00 * b._x + a._r01 * b._y + a._r02 * b._z,
			a._py + a._r10 * b._x + a._r11 * b._y + a._r12 * b._z,
			a._pz + a._r20 * b._x + a._r21 * b._y + a._r22 * b._z
		)
	end
	local r00 = a._r00 * b._r00 + a._r01 * b._r10 + a._r02 * b._r20
	local r01 = a._r00 * b._r01 + a._r01 * b._r11 + a._r02 * b._r21
	local r02 = a._r00 * b._r02 + a._r01 * b._r12 + a._r02 * b._r22
	local r10 = a._r10 * b._r00 + a._r11 * b._r10 + a._r12 * b._r20
	local r11 = a._r10 * b._r01 + a._r11 * b._r11 + a._r12 * b._r21
	local r12 = a._r10 * b._r02 + a._r11 * b._r12 + a._r12 * b._r22
	local r20 = a._r20 * b._r00 + a._r21 * b._r10 + a._r22 * b._r20
	local r21 = a._r20 * b._r01 + a._r21 * b._r11 + a._r22 * b._r21
	local r22 = a._r20 * b._r02 + a._r21 * b._r12 + a._r22 * b._r22
	local px = a._px + a._r00 * b._px + a._r01 * b._py + a._r02 * b._pz
	local py = a._py + a._r10 * b._px + a._r11 * b._py + a._r12 * b._pz
	local pz = a._pz + a._r20 * b._px + a._r21 * b._py + a._r22 * b._pz
	return cframeRaw(px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22)
end
CFrame.__add = function(a, b)
	return cframeRaw(a._px + b._x, a._py + b._y, a._pz + b._z,
		a._r00, a._r01, a._r02, a._r10, a._r11, a._r12, a._r20, a._r21, a._r22)
end
CFrame.__sub = function(a, b)
	return cframeRaw(a._px - b._x, a._py - b._y, a._pz - b._z,
		a._r00, a._r01, a._r02, a._r10, a._r11, a._r12, a._r20, a._r21, a._r22)
end
CFrame.__tostring = function(a)
	return string.format("%f, %f, %f", a._px, a._py, a._pz)
end

local Color3 = {}
Color3.__index = function(self, key)
	if key == "R" then
		return self._r
	elseif key == "G" then
		return self._g
	elseif key == "B" then
		return self._b
	end
	return nil
end
local function colorRaw(r, g, b)
	return setmetatable({ _tag = "Color3", _r = r, _g = g, _b = b }, Color3)
end
function Color3.fromRGB(r, g, b)
	return colorRaw((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
function Color3.fromHSV(h, s, v)
	local c = v * s
	local x = c * (1 - math.abs((h * 6) % 2 - 1))
	local m = v - c
	local r, g, b
	local sector = math.floor(h * 6) % 6
	if sector == 0 then
		r, g, b = c, x, 0
	elseif sector == 1 then
		r, g, b = x, c, 0
	elseif sector == 2 then
		r, g, b = 0, c, x
	elseif sector == 3 then
		r, g, b = 0, x, c
	elseif sector == 4 then
		r, g, b = x, 0, c
	else
		r, g, b = c, 0, x
	end
	return colorRaw(r + m, g + m, b + m)
end
Color3.__eq = function(a, b)
	return a._r == b._r and a._g == b._g and a._b == b._b
end
Color3.__tostring = function(a)
	return string.format("%f, %f, %f", a._r, a._g, a._b)
end

local UDim = {}
function UDim.new(scale, offset)
	return { _tag = "UDim", Scale = scale or 0, Offset = offset or 0 }
end
local UDim2 = {}
function UDim2.new(xs, xo, ys, yo)
	return { _tag = "UDim2", X = UDim.new(xs, xo), Y = UDim.new(ys, yo) }
end
function UDim2.fromOffset(x, y)
	return { _tag = "UDim2", X = UDim.new(0, x or 0), Y = UDim.new(0, y or 0) }
end
function UDim2.fromScale(x, y)
	return { _tag = "UDim2", X = UDim.new(x or 0, 0), Y = UDim.new(y or 0, 0) }
end

-- Enum: auto-vivifying, identity-comparable items.
local Enum = {}
local enumTypeCache = {}
local function enumType(typeName)
	if enumTypeCache[typeName] then
		return enumTypeCache[typeName]
	end
	local items = {}
	local t = setmetatable({ _tag = "EnumType", _typeName = typeName }, {
		__index = function(_, itemName)
			if not items[itemName] then
				items[itemName] = setmetatable(
					{ _tag = "EnumItem", EnumType = typeName, Name = itemName },
					{ __tostring = function(self)
						return "Enum." .. typeName .. "." .. itemName
					end }
				)
			end
			return items[itemName]
		end,
	})
	enumTypeCache[typeName] = t
	return t
end
setmetatable(Enum, {
	__index = function(_, typeName)
		return enumType(typeName)
	end,
})

-- ------------------------------------------------------------------
-- Signal
-- ------------------------------------------------------------------

local runtimeErrors = {}

local Signal = {}
Signal.__index = Signal
function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end
function Signal:Connect(fn)
	local conn = { Connected = true, _fn = fn }
	function conn.Disconnect()
		conn.Connected = false
	end
	table.insert(self._handlers, conn)
	return conn
end
function Signal:Fire(...)
	local args = { ... }
	for _, conn in ipairs(self._handlers) do
		if conn.Connected then
			local ok, err = pcall(conn._fn, table.unpack(args))
			if not ok then
				table.insert(runtimeErrors, "event handler: " .. tostring(err))
			end
		end
	end
end
function Signal:Wait()
	if coroutine.isyieldable() then
		return coroutine.yield({ _signal = self })
	end
	return 0
end

-- ------------------------------------------------------------------
-- Virtual-time scheduler (drives the game's task library)
-- ------------------------------------------------------------------

local Scheduler = { now = 0, entries = {}, errors = {} }

function Scheduler.spawn(fn, ...)
	table.insert(Scheduler.entries, {
		co = coroutine.create(fn),
		wake = Scheduler.now,
		args = { ... },
	})
end

function Scheduler.delay(t, fn, ...)
	table.insert(Scheduler.entries, {
		co = coroutine.create(fn),
		wake = Scheduler.now + (t or 0),
		args = { ... },
	})
end

function Scheduler.advance(seconds)
	local target = Scheduler.now + seconds
	local guard = 0
	while true do
		guard += 1
		if guard > 500000 then
			error("harness scheduler guard tripped")
		end
		local best, bestIdx = nil, nil
		for i, e in ipairs(Scheduler.entries) do
			if e.wake <= target and (not best or e.wake < best.wake) then
				best, bestIdx = e, i
			end
		end
		if not best then
			break
		end
		table.remove(Scheduler.entries, bestIdx)
		Scheduler.now = math.max(Scheduler.now, best.wake)
		local args = best.args or { best.resumeValue }
		best.args = nil
		local ok, y1 = coroutine.resume(best.co, table.unpack(args))
		if not ok then
			table.insert(Scheduler.errors, tostring(y1))
		elseif coroutine.status(best.co) ~= "dead" then
			if type(y1) == "table" and y1._wait then
				local w = math.max(y1._wait, 1 / 60)
				best.wake = Scheduler.now + w
				best.resumeValue = w
			elseif type(y1) == "table" and y1._signal then
				best.wake = Scheduler.now + 0.05
				best.resumeValue = 0.05
			else
				best.wake = Scheduler.now + 1 / 60
				best.resumeValue = 0
			end
			table.insert(Scheduler.entries, best)
		end
	end
	Scheduler.now = target
end

local taskMock = {
	spawn = function(fn, ...)
		Scheduler.spawn(fn, ...)
	end,
	defer = function(fn, ...)
		Scheduler.spawn(fn, ...)
	end,
	delay = function(t, fn, ...)
		Scheduler.delay(t, fn, ...)
	end,
	wait = function(t)
		return coroutine.yield({ _wait = t or 0 })
	end,
}

-- ------------------------------------------------------------------
-- Strict Instance system
-- ------------------------------------------------------------------

local INTERNALS = setmetatable({}, { __mode = "k" })

local function isInstance(v)
	return type(v) == "table" and INTERNALS[v] ~= nil
end

local function valueTypeName(v)
	if isInstance(v) then
		return "Instance"
	end
	if type(v) == "table" and v._tag then
		if v._tag == "EnumItem" then
			return "Enum"
		end
		return v._tag
	end
	return type(v)
end

local CLASS_DEFS = {}
local function defClass(name, parent, props, signals, methods)
	CLASS_DEFS[name] = { parent = parent, props = props or {}, signals = signals or {}, methods = methods or {} }
end

local resolvedCache = {}
local function resolveClass(name)
	if resolvedCache[name] then
		return resolvedCache[name]
	end
	local def = CLASS_DEFS[name] or CLASS_DEFS.Instance
	local props, signals, methods = {}, {}, {}
	if def.parent then
		local p = resolveClass(def.parent)
		for k, v in pairs(p.props) do
			props[k] = v
		end
		for k, v in pairs(p.signals) do
			signals[k] = v
		end
		for k, v in pairs(p.methods) do
			methods[k] = v
		end
	end
	for k, v in pairs(def.props) do
		props[k] = v
	end
	for _, s in ipairs(def.signals) do
		signals[s] = true
	end
	for k, v in pairs(def.methods) do
		methods[k] = v
	end
	local rc = { props = props, signals = signals, methods = methods }
	resolvedCache[name] = rc
	return rc
end

local function classChainHas(name, ancestor)
	local cur = name
	while cur do
		if cur == ancestor then
			return true
		end
		local def = CLASS_DEFS[cur]
		cur = def and def.parent or nil
	end
	return false
end

local function getProp(obj, key)
	local int = INTERNALS[obj]
	local v = int.props[key]
	if v == nil then
		local spec = resolveClass(int.class).props[key]
		if spec and spec.d ~= nil then
			if type(spec.d) == "function" then
				return spec.d()
			end
			return spec.d
		end
	end
	return v
end

local function getSignal(obj, key)
	local int = INTERNALS[obj]
	if not int.signals[key] then
		int.signals[key] = Signal.new()
	end
	return int.signals[key]
end

local function descendantsOf(obj, out)
	out = out or {}
	for _, child in ipairs(INTERNALS[obj].children) do
		table.insert(out, child)
		descendantsOf(child, out)
	end
	return out
end

local function setParent(obj, newParent)
	local int = INTERNALS[obj]
	local old = int.props.Parent
	if old == newParent then
		return
	end
	if old and INTERNALS[old] then
		local siblings = INTERNALS[old].children
		for i, c in ipairs(siblings) do
			if c == obj then
				table.remove(siblings, i)
				break
			end
		end
	end
	int.props.Parent = newParent
	if newParent and INTERNALS[newParent] then
		table.insert(INTERNALS[newParent].children, obj)
	end
end

local function checkPropType(propName, spec, value)
	local t = spec.t
	if t == "any" then
		return
	end
	if value == nil then
		if spec.nullable then
			return
		end
		error(string.format("Unable to assign property %s. %s expected, got nil", propName, t), 3)
	end
	local got = valueTypeName(value)
	local ok
	if t == "Enum" then
		ok = got == "Enum"
	elseif t == "Instance" then
		ok = got == "Instance"
	else
		ok = got == t
	end
	if not ok then
		error(string.format("Unable to assign property %s. %s expected, got %s", propName, t, got), 3)
	end
end

-- Base Instance methods (self = the instance).
local baseMethods = {}
function baseMethods.FindFirstChild(self, name, recursive)
	for _, child in ipairs(INTERNALS[self].children) do
		if getProp(child, "Name") == name then
			return child
		end
		if recursive then
			local found = baseMethods.FindFirstChild(child, name, true)
			if found then
				return found
			end
		end
	end
	return nil
end
function baseMethods.FindFirstChildOfClass(self, className)
	for _, child in ipairs(INTERNALS[self].children) do
		if classChainHas(INTERNALS[child].class, className) then
			return child
		end
	end
	return nil
end
function baseMethods.WaitForChild(self, name)
	local child = baseMethods.FindFirstChild(self, name)
	if not child then
		error(string.format("Harness: WaitForChild(\"%s\") on %s \"%s\" found nothing",
			name, INTERNALS[self].class, tostring(getProp(self, "Name"))), 2)
	end
	return child
end
function baseMethods.GetChildren(self)
	local out = {}
	for _, c in ipairs(INTERNALS[self].children) do
		table.insert(out, c)
	end
	return out
end
function baseMethods.GetDescendants(self)
	return descendantsOf(self)
end
function baseMethods.Destroy(self)
	local int = INTERNALS[self]
	setParent(self, nil)
	int.destroyed = true
	local kids = {}
	for _, c in ipairs(int.children) do
		table.insert(kids, c)
	end
	for _, c in ipairs(kids) do
		baseMethods.Destroy(c)
	end
end
function baseMethods.IsA(self, className)
	return classChainHas(INTERNALS[self].class, className)
end
function baseMethods.GetAttribute(self, name)
	return INTERNALS[self].attributes[name]
end
function baseMethods.SetAttribute(self, name, value)
	INTERNALS[self].attributes[name] = value
end
function baseMethods.Clone(self)
	local int = INTERNALS[self]
	local copy = setmetatable({}, getmetatable(self))
	INTERNALS[copy] = {
		class = int.class,
		props = {},
		children = {},
		attributes = {},
		signals = {},
		destroyed = false,
		source = int.source,
	}
	for k, v in pairs(int.props) do
		if k ~= "Parent" then
			INTERNALS[copy].props[k] = v
		end
	end
	for k, v in pairs(int.attributes) do
		INTERNALS[copy].attributes[k] = v
	end
	for _, child in ipairs(int.children) do
		local childCopy = baseMethods.Clone(child)
		setParent(childCopy, copy)
	end
	return copy
end

local INSTANCE_MT = {
	__index = function(obj, key)
		local int = INTERNALS[obj]
		if key == "ClassName" then
			return int.class
		end
		local rc = resolveClass(int.class)
		local m = rc.methods[key]
		if m then
			return m
		end
		if rc.signals[key] then
			return getSignal(obj, key)
		end
		if key == "Position" and classChainHas(int.class, "BasePart") then
			return getProp(obj, "CFrame").Position
		end
		local spec = rc.props[key]
		if spec then
			return getProp(obj, key)
		end
		error(string.format("%s is not a valid member of %s \"%s\"",
			tostring(key), int.class, tostring(getProp(obj, "Name"))), 2)
	end,
	__newindex = function(obj, key, value)
		local int = INTERNALS[obj]
		if key == "Parent" then
			if value ~= nil then
				checkPropType("Parent", { t = "Instance", nullable = true }, value)
			end
			setParent(obj, value)
			return
		end
		if key == "Position" and classChainHas(int.class, "BasePart") then
			local cf = getProp(obj, "CFrame")
			int.props.CFrame = CFrame.new(value) * (cf - cf.Position)
			return
		end
		local rc = resolveClass(int.class)
		local spec = rc.props[key]
		if spec then
			checkPropType(key, spec, value)
			int.props[key] = value
			return
		end
		error(string.format("%s is not a valid member of %s \"%s\"",
			tostring(key), int.class, tostring(getProp(obj, "Name"))), 2)
	end,
	__tostring = function(obj)
		return string.format("%s \"%s\"", INTERNALS[obj].class, tostring(getProp(obj, "Name")))
	end,
}

local function newInstance(className)
	if not CLASS_DEFS[className] then
		defClass(className, "Instance", {}, {}, {})
	end
	local obj = setmetatable({}, INSTANCE_MT)
	INTERNALS[obj] = {
		class = className,
		props = {},
		children = {},
		attributes = {},
		signals = {},
		destroyed = false,
		source = nil,
	}
	return obj
end

local InstanceMock = { new = newInstance }

-- Class definitions. Property sets cover exactly the surface src/
-- uses; anything else is an invalid member, like Roblox.
local function P(t, d, nullable)
	return { t = t, d = d, nullable = nullable }
end

defClass("Instance", nil, {
	Name = P("string", ""),
	Parent = P("Instance", nil, true),
	Archivable = P("boolean", true),
}, {}, baseMethods)

defClass("Folder", "Instance", {}, {}, {})
defClass("Workspace", "Instance", {}, {}, {})
defClass("ReplicatedStorage", "Instance", {}, {}, {})
defClass("ServerScriptService", "Instance", {}, {}, {})
defClass("StarterPlayerScripts", "Instance", {}, {}, {})
defClass("ModuleScript", "Instance", {}, {}, {})
defClass("Script", "Instance", {}, {}, {})
defClass("LocalScript", "Instance", {}, {}, {})
defClass("ForceField", "Instance", { Visible = P("boolean", true) }, {}, {})

defClass("Model", "Instance", {
	PrimaryPart = P("Instance", nil, true),
}, {}, {
	GetPivot = function(self)
		local pp = getProp(self, "PrimaryPart")
		if pp then
			return getProp(pp, "CFrame")
		end
		return CFrame.new()
	end,
	PivotTo = function(self, cf)
		local pivot = self:GetPivot()
		local delta = cf * pivot:Inverse()
		for _, desc in ipairs(descendantsOf(self)) do
			if classChainHas(INTERNALS[desc].class, "BasePart") then
				INTERNALS[desc].props.CFrame = delta * getProp(desc, "CFrame")
			end
		end
	end,
	ScaleTo = function(self, scale)
		local pivot = self:GetPivot()
		for _, desc in ipairs(descendantsOf(self)) do
			if classChainHas(INTERNALS[desc].class, "BasePart") then
				local cf = getProp(desc, "CFrame")
				local localCf = pivot:Inverse() * cf
				local scaledLocal = CFrame.new(localCf.Position * scale) * (localCf - localCf.Position)
				INTERNALS[desc].props.CFrame = pivot * scaledLocal
				INTERNALS[desc].props.Size = getProp(desc, "Size") * scale
			end
		end
	end,
})

defClass("BasePart", "Instance", {
	CFrame = P("CFrame", function()
		return CFrame.new()
	end),
	Size = P("Vector3", function()
		return Vector3.new(1, 1, 1)
	end),
	Anchored = P("boolean", false),
	CanCollide = P("boolean", true),
	CanQuery = P("boolean", true),
	CanTouch = P("boolean", true),
	Transparency = P("number", 0),
	Color = P("Color3", function()
		return Color3.fromRGB(163, 162, 165)
	end),
	Material = P("Enum"),
	Shape = P("Enum"),
	TopSurface = P("Enum"),
	BottomSurface = P("Enum"),
	AssemblyLinearVelocity = P("Vector3", function()
		return Vector3.new()
	end),
	Neutral = P("boolean", false),
}, { "Touched" }, {})
defClass("Part", "BasePart", {}, {}, {})
defClass("WedgePart", "BasePart", {}, {}, {})
defClass("SpawnLocation", "BasePart", { Duration = P("number", 0) }, {}, {})

defClass("GuiObject", "Instance", {
	Size = P("UDim2", function()
		return UDim2.new(0, 0, 0, 0)
	end),
	Position = P("UDim2", function()
		return UDim2.new(0, 0, 0, 0)
	end),
	AnchorPoint = P("Vector2", function()
		return Vector2.new(0, 0)
	end),
	BackgroundColor3 = P("Color3", function()
		return Color3.fromRGB(255, 255, 255)
	end),
	BackgroundTransparency = P("number", 0),
	BorderSizePixel = P("number", 1),
	Visible = P("boolean", true),
	LayoutOrder = P("number", 0),
	ZIndex = P("number", 1),
	ClipsDescendants = P("boolean", false),
}, {}, {})
defClass("Frame", "GuiObject", {}, {}, {})
defClass("TextLabel", "GuiObject", {
	Text = P("string", ""),
	TextColor3 = P("Color3", function()
		return Color3.fromRGB(0, 0, 0)
	end),
	TextSize = P("number", 14),
	Font = P("Enum"),
	TextStrokeTransparency = P("number", 0),
	TextTransparency = P("number", 0),
	TextXAlignment = P("Enum"),
	TextYAlignment = P("Enum"),
	TextScaled = P("boolean", false),
	RichText = P("boolean", false),
}, {}, {})
defClass("TextButton", "TextLabel", {
	AutoButtonColor = P("boolean", true),
}, { "MouseButton1Click" }, {})
defClass("ScreenGui", "Instance", {
	ResetOnSpawn = P("boolean", true),
	Enabled = P("boolean", true),
	DisplayOrder = P("number", 0),
}, {}, {})
defClass("BillboardGui", "Instance", {
	Adornee = P("Instance", nil, true),
	Size = P("UDim2", function()
		return UDim2.new(0, 0, 0, 0)
	end),
	StudsOffset = P("Vector3", function()
		return Vector3.new(0, 0, 0)
	end),
	AlwaysOnTop = P("boolean", false),
	MaxDistance = P("number", 1000),
	LightInfluence = P("number", 1),
	Enabled = P("boolean", true),
}, {}, {})
defClass("UICorner", "Instance", { CornerRadius = P("UDim", function()
	return UDim.new(0, 0)
end) }, {}, {})
defClass("UIListLayout", "Instance", {
	FillDirection = P("Enum"),
	HorizontalAlignment = P("Enum"),
	VerticalAlignment = P("Enum"),
	SortOrder = P("Enum"),
	Padding = P("UDim", function()
		return UDim.new(0, 0)
	end),
}, {}, {})

defClass("ProximityPrompt", "Instance", {
	ActionText = P("string", ""),
	ObjectText = P("string", ""),
	HoldDuration = P("number", 0),
	MaxActivationDistance = P("number", 10),
	RequiresLineOfSight = P("boolean", true),
	Enabled = P("boolean", true),
}, { "Triggered" }, {})

defClass("RemoteEvent", "Instance", {}, { "OnClientEvent", "OnServerEvent" }, {
	FireClient = function(self, _player, ...)
		getSignal(self, "OnClientEvent"):Fire(...)
	end,
	FireAllClients = function(self, ...)
		getSignal(self, "OnClientEvent"):Fire(...)
	end,
	FireServer = function(self, ...)
		getSignal(self, "OnServerEvent"):Fire(...)
	end,
})

-- The single mock player; assigned when the harness "joins" it.
local mockLocalPlayer = nil

defClass("RemoteFunction", "Instance", {
	OnServerInvoke = P("any"),
	OnClientInvoke = P("any"),
}, {}, {
	InvokeServer = function(self, ...)
		local cb = getProp(self, "OnServerInvoke")
		if cb then
			return cb(mockLocalPlayer, ...)
		end
		return nil
	end,
	InvokeClient = function(self, _player, ...)
		local cb = getProp(self, "OnClientInvoke")
		if cb then
			return cb(...)
		end
		return nil
	end,
})

defClass("Humanoid", "Instance", {
	WalkSpeed = P("number", 16),
	Health = P("number", 100),
	MaxHealth = P("number", 100),
}, {}, {
	-- State changes are recorded so tests can prove a wave hit
	-- actually tripped the character (Physics), not just moved data.
	ChangeState = function(self, state)
		local rec = INTERNALS[self]
		rec.stateHistory = rec.stateHistory or {}
		table.insert(rec.stateHistory, state)
		rec.state = state
	end,
	GetState = function(self)
		return INTERNALS[self].state or Enum.HumanoidStateType.Running
	end,
})

defClass("Player", "Instance", {
	UserId = P("number", 0),
	Character = P("Instance", nil, true),
}, { "CharacterAdded" }, {})

local playersList = {}
defClass("Players", "Instance", {
	LocalPlayer = P("Instance", nil, true),
}, { "PlayerAdded", "PlayerRemoving" }, {
	GetPlayers = function(_self)
		local out = {}
		for _, p in ipairs(playersList) do
			table.insert(out, p)
		end
		return out
	end,
	GetPlayerFromCharacter = function(_self, character)
		for _, p in ipairs(playersList) do
			if getProp(p, "Character") == character then
				return p
			end
		end
		return nil
	end,
})

-- ------------------------------------------------------------------
-- Services and the DataModel tree
-- ------------------------------------------------------------------

local warnLog = {}
local printLog = {}

local WorkspaceInst = newInstance("Workspace")
INTERNALS[WorkspaceInst].props.Name = "Workspace"
local ReplicatedStorageInst = newInstance("ReplicatedStorage")
INTERNALS[ReplicatedStorageInst].props.Name = "ReplicatedStorage"
local ServerScriptServiceInst = newInstance("ServerScriptService")
INTERNALS[ServerScriptServiceInst].props.Name = "ServerScriptService"
local PlayersInst = newInstance("Players")
INTERNALS[PlayersInst].props.Name = "Players"

local RunServiceMock = {
	IsStudio = function(_self)
		return true
	end,
	Heartbeat = Signal.new(),
	RenderStepped = Signal.new(),
}
local DataStoreServiceMock = {
	GetDataStore = function(_self, _name)
		return {
			GetAsync = function(_s, _key)
				return nil
			end,
			SetAsync = function(_s, _key, _value)
				return true
			end,
		}
	end,
}

local services = {
	Workspace = WorkspaceInst,
	ReplicatedStorage = ReplicatedStorageInst,
	ServerScriptService = ServerScriptServiceInst,
	Players = PlayersInst,
	RunService = RunServiceMock,
	DataStoreService = DataStoreServiceMock,
}

local gameMock = {}
function gameMock:GetService(name)
	local svc = services[name]
	if not svc then
		error("harness game:GetService: no mock for " .. tostring(name))
	end
	return svc
end
function gameMock:BindToClose(_fn) end
gameMock.PlaceId = 122996066064591
gameMock.GameId = 10777537289

-- Build the script tree the way default.project.json maps it.
local function addScript(parent, className, instName, path)
	local inst = newInstance(className)
	INTERNALS[inst].props.Name = instName
	INTERNALS[inst].source = readSrc(path)
	setParent(inst, parent)
	return inst
end

local sharedFolder = newInstance("Folder")
INTERNALS[sharedFolder].props.Name = "Shared"
setParent(sharedFolder, ReplicatedStorageInst)
addScript(sharedFolder, "ModuleScript", "Config", "src/shared/Config.luau")
addScript(sharedFolder, "ModuleScript", "BrainrotData", "src/shared/BrainrotData.luau")

local moduleScripts = {}
for _, name in ipairs({ "BrainrotFactory", "GameState", "EconomyService", "CatchService", "StealService", "WorldBuilder" }) do
	moduleScripts[name] = addScript(ServerScriptServiceInst, "ModuleScript", name, "src/server/" .. name .. ".luau")
end
local mainScript = addScript(ServerScriptServiceInst, "Script", "Main", "src/server/Main.server.luau")
local hudScript = addScript(newInstance("StarterPlayerScripts"), "LocalScript", "HUD", "src/client/HUD.client.luau")
local effectsScript = addScript(newInstance("StarterPlayerScripts"), "LocalScript", "Effects", "src/client/Effects.client.luau")

-- ------------------------------------------------------------------
-- Environments and require
-- ------------------------------------------------------------------

local STD_COPY = {
	"pairs", "ipairs", "next", "select", "tostring", "tonumber", "type", "typeof",
	"pcall", "xpcall", "error", "assert", "setmetatable", "getmetatable",
	"rawget", "rawset", "rawequal", "rawlen", "string", "math", "table",
	"coroutine", "utf8", "bit32",
}

local moduleCache = {} -- [instance] = { server = value, client = value }

local function makeEnv(side, scriptInst)
	local env = {}
	for _, k in ipairs(STD_COPY) do
		env[k] = _G[k]
	end
	env.game = gameMock
	env.workspace = WorkspaceInst
	env.Workspace = WorkspaceInst
	env.Instance = InstanceMock
	env.Enum = Enum
	env.Vector3 = Vector3
	env.Vector2 = Vector2
	env.CFrame = CFrame
	env.Color3 = Color3
	env.UDim = UDim
	env.UDim2 = UDim2
	env.task = taskMock
	env.os = {
		clock = function()
			return Scheduler.now
		end,
		time = function()
			return 1700000000 + math.floor(Scheduler.now)
		end,
	}
	env.warn = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			table.insert(parts, tostring(select(i, ...)))
		end
		table.insert(warnLog, table.concat(parts, " "))
	end
	env.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			table.insert(parts, tostring(select(i, ...)))
		end
		table.insert(printLog, table.concat(parts, " "))
	end
	env.script = scriptInst
	env.require = function(target)
		if isInstance(target) then
			return requireModule(target, side)
		end
		error("harness require: unsupported target " .. tostring(target))
	end
	setmetatable(env, { __index = _G })
	return env
end

function requireModule(inst, side)
	local perSide = moduleCache[inst]
	if perSide and perSide[side] ~= nil then
		return perSide[side]
	end
	local int = INTERNALS[inst]
	local fn, err = luau.load(int.source, {
		environment = makeEnv(side, inst),
		chunkName = getProp(inst, "Name"),
	})
	if not fn then
		error("harness: failed to load " .. tostring(getProp(inst, "Name")) .. ": " .. tostring(err))
	end
	local value = fn()
	if not perSide then
		perSide = {}
		moduleCache[inst] = perSide
	end
	perSide[side] = value
	return value
end

local function runScript(inst, side)
	local int = INTERNALS[inst]
	local fn, err = luau.load(int.source, {
		environment = makeEnv(side, inst),
		chunkName = getProp(inst, "Name"),
	})
	if not fn then
		error("harness: failed to load script " .. tostring(getProp(inst, "Name")) .. ": " .. tostring(err))
	end
	fn()
end

-- ------------------------------------------------------------------
-- Boot + assertions
-- ------------------------------------------------------------------

math.randomseed(20261119)

lintPivotOffset()
lintStringColors()
lintModelPivotProps()
compileAll()

-- Server boot: run Main inside a scheduler coroutine (it connects
-- PlayerAdded first, then starts every service behind pcall).
Scheduler.spawn(function()
	runScript(mainScript, "server")
end)
Scheduler.advance(1)

local function warnContains(needle, fromIdx)
	for i = fromIdx or 1, #warnLog do
		if warnLog[i]:find(needle, 1, true) then
			return true
		end
	end
	return false
end

check("BOOT EconomyService live", warnContains("EconomyService live"))
check("BOOT CatchService live with full wild population", warnContains("CatchService live, wild population = 14"))
check("BOOT StealService live", warnContains("StealService live"))
check("BOOT no service failed to start", not warnContains("failed to start"))
check("BOOT no scheduler errors", #Scheduler.errors == 0, table.concat(Scheduler.errors, "; "))

-- Wild population invariants.
local Config = requireModule(baseMethods.FindFirstChild(sharedFolder, "Config"), "server")
local GameState = requireModule(moduleScripts.GameState, "server")
local BrainrotFactory = requireModule(moduleScripts.BrainrotFactory, "server")

local wildFolder = baseMethods.FindFirstChild(WorkspaceInst, "WildBrainrots")
check("WILD folder exists under Workspace", wildFolder ~= nil)
local wildModels = wildFolder and baseMethods.GetChildren(wildFolder) or {}
check("WILD population == WildCount (14)", #wildModels == Config.WildCount, "got " .. #wildModels)

local function ancestorReachesWorkspace(inst)
	local cur = getProp(inst, "Parent")
	while cur do
		if cur == WorkspaceInst then
			return true
		end
		cur = getProp(cur, "Parent")
	end
	return false
end

local wildOk, wildDetail = true, nil
for _, model in ipairs(wildModels) do
	if not ancestorReachesWorkspace(model) then
		wildOk, wildDetail = false, "parent chain broken for " .. tostring(getProp(model, "Name"))
		break
	end
	local root = getProp(model, "PrimaryPart")
	if not root or getProp(root, "Name") ~= "Root" then
		wildOk, wildDetail = false, "PrimaryPart is not the factory Root for " .. tostring(getProp(model, "Name"))
		break
	end
	if getProp(root, "Anchored") ~= true then
		wildOk, wildDetail = false, "root not anchored for " .. tostring(getProp(model, "Name"))
		break
	end
	local pos = model:GetPivot().Position
	if pos.Y < 0 or pos.X < Config.Field.MinX or pos.X > Config.Field.MaxX
		or pos.Z < Config.Field.MinZ or pos.Z > Config.Field.MaxZ then
		wildOk, wildDetail = false, "pivot out of field: " .. tostring(pos)
		break
	end
end
check("WILD every model: Workspace-parented, Root anchored, pivot in field above floor", wildOk, wildDetail)

-- Join a player.
local player = newInstance("Player")
INTERNALS[player].props.Name = "koncone_mase"
INTERNALS[player].props.UserId = 424242
local playerGui = newInstance("Folder")
INTERNALS[playerGui].props.Name = "PlayerGui"
setParent(playerGui, player)
local character = newInstance("Model")
INTERNALS[character].props.Name = "koncone_mase"
local head = newInstance("Part")
INTERNALS[head].props.Name = "Head"
INTERNALS[head].props.CFrame = CFrame.new(0, 5, 100)
setParent(head, character)
local hrp = newInstance("Part")
INTERNALS[hrp].props.Name = "HumanoidRootPart"
INTERNALS[hrp].props.CFrame = CFrame.new(0, 3, 100)
setParent(hrp, character)
local humanoid = newInstance("Humanoid")
INTERNALS[humanoid].props.Name = "Humanoid"
setParent(humanoid, character)
INTERNALS[player].props.Character = character
setParent(character, WorkspaceInst)
table.insert(playersList, player)
INTERNALS[PlayersInst].props.LocalPlayer = player
mockLocalPlayer = player

getSignal(PlayersInst, "PlayerAdded"):Fire(player)
Scheduler.advance(2)

local data = GameState.GetPlayerData(player)
check("STATE player data exists after join", data ~= nil)
check("STATE fresh player cash == StartingCash (150)", data and data.Cash == 150,
	data and ("cash=" .. tostring(data.Cash)))

local remotesFolder = baseMethods.FindFirstChild(ReplicatedStorageInst, "BerburuMusengRemotes")
local getStateFn = remotesFolder and baseMethods.FindFirstChild(remotesFolder, "GetStateFunction")
local buyEggFn = remotesFolder and baseMethods.FindFirstChild(remotesFolder, "BuyEggFunction")
check("STATE remotes exist", getStateFn ~= nil and buyEggFn ~= nil)

local stateResult = getStateFn and getStateFn:InvokeServer()
check("STATE GetState returns cash 150 + base 1 + pads table",
	stateResult ~= nil and stateResult.Cash == 150 and stateResult.BaseIndex == 1
		and type(stateResult.Pads) == "table",
	stateResult and ("cash=" .. tostring(stateResult.Cash) .. " base=" .. tostring(stateResult.BaseIndex)))

-- BuyEgg success path: exactly one deduction, one placed brainrot.
local eggResult = buyEggFn and buyEggFn:InvokeServer(1)
local padCount = 0
for _ in pairs(data.Pads) do
	padCount += 1
end
local padModel = nil
for _, m in pairs(data.PadModels) do
	padModel = m
end
check("EGG BuyEgg(1) hatches (no Error, has Name)",
	eggResult ~= nil and eggResult.Error == nil and type(eggResult.Name) == "string",
	eggResult and tostring(eggResult.Error))
check("EGG cash deducted exactly once (150 -> 50)", data.Cash == 50, "cash=" .. tostring(data.Cash))
check("EGG exactly one pad occupied with a Workspace-parented model",
	padCount == 1 and padModel ~= nil and getProp(padModel, "Parent") == WorkspaceInst)
check("EGG placed model PrimaryPart is the factory Root",
	padModel ~= nil and getProp(getProp(padModel, "PrimaryPart"), "Name") == "Root")

-- Forced factory failure: cash and pads must not move.
local warnMark = #warnLog
local originalBuild = BrainrotFactory.BuildCharacter
BrainrotFactory.BuildCharacter = function()
	error("forced factory failure (harness)")
end
GameState.AddCash(player, 1000)
local cashBeforeFail = data.Cash
local failResult = buyEggFn:InvokeServer(1)
BrainrotFactory.BuildCharacter = originalBuild
local padCountAfterFail = 0
for _ in pairs(data.Pads) do
	padCountAfterFail += 1
end
check("EGG forced factory failure returns the hiccup error",
	failResult ~= nil and failResult.Error == "The shop hiccuped - try again",
	failResult and tostring(failResult.Error))
check("EGG forced factory failure leaves cash unchanged", data.Cash == cashBeforeFail,
	"cash " .. tostring(cashBeforeFail) .. " -> " .. tostring(data.Cash))
check("EGG forced factory failure leaves pads unchanged", padCountAfterFail == padCount)
check("EGG forced failure was traced (factory error warn)", warnContains("brainrot build failed", warnMark))

-- Watchdog: a wild model dropped out of the world is respawned.
local victim = wildModels[1]
if victim then
	victim:PivotTo(CFrame.new(0, -50, 0))
	Scheduler.advance(6)
	local wildAfter = baseMethods.GetChildren(wildFolder)
	check("WATCHDOG fallen wild model respawned, population back to 14", #wildAfter == Config.WildCount,
		"got " .. #wildAfter)
	check("WATCHDOG fall was traced", warnContains("fell out of the world"))
else
	check("WATCHDOG fallen wild model respawned, population back to 14", false, "no wild model to drop")
	check("WATCHDOG fall was traced", false, "no wild model to drop")
end
check("WATCHDOG no scheduler errors", #Scheduler.errors == 0, table.concat(Scheduler.errors, "; "))

-- ------------------------------------------------------------------
-- Round 5: factory polish -- every character builds as a character.
-- ------------------------------------------------------------------

local BrainrotData = requireModule(baseMethods.FindFirstChild(sharedFolder, "BrainrotData"), "server")

local function countChildrenNamed(model, name)
	local n = 0
	for _, child in ipairs(baseMethods.GetChildren(model)) do
		if getProp(child, "Name") == name then
			n += 1
		end
	end
	return n
end

local function countBaseParts(model)
	local n = 0
	for _, child in ipairs(baseMethods.GetChildren(model)) do
		if classChainHas(INTERNALS[child].class, "BasePart") then
			n += 1
		end
	end
	return n
end

local factoryOk, factoryDetail = true, nil
for _, character in ipairs(BrainrotData.Characters) do
	local built = BrainrotFactory.BuildCharacter(character.Id, "None", CFrame.new(500, 0, 500))
	if not built then
		factoryOk, factoryDetail = false, "build returned nil for " .. character.Id
		break
	end
	local parts = countBaseParts(built)
	if parts < 12 then
		factoryOk, factoryDetail = false, character.Id .. " built with only " .. parts .. " parts"
		break
	end
	local hasHead = baseMethods.FindFirstChild(built, "Head") ~= nil
	local hasEyes = countChildrenNamed(built, "Eye") >= 2 or baseMethods.FindFirstChild(built, "Visor") ~= nil
	if character.Id == "hiu_hoodie" then
		-- The shark's face is its body front: eyes, no separate head.
		if not hasEyes then
			factoryOk, factoryDetail = false, "hiu_hoodie has no eyes"
			break
		end
	elseif not hasHead or not hasEyes then
		factoryOk, factoryDetail = false, character.Id .. " missing head or eyes"
		break
	end
end
check("FACTORY all 19 characters build with >=12 parts, a head and two eyes", factoryOk, factoryDetail)

local omegaBuild = BrainrotFactory.BuildCharacter("museng_omega", "None", CFrame.new(500, 0, 500))
local commonBuild = BrainrotFactory.BuildCharacter("kucing_kardus", "None", CFrame.new(500, 0, 500))
check("FACTORY rarity ring on Brainrot God, none on Common",
	omegaBuild ~= nil and baseMethods.FindFirstChild(omegaBuild, "RarityRing") ~= nil
		and commonBuild ~= nil and baseMethods.FindFirstChild(commonBuild, "RarityRing") == nil)

-- ------------------------------------------------------------------
-- Round 5: the Speed upgrade applies to the CURRENT character in
-- the same call that buys it, and respawn re-applies it.
-- ------------------------------------------------------------------

local buyUpgradeFn = remotesFolder and baseMethods.FindFirstChild(remotesFolder, "BuyUpgradeFunction")
check("SPEED BuyUpgradeFunction remote exists", buyUpgradeFn ~= nil)
local cashBeforeSpeed = data.Cash
local speedResult = buyUpgradeFn and buyUpgradeFn:InvokeServer("Speed")
check("SPEED purchase succeeds", speedResult ~= nil and speedResult.Upgraded == "Speed",
	speedResult and tostring(speedResult.Error))
check("SPEED SpeedLevel rose and exactly the level cost was charged",
	data.SpeedLevel == 1 and data.Cash == cashBeforeSpeed - Config.SpeedUpgradeCosts[1],
	"level=" .. tostring(data.SpeedLevel) .. " cash " .. tostring(cashBeforeSpeed)
		.. " -> " .. tostring(data.Cash))
check("SPEED WalkSpeed applied to the live humanoid in the same call (16 -> 20)",
	getProp(humanoid, "WalkSpeed") == Config.BaseWalkSpeed + Config.SpeedPerLevel,
	"walkspeed=" .. tostring(getProp(humanoid, "WalkSpeed")))
INTERNALS[humanoid].props.WalkSpeed = 16
getSignal(player, "CharacterAdded"):Fire(character)
Scheduler.advance(1)
check("SPEED CharacterAdded re-applies the purchased speed after a reset",
	getProp(humanoid, "WalkSpeed") == Config.BaseWalkSpeed + Config.SpeedPerLevel,
	"walkspeed=" .. tostring(getProp(humanoid, "WalkSpeed")))

-- ------------------------------------------------------------------
-- Round 5: wander stability. The round-4 churn root cause was the
-- wander step re-adding its bob to a target that already contained
-- last frame's bob, integrating Y into an unbounded random walk
-- until the watchdog (correctly) destroyed healthy models. Fire a
-- full simulated minute of Heartbeats, then let watchdog ticks run:
-- nothing may fall, and every pivot stays in the bob band.
-- ------------------------------------------------------------------

local function countFalls()
	local n = 0
	for _, line in ipairs(warnLog) do
		if line:find("fell out of the world", 1, true) then
			n += 1
		end
	end
	return n
end

local fallsBeforeWander = countFalls()
for _ = 1, 3600 do
	RunServiceMock.Heartbeat:Fire(1 / 60)
end
Scheduler.advance(12)
check("WANDER 60s of heartbeats + watchdog ticks: zero falls",
	countFalls() == fallsBeforeWander,
	"falls before=" .. fallsBeforeWander .. " after=" .. countFalls())
local wanderOk, wanderDetail = true, nil
local wildAfterWander = baseMethods.GetChildren(wildFolder)
if #wildAfterWander ~= Config.WildCount then
	wanderOk, wanderDetail = false, "population " .. #wildAfterWander
else
	for _, model in ipairs(wildAfterWander) do
		local y = model:GetPivot().Position.Y
		if y < -0.02 or y > 0.32 then
			wanderOk, wanderDetail = false, "pivot Y out of bob band: " .. tostring(y)
			break
		end
	end
end
check("WANDER population intact, every pivot Y inside the bob band", wanderOk, wanderDetail)

-- ------------------------------------------------------------------
-- Round 5: the tsunami hits. Player 1 catches a brainrot, then
-- stands IN THE FIELD (the wave only threatens the field: outside
-- it, on high ground, or in a base is safe by design). At the
-- crossing he must lose the carry AND be knocked (impulse + Physics
-- trip) without dying. At the NEXT crossing he waits on the mesa:
-- completely untouched.
-- ------------------------------------------------------------------

local waveModelInst = baseMethods.FindFirstChild(WorkspaceInst, "TsunamiWave", true)
check("WAVE wave model exists in the world", waveModelInst ~= nil)

-- Catch the first wild brainrot: walk it up to the player and fire
-- its real catch prompt.
local catchVictim = baseMethods.GetChildren(wildFolder)[1]
local catchPrompt = catchVictim and baseMethods.FindFirstChild(catchVictim, "CatchPrompt", true)
if catchVictim then
	catchVictim:PivotTo(CFrame.new(0, 0.15, 92))
end
if catchPrompt then
	getSignal(catchPrompt, "Triggered"):Fire(player)
end
Scheduler.advance(1)
check("WAVE player is carrying before the wave", #data.Carrying == 1,
	"carrying=" .. tostring(#data.Carrying))

-- Move into the open field and run the clock to the crossing
-- (warning at t=70, crossing t=80-89), sampling the wave's X.
INTERNALS[hrp].props.CFrame = CFrame.new(0, 3, 0)
Scheduler.advance(54)
local waveMaxX = -math.huge
for _ = 1, 12 do
	Scheduler.advance(1)
	if waveModelInst then
		waveMaxX = math.max(waveMaxX, waveModelInst:GetPivot().Position.X)
	end
end
check("WAVE the crossing swept past the player's X", waveMaxX > 0,
	"maxWaveX=" .. tostring(waveMaxX))
check("WAVE carrier in the open lost the carried brainrot", #data.Carrying == 0,
	"carrying=" .. tostring(#data.Carrying))
local p1Velocity = getProp(hrp, "AssemblyLinearVelocity")
check("WAVE carrier was knocked back (+X and up) by the wave",
	p1Velocity.X == 34 and p1Velocity.Y == 24,
	"velocity=" .. tostring(p1Velocity))
local p1States = INTERNALS[humanoid].stateHistory or {}
local p1Tripped = false
for _, s in ipairs(p1States) do
	if s == Enum.HumanoidStateType.Physics then
		p1Tripped = true
	end
end
check("WAVE carrier was tripped (Humanoid Physics state)", p1Tripped)
check("WAVE carrier was NOT killed", getProp(humanoid, "Health") == 100)

-- Second crossing: wait it out on the mesa (high ground inside the
-- field). Reset the harness-side evidence of the first hit first.
INTERNALS[hrp].props.CFrame = CFrame.new(110, 16, -120)
INTERNALS[hrp].props.AssemblyLinearVelocity = Vector3.new()
INTERNALS[humanoid].stateHistory = {}
Scheduler.advance(95)
local p2Velocity = getProp(hrp, "AssemblyLinearVelocity")
local p2States = INTERNALS[humanoid].stateHistory or {}
check("WAVE player on high ground completely untouched by the next crossing",
	p2Velocity.X == 0 and p2Velocity.Y == 0 and p2Velocity.Z == 0 and #p2States == 0,
	"velocity=" .. tostring(p2Velocity) .. " states=" .. tostring(#p2States))
check("WAVE no scheduler errors", #Scheduler.errors == 0, table.concat(Scheduler.errors, "; "))

-- Client boot: HUD first (it must render the server state it pulls),
-- then Effects. Both load inside scheduler coroutines.
local errorsBeforeClient = #Scheduler.errors
Scheduler.spawn(function()
	runScript(hudScript, "client")
end)
Scheduler.advance(3)

local gui = baseMethods.FindFirstChild(playerGui, "BerburuMusengHUD")
check("HUD script loaded and built its ScreenGui", gui ~= nil)
check("HUD load produced no scheduler errors", #Scheduler.errors == errorsBeforeClient,
	table.concat(Scheduler.errors, "; "))

local function findInGui(name)
	return gui and baseMethods.FindFirstChild(gui, name, true)
end

local cashLabel = findInGui("CashLabel")
local expectedCash = "$" .. math.floor(GameState.GetPlayerData(player).Cash)
check("HUD CashLabel renders pulled server state", cashLabel ~= nil and getProp(cashLabel, "Text") == expectedCash,
	cashLabel and ("text=" .. tostring(getProp(cashLabel, "Text")) .. " expected=" .. expectedCash))

local buttonsOk, buttonsDetail = true, nil
for _, name in ipairs({ "EggButton1", "EggButton2", "EggButton3", "SpeedButton", "CarryButton", "RebirthButton", "ShopToggle" }) do
	if not findInGui(name) then
		buttonsOk, buttonsDetail = false, "missing " .. name
		break
	end
end
check("HUD every shop button built (incl. ShopToggle)", buttonsOk, buttonsDetail)
check("HUD pad list rendered the placed brainrot", findInGui("PadRow1") ~= nil)

Scheduler.spawn(function()
	runScript(effectsScript, "client")
end)
Scheduler.advance(1)
check("FX Effects script loaded cleanly", #Scheduler.errors == errorsBeforeClient,
	table.concat(Scheduler.errors, "; "))
check("RUNTIME no event-handler errors across the whole run", #runtimeErrors == 0,
	table.concat(runtimeErrors, "; "))

-- ------------------------------------------------------------------
-- Summary
-- ------------------------------------------------------------------

local failures = 0
for _, r in ipairs(results) do
	if not r.Ok then
		failures += 1
	end
end
print(string.format("---- harness: %d checks, %d passed, %d failed", #results, #results - failures, failures))
process.exit(failures == 0 and 0 or 1)
