-- Diagnosis: SETUP-menu digit-2 inertness on CY-845 (emu-mode keyboard).
-- Measures, per tick: cpu.pc histogram (baseline idle vs during digit-2 press),
-- the emu keyboard registers 0x8E00-0x8E02, the 0xF040 KI region, and the input
-- buffer. Sequence: warm SHIFT/AC -> SHIFT/MODE (menu open) -> baseline pc-hist
-- -> digit-2 hold (pc-hist + reg sampling) -> input-buffer check.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local pc_hist, pc_cur = {}, {}
local reg_log = {}
local T = 0
local pchist_base, pchist_press = {}, {}

local function addhist(t, pc)
	t[pc] = (t[pc] or 0) + 1
end
local function dump_mode(name, t)
	local s = {}
	for pc, cnt in pairs(t) do
		s[#s + 1] = string.format("%04X:%d", pc, cnt)
	end
	table.sort(s, function(a, b)
		local na, nb = tonumber(a:match("(%x+):")), tonumber(b:match("(%x+):"))
		return (na or 0) < (nb or 0)
	end)
	print("PCMAP " .. name .. " {" .. table.concat(s, ", ") .. "}")
end

local SHIFT, MODE, K2, AC = 0x07, 0x47, 0x10, 0x42
local stage = "boot"
local hold_t, gap_t, press = 0, 0, nil
local reg_start, reg_end = "", ""

addposttick(function()
	T = T + 1
	-- continuously follow the emu keyboard regs
	if #reg_log < 40 then
		local v = string.format("%02X%02X%02X", data[0x8E00] or 0, data[0x8E01] or 0, data[0x8E02] or 0)
		local entry = v .. " stage=" .. tostring(stage) .. " t=" .. tostring(T)
		if #reg_log == 0 or reg_log[#reg_log] ~= entry then
			reg_log[#reg_log + 1] = entry
		end
	end

	if stage == "boot" then
		if T == 1 then Keyboard:PressKey(SHIFT) end
		if T == 17001 then Keyboard:ReleaseAll(); stage = "ac"; press = AC; hold_t = 12000 end
	elseif stage == "ac" then
		addhist(pc_cur, cpu.pc); pc_cur = {}
		Keyboard:PressKey(press)
		hold_t = hold_t - 1
		if hold_t <= 0 then Keyboard:ReleaseAll(); stage = "shift"; hold_t = 16000; T_wait = 0 end
	elseif stage == "shift" then
		addhist(pc_cur, cpu.pc); pc_cur = {}
		Keyboard:PressKey(SHIFT)
		hold_t = hold_t - 1
		if hold_t <= 0 then Keyboard:ReleaseAll(); stage = "mode"; hold_t = 16000 end
	elseif stage == "mode" then
		addhist(pc_cur, cpu.pc); pc_cur = {}
		Keyboard:PressKey(MODE)
		hold_t = hold_t - 1
		if hold_t <= 0 then
			Keyboard:ReleaseAll(); stage = "menu-settle"; hold_t = 120000
			pc_hist, pchist_base = {}, nil
		end
	elseif stage == "menu-settle" then
		-- baseline pc histogram with the menu open, no key pressed
		addhist(pchist_base or pc_hist, cpu.pc)
		hold_t = hold_t - 1
		if hold_t <= 0 then
			pchist_base = pc_hist
			pc_hist = {}
			dump_mode("menu-idle", pchist_base)
			stage = "press2"; hold_t = 60000
			reg_start = string.format("%02X%02X%02X", data[0x8E00] or 0, data[0x8E01] or 0, data[0x8E02] or 0)
		end
	elseif stage == "press2" then
		addhist(pc_hist, cpu.pc)
		if hold_t == 60000 or hold_t == 59000 or hold_t == 58000 then
			Keyboard:PressKey(K2)
		end
		reg_end = string.format("%02X%02X%02X", data[0x8E00] or 0, data[0x8E01] or 0, data[0x8E02] or 0)
		hold_t = hold_t - 1
		if hold_t <= 0 then
			Keyboard:ReleaseAll()
			dump_mode("during-2-press", pc_hist)
			print(string.format("REGBEFORE press2: %s  REGENDDURING: %s", reg_start, reg_end))
			print("REGLOG:")
			for _, l in ipairs(reg_log) do print("  " .. l) end
			stage = "after2"; hold_t = 80000; pc_hist = {}
		end
	elseif stage == "after2" then
		addhist(pc_hist, cpu.pc)
		hold_t = hold_t - 1
		if hold_t <= 0 then
			dump_mode("after-2-release", pc_hist)
			-- input-buffer check: did 2 land anywhere?
			local blen, s = 0, ""
			while blen <= 99 and (data[0x8154 + blen] or 0) ~= 0 do
				s = s .. string.format("%02X", data[0x8154 + blen]); blen = blen + 1
			end
			print(string.format("INPUTBUF len=%d buf=%s", blen, s))
			-- LCD row2 before/after compare is done visually by the caller prints
			emu:set_paused(true)
		end
	end
end)
