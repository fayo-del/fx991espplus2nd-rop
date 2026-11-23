-- MB04 run 4: reach the typed cap (blen=99) then battery of keys AT THE CAP,
-- watching 0x81B7 (input index 99) / strlen(0x8154): can any key push strlen past 99?
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")
emu:SetClockSpeed(8)

local T = 0
local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, RIGHT, UP, DOWN, K1, K9, KX10, RCL =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x37, 0x27, 0x36, 0x00, 0x22, 0x62, 0x24

local HOLD, GAP = 12000, 14000
local state, hold_t, gap_t = "idle", 0, 0
local phase = "run"
local final_t = 0
local maxlen, maxslen, b7ever = 0, 0, 0

local function slen()
	for a = 0x8154, 0x8DFE do if (data[a] or 0) == 0 then return a - 0x8154 end end
	return 0x8DFF - 0x8154 + 1
end
local function blen()
	for i = 0, 99 do if (data[0x8154 + i] or 0) == 0 then return i end end
	return 100
end
local function bdump(n, base)
	local s = ""
	base = base or 0x8154
	for i = 0, (n or 24) - 1 do s = s .. string.format("%02X", data[base + i] or 0) end
	return s
end
local function L() return (data[0x8114] or 0) & 0xFF end
local function LK() return (data[0x80F5] or 0) & 0xFF end
local function sample(tag)
	local l, sl, b7 = L(), slen(), (data[0x81B7] or 0) & 0xFF
	if l > maxlen then maxlen = l end
	if sl > maxslen then maxslen = sl end
	if b7 ~= 0 and b7ever == 0 then b7ever = 1 end
	print(string.format("S %-16s len8114=%3d slen=%4d blen=%3d b7=%02X b8=%02X lastkey=%02X tail=%s",
		tag, l, sl, blen(), b7, (data[0x81B8] or 0) & 0xFF, LK(), bdump(12, 0x81B0)))
end

local goals, gi, goal = {}, 0, nil
local function g(code, label, cond, maxn, samp)
	goals[#goals + 1] = { code = code, label = label, cond = cond, max = maxn or 1, samp = samp or 1 }
end

g(AC, "warm", nil, 2)
g(K1, "fill99", function() return blen() >= 99 end, 420, 60)
-- at-cap battery
g(0x56, "shift", nil, 1)          -- modifier press alone
g(0x56, "sigma-at-cap", nil, 1)   -- shift+0x56 was already consumed; press 0x56 again
g(ALPHA, "alpha", nil, 1)
g(0x33, "X-at-cap", nil, 1)
g(K9, "K9-at-cap", nil, 1)
g(DEL, "DEL-at-cap", nil, 1)
g(K9, "K9-after-DEL", nil, 1)
g(LEFT, "LEFT-at-cap", nil, 1)
g(RIGHT, "RIGHT-at-cap", nil, 1)
g(UP, "UP-at-cap", nil, 1)
g(0x24, "RCLkey-at-cap", nil, 1)
g(EXE, "EXE-at-cap", nil, 1)
g(LEFT, "LEFT-after-EXE", nil, 1)
g(K1, "K1-after-LEFT", nil, 1)

addposttick(function()
	T = T + 1
	if phase == "run" then
		if state == "idle" then
			if goal == nil or (goal.cond and goal.cond()) or goal.n >= goal.max then
				gi = gi + 1
				if gi > #goals then
					phase = "final"
					print(string.format("DONE maxlen8114=%d maxslen=%d b7ever=%d slen=%d blen=%d",
						maxlen, maxslen, b7ever, slen(), blen()))
					print("DUMPEND " .. bdump(0x8300 - 0x8154 + 1))
					return
				end
				goal = goals[gi]
				goal.n = 0
			end
			if goal then
				goal.n = (goal.n or 0) + 1
				Keyboard:PressKey(goal.code)
				state = "press"; hold_t = HOLD
			end
		elseif state == "press" then
			hold_t = hold_t - 1
			if hold_t <= 0 then
				Keyboard:ReleaseAll()
				state = "rel"; gap_t = GAP
			end
		elseif state == "rel" then
			gap_t = gap_t - 1
			if gap_t <= 0 then
				if goal and (goal.n % goal.samp == 0) then
					sample(string.format("%s#%d", goal.label, goal.n))
				end
				state = "idle"
			end
		end
	elseif phase == "final" then
		final_t = final_t + 1
		if final_t == 120000 then
			print(string.format("FINAL2 slen=%d blen=%d len8114=%d maxslen=%d b7ever=%d pc=%04X sp=%04X",
				slen(), blen(), L(), maxslen, b7ever, cpu.pc, cpu.sp))
			print("DUMPFINAL " .. bdump(0x8300 - 0x8154 + 1))
			emu:set_paused(true)
			phase = "done"
		end
	end
end)
