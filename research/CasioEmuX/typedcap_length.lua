-- TYPEDCAP LENGTH: max length of the 0x8154 input line reachable by PURE KEY
-- PRESSES (Keyboard:PressKey only; no memory writes) on fx991esplus2 (CY-845).
-- Phases:
--  1: sweep every keycode 0x00-0x67 x {base, SHIFT+, ALPHA+, ALPHA+SHIFT+} into
--     an EMPTY line (AC-reset before each probe); record strlen(0x8154) before/
--     after and the inserted bytes -> key->expansion table, multi-byte templates.
--  2: cap crossing: fill the line to EXACTLY N single-byte tokens (rotating
--     digit keys; fillto steps re-press until strlen==N because the ROM key
--     scan drops ~half of back-to-back presses), then ONE multi-byte template
--     chord (with delivery retry), N=80..99, for the 13-byte template
--     (SHIFT+0x05) and N=94..99 for the 9-byte base template (0x05); record
--     resulting strlen(0x8154) + full dump 0x8154-0x81C3, then probe singles.
--  3: pure-singles-to-cap reference; template-first + fill to cap; two
--     templates + fill; DEL/INS and mid-line (LEFT) template inserts at the
--     boundary. Track global max strlen and the achieving sequence.
dofile("emulator/lua-common.lua")
io.stdout:setvbuf("no")
emu:SetClockSpeed(16)

local T = 0
local SHIFT, ALPHA, AC, DEL, LEFT = 0x07, 0x17, 0x42, 0x32, 0x26

local q, qi = {}, 1
local state, hold_t, gap_t, cur = "idle", 0, 0, nil
local pre_slen = -1
local fillcnt = 0
local FILLC = { 0x00, 0x10, 0x20, 0x01, 0x11, 0x21, 0x02, 0x12, 0x22 } -- digits 1-9, 1-byte tokens

local maxslen, maxseq = -1, ""
local expansions = {} -- probe tag -> {pre=, post=, d=}

local function slen()
	for i = 0, 0x1AC do if (data[0x8154 + i] or 0) == 0 then return i end end
	return 0x1AD
end
local function lenvar() return (data[0x8114] or 0) & 0xFF end
local function bdump(n, base)
	local s = ""
	for i = 0, (n or 16) - 1 do s = s .. string.format("%02X", (data[(base or 0x8154) + i] or 0) & 0xFF) end
	return s
