# SecEmuAudit — CasioEmuX host-side audit (untrusted ROM / hostile Lua keyscript)

Scope: `research/CasioEmuX/emulator/src/**` (live `src`, identical to the copy in this repo —
`diff -rq src.orig src` shows only MMU.cpp + Keyboard.* were patched), `emulator/lua-common.lua`,
`models/*/model.lua`. Binary checked: pristine `emulator/emulator`, md5
`4dcb0b1c6ce05aff52c2b1cb9de5631a` ✓. Two headless runs used; run 2 was decisive (finding 1).

## Ranked findings

### 1. CRITICAL — KeyLog heap overflow + heap-exfil via `Keyboard:StartKeyLog` (confirmed by run)
- `Peripheral/Keyboard.cpp:217` — `KeyLog = new uint8_t[100000]` (allocated only in StartKeyLog).
- `Keyboard.cpp:520-521` — inside `PressButton()`, when `isKeyLogToggled`:
  `KeyLog[KeyLogIndex] = keycode; KeyLogIndex++;` — **no bound check**, `KeyLogIndex` is plain
  `int` (`Keyboard.hpp:55`). Every press (script `press()`, `KeyInj` thread, or GUI click) appends
  one byte.
- `Keyboard.cpp:577` — `StoreKeyLog()` then does `keylog_handle.write((char*)KeyLog, KeyLogIndex)`
  — copies `KeyLogIndex` bytes, i.e. **reads the OOB region too** and writes the whole thing to a
  file of the script's choosing.
- Trigger: hostile Lua keyscript (Keyboard global + `keylog()/press()/stoplog()` are exposed to any
  `script=` at `Emulator.cpp:185-203`, `lua-common.lua:278-302`): `keylog(path)` then a press loop.
- Verified (headless run 2, pristine binary, `SDL_VIDEODRIVER=dummy`, 100200 presses via
  `keylog('/tmp/sec-audit-keylog.bin'); for i=1,100200 do press(0x21) end; stoplog()`):
  output file is exactly **100200 bytes** from a **100000-byte** allocation → 200 bytes written
  past the end of the heap chunk and exfiltrated. Repeatable.
- Impact: linear heap OOB write, attacker-controlled count and per-press byte values → heap
  metadata/object corruption in the host → potential host code execution; plus host memory-leak
  into a file (meaningful if the emu is ever shipped with semi-trusted keyscripts).
- Severity: **critical**. Fix: `if (KeyLogIndex >= 100000) return;` before the store (and take the
  buffer size from a parameter; also free `KeyLog` in `StopKeyLog` — currently only freed in
  `Uninitialise`, `Keyboard.cpp:436-440`, and leaked on every re-`StartKeyLog`).

### 2. HIGH — dangling Lua string pointers in `keyseq_filename` / `keylog_filename` (UAF)
- `Keyboard.cpp:203` and `:214` store the raw `lua_tostring(lua_state, 2)` result into
  `const char*` members (`Keyboard.hpp:51-52`) — **not copied**. Nothing anchors the Lua string.
- The detached inject thread later reads `keyseq_filename` (`Keyboard.cpp:553`,
  `std::ifstream keyseq_handle(keyseq_filename...)`) or `StoreKeyLog` reads `keylog_filename`
  (`Keyboard.cpp:572`) — if GC collected the string in between (runtime GC at scale it is a
  runaway `KeyInj` thread, or minutes between StartKeyLog/StopKeyLog), the thread uses a freed
  pointer: ifstream/ofstream constructed from freed memory.
- Trigger: hostile keyscript; dynamic filename + GC pressure, or simply a long-running injection.
- Impact: UAF read → emu crash; ofstream may open a garbage path. [INFERENCE] on reliable
  triggering; the code pattern (unanchored Lua string outliving the call) is objectively unsafe.
- Severity: **high** (crash DoS, likely exploitable heap UAF). Fix: copy into `std::string`.

