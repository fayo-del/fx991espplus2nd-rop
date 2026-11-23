-- real03_complete.lua — COMPLETE game (move + erase + score + game-over park) from the
-- typed hackstring ROP chain, on the real01_game2d skeleton.
--
-- GAME: 1-byte cell on the LCD (dst = ER2 = 0xF8|POS). POS persists in RAM 0x8BBD
--   (payload[65] = initial 0x30). Per pass (steady loop, pivot 0x75DE re-arms SP=0x8DA4):
--     b? erase old cell : 0x14CA2 (b1) ST R0,[ER2]; MOV R0,#0   (r0=0, ER2=old dst)
--     keyscan 0x4D0E      -> r2 = KID (7F=Right/Up, BF=Left/Down, FF=none)
--     0x3722/0x16E0C      -> r0 = POS_old ; 0x4AA8 SUB R0,R2 -> r0 = POS' = POS-KID
--     0x49C2/0x4292       -> ER2 = 0xF8|POS' (persists to next pass) ; 0x14CA2 DRAW byte=POS'
--     0x3722/0x2B20       -> mem[0x8BBD] = POS'
--     reload POS' ; 0x3A50 CMP R0,#1;BC -> r0 = 0 iff POS'==0x01 (WALL) else 1
--     0x3066/0x10470C     -> store flag at gate tile's csr-lo (0x8DEE): 0 -> bank0 -> 0x4EF2 PARK
--     gate tile 0x4EF2 (csr-lo=0x01 -> bank1 0x14EF2 POP XR4; POP PC) ; primer ; pivot
--   SCORE = pass counter (survival); WALL = POS'==0x01 -> game over -> park 0x4EF2.
--
-- Harness: typed trigger queue identical to rop_e2e.lua / real01_game2d.lua (PressKey
-- from T=1), payload equipped pre-trigger at 0x8154 (documented stand-in for the HW
-- overflow+flash-walk delivery), then AC,LEFT,EXE typed -> strcpy flood -> chain.
-- PLAYER = pass-driven arrow schedule (PressKey only). No data[] writes post-trigger.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")
local SCHED = "L" .. string.rep("N", 170)
local T = 0
local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, DOWN, K1, K2, K9, KX10 =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x36, 0x00, 0x10, 0x22, 0x62
local PAY_IN = 0x8154
local POS_ADDR = 0x8BBD
local PAYHEX = "22370E4DBD8B0C6E014D503A0E4D66300E4DEE8D0C47014DF24E014D0E0E0E0E66300E4DA48DDE750E4D0E0E66300E4DA48DDE75A48DA24C014D0E4D0E4D22370E30BD8B0C6E014DA84A0E4DC2490E4D0CF892420E4DA24C014D22370E4DBD8B202B0E4D"

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase, final_t = "type", 0
local scan_hits = 0
local lineio = false
PIVN = 0
PASSN = 0
PARKED = false
cur_key = "Right@trigger"

local function blen()
	for i = 0, 99 do if (data[0x8154 + i] or 0) == 0 then return i end end
	return 100
end
local function bdump(n)
	local s = ""
	for i = 0, (n or 32) - 1 do s = s .. string.format("%02X", data[0x8154 + i] or 0) end
	return s
