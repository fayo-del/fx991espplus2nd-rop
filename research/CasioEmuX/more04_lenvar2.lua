-- MB04 run 2 (goal-driven): (b) Right-arrow INC of 0x8114 past 99, (c) RCL/UP paste
-- of a long history entry into a non-empty line (concat >100?).
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")
emu:SetClockSpeed(8)

local T = 0
local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, RIGHT, UP, DOWN, K1, K2, K9, PLUS =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x37, 0x27, 0x36, 0x00, 0x10, 0x22, 0x30

local HOLD, GAP = 16000, 20000
local state, hold_t, gap_t = "idle", 0, 0
local curcode, curlabel = nil, nil
local phase = "run"   -- run | final
local final_t = 0
local maxlen = 0
local goal = nil
local tries = 0

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
local function sample(tag)
	local l = L()
	if l > maxlen then maxlen = l end
	print(string.format("S %-22s len8114=%3d slen=%4d blen=%3d b7=%02X lastkey=%02X buf=%s",
		tag, l, slen(), blen(), (data[0x81B7] or 0) & 0xFF, (data[0x80F5] or 0) & 0xFF, bdump(24)))
end

-- goals: {press=code, label=..., until=fn, max=tries, sampleEvery=n}
local goals = {}
local gi = 0
local function g(code, label, untilf, maxn, samp)
	goals[#goals + 1] = { code = code, label = label, cond = untilf, max = maxn or 1, samp = samp or 1 }
end

-- 1. warmup + short line "1+1"
g(AC, "warm-AC", nil, 1)
g(K1, "type1", function() return blen() >= 1 end, 6)
g(PLUS, "type+", function() return blen() >= 2 end, 6)
g(K1, "type1b", function() return blen() >= 3 end, 6)
-- 2. RIGHT x30 (INC 0x8114 test on nonempty line)
g(RIGHT, "RIGHTx30", function() return L() >= 33 end, 30, 1)
-- 3. LEFT x3
g(LEFT, "LEFTx3", nil, 3, 1)
-- 4. fill to 99 with K1
g(K1, "fill99", function() return blen() >= 99 end, 150, 25)
-- 5. RIGHT x45 on full line (can 0x8114 pass 99?)
g(RIGHT, "RIGHTx45-full", function() return L() >= 144 end, 45, 5)
-- 6. DEL once, K9 once (writes past 0x81B7?)
g(DEL, "DEL-once", nil, 1, 1)
g(K9, "K9-once", nil, 1, 1)
-- 7. EXE (history entry), AC
g(EXE, "EXE", nil, 1, 1)
g(AC, "AC-after-EXE", nil, 1, 1)
-- 8. RCL candidates into empty line: try 0x03, SHIFT+0x03, 0x13, 0x23, UP
g(0x03, "RCL-a", nil, 1, 1)
g(UP, "UP-a", nil, 1, 1)
g(0x13, "RCL-b", nil, 1, 1)
g(0x23, "RCL-c", nil, 1, 1)
-- 9. nonempty "12" then UP / RCL-a
g(AC, "AC2", nil, 1, 1)
g(K1, "t1", function() return blen() >= 1 end, 6)
g(K2, "t2", function() return blen() >= 2 end, 6)
g(UP, "UP-into-12", nil, 1, 1)
g(0x03, "RCLa-into-12", nil, 1, 1)
-- 10. trigger if long
g(AC, "T-AC", nil, 1, 1)
g(LEFT, "T-LEFT", nil, 1, 1)
g(EXE, "T-EXE", nil, 1, 1)

addposttick(function()
	T = T + 1
	if phase == "run" then
		if state == "idle" then
			if goal == nil or (goal.cond and goal.cond()) or goal.n >= goal.max then
				gi = gi + 1
				if gi > #goals then
					phase = "final"
					print(string.format("DONE maxlen8114=%d slen=%d blen=%d", maxlen, slen(), blen()))
					print("DUMPEND " .. bdump(0x8300 - 0x8154 + 1))
					return
				end
				goal = goals[gi]
				goal.n = 0
				tries = 0
			end
			if goal then
				goal.n = (goal.n or 0) + 1
				curcode, curlabel = goal.code, goal.label
				Keyboard:PressKey(curcode)
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
		if final_t == 200000 then
			local L2 = slen()
			print(string.format("FINAL2 slen=%d len8114=%d maxlen=%d pc=%04X sp=%04X", L2, L(), maxlen, cpu.pc, cpu.sp))
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
