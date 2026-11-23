-- more09_abab.lua: adversarial test (b) -- payload with an INTERNAL period (ABAB x50).
-- Recipe = rop_e2e.lua verbatim (41-key typed queue from T=1; final-phase Right+AC, LEFT,
-- payload plant at final_t==36001, EXE at 40001).  Payload = 0x41,0x42 alternating x50
-- (minimal period 2, zero-free).  Question: does the flood keep period-100 anchoring
-- (flood[a] == PAY[(a-0x8154)%100]) or shrink to the string's minimal period?
-- At flood completion dump and analyze the FULL span 0x8154..0x8DFF, aliases, 0x8E00+.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")

local T = 0
local SHIFT, ALPHA, MODE, CALC, EXE, AC, DEL, LEFT, DOWN, K1, K2, K9, KX10 =
	0x07, 0x17, 0x47, 0x06, 0x60, 0x42, 0x32, 0x26, 0x36, 0x00, 0x10, 0x22, 0x62
local PAY_IN = 0x8154
local OUT = "/home/yoxu/Projects/fx991espplus2nd/research/CasioEmuX/"

-- ABAB payload: PAY[i] = 0x41 (even i) / 0x42 (odd i), minimal period 2
local PAY = {}
for i = 0, 99 do PAY[i] = (i % 2 == 0) and 0x41 or 0x42 end

local keys, ki = {}, 0
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local phase, final_t, snap0 = "type", 0, {}
local flood_t, analyzed, pop2b1e = nil, false, 0

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
local function chord(mod, code, label, expect)
	push(mod, label .. "/mod", nil, 16000, 16000)
	push(code, label, expect, 16000, 16000)
end

-- ===== typed queue: rop_e2e.lua verbatim =====
push(SHIFT, "w1", nil, 12000, 12000); push(AC, "w2", nil, 12000, 24000)
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
push(CALC, "CALC", nil, 16000, 24000)
push(EXE, "EXE", nil, 24000, 30000)
push(AC, "AC", nil, 16000, 24000)
push(LEFT, "LEFT", nil, 16000, 16000)
push(DEL, "DEL1", nil, 16000, 12000)
push(DEL, "DEL2", nil, 16000, 12000)
push(DEL, "DEL3", nil, 16000, 12000)
push(K2, "two", { { 0x32 } })
push(CALC, "CALC2", nil, 16000, 24000)
push(EXE, "EXE2", nil, 24000, 30000)
push(LEFT, "LEFT2", nil, 16000, 20000)
push(K1, "PROBE1", nil, 16000, 16000)

break_at(0x2B1E, function()
	if phase == "final" and final_t > 40001 then
		pop2b1e = pop2b1e + 1
		if pop2b1e <= 3 then
			print(string.format("POP2B1E post-EXE #%d: pc=%04X sp=%04X dsr=%02X", pop2b1e, cpu.pc, cpu.sp, cpu.dsr))
		end
	end
	emu:set_paused(false)
end)

local SAMPLES = { 0x81B8, 0x8600, 0x8A00, 0x8C70, 0x8DF0, 0x8DFF }
local function sample_ok()
	for _, a in ipairs(SAMPLES) do
		if (data[a] or 0) ~= PAY[(a - PAY_IN) % 100] then return false end
	end
	return true
end

local function hexr(a, n)
	local s = ""
	for i = 0, n - 1 do s = s .. string.format("%02X", (data[a + i] or 0) & 0xFF) end
	return s
end

