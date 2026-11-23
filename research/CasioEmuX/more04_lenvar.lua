-- MB04 len-var / RCL-paste test: (a) what the AC gate measures (static, see findings),
-- (b) can 0x8114 be pushed >99 from keys (Right-arrow INC [EA] at ROM 0x6196),
-- (c) can RCL/history paste place >100 bytes at 0x8154 in one step (insert-gate
--     0x655A checks strlen<99 BEFORE the insert; a 99-byte entry inserted into a
--     2-byte line would land 101 bytes).
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")
emu:SetClockSpeed(8)

local T = 0
local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, RIGHT, UP, K1, K2, K9, PLUS, RCL =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x37, 0x27, 0x00, 0x10, 0x22, 0x30, 0x03

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase, final_t = "type", 0
local maxlen = 0

local function slen() -- full strlen from 0x8154 up to RAM end
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
local function sample(tag)
	local l = (data[0x8114] or 0) & 0xFF
	if l > maxlen then maxlen = l end
	print(string.format("SAMPLE %-14s len8114=%3d slen=%4d blen=%3d b7=%02X b8=%02X lastkey=%02X buf=%s",
		tag, l, slen(), blen(), (data[0x81B7] or 0) & 0xFF, (data[0x81B8] or 0) & 0xFF,
		(data[0x80F5] or 0) & 0xFF, bdump(20)))
end
local function dumpbig(tag)
	print(string.format("DUMP %s 0x8154..0x8300: %s", tag, bdump(0x8300 - 0x8154 + 1)))
end

local function push(code, label, hold, gap, act)
	keys[#keys + 1] = { code = code, label = label, hold = hold or 16000, gap = gap or 16000, act = act }
end

-- === Phase A: does Right (token 0xE2) INC 0x8114 unconditionally (ROM 0x6192-0x6196)?
push(AC, "A-AC")
push(K1, "A-1")
push(K2, "A-2")
for i = 1, 8 do push(RIGHT, "A-R" .. i, 16000, 16000, "sample") end
push(LEFT, "A-L1", 16000, 16000, "sample")
push(LEFT, "A-L2", 16000, 16000, "sample")
push(RIGHT, "A-R9", 16000, 16000, "sample")
-- === Phase B: build a 99-byte history entry "1+1+...+1" (50 ones, 49 pluses = 99B), EXE
push(AC, "B-AC")
for i = 1, 50 do push(K1, "B-1-" .. i, 12000, 12000); if i < 50 then push(PLUS, "B-+" .. i, 12000, 12000) end end
push(EXE, "B-EXE", 24000, 30000, "sample")
push(AC, "B-AC2", 16000, 24000, "sample")
dumpbig("B-after-EXE-AC")
-- === Phase C: RCL into EMPTY input (overwrite or insert?)
push(RCL, "C-RCL-empty", 16000, 24000, "sample")
dumpbig("C-after-RCL-empty")
push(AC, "C-AC", 16000, 24000, "sample")
-- === Phase D: RCL into NON-EMPTY input ("12") — concatenation would give 2+99=101
push(K1, "D-1", 16000, 16000, "sample")
push(K2, "D-2", 16000, 16000, "sample")
push(RCL, "D-RCL-into-12", 16000, 24000, "sample")
dumpbig("D-after-RCL-into-12")
-- === Phase E: history-up (0x27) into non-empty input
push(AC, "E-AC", 16000, 24000, "sample")
push(K1, "E-1", 16000, 16000, "sample")
push(K2, "E-2", 16000, 16000, "sample")
push(UP, "E-UP-into-12", 16000, 24000, "sample")
dumpbig("E-after-UP-into-12")
-- === Phase F: if anything placed >100 bytes, trigger AC,LEFT,EXE and measure flood period
push(AC, "F-AC", 16000, 24000, "sample")
push(LEFT, "F-LEFT", 16000, 16000, "sample")
push(EXE, "F-EXE", 24000, 30000, "sample")

addposttick(function()
	T = T + 1
	if phase == "type" then
		if state == "idle" then
			ki = ki + 1
			if ki > #keys then
				phase = "final"
				print(string.format("DONE typing maxlen8114=%d slen=%d blen=%d", maxlen, slen(), blen()))
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
				if cur.act == "sample" or true then sample(cur.label) end
				state = "idle"
			end
		end
	elseif phase == "final" then
		final_t = final_t + 1
		if final_t == 1 then
			print(string.format("FINAL slen=%d blen=%d len8114=%d maxlen8114=%d pc=%04X sp=%04X",
				slen(), blen(), (data[0x8114] or 0) & 0xFF, maxlen, cpu.pc, cpu.sp))
			-- measure flood period if trigger ran: sample a few addresses mod slen
			local L = slen()
			if L >= 100 then
				local ok, bad = true, 0
				for a = 0x8240, 0x8DF8, 7 do
					local want = (data[0x8154 + ((a - 0x8154) % L)] or 0) & 0xFF
					local got = (data[a] or 0) & 0xFF
					if want ~= got then bad = bad + 1 end
				end
				print(string.format("FLOODCHECK period=%d mismatches(7-step sample)=%d", L, bad))
			end
			dumpbig("FINAL")
		end
		if final_t > 400000 then
			print(string.format("FINAL2 t=%d slen=%d len8114=%d pc=%04X sp=%04X", final_t, slen(),
				(data[0x8114] or 0) & 0xFF, cpu.pc, cpu.sp))
			local L = slen()
			if L >= 100 then
				local bad = 0
				for a = 0x8240, 0x8DF8, 7 do
					local want = (data[0x8154 + ((a - 0x8154) % L)] or 0) & 0xFF
					if want ~= ((data[a] or 0) & 0xFF) then bad = bad + 1 end
				end
				print(string.format("FLOODCHECK2 period=%d mismatches=%d", L, bad))
			end
			dumpbig("FINAL2")
			emu:set_paused(true)
			phase = "done"
		end
	end
end)