end
local function push(code, label, expect, hold, gap)
	keys[#keys + 1] = { code = code, label = label, expect = expect, hold = hold or 16000, gap = gap or 20000 }
end
local function render(tag) keys[#keys + 1] = { render = tag } end
local function render_screen(tag)
	print("SCREEN: ---- " .. tag .. " ----")
	for r = 0, 31 do
		local line = ""
		for b = 0, 11 do
			local v = data[0xF800 + r * 16 + b] or 0
			for bit = 7, 0, -1 do line = line .. (((v >> bit) & 1) == 1 and "#" or ".") end
		end
		print("SCREEN: " .. line)
	end
end
local function chord(mod, code, label, expect)
	push(mod, label .. "/mod", nil, 16000, 16000)
	push(code, label, expect, 16000, 16000)
end
local function lcdrows(r0n, r1n)
	local out = {}
	for rr = r0n, r1n do
		local s = ""
		for i = 0, 11 do s = s .. string.format("%02X", (data[0xF800 + rr * 16 + i] or 0) & 0xFF) end
		out[#out + 1] = s
	end
	return table.concat(out, "|")
end
local function save_frame(name)
	local f = io.open(name, "wb")
	for i = 0, 511 do f:write(string.char((data[0xF800 + i] or 0) & 0xFF)) end
	f:close()
	print("FRAME: saved " .. name)
end

-- warm-up (keys here may be eaten by boot; harmless)
push(SHIFT, "w1", nil, 12000, 12000); push(AC, "w2", nil, 12000, 24000)
-- SETUP open + digit-2 (page-1 select LineIO)
chord(SHIFT, MODE, "setup1")
render("setup1")
push(K2, "setup1-digit2", nil, 30000, 40000)
render("setup1 after 2")
chord(SHIFT, 0x56, "sigma-verify")
chord(SHIFT, MODE, "setup2")
push(K2, "setup2-digit2", nil, 30000, 40000)
render("setup2 after 2")
chord(SHIFT, 0x56, "sigma-verify2")
push(AC, "AC-clear", nil, 16000, 24000)
-- ====== formula: X = Σ(X,1,1×10^9 ======
chord(ALPHA, 0x33, "X1", { { 0x58 } })
chord(ALPHA, CALC, "eq", { { 0x3D } })
chord(SHIFT, 0x56, "Sigma", { { 0x69, 0xB8 } })
chord(ALPHA, 0x33, "X2", { { 0x58 } })
chord(SHIFT, 0x33, "comma1", { { 0x2C } })
push(K1, "one", { { 0x31 } })
chord(SHIFT, 0x33, "comma2", { { 0x2C } })
push(K1, "one2", { { 0x31 } })
push(KX10, "x10", { { 0x74 } })
push(K9, "nine", { { 0x39 } })
render("formula typed")
-- ====== calc = ac <- ======
push(CALC, "CALC", nil, 16000, 24000)
push(EXE, "EXE", nil, 24000, 30000)
push(AC, "AC", nil, 16000, 24000)
push(LEFT, "LEFT", nil, 16000, 16000)
-- ====== del del del 2 ======
push(DEL, "DEL1", nil, 16000, 12000)
push(DEL, "DEL2", nil, 16000, 12000)
push(DEL, "DEL3", nil, 16000, 12000)
push(K2, "two", { { 0x32 } })
-- ====== calc = <- ======
push(CALC, "CALC2", nil, 16000, 24000)
push(EXE, "EXE2", nil, 24000, 30000)
push(LEFT, "LEFT2", nil, 16000, 20000)
push(K1, "PROBE1", nil, 16000, 16000)

function finish(tag)
	print(string.format("PROTO: %s passes=%d pc=%04X sp=%04X piv=%d parked=%s POS=%02X rows0-3=%s",
		tag, PASSN, cpu.pc, cpu.sp, PIVN, tostring(PARKED), data[POS_ADDR] or 0, lcdrows(0, 3)))
	phase = "done"
end

local CSR_SET = {0x0,0x1,0x2,0x3,0x4,0x5,0x6,0x7,0x8,0x9,0xA,0xB,0xC,0xD,0xE,0xF}

-- pass event: walk keyscan RT (0x4D20), one per pass after trigger
local function sched_apply()
	if PASSN < #SCHED then
		local c = SCHED:sub(PASSN + 1, PASSN + 1)
		Keyboard:ReleaseAll()
		if c == "R" then Keyboard:PressKey(0x37); cur_key = "Right"
		elseif c == "L" then Keyboard:PressKey(0x26); cur_key = "Left"
		else cur_key = "none" end
	else
		Keyboard:ReleaseAll(); cur_key = "none"
	end
end
break_at(0x4D20, function()
	scan_hits = scan_hits + 1
	if cpu.lr == 0x2B1E and final_t >= 60001 and not PARKED and phase ~= "done" then
		PASSN = PASSN + 1
		sched_apply()
		local fr = PASSN

		if PASSN <= 40 then
			print(string.format("PASS#%d ft=%d r0=%02X r2(KID)=%02X POS=%02X key=%s lcd0-3=%s",
				PASSN, final_t, cpu.r0 & 0xFF, cpu.r2 & 0xFF, data[POS_ADDR] or 0, cur_key, lcdrows(0, 3)))
		end
	end
	emu:set_paused(false)
end)

-- SUB entry (0x4AA8): r0=POS_old, r2=KID
break_at(0x4AA8, function()
	if cpu.lr == 0x2B1E and final_t >= 60001 and PASSN <= 40 and phase ~= "done" then
		print(string.format("SUB#%d r0(POS_old)=%02X r2(KID)=%02X", PASSN, cpu.r0 & 0xFF, cpu.r2 & 0xFF))
	end
	emu:set_paused(false)
end)

-- 0x14CA2 (b1) ST R0,[ER2]; MOV R0,#0: erase / draw / gate stores
local function mk14CA2()
	return function()
		if cpu.lr == 0x2B1E and final_t >= 60001 and PASSN <= 40 and phase ~= "done" then
			local er2 = (cpu.r3 & 0xFF) * 0x100 + (cpu.r2 & 0xFF)
			local tag = "ST"
			if er2 == 0x8DEE then tag = "GATE" elseif er2 >= 0xF800 then tag = "LCD" end
			print(string.format("%s#%d ER2=%04X r0=%02X POS=%02X", tag, PASSN, er2, cpu.r0 & 0xFF, data[POS_ADDR] or 0))
			if tag == "LCD" and (cpu.r0 & 0xFF) > 1 and phase ~= "done" and not PARKED then
				local fr = PASSN
				if fr == 2 or fr == 5 or fr == 8 or fr == 17 or fr == 30 or fr == 60 or fr == 100 or fr == 140 then
					save_frame(string.format("real03_frame%d.raw", fr))
				end
			end
		end
		emu:set_paused(false)
	end
end
-- 0x2B20 ST R2,[ER0]: POS store
break_at(0x2B20, function()
	if cpu.lr == 0x2B1E and final_t >= 60001 and PASSN <= 40 and phase ~= "done" then
		print(string.format("POSST#%d ER0=%04X r2(POS')=%02X", PASSN,
			(cpu.r1 & 0xFF) * 0x100 + (cpu.r0 & 0xFF), cpu.r2 & 0xFF))
	end
	emu:set_paused(false)
end)
-- 0x3A50 branch: r0 in = POS'
break_at(0x3A50, function()
	if cpu.lr == 0x2B1E and final_t >= 60001 and PASSN <= 40 and phase ~= "done" then
		print(string.format("BR#%d r0(POS')=%02X -> flag %s", PASSN, cpu.r0 & 0xFF,
			((cpu.r0 & 0xFF) == 1) and "WALL(0)" or "ok(1)"))
	end
	emu:set_paused(false)
end)
for _, csr in ipairs(CSR_SET) do
	break_at((csr << 16) | 0x14CA2, mk14CA2())
end
-- pivot
break_at(0x75DE, function()
	PIVN = PIVN + 1
	if final_t >= 60001 and phase ~= "done" and not PARKED then
		local fr = PASSN
		if fr == 2 or fr == 5 or fr == 8 or fr == 11 or fr == 14 or fr == 17 or fr == 30 or fr == 60 or fr == 100 or fr == 140 then
			save_frame(string.format("real03_frame%d.raw", fr))
		end
	end
	emu:set_paused(false)
end)
-- park detection
break_at(0x4EF2, function()
	if final_t >= 60001 and not PARKED then
		PARKED = true
		print(string.format("PARK-ENTRY 0x4EF2 pass=%d ft=%d pc=%04X sp=%04X POS=%02X rows0-3=%s",
			PASSN, final_t, cpu.pc, cpu.sp, data[POS_ADDR] or 0, lcdrows(0, 3)))
		save_frame("real03_framePARK.raw")
	end
	emu:set_paused(false)
end)
break_at(0x4B96, function()
	if final_t >= 60001 and not PARKED then
		PARKED = true
		print(string.format("PARK-SPIN 0x4B96 pass=%d ft=%d POS=%02X", PASSN, final_t, data[POS_ADDR] or 0))
	end
	emu:set_paused(false)
end)

local len_before_probe = nil

addposttick(function()
	T = T + 1
	if phase == "type" then
		if state == "idle" then
			ki = ki + 1
			if ki > #keys then
				phase = "final"
				print("INPUT: typing done len=" .. blen() .. " buf=" .. bdump(48))
				return
			end
			cur = keys[ki]
			if cur.code then
				Keyboard:PressKey(cur.code)
				state = "press"; hold_t = cur.hold
			else
				render_screen(cur.render)
			end
		elseif state == "press" then
			hold_t = hold_t - 1
			if hold_t <= 0 then
				Keyboard:ReleaseAll()
				state = "rel"; gap_t = cur.gap
			end
		elseif state == "rel" then
			gap_t = gap_t - 1
			if gap_t <= 0 then
				local lb = cur.label
				if lb == "sigma-verify" or lb == "sigma-verify2" then
					local n = blen()
					local bare = n >= 2 and (data[0x8154 + n - 2] == 0x69) and (data[0x8154 + n - 1] == 0xB8)
					local boxed = false
					for i = 0, 97 do
						if (data[0x8154 + i] or 0) == 0x21 and (data[0x8154 + i + 1] or 0) == 0xBA then boxed = true; break end
					end
					print(string.format("SIGMA: %s len=%d bare=%s boxed=%s", lb, n, tostring(bare), tostring(boxed)))
					if bare and not boxed then lineio = true end
				elseif lb == "PROBE1" then
					len_before_probe = len_before_probe or blen()
					print(string.format("PROBE1: before=%d after=%d %s", len_before_probe, blen(),
						blen() > len_before_probe and "GREW(bad)" or "NOT-INSERTED(good)"))
				end
				state = "idle"
			end
		end

	elseif phase == "final" then
		final_t = final_t + 1
		if final_t == 1 then
			Keyboard:PressKey(0x37)   -- Right held at trigger
			Keyboard:PressKey(AC)
		elseif final_t == 16001 then
			Keyboard:ReleaseAll()
		elseif final_t == 20001 then
			Keyboard:PressKey(LEFT)
		elseif final_t == 36001 then
			Keyboard:ReleaseAll()
			-- ===== payload: 100 zero-free bytes at 0x8154 (real03 chain) =====
			for i = 0, 99 do
				data[PAY_IN + i] = tonumber(PAYHEX:sub(i * 2 + 1, i * 2 + 2), 16)
			end
			local zf, hex = true, ""
			for i = 0, 99 do
				local b = data[PAY_IN + i] or 0
				if b == 0 then zf = false end
				hex = hex .. string.format("%02X", b)
			end
			local bf = io.open("real03_payload.bin", "wb")
			for i = 0, 99 do bf:write(string.char(data[PAY_IN + i] & 0xFF)) end
			bf:close()
			print("PAYLOAD: len=" .. blen() .. " zerofree=" .. tostring(zf))
			print("PAYHEX: " .. hex)
			print("INPUT: payload planted len=" .. blen() .. " buf=" .. bdump(100))
			print(string.format("INPUT: initial POS[8BBD]=%02X", data[POS_ADDR] or 0))
		elseif final_t == 40001 then
			Keyboard:PressKey(0x37)   -- Right held at the EXE trigger
			Keyboard:PressKey(0x60)   -- EXE: strcpy flood -> chain starts
		elseif final_t == 60001 then
			emu:SetClockSpeed(16)
			Keyboard:ReleaseAll()
			PASSN = 0
			sched_apply()  -- hold SCHED[1] from the walk start
			print("WATCH: 16x, pass-driven key schedule begins")
		elseif final_t > 60001 then
			if (final_t - 60001) % 200000 == 0 then
				print(string.format("WATCH: ft=%d pc=%04X sp=%04X ER2=%04X POS=%02X passes=%d piv=%d parked=%s key=%s rows0-3=%s",
					final_t, cpu.pc, cpu.sp, (cpu.r3 & 0xFF) * 0x100 + (cpu.r2 & 0xFF), data[POS_ADDR] or 0,
					PASSN, PIVN, tostring(PARKED), cur_key, lcdrows(0, 3)))
			end
			if PARKED then
				if not _G.parkt then _G.parkt = final_t + 30000 else
					if final_t >= _G.parkt then finish("GAMEOVER-PARKED") end
				end
			elseif PASSN >= 175 then finish("PASS-LIMIT")
			elseif final_t > 3600000 then finish("NO-TRIGGER") end
		end
	end
end)