local function analyze()
	-- (c) full-span rescan 0x8154..0x8DFF vs payload periodic extension
	local mism, mism_list = 0, {}
	local distinct = {}
	for a = 0x8154, 0x8DFF do
		local v = (data[a] or 0) & 0xFF
		distinct[v] = true
		local e = PAY[(a - PAY_IN) % 100]
		if v ~= e then
			mism = mism + 1
			if #mism_list < 60 then mism_list[#mism_list + 1] = string.format("%04X(exp%02X,got%02X)", a, e, v) end
		end
	end
	local dlist, nd = {}, 0
	for v in pairs(distinct) do dlist[#dlist + 1] = v; nd = nd + 1 end
	table.sort(dlist)
	local ds = ""
	for _, v in ipairs(dlist) do ds = ds .. string.format("%02X ", v) end
	print(string.format("SPAN-CHECK: 0x8154..0x8DFF (3244 bytes) mismatches=%d distinct-values=%d", mism, nd))
	if mism > 0 then print("MISMATCHES: " .. table.concat(mism_list, " ")) else print("MISMATCHES: none -- every a matches PAY[(a-0x8154)%%100]") end
	print("DISTINCT-VALUES-IN-SPAN: " .. ds)

	-- minimal period of the flooded span
	local mp = nil
	for p = 1, 100 do
		local ok = true
		for a = 0x8154, 0x8DFF - p do
			if (data[a] or 0) ~= (data[a + p] or 0) then ok = false; break end
		end
		if ok then mp = p; break end
	end
	print(string.format("SPAN-MINIMAL-PERIOD: %s", tostring(mp)))

	-- payload self-check: minimal period of PAY, distinct count
	local pdistinct = {}
	for i = 0, 99 do pdistinct[PAY[i]] = true end
	local pnd = 0; for _ in pairs(pdistinct) do pnd = pnd + 1 end
	local pp = nil
	for p = 1, 100 do
		local ok = true
		for i = 0, 99 - p do if PAY[i] ~= PAY[i + p] then ok = false; break end end
		if ok then pp = p; break end
	end
	print(string.format("PAYLOAD: distinct=%d minimal-period=%s first32=%s", pnd, tostring(pp), bdump(32)))

	-- 0x8100..0x8153 vs pre-trigger snapshot
	local chg, chglist = 0, {}
	for a = 0x8100, 0x8153 do
		if (data[a] or 0) ~= (snap0[a] or 0) then chg = chg + 1; if #chglist < 40 then chglist[#chglist + 1] = string.format("%04X(%02X->%02X)", a, snap0[a] or 0, data[a] or 0) end end
	end
	print(string.format("PRE-INPUT 0x8100..0x8153 changed-vs-pretrigger=%d %s", chg, table.concat(chglist, " ")))

	-- whole-RAM distinct 0x8000..0x8DFF
	local wall = {}
	for a = 0x8000, 0x8DFF do wall[(data[a] or 0) & 0xFF] = true end
	local wnd = 0; for _ in pairs(wall) do wnd = wnd + 1 end
	print(string.format("WHOLE-RAM-DISTINCT 0x8000..0x8DFF = %d (includes non-attacker 0x8000..0x8153)", wnd))

	-- (d) alias reads
	print(string.format("ALIAS: data[0x8154]=%02X data[0x18154](seg1)=%02X data[0x28154](seg2)=%02X data[0x98154]=%02X",
		data[0x8154] or 0, data[0x18154] or 0, data[0x28154] or 0, data[0x98154] or 0))
	print(string.format("ALIAS: seg1 0x18154..0x18163 = %s | seg0 RAM 0x8154..0x8163 = %s", hexr(0x18154, 16), hexr(0x8154, 16)))
	print(string.format("ALIAS: shim 0x9800..0x980F post = %s (pre = %s)", hexr(0x9800, 16), (function() local s="" for i=0,15 do s=s..string.format("%02X", snap0[0x9800+i] or 0) end return s end)()))

	-- (e) 0x8E00+ post-trigger (0x8E00-0x8E02 = keyboard MMIO emu regions; read only now, keys done)
	print(string.format("POST-8E00: 0x8E00..0x8E1F = %s", hexr(0x8E00, 32)))
	print(string.format("POST-8E00: 0x9800..0x981F (shim alias) = %s", hexr(0x9800, 32)))
	print(string.format("POST-8E00: 0x8E00 pre-trigger was snap0-untracked (MMIO); 0x8E03..0x8E1F unmapped-in-seg0 read as above"))
	print(string.format("STATE: pc=%04X sp=%04X dsr=%02X csr=%d pop2b1e-postEXE=%d flood_final_t=%s", cpu.pc, cpu.sp, cpu.dsr, cpu.csr, pop2b1e, tostring(flood_t)))

	-- dumps for offline verification
	local f = io.open(OUT .. "more09_abab_post.bin", "wb")
	for a = 0x8000, 0x98FF do f:write(string.char((data[a] or 0) & 0xFF)) end
	f:close()
	f = io.open(OUT .. "more09_abab_payload.bin", "wb")
	for i = 0, 99 do f:write(string.char(PAY[i])) end
	f:close()
	f = io.open(OUT .. "more09_abab_pre.bin", "wb")
	for a = 0x8000, 0x98FF do f:write(string.char(snap0[a] or 0)) end
	f:close()
	print("DUMPS: more09_abab_post.bin / _payload.bin / _pre.bin written (0x8000..0x98FF)")
end

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
				print("SCREEN: ---- " .. cur.render .. " ----")
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
					print(string.format("SIGMA: %s len=%d bare=%s", lb, n, tostring(bare)))
				elseif lb == "PROBE1" then
					print(string.format("PROBE1: len=%d (must not grow past pre-overflow)", blen()))
				end
				state = "idle"
			end
		end
	elseif phase == "final" then
		final_t = final_t + 1
		if final_t == 1 then
			for a = 0x8000, 0x8DFF do snap0[a] = (data[a] or 0) & 0xFF end
			for a = 0x9800, 0x98FF do snap0[a] = (data[a] or 0) & 0xFF end
			-- marker in stack area: must be overwritten by the flood
			data[0x8C70] = 0xDE; data[0x8C71] = 0xAD
			print("PRE: snap0 taken; marker DE AD at 0x8C70; 0x8C70 pre=" .. string.format("%02X%02X", data[0x8C70], data[0x8C71]))
			Keyboard:PressKey(0x37)
			Keyboard:PressKey(AC)
		elseif final_t == 16001 then
			Keyboard:ReleaseAll()
		elseif final_t == 20001 then
			Keyboard:PressKey(LEFT)
		elseif final_t == 36001 then
			Keyboard:ReleaseAll()
			for i = 0, 99 do data[PAY_IN + i] = PAY[i] end
			print("INPUT: diverse payload planted, len=" .. blen() .. " buf=" .. bdump(32))
		elseif final_t == 40001 then
			Keyboard:PressKey(0x60)   -- EXE: triggers the strcpy flood
		elseif final_t == 60001 then
			Keyboard:ReleaseAll()
		end
		if final_t > 40001 and not flood_t then
			if sample_ok() then
				flood_t = final_t
				print(string.format("FLOOD-DETECTED: final_t=%d pc=%04X sp=%04X dsr=%02X marker@8C70 now %02X%02X",
					final_t, cpu.pc, cpu.sp, cpu.dsr, data[0x8C70] or 0, data[0x8C71] or 0))
			end
		elseif flood_t and not analyzed and final_t >= flood_t + 300 then
			analyzed = true
			Keyboard:ReleaseAll()
			analyze()
			print("VERDICT-DONE: paused after analysis")
			emu:set_paused(true)
			phase = "done"
		elseif not flood_t and final_t > 40001 + 3000000 then
			print(string.format("NO-FLOOD: final_t=%d pc=%04X sp=%04X buf=%s", final_t, cpu.pc, cpu.sp, bdump(32)))
			emu:set_paused(true)
			phase = "done"
		end
	end
end)
