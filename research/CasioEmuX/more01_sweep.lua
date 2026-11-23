-- MORE01 SWEEP: map every physical key code 0x00-0x67 (base, SHIFT+, ALPHA+)
-- to the bytes it inserts at 0x8154 in MathIO. AC between probes (with latch
-- eaters after SHIFT/ALPHA so SHIFT+AC=OFF never fires).
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")
emu:SetClockSpeed(8)

local T = 0
local SHIFT, ALPHA, AC = 0x07, 0x17, 0x42

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil

local function slen()
	for i = 0, 0x1AC do if (data[0x8154 + i] or 0) == 0 then return i end end
	return 0x1AD
end
local function bdump(n, base)
	local s = ""
	for i = 0, (n or 16) - 1 do s = s .. string.format("%02X", (data[(base or 0x8154) + i] or 0) & 0xFF) end
	return s
end
local function push(code, label, hold, gap)
	keys[#keys + 1] = { code = code, label = label, hold = hold or 26000, gap = gap or 10000 }
end
local function sample(tag)
	print(string.format("SW %-8s slen=%2d len=%2d h=%s", tag, slen(), (data[0x8114] or 0) & 0xFF, bdump(10)))
end

-- helper: reset input. If latch possibly armed (prev SHIFT/ALPHA), eat with K1 first.
local function reset(prevshift)
	if prevshift then push(0x00, "eat") end
	push(AC, "ac")
end

-- Phase BASE: every code 0x00..0x67
local prevshift = false
for c = 0x00, 0x67 do
	reset(prevshift)
	push(c, string.format("b%02X", c))
	prevshift = (c == 0x07 or c == 0x17)
end
reset(prevshift)
-- Phase SHIFT: SHIFT + interesting codes (never 0x07/0x42)
local PAD = { 0x00,0x01,0x02,0x10,0x11,0x12,0x20,0x21,0x22,0x30,0x31,0x32,0x33,0x40,0x41,0x60,0x61,0x62,0x63,0x64,
	0x03,0x04,0x05,0x13,0x14,0x15,0x23,0x24,0x25,0x34,0x35,0x43,0x44,0x45,0x53,0x54,0x55,
	0x06,0x16,0x26,0x27,0x36,0x37,0x46,0x47,0x56 }
for _, c in ipairs(PAD) do
	if c ~= 0x07 and c ~= 0x42 then
		reset(false)
		push(SHIFT, "sh")
		push(c, string.format("s%02X", c))
		push(0x00, "eat2")  -- eat any residual shift latch
	end
end
reset(false)
-- Phase ALPHA
for _, c in ipairs(PAD) do
	reset(false)
	push(ALPHA, "al")
	push(c, string.format("a%02X", c))
	push(0x00, "eat3")
end
reset(false)

addposttick(function()
	T = T + 1
	if state == "idle" then
		ki = ki + 1
		if ki > #keys then
			print(string.format("DONE sweep: final slen=%d len=%d", slen(), (data[0x8114] or 0) & 0xFF))
			emu:set_paused(true)
			state = "done"
			return
		end
		cur = keys[ki]
		Keyboard:PressKey(cur.code)
		state = "press"; hold_t = cur.hold
	elseif state == "press" then
		hold_t = hold_t - 1
		if hold_t <= 0 then
			Keyboard:ReleaseAll()
			state = "rel"; gap_t = cur.gap
		end
	elseif state == "rel" then
		gap_t = gap_t - 1
		if gap_t <= 0 then
			local lb = cur.label or "?"
			if lb:sub(1, 1) == "b" or lb:sub(1, 1) == "s" or lb:sub(1, 1) == "a" then
				if #lb == 3 then sample(lb) end
			end
			state = "idle"
		end
	end
end)
