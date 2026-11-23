-- MB04 run 3: RCL (scancode 0x24) paste tests.
--  (c) Can one key step place >100 bytes at 0x8154? RCL path = strcpy(0x8184<-0x85AA)
--      then strcpy([ER8]<-0x8184) with NO cap (ROM 0x7540-0x756A). Test paste into
--      EMPTY line and into a NON-EMPTY line ("12") -> concat would give 2+99=101.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")
emu:SetClockSpeed(8)

local T = 0
local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, RIGHT, UP, K1, K2, PLUS, RCL =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x37, 0x27, 0x00, 0x10, 0x30, 0x24

local HOLD, GAP = 16000, 22000
local state, hold_t, gap_t = "idle", 0, 0
local phase = "run"
local final_t = 0
local maxlen, maxslen = 0, 0

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
	local l, sl = L(), slen()
	if l > maxlen then maxlen = l end
	if sl > maxslen then maxslen = sl end
	print(string.format("S %-20s len8114=%3d slen=%4d blen=%3d b7=%02X b8=%02X lastkey=%02X buf=%s",
		tag, l, sl, blen(), (data[0x81B7] or 0) & 0xFF, (data[0x81B8] or 0) & 0xFF, LK(), bdump(24)))
end

-- goal list; each goal: {code,label,cond,tok,max,samp,dump}
local goals, gi, goal = {}, 0, nil
local function g(code, label, cond, tok, maxn, samp, dumpbig)
	goals[#goals + 1] = { code = code, label = label, cond = cond, tok = tok, max = maxn or 1, samp = samp or 1, big = dumpbig }
end

-- 1 warmup + verify line entry
g(AC, "warm1", nil, nil, 2)
g(K1, "t1", function() return blen() >= 1 end, 0x31, 8)
g(PLUS, "t+", function() return blen() >= 2 end, 0x2B, 8)
g(K1, "t1b", function() return blen() >= 3 end, 0x31, 8)
-- 2 fill to 99
g(K1, "fill99", function() return blen() >= 99 end, 0x31, 220, 40, true)
-- 3 EXE -> history entry (retry until lastkey=F0)
g(EXE, "EXE", function() return LK() == 0xF0 end, 0xF0, 6, 1, true)
-- 4 AC
g(AC, "AC1", function() return LK() == 0xE6 end, 0xE6, 6, 1, true)
-- 5 RCL into empty
g(RCL, "RCL-empty", function() return LK() ~= 0xE6 end, nil, 6, 1, true)
-- 6 AC, type 12, RCL into non-empty (CONCAT TEST)
g(AC, "AC2", function() return LK() == 0xE6 end, 0xE6, 6)
g(K1, "d1", function() return blen() >= 1 end, 0x31, 8)
g(K2, "d2", function() return blen() >= 2 end, 0x32, 8)
g(RCL, "RCL-into-12", function() return LK() ~= 0x32 end, nil, 6, 1, true)
-- 7 AC, UP (history recall) into empty
g(AC, "AC3", function() return LK() == 0xE6 end, 0xE6, 6)
g(UP, "UP-empty", function() return LK() == 0xE0 end, 0xE0, 6, 1, true)
-- 8 AC, type 12, UP into non-empty
g(AC, "AC4", function() return LK() == 0xE6 end, 0xE6, 6)
g(K1, "e1", function() return blen() >= 1 end, 0x31, 8)
g(K2, "e2", function() return blen() >= 2 end, 0x32, 8)
g(UP, "UP-into-12", function() return LK() == 0xE0 end, 0xE0, 6, 1, true)
-- 9 trigger
g(AC, "T-AC", function() return LK() == 0xE6 end, 0xE6, 6, 1, true)
g(LEFT, "T-LEFT", function() return LK() == 0xE3 end, 0xE3, 6, 1, true)
g(EXE, "T-EXE", function() return LK() == 0xF0 end, 0xF0, 6, 1, true)

addposttick(function()
	T = T + 1
	if phase == "run" then
		if state == "idle" then
			if goal == nil or (goal.cond and goal.cond()) or goal.n >= goal.max then
				gi = gi + 1
				if gi > #goals then
					phase = "final"
					print(string.format("DONE maxlen8114=%d maxslen=%d slen=%d blen=%d", maxlen, maxslen, slen(), blen()))
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
					if goal.big then print("D " .. goal.label .. " " .. bdump(0x8300 - 0x8154 + 1)) end
				end
				state = "idle"
			end
		end
	elseif phase == "final" then
		final_t = final_t + 1
		if final_t == 300000 then
			local L2 = slen()
			print(string.format("FINAL2 slen=%d len8114=%d maxslen=%d pc=%04X sp=%04X", L2, L(), maxslen, cpu.pc, cpu.sp))
			if L2 >= 100 then
				local bad, n = 0, 0
				for a = 0x8240, 0x8DF8, 5 do
					n = n + 1
					local want = (data[0x8154 + ((a - 0x8154) % L2)] or 0) & 0xFF
					if want ~= ((data[a] or 0) & 0xFF) then bad = bad + 1 end
				end
				print(string.format("FLOODCHECK period=%d sampled=%d mismatches=%d", L2, n, bad))
			end
			print("DUMPFINAL " .. bdump(0x8300 - 0x8154 + 1))
			emu:set_paused(true)
			phase = "done"
		end
	end
end)
