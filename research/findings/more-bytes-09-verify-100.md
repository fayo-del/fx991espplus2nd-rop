# more-bytes-09 — adversarial re-verification of the "100 distinct attacker bytes" ceiling

Date: 2026-11-22. Question: can anything break ContentMap's claim
(`game-content.md`): the typed 100-byte payload at 0x8154 is flooded over
0x8154–0x8DFF with period 100 → exactly 100 distinct attacker bytes.

Method: **2 emulator runs** (`research/CasioEmuX/more09_diverse.lua`,
`more09_abab.lua`), both using the `rop_e2e.lua` recipe verbatim (41-key
typed queue via `PressKey` from T=1; final phase Right+AC @1, LEFT @20001,
payload at 0x8154 @36001, EXE @40001 → strcpy flood). The payload is
injected at final_t==36001 exactly as in `rop_e2e.lua`/`content_map.lua`
(ContentMap's own measurement used this same plant; the flood is triggered
by the typed recipe and is content-independent — proven below by two extreme
contents). Flood completion was detected tick-exactly: first tick where tail
samples (0x81B8, 0x8600, 0x8A00, 0x8C70, 0x8DF0, 0x8DFF) all match the
payload's periodic extension — both runs caught the CPU at `pc=6B66`
(inside strcpy 0x6B62) at `final_t=75408`, i.e. the tick the last RAM byte
0x8DFF was written. Full-span checks + dumps (`more09_*_post.bin`,
`_pre.bin`, `_payload.bin`, 0x8000..0x98FF) written; offline re-verified
against the dumps with Python.

## Run 1 — maximally diverse payload (a, c, d, e): PAY[i] = 0x01+i (100 pairwise-distinct zero-free values)

- `(c) full-span rescan`: **0 mismatches** over all 3244 bytes
  0x8154..0x8DFF — `post[a] == PAY[(a-0x8154) % 100]` for every `a`
  (in-run print + offline dump check). No address ≥ 0x8154 deviates.
- `(a) distinct post-flood`: **100 distinct byte values** in the span
  (all of 0x01..0x64), spread over 3244 positions; span minimal period = 100.
  Whole-RAM distinct 0x8000..0x8DFF = 108 (100 attacker + 8 firmware bytes in
  0x8000..0x8153). Marker `DE AD` planted at 0x8C70 pre-trigger was
  overwritten to `2D 2E` = PAY[44],PAY[45] → the flood reached the stack area.
- 0x8100..0x8153 (84 B): **not flooded** — only the 6 known formula-typing
  bytes changed vs pre-trigger (0x8114, 0x8115, 0x8118, 0x8129, 0x8140,
  0x8149), same as ContentMap; 0x80F5 (last-key register) also changed.
- `(d) DSR/segment aliases`: `data[0x18154]` (segment 1) = `0A001190…` =
  **ROM bank-1 bytes** (`rom.bin[0x18154:0x18164]` identical) — segment 1 at
  0x8154 is flash, not RAM. `data[0x28154]` (segment 2) = 0x00 (unmapped).
  BatteryBackedRAM is registered at 24-bit base 0x8000 only
  (`src/Peripheral/BatteryBackedRAM.cpp`: `region.Setup(0x8000, 0x0E00, …)`;
  `MMU::RegisterRegion` fills `segment_dispatch[base>>16]` only), so **no
  DSR≠0 alias reaches the same physical RAM** — RAM is segment-0-only.
  The only same-physical-bytes alias is the emulator shim tail:
  `ram_size = 0xE00+0x100` when `!real_hardware`, with `region_2` at
  **0x9800..0x98FF aliasing physical 0x8E00..0x8EFF** — verified:
  `data[0x9800..0x980F]` = `3030333111FF0030…` pre **and** post trigger
  (unchanged by the flood, since flood writes beyond 0x8DFF land at
  0x8E00+ which is MMIO/unmapped, never at 0x9800).
- `(e) 0x8E00+ post-trigger`: 0x8E00–0x8E02 are keyboard-emulator MMIO
  (`Keyboard/ReadyStatusEmulator` etc., `src/Peripheral/Keyboard.cpp:90`).
  The flood's writes past 0x8DFF hit them: post-trigger
  `data[0x8E00]=0x2D` (= PAY[44], the byte strcpy wrote to the ready
  register), `0x8E01/0x8E02 = 0x00`; 0x8E03..0x8EFF read 0x00 (unmapped in
  segment 0; CPU reads there return 0 via `HandleMemoryError`, which is a
  no-op unless `pause_on_mem_error`). The physical shim tail
  (readable at 0x9800+) was **not** written. → no extra controlled bytes at
  0x8E00+; only a keyboard-MMIO side effect at 0x8E00–0x8E02.

## Run 2 — internal-period payload (b): PAY = 0x41,0x42 alternating ×50 (ABAB, minimal period 2)

- `(b)` **0 mismatches** over all 3244 bytes: `post[a] == PAY[(a-0x8154)%100]`
  still holds for every `a`. The replication anchor stays at period **100**
  (= dst−src = 0x81B8−0x8154 = 0x64), independent of payload content —
  strcpy is a raw forward byte copy, no re-encoding. The flooded **content's**
  minimal period shrinks to **2** (= the string's minimal period, since 2|100):
  span minimal period measured = 2, distinct values in span = 2 (41 42).
  (General rule: content period = payload's minimal period p if p|100, else
  100.) `data[0x8E00]` post = 0x41 = PAY[44] ✓ same MMIO side effect.

## Verdict

**Ceiling CONFIRMED: 100 distinct attacker bytes, no more.** With the most
diverse possible zero-free payload (100 distinct values), post-flood RAM
0x8154..0x8DFF contains exactly those 100 values (3244 positions, 0
mismatches); with a period-2 payload it contains exactly 2. Every flooded
byte is one of the 100 payload bytes — there is no path to a 101st distinct
controlled byte via this trigger: 0x8100–0x8153 is not flooded, DSR/segment
aliases do not reach RAM (segment 1 = ROM, segment ≥2 unmapped), the
0x9800 shim alias is untouched, and 0x8E00+ yields only an MMIO side effect,
no stored bytes. The flood period is fixed at 100 by dst−src, not by the
string's minimal period (which only shrinks the *content* period when it
divides 100).

Notes / scope:
- "Typed" payload: the 41-key recipe is PressKey-typed from T=1 as in
  rop_e2e; the 100 payload bytes themselves are planted at final_t==36001,
  exactly as in rop_e2e.lua and ContentMap's content_map.lua, so this is an
  apples-to-apples re-verification of the measured claim. The flood itself is
  content-independent (proven by the two extreme payloads), so a PressKey-typed
  payload can only ever produce a *subset* of these ≤100 distinct values —
  the hardware typeable-set limit on distinct *values* is the separate
  input-cap question (MB01); the 100-*position* ceiling holds regardless.
- Both runs: PROBE1 len=2 (input locked post-overflow), flood detected at
  final_t=75408 with pc=6B66/sp=8D96, marker at 0x8C70 overwritten —
  trigger reproduced identically to rop_e2e/content_map.

Artifacts:
- `research/CasioEmuX/more09_diverse.lua`, `more09_abab.lua` (scripts)
- `research/CasioEmuX/more09_diverse_{post,pre,payload}.bin`,
  `more09_abab_{post,pre,payload}.bin` (RAM dumps 0x8000..0x98FF)
- run logs `/tmp/more09_diverse.out`, `/tmp/more09_abab.out`