end
local function push(code, tag, hold, gap)
	q[#q + 1] = { code = code, tag = tag, hold = hold or 24000, gap = gap or 12000 }
end
local function pushfn(f) q[#q + 1] = f end
local function pushfill(n, tag, maxpress)
	q[#q + 1] = { fillto = n, tag = tag or "F", maxpress = maxpress or (math.ceil(n * 2.5) + 12) }
end
local function splice(steps) -- insert at current qi (front of remaining queue)
	for i = #steps, 1, -1 do table.insert(q, qi, steps[i]) end
end

local function reset()
	push(AC, "r"); push(AC, "r"); push(AC, "r")
	push(0x00, "r") -- eat any residual SHIFT/ALPHA latch
	push(AC, "r")
end
local function chordsteps(mods, code, tag)
	local st = {}
	for _, m in ipairs(mods) do st[#st + 1] = { code = m, tag = "m", hold = 30000, gap = 12000 } end
	st[#st + 1] = { code = code, tag = tag, hold = 30000, gap = 16000 }
	return st
end
local function chord(mods, code, tag) for _, s in ipairs(chordsteps(mods, code, tag)) do q[#q + 1] = s end end
-- chord with delivery retry: after the chord key, if strlen grew by less
-- than mindelta, splice the chord again (up to 3 times) right in the queue
local function chordchk(mods, code, tag, mindelta)
	chord(mods, code, tag)
	mindelta = mindelta or 1
	local retries = 0
	local function chk()
		if (slen() - pre_slen) < mindelta and retries < 3 then
			retries = retries + 1
			local st = chordsteps(mods, code, tag .. "r" .. retries)
			splice(st)
			table.insert(q, qi + #st, chk)
		end
	end
	pushfn(chk)
end
-- single key with delivery retry (detected via strlen change)
local function presschk(code, tag, hold, gap)
	push(code, tag, hold or 30000, gap or 12000)
	local retries = 0
	local function chk()
		if slen() == pre_slen and retries < 3 then
			retries = retries + 1
			splice({ { code = code, tag = tag .. "r" .. retries, hold = hold or 30000, gap = gap or 12000 } })
			table.insert(q, qi + 1, chk)
		end
	end
	pushfn(chk)
end

local function note_max(tag)
	local s = slen()
	if s > maxslen then maxslen, maxseq = s, tag end
end
local function sample(tag)
	local s, l = slen(), lenvar()
	local off = (pre_slen >= 0 and pre_slen or 0)
	local d = s - off
	print(string.format("S %-14s pre=%3d post=%3d d=%+3d len8114=%3d buf=%s", tag, off, s, d, l, bdump(math.min(48, math.max(s, 16)))))
	if tag:sub(1, 2) == "P " then expansions[tag] = { pre = off, post = s, d = d } end
	note_max(tag)
end

-- warm-up
reset()

-- ================= PHASE 1: per-key sweep =================
-- skipped with TC_SKIP_PHASE1=1 (sweep table is stable across runs; skipping
-- saves ~100M ticks so the long fill-to-N phases fit the run budget)
if os.getenv("TC_SKIP_PHASE1") == nil then
	local MODES = {
		{ "b", {} },
		{ "s", { SHIFT } },
		{ "a", { ALPHA } },
		{ "q", { ALPHA, SHIFT } },
	}
	for _, m in ipairs(MODES) do
		for c = 0x00, 0x67 do
			reset()
			chord(m[2], c, string.format("P %s%02X", m[1], c))
		end
	end
	reset()
end

-- ================= PHASE 2+3 (built after phase 1 results) =================
pushfn(function()
	local list = {}
	for tag, e in pairs(expansions) do
		if e.d >= 2 then list[#list + 1] = { tag = tag, d = e.d, pre = e.pre, post = e.post } end
	end
	table.sort(list, function(a, b) return a.d > b.d end)
	print("TPLRANK template probes (d>=2) top 15:")
	for i = 1, math.min(#list, 15) do
		local t = list[i]
		print(string.format("  TPLRANK %-8s d=%2d pre=%d post=%d", t.tag, t.d, t.pre, t.post))
	end
	local function decode(tag)
		local m = tag:sub(3, 3)
		local code = tonumber(tag:sub(4, 5), 16)
		if m == "b" then return {}, code end
		if m == "s" then return { SHIFT }, code end
		if m == "a" then return { ALPHA }, code end
		return { ALPHA, SHIFT }, code
	end
	local t13, t9
	for _, t in ipairs(list) do
		if not t13 and t.d >= 13 then t13 = t end
		if not t9 and t.tag:sub(3, 3) == "b" and t.d >= 9 then t9 = t end
	end
	if not t13 then t13 = { tag = "P s05", d = 13 } end
	if not t9 then t9 = { tag = "P b05", d = 9 } end
	print(string.format("TPLSEL t13=%s t9=%s", t13.tag, t9.tag))

	-- PHASE 2a: fill to exactly N, then 9-byte BASE template (single key 0x0D,
	-- no latch -> reliable), N=80..99, then single-key probes past the template
	do
		local mods, code = decode(t9.tag)
		for N = 80, 99 do
			reset()
			pushfill(N, "F")
			presschk(code, string.format("X t1N%02d", N))
			pushfill(N + 10, string.format("X t1N%02da", N), 6)
			pushfill(N + 11, string.format("X t1N%02db", N), 6)
		end
	end
	-- PHASE 2b: fill to N, then 13-byte SHIFT template chord (retry if the
	-- insert was smaller than 12 bytes), N=90..99
	do
		local mods, code = decode(t13.tag)
		for N = 90, 99 do
			reset()
			pushfill(N, "F")
			chordchk(mods, code, string.format("X t2N%02d", N), 12)
			pushfill(N + 14, string.format("X t2N%02da", N), 6)
		end
	end

	-- PHASE 3a: pure singles to cap (reference)
	do
		reset()
		pushfill(99, "F", 260)
		pushfill(100, "T r100", 6)
		pushfill(101, "T r101", 6)
	end
	-- PHASE 3b: template first, then fill to cap
	do
		local mods, code = decode(t13.tag)
		reset()
		chordchk(mods, code, "T t1tpl")
		pushfill(100, "T a", 260)
	end
	-- PHASE 3c: two templates, then fill to cap
	do
		local mods, code = decode(t13.tag)
		reset()
		chordchk(mods, code, "T t2tpl1")
		chordchk(mods, code, "T t2tpl2")
		pushfill(105, "T b", 260)
	end
	-- PHASE 3d: fill 99, DEL, template, single
	do
		local mods, code = decode(t13.tag)
		reset()
		pushfill(99, "F", 260)
		presschk(DEL, "B d1del")
		chordchk(mods, code, "B d1tpl")
		pushfill(101, "B d1k", 6)
	end
	-- PHASE 3e: fill 98, DEL (->97), template, single
	do
		local mods, code = decode(t13.tag)
		reset()
		pushfill(98, "F", 260)
		presschk(DEL, "B e1del")
		chordchk(mods, code, "B e1tpl")
		pushfill(100, "B e1k", 6)
	end
	-- PHASE 3f: fill 99, INS (SHIFT+DEL), template, single
	do
		local mods, code = decode(t13.tag)
		reset()
		pushfill(99, "F", 260)
		push(SHIFT, "m", 30000, 12000)
		presschk(DEL, "B f1ins")
		chordchk(mods, code, "B f1tpl")
		pushfill(101, "B f1k", 6)
	end
	-- PHASE 3g: mid-line at cap: fill 95, LEFT x3, template, single
	do
		local mods, code = decode(t13.tag)
		reset()
		pushfill(95, "F", 260)
		push(LEFT, "m", 30000, 12000); push(LEFT, "m", 30000, 12000); push(LEFT, "m", 30000, 12000)
		chordchk(mods, code, "B g1tpl")
		pushfill(99, "B g1k", 6)
	end
	print("PHASE23 queued")
end)

addposttick(function()
	T = T + 1
	if state == "idle" then
		while true do
			while qi <= #q and type(q[qi]) == "function" do
				local f = table.remove(q, qi)
				f()
			end
			if qi > #q then
				print(string.format("DONE T=%d maxslen=%d maxseq=%s finalslen=%d len8114=%d", T, maxslen, maxseq, slen(), lenvar()))
				print("DUMP 8100-83FF: " .. bdump(0x300, 0x8100))
				local f = io.open("/tmp/typedcap_dump.bin", "wb")
				local parts = {}
				for a = 0x8100, 0x8DFF do parts[#parts + 1] = string.char((data[a] or 0) & 0xFF) end
				f:write(table.concat(parts)); f:close()
				print("DUMPFILE /tmp/typedcap_dump.bin")
				emu:shutdown()
				state = "done"
				return
			end
			cur = q[qi]
			if cur.fillto then
				if slen() >= cur.fillto or (cur.presses or 0) >= cur.maxpress then
					qi = qi + 1 -- satisfied: consume the step and move on
					cur = nil
				else
					cur.presses = (cur.presses or 0) + 1
					fillcnt = fillcnt + 1
					cur.code = FILLC[fillcnt % #FILLC + 1]
					cur.hold, cur.gap = 30000, 12000
					break -- press again from the SAME step (do not advance qi)
				end
			else
				qi = qi + 1
				break
			end
		end
		if not cur then state = "idle" return end
		local c1 = (cur.tag or ""):sub(1, 1)
		if c1 == "P" or c1 == "X" or c1 == "T" or c1 == "B" then pre_slen = slen() end
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
			local lb = cur.tag or "?"
			local c1 = lb:sub(1, 1)
			if c1 == "P" or c1 == "X" or c1 == "T" or c1 == "B" then
				sample(lb)
				if c1 == "X" then
					print(string.format("  XFULL %-10s buf8154-81C3=%s", lb, bdump(0x70, 0x8154)))
				end
			end
			state = "idle"
		end
	end
end)