### 3. HIGH — "sandbox" claim void: full Lua stdlib exposed to keyscripts
- `Emulator.cpp:24` — `luaL_openlibs(lua_state)`; `os`, `io`, `package`, `dofile`/`load` are all
  live in both `model.lua` and any `script=` keyscript (same global state).
- A hostile keyscript needs no memory bug: `os.execute(...)`, `io.open(path,"w")`,
  `dofile("/...")` are arbitrary host file access and **host code execution** (lua-common itself
  uses `io.open`, `loadstring`, `load` — `lua-common.lua:217-228,737`).
- Severity: **high** (by design, confirmed at Emulator.cpp:24,168-203). Fix: whitelist a minimal
  set of libraries (strip `os`, `io`, `package`, `dofile`, `require`) before loading model/script.

### 4. HIGH — unlocked Lua/emu-state execution paths (thread races)
- `Emulator::RunStartupScript` (`Emulator.cpp:185-203`) runs the keyscript **without** holding
  `access_mx`, while the tick thread runs `TimerCallback → Emulator::Tick → chipset.Tick()` with
  Lua hook pcalls under the lock (`Emulator.cpp:313-330, 371-400`).
- `Emulator::Tick` itself takes **no lock** — a keyscript in a `while true do emu:tick() end` loop
  (`lua-common.lua:304-312,374-396` patterns) mutates the full chipset state concurrently with the
  tick thread.
- The `KeyInj` detached thread (`Keyboard.cpp:550-568`) calls `PressButtonByCode → PressButton`,
  mutating `buttons[]`, `keyboard_out`, interrupt SFRs and `pending_interrupt_count++` with no
  lock, racing the tick thread that does the same under `access_mx`.
- Impact: data race on `lua_State` (heap corruption inside the Lua allocator) and on all emulator
  state → crashes/corrupt execution; a hostile script can deliberately race to corrupt host heap.
- Severity: **high**. Fix: single ownership — run scripts on the tick thread or lock every Lua C
  entry point.

### 5. HIGH — `CodeViewer` `_disas.txt` parser: memcpy size underflow + overflow
- `Gui/CodeViewer.cpp:19-58`: lines read from `<model>/_disas.txt` during construction.
  - `memcpy(e.srcbuf, buf + 28, len - 28)` at `:47`: a line shorter than 28 chars gives negative
    int → huge `size_t` → immediate segfault; a 68-199-char line copies up to 171 bytes into
    `char srcbuf[40]` (`CodeViewer.hpp:8`) → stack smash in the loader thread.
  - lines >199 chars: `f.getline(buf, 200)` at `:32` sets failbit, `while (!f.eof())` at `:31`
    never advances → **infinite loop** appending truncated lines (OOM DoS).
- Trigger: any model directory with a crafted/edited `_disas.txt` (model dirs are single-supplied
  inputs, but this is the ROM-floor-adjacent surface that rides along with any exchanged model).
- Severity: **high** (deterministic crash; controlled 171-byte stack overflow with a crafted file
  only constrained by line content). Fix: bounds-check `len`, `std::getline` into `std::string`,
  cap `srcbuf` copy at 39.

### 6. MEDIUM — GUI thread races + detached-thread UAF at shutdown
- Gui thread `t1` is detached (`casioemu.cpp:142-167`) and calls `gui_loop()` (`Gui/Command.cpp:23-57`)
  → `code_viewer->DrawWindow()` without `access_mx`, while the CPU thread reads the same
  `break_points` map / `debug_flags` (`CPU.cpp:444-451`, `CodeViewer.cpp:81-103`) → concurrent
  `std::map` read/mutate → UAF inside the red-black tree when debug STEP/breakpoints are clicked
  while the ROM runs.
- The mem-editor windows use `mmu->ReadData/WriteData` directly from this thread
  (`Gui/hex.hpp:314,341,364-365`) — read/execute concurrently with the tick thread.
