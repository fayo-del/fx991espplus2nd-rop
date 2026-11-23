-- bytes_chain.lua — FINAL RUN: chain-readability proof for the typed stores.
-- A) type tokens (input 0x8154), commit (cache 0x81B8 + journal 0x8230..)
-- B) kick memcpy12 gadget chain dst ER2=0x87D0, r0=32 -> copy 384 B from the typed store
--    into the render window; print verbatim window + store readback + LCD rows.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

data:addr_region(0x8154); data:addr_region(0x8900); data:addr_region(0x8A00)

local function envhex(name, def) return tonumber(os.getenv(name) or def) end
local SRC1, SRC2, SRC3 = envhex("SRC1", 0x8154), envhex("SRC2", 0x81B8), envhex("SRC3", 0x8900)

local SHIFT, ALPHA, MODE, EXE, AC, DEL, LEFT, RCL =
	0x07, 0x17, 0x47, 0x60, 0x42, 0x32, 0x26, 0x24
local marks = 0
local D = { ["1"]=0x00, ["2"]=0x10, ["3"]=0x20, ["4"]=0x01, ["5"]=0x11,
	["6"]=0x21, ["7"]=0x02, ["8"]=0x12, ["9"]=0x22, ["0"]=0x64 }

local seq = {}
local function push(code, label, hold, gap)
	seq[#seq + 1] = { code = code, label = label or "", hold = hold or 16000, gap = gap or 20000 }
end
local function mark(tag) seq[#seq + 1] = { dump = tag }; marks = marks + 1 end
local function dpush(str) for c in str:gmatch("%d") do push(D[c]) end end

-- Phase A typing: varied tokens -> input; EXE commits to cache+journal
push(AC, "warm", 12000, 24000)
dpush("1"); push(0x30, "plus"); dpush("3"); push(0x40, "minus"); dpush("5")
push(0x63, "dot"); dpush("7"); push(0x23, "open"); dpush("9"); push(0x33, "close")
dpush("2"); push(0x41, "div"); dpush("4"); push(0x31, "mul"); dpush("6")
push(0x53, "M"); push(0x04, "A"); push(0x04, "A2"); push(0x04, "A3"); push(0x04, "A4")
mark("INPUT-36")
push(EXE, "commit1", 24000, 40000)
mark("COMMIT-INPUT36")

local T, si, state, hold_t, gap_t, marks, cur = 0, 0, "idle", 0, 0, 0, nil
local phase, sub, FW_PC, FW_SP = 0, 0, 0x75C0, 0x8DDC
local snap = {}
local function hx(lo, n)
	local out = {}
	for a = lo, lo + n - 1, 24 do
		local l = string.format("%04X ", a)
		for i = 0, 23 do l = l .. string.format("%02X", (data[a + i] or 0) & 0xFF) end
		out[#out + 1] = l
	end
	return table.concat(out, "\n")
end
local function lcdrows(nrow)
	local out = {}
	for r = 0, (nrow or 8) - 1 do
		local l = string.format("LCD%02d ", r)
		for i = 0, 15 do l = l .. string.format("%02X", (data[0xF800 + r * 16 + i] or 0) & 0xFF) end
		out[#out + 1] = l
	end
	return table.concat(out, "\n")
end
local function kick(src)
	local DST, CH, POPPC, CPY, PARK = 0x87D0, 0x8C80, 0x2B1E, 0x35BE, 0x4EF2
	for a = CH, CH + 0x1B do data[a] = 0x00 end
	local function wr16(a, v) data[a] = v & 0xFF; data[a + 1] = (v >> 8) & 0xFF end
	local function wr32(a, v) wr16(a, v); wr16(a + 2, 0) end
	wr32(CH + 0x00, CPY); wr32(CH + 0x04, src)
	wr32(CH + 0x08, 0); wr32(CH + 0x0C, 0); wr32(CH + 0x12, PARK)
	cpu.csr = 0; cpu.sp = CH; cpu.pc = POPPC; cpu.lr = POPPC
	cpu.r0 = 32
	cpu.r2 = DST & 0xFF; cpu.r3 = (DST >> 8) & 0xFF
	emu:SetClockSpeed(16)
end
local function restore()
	emu:SetClockSpeed(1)
	cpu.pc, cpu.sp, cpu.csr = FW_PC, FW_SP, 0
end

-- PARK-break capture: the chain parks at 0x4EF2 right after memcpy12 finishes;
-- sample the window the instant the copy lands (before any app redraw).
local pend, pendwait, CURN, CURSRC = nil, 0, 0, 0
break_at(0x4EF2, function()
	if pend == nil and (phase == 2 or phase == 4 or phase == 6) then
		CURN = (phase == 2) and 1 or (phase == 4) and 2 or 3
		CURSRC = (CURN == 1) and SRC1 or (CURN == 2) and SRC2 or SRC3
		print(string.format("PARK-HIT%d src=%04X window-at-park:\n%s", CURN, CURSRC, hx(0x87D0, 384)))
		print(string.format("PARK-HIT%d src-readback:\n%s", CURN, hx(CURSRC, 384)))
		pend, pendwait = CURN, 0
	end
	emu:set_paused(false)
end)

addposttick(function()
	T = T + 1
	if pend then
		pendwait = pendwait + 1
		if pendwait == 500 then
			print(string.format("PARK-HIT%d LCD-after-500:\n%s", pend, lcdrows(24)))
			local done = pend
			pend = nil
			restore()
			if done == 3 then
				print("CHAIN-DONE")
				emu:set_paused(true)
			else
				phase = done * 2 + 1
				sub = 0
			end
		end
		return
	end
	if phase == 0 then
		-- typing phase: drain seq, then kick the chain from the store
		if state == "idle" then
			si = si + 1
			if si > #seq then
				phase = 1; sub = 0
				snap = {}
				for a = 0x8000, 0x8DFF do snap[a] = (data[a] or 0) & 0xFF end
				print("STORE-FILLED pc=" .. string.format("%04X", cpu.pc))
				print("INPUT-8154:\n" .. hx(0x8154, 100))
				print("CACHE-81B8:\n" .. hx(0x81B8, 100))
				print("JOURNAL-8230:\n" .. hx(0x8230, 64))
				print("REC-8398:\n" .. hx(0x8398, 48))
				emu:SetClockSpeed(1)
				return
			end
			cur = seq[si]
			if cur.dump then
				print(string.format("SNAP[%s]", cur.dump))
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
	elseif phase == 1 then
		-- settle 100k ticks after typing, check store stability, then kick #1
		sub = sub + 1
		if sub == 100000 then
			local n = 0
			for a = 0x8900, 0x894F do if (data[a] or 0) & 0xFF ~= snap[a] then n = n + 1 end end
			print("SETTLED diff-8900=" .. n)
			SRC = SRC1
			kick(SRC1)
			phase = 2; sub = 0
		end
	elseif phase == 2 then
		sub = sub + 1
		if sub == 200 then
			print("KICK1-SRC-8154 window:\n" .. hx(0x87D0, 384))
			print("KICK1 readback:\n" .. hx(SRC1, 384))
			print("KICK1 " .. lcdrows(6))
		elseif sub == 100000 then
			print("KICK1+100k window0:\n" .. hx(0x87D0, 48) .. "\nKICK1+100k " .. lcdrows(3))
			restore()
			phase = 3; sub = 0
		end
	elseif phase == 3 then
		sub = sub + 1
		if sub == 2000 then
			kick(SRC2)
			phase = 4; sub = 0
		end
	elseif phase == 4 then
		sub = sub + 1
		if sub == 200 then
			print("KICK2-SRC-81B8 window:\n" .. hx(0x87D0, 384))
			print("KICK2 readback:\n" .. hx(SRC2, 384))
			print("KICK2 " .. lcdrows(6))
		elseif sub == 100000 then
			print("KICK2+100k window0:\n" .. hx(0x87D0, 48) .. "\nKICK2+100k " .. lcdrows(3))
			restore()
			phase = 5; sub = 0
		end
	elseif phase == 5 then
		sub = sub + 1
		if sub == 2000 then
			kick(SRC3)
			phase = 6; sub = 0
		end
	elseif phase == 6 then
		sub = sub + 1
		if sub == 200 then
			print("KICK3-SRC-8900 window:\n" .. hx(0x87D0, 384))
			print("KICK3 readback:\n" .. hx(SRC3, 384))
			print("KICK3 " .. lcdrows(6))
		elseif sub == 100000 then
			print("KICK3+100k window0:\n" .. hx(0x87D0, 48) .. "\nKICK3+100k " .. lcdrows(3))
			restore()
			print("CHAIN-DONE")
			emu:set_paused(true)
		end
	end
end)
