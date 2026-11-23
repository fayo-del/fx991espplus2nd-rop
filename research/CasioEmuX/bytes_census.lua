-- bytes_census.lua — RUN: full data-RAM cartography of typed stores (Ans,
-- variables A/X/Y/M via STO, MODE editors). Physical keys only. Diff 0x8000..0x8DFF per mark.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

data:addr_region(0x8000); data:addr_region(0x87D0); data:addr_region(0x8E00)

local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, RIGHT, RCL =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x37, 0x24
local T = 0

local D = { ["1"]=0x00, ["2"]=0x10, ["3"]=0x20, ["4"]=0x01, ["5"]=0x11,
	["6"]=0x21, ["7"]=0x02, ["8"]=0x12, ["9"]=0x22, ["0"]=0x64 }

local seq, snap, cur = {}, nil, nil
local si, state, hold_t, gap_t, marks = 0, "idle", 0, 0, 0

local function push(code, label, hold, gap)
	seq[#seq + 1] = { code = code, label = label or "", hold = hold or 16000, gap = gap or 20000 }
end
local function mark(tag) seq[#seq + 1] = { dump = tag }; marks = marks + 1 end
local function dpush(str) for c in str:gmatch("%d") do push(D[c]) end end

push(AC, "warm", 12000, 24000)
mark("WarmAC")

-- PH1: Ans number format
dpush("1234567890"); push(EXE, "ansEval", 24000, 40000)
mark("Ans")

-- PH2: variables via STO (value SHIFT RCL var-key; A=0x04 X=0x33 Y=0x43 M=0x53)
local function sto(str, varkey, mod)
	dpush(str)
	push(SHIFT, "s", 16000, 16000)
	push(RCL, "rcl", 16000, 16000)
	if mod then push(ALPHA, "amod", 16000, 16000) end
	push(varkey, "v", 16000, 24000)
	mark("STO " .. str .. "->04")
end
sto("19", 0x04)
sto("88", 0x04, true)
dpush("345678901234"); sto("X12d", 0x33)
sto("66", 0x33, true)
sto("6", 0x43)
sto("7", 0x33)
sto("5", 0x53)
push(SHIFT, "sM2", 16000, 16000); push(0x53, "Mkey", 16000, 24000); mark("SHIFT-M")

-- PH3: MODE editor probes
local function modeProbe(digit, tag)
	push(MODE, "mode", 30000, 40000)
	push(digit, "digit", 30000, 40000)
	mark("M" .. tag .. "-open")
	dpush("1"); push(EXE, "rowexe", 24000, 40000)
	mark("M" .. tag .. "-r1")
	dpush("7891"); push(EXE, "row2exe", 24000, 40000)
	mark("M" .. tag .. "-r2")
	push(AC, "ac", 16000, 24000)
	mark("M" .. tag .. "-AC")
end
modeProbe(D["3"], "3")
modeProbe(D["2"], "2")
modeProbe(D["6"], "6")
modeProbe(D["7"], "7")
modeProbe(D["5"], "5")
mark("END-MODES")

push(MODE, "modefin", 30000, 40000)
push(D["1"], "comp", 30000, 40000)
push(AC, "acc", 16000, 24000)
mark("END")

local function diffspans()
	local out, s, prev = {}, nil, nil
	for a = 0x8000, 0x8DFF do
		local v = (data[a] or 0) & 0xFF
		if v ~= (snap and snap[a] or 0) then
			if s then
				if a == prev + 1 then prev = a
				else out[#out + 1] = string.format("%04X-%04X", s, prev); s, prev = a, a end
			else s, prev = a, a end
		end
	end
	if s then out[#out + 1] = string.format("%04X-%04X", s, prev) end
	return table.concat(out, " ")
end
local function hx(lo, n)
	local out = {}
	for a = lo, lo + n - 1, 24 do
		local l = string.format("%04X ", a)
		for i = 0, 23 do l = l .. string.format("%02X", (data[a + i] or 0) & 0xFF) end
		out[#out + 1] = l
	end
	return table.concat(out, "\n")
end

addposttick(function()
	T = T + 1
	if state == "idle" then
		si = si + 1
		if si > #seq then
			emu:set_paused(true)
			print("CENSUS-DONE pc=" .. string.format("%04X", cpu.pc))
			print("FINAL-8100-8DFF\n" .. hx(0x8100, 0xD00))
			return
		end
		cur = seq[si]
		if cur.dump then
			print(string.format("SNAP[%s] diff=%s", cur.dump, diffspans()))
			snap = {}
			for a = 0x8000, 0x8DFF do snap[a] = (data[a] or 0) & 0xFF end
		else
			Keyboard:PressKey(cur.code)
			state = "press"; hold_t = cur.hold
		end
	elseif state == "press" then
		hold_t = hold_t - 1
		if hold_t <= 0 then Keyboard:ReleaseAll(); state = "rel"; gap_t = cur.gap; end
	elseif state == "rel" then
		gap_t = gap_t - 1
		if gap_t <= 0 then state = "idle" end
	end
end)