- After `emulator` is destroyed at scope end (`casioemu.cpp:80-81`), the still-looping detached
  gui thread dereferences `m_emu` (`Command.cpp:24,47`) → genuine UAF on every raced shutdown.
- Trigger: debug window use / shutdown while ROM runs ("emulator closes → 1-in-N crash").
- Severity: **medium** (crash DoS, hard to weaponize). Fix: fence gui thread on shutdown, guard
  `code_viewer` access same as chipset.

### 7. MEDIUM — Flash controller OOB (CLASSWIZ / CLASSWIZ II / 5800P only — not on ES_PLUS; flash
is never pushed/Initialised for `HW_ES_PLUS` — `Chipset.cpp:291,311-312` and `Flash.cpp:46-47` runs
no register setup only for 5800P — so CY-845 is unaffected)
- `Flash::Write` (`Peripheral/Flash.cpp:123-135`): `offset` (ROM-controlled FLASHA, 16-bit) is
  never checked against `SegmentSize[seg]`; only `FlashStat[seg][offset/2]` guards the write →
  OOB read of an 8 KiB max `bool[]` array (index up to 0x7FFF past a 2048-byte allocation) and,
  when the OOB byte reads true, a **2-byte OOB write into `rom_data`** at `(seg<<16)|offset`
  (vector OOB write at values the ROM controls, e.g. seg=0x1F, offset≈0xFFF0).
- `Flash::ReadWord` (`Flash.cpp:79-81,91,106`): bounds are `SegmentSize[seg]`, not
  `rom_data.size()` — a truncated/hostile ROM file (smaller than the model expects) makes ROM
  reads return host heap bytes OOB-read into the emulated instrument.
- `Flash::Write`/`BlockErase` with any segment whose `SegmentSize` is 0 → `FlashStat[seg]`
  is `nullptr` → null-pointer dereferenced crash (`Flash.cpp:127,140-144` vs `Flash.cpp:36-42`).
- Trigger: ROM sets FLASHACP 0xFA/0xF5 (`Flash.cpp:67-72`), writes FLASHSEG/FLASHA/FLASHD.
  ROM-triggered and present on all flash models. Severity: **medium-high** (hits the class that
  mupen/casio-style emulators aim to be "ROM-safe"). Fix: validate `offset < SegmentSize[seg]`
  and `real_offset + 1 < rom_data.size()` in Write/Read; reject zero-size segments.

### 8. MEDIUM — `data:addr_region` skips all offset checks (host segfault by script)
- `MMU::GetAddressRegion` (`Chipset/MMU.cpp:455-458`) indexes `segment_dispatch[offset >> 16]`
  with **no 2^24 check** — unlike `ReadData`/`WriteData` (`MMU.cpp:218, 365`) which PANIC.
- `data:addr_region(0x30000000)` from a keyscript/console reads `segment_dispatch[0x30000]`
  (>0x10000 bytes past a 256-pointer array) → garbage pointer dereference → segfault
  (`MMU.cpp:145`, `Emulator.cpp` data `__index` at `MMU.cpp:135-151`).
- Severity: **medium** (crash DoS from any script; OOB read of an 8 KiB heap region →
  description-string dereference). Fix: same `offset >= (1 << 24)` PANIC/return as ReadData.

### 9. LOW — signed-shift UB in interrupt SFR writes
- `Chipset.cpp:89,110` — `data << (offset * 8)` and `0xFF << (offset * 8)` with `offset==3` gives
  `255 << 24` on `int` (UB, gcc wraps) — currently self-corrects via `data_int_mask &= mask`
  (`uint32_t`, `Chipset.hpp:68`) but silently limits what a write of a stale value means.
  Trigger: ROM writes 0xFF to 0xF017/0xF013. Impact: UB only, no OOB. Fix: cast to `(uint32_t)`
  before shifting.

### 10. LOW — `SetClockSpeed` accepts garbage floats
- `Emulator.cpp:228-237,494-496` — `emu:SetClockSpeed(nan|inf|-1)` → `(unsigned int)(...)` UB,
  a huge/1 value changes emulation pacing: huge → effectively single-threaded hang (easily
  reversible DoS), 0 → LSCLK tick every cycle. No memory unsafety found downstream
  (`Chipset.cpp:218` divides by constant 16384 only). Fix: clamp/validate.

### 11. Checked-negative (audited, no bug found)
- `PressButtonByCode`/`PressAt` (`Keyboard.cpp:525-548`): index formula max 63, `buttons[64]` — safe.
- 0x8E00-0x8E02 emu-shim regions (`Keyboard.cpp:90-165`): single-byte reads/writes into
  bool/uint8 members, read-count rollovers — no OOB; no overlap with BatteryBackedRAM region
  (0x8000+0xE00 ends exactly at 0x8E00).
- Env-gated trace fprintf (`MMU.cpp:220-230,371-393`, `Keyboard.cpp:94,131`): all fixed formats
  (`%06zX/%02X`); the two `%s` filename prints (`Keyboard.cpp:555,574`) pass the filename as the
  argument — **no format-string vulnerability**.
- `data[i]=v` / `code[i]` basics (`MMU.cpp:168-214,216-289,363-414`): `PANIC` (fprintf+exit,
  `Config.hpp:11-14`) on ≥2^24/odd fetch — abort, not corruption; rwatch/watch segment+offset
  bounded by the 0x10000-entry dispatch table.
- `CorruptByDSR` (`CPU.cpp:551-554`): sets `fetch_addition=0x0FF0` — PC skew stays inside
  `ReadCode`'s 20-bit check → misfetch returns 0/PANIC; no host effect beyond exit/DoS.
- `RecalculateGhost/KI` (`Keyboard.cpp:581-681`), OOB-free fixed 64-button loops; `OP_SWI`
  (`CPUControl.cpp:182-185`) bounded to 0x40..0x7F < INT_COUNT; `OP_CTRL`/`RTI` ELEVEL masked
  0x3 (`CPU.hpp:117`); `OP_DIV`/coprocessor dividers all have div-by-zero paths; `reg_r[...]`
  index masks deliberately even-aligned and ≤15+7=15 in every dispatched 8-byte op (e.g. the
  `0x0008` masks at `CPU.cpp:69-70,104-105,109`).
- `model.lua` button-map parsing (`Keyboard.cpp:244-321`, `models/fx991esplus2/model.lua`):
  every index is PANIC-guarded; `models/fx991esplus2` is 6-element (`px,py,w,h,code,name`) and
  `strlen` checked for embedded NULs — safe.
- rtc `day_count[0x12]` tables are 18 entries (`RealTimeClock.hpp:22-23`) — `RTCMON-1 ∈ 0..0x11`
  in bounds at `RealTimeClock.cpp:74,130`.
- SDL/SDL_image: only parses the model's own `interface.png` (not ROM-derived input).

## Verdict

**Not a safe sandbox today.** For a hostile *keyscript* the answer is by design no (full
`os`/`io`/`dofile` — finding 3) and by accident no either (confirmed heap OOB write+exfil —
finding 1, UAF filenames — finding 2, unlocked execution paths — finding 4). For a hostile *ROM*
on the CY-845/ES-PLUS target the C++ core holds up: every data write is routed through
bounded MMU regions/PANICs, and I found no host memory-unsafety reachable from the mask ROM;
the flash-controller and `_disas.txt` bugs (findings 5, 7) are real host-corruption paths for
other models/hostile model dirs.

Count: 1 critical, 4 high, 3 medium, 3 low (11 findings; 11 checked-negative areas).
Top bug: KeyLog heap overflow (`Keyboard.cpp:217` vs `:520-521,577`) — confirmed by headless run
(100200-byte keylog file from a 100000-byte allocation).
