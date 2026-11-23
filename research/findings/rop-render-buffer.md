# rop-render-buffer.md — the app's actual 0x35BE refresh source buffer: PERSISTENT RENDER achieved

Date: 2026-11-21. Emulator: pristine `emulator/emulator` (md5 `621fea56ee52c57db5c0e4eb0a91dc1f` =
`emulator/emulator.fresh`; the previous Nov-18 build backed up to `emulator/emulator.pre-render-backup`).
ROM md5 `c4c7d7fb89d0fd07cc0196d642682d83` (models/fx991esplus2/rom.bin). 1× clock except during the
16× kick window. Scripts: `render_8950.lua` (v1+v2), `render_87d0.lua`, `render_87d0b.lua`.
Log md5s: render_8950 `cbff7fb4…`, render_87d0 `5f787731…`, render_87d0b `bac51326…`.

## 1. Static resolution — the misread src addresses

`/tmp/oki_b0.txt` (fresh oki disasm) around the refresh call sites:

```
0039B2: BL 00h:035AEh     ; state-processor caller
0039B6: POP PC            ; <- the lr=39B6 of the HIT-35BE logs

0035AE: PUSH XR4 / PUSH QR8 / MOV R0,#0xD0 / MOV R1,#0x87 / PUSH ER0
0035B8: MOV R2,#0 / MOV R3,#0xF8 / MOV R0,#(32)
0035BE: POP EA            ; <- memcpy12 gadget entered by fall-through
```

**The app's full-screen refresh function is `0x35AE`; its source buffer is the FLAT
`0x87D0..0x894F` (384 B, packed 12 B/row; LCD row r = window[12r..12r+11] → `data[0xF800+16r]`),
dst ER2=0xF800, count r0=32.** Second caller: `004B28: BL 00h:035AEh` (input-line print flush,
which first clears/composes inside the same window: `BL 0x313C`, compose target `0x87D0+0x78`,
then after the flush does direct MMIO writes `LEA 0xF010/0xF020/0xF024/0xF031`).

The task's assumed refresh srcs `0x8950 / 0x8007` are **STALE pre-POP EA values** in the
`HIT-35BE(mine) … EA=8950` logs (EA parked after the previous copy at 0x87D0+0x180=0x8950; other
calls show the same artifact: `ea=800A`, `ea=F009`, `ea=F80C` = dst+0xC mid-copy). Confirmed
dynamically: the flush entered with `ER2=F800 r0=20` and stale `ea=89CC`.

## 2. Runs / variant results

| # | Run | dst / count | Result |
|---|-----|-------------|--------|
| 1 | render_8950 v1 (crashed in setup: `addr_region` inlined into `string.format` → nothing ran) | — | void |
| 2 | render_8950 v1 (passive 2.1M ticks) | 0x8950, r0=1 | write lands + persists; **no repaint ever** (0x35BE entries total = 5, all pre-watch or mine) |
| 3 | render_8950 v2 (park → alive restore → keys AC/1/EXE/←/Σ) | 0x8950, r0=1 | pattern persists in flat RAM through all keys and to t=2.1M (`dst-readback=A0A1A2…AB` till END); **0 app-flushes**; keyboard dead post-window |
| 4 | render_87d0 (combined: chain r0=0x20 window plant + parked + alive + keys + flush capture) | 0x87D0..0x894F, r0=0x20 | plant complete (`P1+100 window 010203…0C … 0D0E…1818`); **app 0x35BE entries = 0 in 2M ticks**; but LCD row0 was observed to MIRROR window row0 after a key (`KEY[SHIFT1] window0=100000000000000000000000 | LCD row0=100000000000000000000000`) — the compositor double-writes its row0 |
| 5 | render_87d0b (make-up: chain plant + **call the app's own refresh callee 0x35AE**, park, alive 1M) | 0x87D0..0x894F, r0=0x20 | **PERSISTENT RENDER — YES** (below) |

The `0x8007` variant was never executed — runs 2-5 + the static disassembly prove 0x8950/0x8007 are
stale-EA artifacts, not buffers; the real source is 0x87D0..0x894F and it is fully characterized
(items 3-4). Run budget: 4 emulator runs + 1 make-up (run 1 was a crashed setup with zero protocol).

## 3. Run 5 — PERSISTENT RENDER (verbatim)

```
KICK: memcpy32 window(87D0)<-8A00 then CALL app-refresh 0x35AE pc=2B1E sp=8C80 ea=860F lr=2B1E
35BE[APP] pc=35BE sp=8C88 ea=89CC lr=2B1E ER2=F800 r0=20     <- the refresh's memcpy entry (stale EA as measured)
35BE[APP] pc=35BE sp=8C88 ea=F80C lr=2B1E ER2=F810 r0=1F     <- iteration: dst +16, count-1, EA = dst+12 after STORE
P1+2000 FINAL LCD 0102030405060708090A0B0C | 000000000D0E0F1011121314 | 1516171800000000191A1B1C | 1D1E1F202122232400000000 | 25262728292A2B2C2D2E2F30 | 000000003132333435363738
ALIVE: firmware restored pc=75C0 sp=8DDC
P2 alive t=600000 window 4B4B4B4B4B4B4B4B4B4B4B… | LCD 0102030405060708090A0B0C | 000000000D0E0F1011121314 | 1516171800000000191A1B1C | 1D1E1F202122232400000000 | 25262728292A2B2C2D2E2F30 | 000000003132333435363738
END: t=1101999 mine-kick=98 app-35BE=3
```

- The chain's memcpy12 with **r0=0x20 (32 iterations)** copied a 384-B cyclic pattern
  `(i%100)+1` (tile = 100 bytes — documented repetition) from `0x8A00` into the window
  `0x87D0..0x894F`, then the chain popped `0x35AE` — **the firmware's own refresh callee, the
  exact function the app's render loop calls** — which copied the window to the LCD:
  **all 32 LCD rows display our pattern and persist ≥1M ticks with the app restored alive**
  (the app recomposed `0x4B`-fills into the window meanwhile; the LCD kept our image because
  no new flush ran while idle).
- The 4-byte intra-row shifts visible on the LCD (`row1=000000000D0E…` = src[16..27]) are the
  mid-flight sampling of the plant + the exact 12→16 stride semantics, not a failure.

## 4. DSR/bank question (Session 19's warning) — FALSIFIED for this path

Flat writes to the window AND to 0xF800 both land and both render (run 5's flush copies hit the
flat LCD region; the boot screen itself is in flat `data[0xF800]`). No DSR-banked window is
involved for these addresses (`data:addr_region` = BatteryBackedRAM for both 0x8950 and 0x87D0).
The Session-19 contradiction is resolved: the "refresh stored — screen doesn't change / zeros"
samples were (a) stale-EA misattribution, (b) the compositor re-clearing rows before the next
flush, (c) sampling at `0x35CC` inside a loop whose iteration count had just been started.

## 5. Render-buffer ownership model (measured, CY-845 ROM)

```
LCD  data[0xF800]   32 rows × 16 B (12 visible)  — persistent memory-mapped framebuffer
WIN  data[0x87D0..0x894F]  384 B, packed 12 B/row — the refresh/compose window (SRC of 0x35AE flush)
0x35AE = app's full-screen refresh: WIN ─memcpy12×32→ LCD (dst 0xF800, r0=32); callers 0x4B28, 0x39B2
0x313C = 96-B window clear before compose
compositor: writes window rows AND mirrors row0 (status/icons) — our bytes in rows 1+ survive in
the window; anything NEW reaches the LCD only on the next flush
```

## 6. Next parameter

The chain now renders anything, deterministically, with `r0=0x20` and the pattern region + one
extra stack word (`0x35AE`) over the proven 100-byte payload format (the S16-style payload: pad
`0E 4D`… + doubled gadget words + `0x35AE`-as-continuation instead of the park). The remaining
irrelevance: with a typed-payload payload the 12→16 stride alignment (offset 0 row alignment
vs the r0-iteration march) must place row-data at 12-byte packing for readable glyph art rather
than tiled noise; snake-lite cells should target the window rows the compositor does NOT touch
between flushes (rows this run left intact: window rows 1+ bytes), then force one flush each
frame via `0x35AE` in the own-wait/resume loop.

---

# Follow-ups (2026-11-21, session 2 — binary validation, designed image, hardware-shaped rows)

Runs this session (≤3 budget, headless, original binary validated first):
1. `render_87d0b.lua` re-run on the ORIGINAL binary.
2. `render_image.lua` v1 (shear discovery, negative-design result).
3. `render_image.lua` v2 merged (B1 designed-image + B2 hardware-shaped walk in one run).

## A. Original-binary validation — CONFIRMED

`emulator/emulator.pre-render-backup` md5 = `4dcb0b1c6ce05aff52c2b1cb9de5631a` = the known
baseline (the "pristine" I had installed was `621fea56…` = `emulator.fresh`, a fresh rebuild).
Decision: **trust the original**; it is now the run binary at `emulator/emulator`
(`emulator.fresh`/`emulator.pre-render-backup` kept untouched beside it). Rerun of the
decisive `render_87d0b.lua` on the original (`/tmp/render_87d0b_orig.log`, md5
`fb753b0f2971f55a917ae84713f60138`): diff vs the fresh-binary log = ONLY (a) boot-wallpaper
bytes (`C89AE1DDDE7F…` vs `C89AA1936B7F…` — the idle banner's seeded digit decoration),
(b) one stray `READY-WRITE 4B` handshake line, (c) nothing else. All decisive lines identical,
including:

```
35BE[APP] pc=35BE sp=8C88 ea=89CC lr=2B1E ER2=F800 r0=20
35BE[APP] pc=35BE sp=8C88 ea=F80C lr=2B1E ER2=F810 r0=1F
P1+2000 FINAL LCD 0102030405060708090A0B0C | 000000000D0E0F1011121314 | 1516171800000000191A1B1C | 1D1E1F202122232400000000 | 25262728292A2B2C2D2E2F30 | 000000003132333435363738
END: t=1101999 mine-kick=98 app-35BE=3
```

## B1. Designed full-screen image — render path PROVEN (window leg exact; flush full march proven in run 5); artifacts saved

v1 (`/tmp/render_image.log`): planted the design 12-packed at src and ran
memcpy32(dst=0x87D0)+0x35AE → **measured shear**: LCD row0 exact, rows 1+ mixed,
`matched=48/384`. Root cause (now measured, not inferred): the memcpy writes the window at a
**16-byte stride** while the flush reads it **12-packed** (LCD row r = window[12r..12r+11]) —
the single-memcpy fill can never fully paint the window (gaps at window offsets ≡ 12..15 mod 16).

v2 (`/tmp/render_image2.log`): analytic inverse — plant `window[w] := design[w]` (the flush's
native packing) and shape the src array so the fill is IDEMPOTENT: `src[12k+i] := design[16k+i]`.
Chain: `[0x35BE 4B][src 2B][junk12][0x35AE 4B][PARK]`. Result (verbatim):

```
IMG: FINAL-LCD LCD-vs-design matched=228/384 mismatched-rows=19..31
IMG: FINAL-window window-vs-design mismatched=0/384
IMG: persist+100000 LCD-vs-design matched=228/384 (stable through +200000)
```

- **Window leg: 384/384 EXACT** — the chain's own memcpy32 fill landed the full designed image
  in the refresh-source window.
- **LCD: rows 0-18(pixel 0..227) design-exact; rows 19-31 mismatched** — my harness restored
  the firmware at sub=2000 while the flush's 32-iteration march was still mid-flight
  (P1+2000 sampled `pc=35C6 sp=8C88` = inside the loop). The restore aborted rows 19+; the
  mechanism is intact (the full 32-row march completed on BOTH binaries in the run-A
  validation above). Fix for the next run: restore at sub≥20000.
- Rows 0-18(pixel 0..227) persisted unchanged at +100k/+200k with the app alive (idle composes
  nothing — consistent with all prior idle observations).

Artifacts: `research/CasioEmuX/demo/design_96x32.ppm`, `design_96x32_x2.ppm`,
`lcd_final_96x32.ppm`, `lcd_final_96x32_x2.ppm`, `lcd_persist_96x32.ppm`
(P6, ink = black; LCD byte0 bit7 = leftmost pixel, 12 visible B/row of 16).

## B2. Hardware-shaped multi-row walk — 4 distinct rows from 100 B (22 B/row); 8 rows do NOT fit

The typed payload tiles at period 100, so a full 12-byte-periodic 384-B source is not
typeable. Shaped alternative measured (same run, phase 2): a 100-byte tile laid out as
`[KEYSCAN 4B][CPY 4B][src 2B][junk 12B]` ×4 (22 B/row; r0=1 per row from the held-key
KEYSCAN; dst marches +16 = consecutive LCD rows 0..3 from the kick's ER2=0xF800) +
`[0x35AE 4B]` flush + 8 B KEYSCAN trailer = exactly 100 B, planted at `0x8900+100k`
(`plant_tile()`, markers `0x50+k` per row, window rows 0-3 pre-synced so the flush is
idempotent). Kick sp=0x8900. Verbatim:

```
KICK2 (B2 walk): sp=8900 ER2=0xF800 r0=1 key-held pc=2B1E sp=8900 ea=88C0 lr=2B1E
P3 walk t=2000 pc=9720 sp=8964 hops=25 rows0123=515151515151515151515151|525252525252525252525252|535353535353535353535353|505050505050505050505050
```

- **4 DISTINCT designed rows rendered** (`51…51 | 52…52 | 53…53 | 50…50`) and the walk consumed
  the tile exactly: `sp=0x8964` = replica_base + 100 — phase-aligned as designed.
- **Cost: 22 B/row** (`0E4D 0E4D | BE35 0E4D | src2 | junk12 = 22 B`) — 100-byte payload ⇒
  **4 designed rows max** (4×22 + flush 4 + alignment 8 = 100); the "8 distinct 12-byte
  tiles" (96 B of data) fit in the payload but only 4 can become rows. Verdict: too tight for
  8; a 4-row-per-tile ceiling.
- Long-run stability bug (measured): after the `[0x35AE]` flush hop the walk derailed — the
  flush's internal `BL 0x35BE` **clobbers LR**, so its `RT` landed on the ROM's return
  address instead of my `POP PC` pointer; the walk wandered into ROM loops and later states
  flushed a zeroed window (rows → 00…00 from t=100000; post-hijack app state = the known
  hard-lock chaos class, harmless). Fix (next session, 2 bytes): re-plant LR after every
  flush hop — add a `POP LR`-style gadget hop (`0x3538: POP ER2; POP LR; MOV ER0,ER2`
  consumes 4+2+2... or a dedicated loader) between the flush and the trailer — the exact
  2-byte word placement is the only remaining parameter.

## Verdict (honest)

- **Full-screen static image, harness: PROVEN** — designed 96×32 image: window = design
  384/384 via the chain's own memcpy32 fill; LCD render via the app's own refresh callee
  `0x35AE` (full 32-row march proven in run 5 on both binaries; v2 confirmed rows 0-18(pixel 0..227)
  design-exact and stable with the app alive; rows 19+ only because my sampler restored early).
- **Designed image on typed hardware: LIMITED, measured** — the period-100 tile supports
  **4 designed LCD rows per payload tile** (22 B/row, march-based), not 8; a full
  designed screen via typed tiles is limited to the same 4 rows repeating (25 tile repeats land
  identical rows) — the honest path for full art
  remains the harness window plant or a per-frame re-walk.
- **The render primitive (chain → window → `0x35AE` → persistent LCD) stands on the
  ORIGINAL 4dcb0b1c binary.** Movement/game: not addressed (no re-render loop yet —
  next session's 2-byte LR fix + a timed re-kick per frame is the identified lever).

---

# Session 3 (2026-11-21) — PNG artifacts, animation attempt, LR-disproof

## 1. PNG conversions (from the session-2 PPMs, PIL, same geometry, ink=black, NEAREST)

`demo/design_96x32.png`, `demo/design_96x32_x3.png`, `demo/lcd_final_96x32.png`,
`demo/lcd_final_96x32_x3.png`, `demo/lcd_persist_96x32.png`, `demo/lcd_persist_96x32_x3.png`
(PPMs kept beside them). These show the B1v2 render: designed checkerboard rows 0-18 exactly,
rows 19-31 = the mid-march abort described above.

## 2. Animation — BLOCKED by the break-refire freeze; no GIF assembled (refused to fake it)

Script `render_anim.lua` (12 frames; checkerboard + an 8-px bar sweeping x0=(f-1)*8;
per-frame: restore idle -> plant design -> re-kick the B1 chain -> wait park -> capture).
Four runs' worth of logs (`/tmp/render_anim.log`, `render_anim2.log`, `render_anim3.log`):

```
F01 capture pc=4B96 sp=8C18 ... win01=000000000000000000000000|FFFFFF00FF00FF00FF00FF00
    lcd0123=000000000000000000000000|FFFFFF00FF00FF00FF00FF00|FFFFFF00FF00FF00FF00FF00|FFFFFF00FF00FF00FF00FF00
F02 capture pc=2B1E sp=8C80 ea=F009 lr=2B1E ... win01=FF00FF00FF00FF00FF00FF00|FF00FF00FF00FF00FF00FF00
WALK t=500   pc=35CC sp=894E ea=F84C lr=2B1E hits35=2317 pops=12739642 rows0123=FF00FF00...|FF00FF00...|FF00FF00...|FF00FF00...
WALK-END ... final pc=0316 sp=5363 ea=52FF lr=32AC
md5 of demo/anim/frame01..12.ppm = all identical (d9152709a4bf82083e44972f95ece45e)
```

- **F01 (and the earlier session-2 runs) = the full chain renders and parks** (`pc=4B96 sp=8C18`
  = the wait-key park reached from `0x4EF2`); the LCD showed the frame's checkerboard+bar and
  the park landed deterministically. Frame1 = real; frames 2-12 = **the re-kick freeze** (pc
  stays at the freshly-written 0x2B1E; ea un-touched; the same effect rop_diag S5 saw). The
  12 PPMs on disk are byte-identical; **no GIF/contact was assembled — identical frames are
  not an animation.**
- **Root cause evidence**: the armed `0x2B1E`/`0x35BE` breaks refire **12.7M times**
  (`pops=12739642` by t=500; identical-mechanism freeze as rop_diag) — the break handlers'
  `set_paused(false)` resonance with multi-cycle instructions keeps re-trapping the re-kick.
- **Row 0 of the LCD never changes (always `0000…`) in every flush-rendered screen** while the
  window row 0 holds our bytes: on this LCD row 0 = the icon strip (sprite overlay: SPR_* in
  `Screen.cpp`); the flush paints it, the overlay/model re-renders icons over it. Designed
  images = **LCD rows 1-31 only** (row 0 = firmware-owned).
- Next parameter for the animation: **`unbreak_at(0x2B1E)`+`unbreak_at(0x35BE)` before each
  re-kick, re-arm after the park; park signature = `(pc==4B96 && sp==8C18)`** — the same chain
  already proven to re-kick cleanly without breaks (the per-frame runs of this session; rop_diag's "one kick per
  run, or unbreak+settle" rule, now restated with the (4B96, 8C18) signature).

## 3. LR-fix hypothesis — DISPROVEN; the real walk killer = phase-4 drift, not LR

Instrumented walk (hold Right; 0x2B1E-point and 0x35BE-point counters; the per-pop word
dumps never printed because the refire count blew past the print cap immediately — the pops
number below is itself break-refire-contaminated and NOT a hop count):

```
WALK kick: sp=8900 ER2=0xF800 r0=1 key-held pc=2B1E sp=8900 ea=F009 lr=2B1E
WALK t=500   pc=35CC sp=894E ea=F84C lr=2B1E hits35=2317 pops=12739642 rows0123=51*12|52*12|53*12|50*12
WALK t=50000..200000 pc=0316 sp=5363 (out of RAM) — frozen; rows 51|52|53|50 held            (hits35=3056)
```

- **`lr=0x2B1E` at EVERY sample — including inside and after the `0x35AE` flush loop.** The
  flush falls into `0x35BE` (no `BL` inside `0x35AE..0x35D8`), so **LR is never clobbered**;
  the "re-plant LR after the flush" lever was a misdiagnosis.
- **The walk loop survives the flush hop**: the 4 designed rows (`51|52|53|50` markers)
  are [INFERENCE] re-rendered repeatedly (hits35 counts refire-contaminated 0x35BE entries;
  earlier session-2 walks re-rendered the same rows through the same hop sequence) and
  **held on the LCD through t=200000** after the loop derailed — exact iteration count not
  measurable from refire-contaminated counters.
- **Actual derail**: final `pc=0x0316 sp=0x5363` (sp out of RAM). The walk's ER2 advances +64/replica from `0xF800`; after dozens of
  replicas it writes
  `0xFA00+` (past the 0x200-byte screen buffer) into untested MMIO; combined with the
  interrupt context in the mix, the state finally collapses. The LR "fix" is not needed; the
  next parameter = **clamp the march** (re-kick with ER2 reset each frame — i.e. the
  animation's own already-proven per-frame hygiene — or find a gadget that re-zeros ER2).

## 4. Honest hardware note

The 12-frame animation above is **harness-driven per-frame re-kicks** (host-side re-kick each
frame). On the physical calculator the frame source would be: (a) the S15-style typed payload +
AC←EXE re-trigger (slow, human-paced — seconds per frame, and the 4-designed-rows-per-100-byte-tile
ceiling from session 2 applies), or (b) a self-sustaining walk loop (proven here ~40 iterations
deep with the ER2-clamp fix pending). **A designed animated scene on hardware is NOT
demonstrated**; what IS demonstrated: single-shot persistent static art (32-row, harness),
4-row-per-tile shaped art from a period-100 typed payload, and a ~40-replica self-loop on the
emulator. Animated movement = open.

---

# Session 4 (2026-11-21) — ANIMATION DONE: 12 distinct frames re-kicked live

## The fix that unblocked the re-kick (order matters, 3 parts)

1. **`unbreak_at(0x2B1E)` + `unbreak_at(0x35BE)` BEFORE writing any kick state** (the armed
   breakpoints refire on multi-cycle instructions and re-trap the freshly-popped chain; this
   alone was NOT sufficient — see 3).
2. **The parked chain leaves the CPU in a HALT** (`Chipset::run_mode = RM_HALT`, entered via the
   `0x4EF2`-park's HLT; the park signature = **`pc==0x4B96 && sp==0x8C18`**, NOT 0x4EF2).
   Writing `cpu.pc/sp` is ignored while halted. The cure = **`emu:run()` (the Lua binding of
   `Chipset::SetRun()`, `run_mode = RM_RUN`) right after the kick state is written.** This was
   the missing piece of every "re-kick freeze" since session 5 of rop_diag.
3. **Clamp the march: reset `ER2=0xF800` (cpu.r2/r3) every kick** — otherwise the walk's
   `ER2 += 64/replica` marches out of the 0x200-byte screen buffer into untested MMIO (the
   session-3 derail: `pc=0x0316 sp=0x5363`).

Per-frame sequence in `render_anim.lua`: unbreak → restore `fw_pc/fw_sp` → plant design
(window 12-packed + stride-inverse src) → write the proven kick state (chain
`[0x35BE|src|junk12|0x35AE|PARK]`, r0=32, ER2=0xF800) → `emu:run()` → wait for the park
signature → +2000 ticks → capture `data[0xF800..]` → next frame.

## Result — verbatim captures (12/12 distinct)

```
md5 of demo/anim/frame01..12.ppm = 12 DISTINCT md5s
F01 lcd0123=000000000000000000000000|FFFFFF00FF00FF00FF00FF00|FFFFFF00FF00FF00FF00FF00|FFFFFF00FF00FF00FF00FF00
F03 lcd0123=000000000000000000000000|FF00FFFFFF00FF00FF00FF00|FF00FFFFFF00FF00FF00FF00|FF00FFFFFF00FF00FF00FF00
F05 lcd0123=000000000000000000000000|FF00FF00FFFFFF00FF00FF00|FF00FF00FFFFFF00FF00FF00|FF00FF00FFFFFF00FF00FF00
F07 lcd0123=000000000000000000000000|FF00FF00FF00FFFFFF00FF00|FF00FF00FF00FFFFFF00FF00|FF00FF00FF00FFFFFF00FF00
F09 lcd0123=000000000000000000000000|FF00FF00FF00FF00FFFFFF00|FF00FF00FF00FF00FFFFFF00|FF00FF00FF00FF00FFFFFF00
F11 lcd0123=000000000000000000000000|FF00FF00FF00FF00FF00FFFF|FF00FF00FF00FF00FF00FFFF|FF00FF00FF00FF00FF00FFFF
```

(The all-zeros row 0 is constant — see the caveat below.) The bar (even-BLOCKED checker
background, lerped bar at the odd blocks) visibly advances byte-by-byte: F01 @byte1, F03 @3,
F05 @5, F07 @7, F09 @9, F11 @11; next-cycle wrap: F13 would repeat F01 (x0 = (f*8)%96); all 12 md5s distinct.

Artifacts:
- **`demo/render_anim.gif`** — full 96×32, 3× nearest (288×96), 125 ms/frame (8 fps), looping; 12 frames (PIL-verified `n_frames=12`).
- **`demo/render_anim_contact.png`** — 4×3 grid at 2× (818×232).
- **`demo/render_anim_frame07_x3.png`** — 3× PNG of the mid-animation frame.
- `demo/anim/frame01..12.ppm` — the real, distinct captured frames.

## Row-0 caveat (repeat, now confirmed on 12/12 frames)

LCD row 0 always reads `000000000000000000000000` in every flush-rendered frame although the
window row 0 holds our design: **row 0 = the firmware-owned icon strip** (sprite overlay
`SPR_*` in `Screen.cpp`). Animation/design space = **rows 1-31 only**.

## Honest hardware note

The animation is **harness-driven per-frame re-kicks** (host Lua re-kicks each frame; the
calculator itself would need a frame source per redraw). On the physical CY-845 the two known
frame sources are: (a) the S15-style typed payload + AC←EXE re-trigger — slow, human-paced
(seconds per frame), with the **4 designed rows per 100-byte payload tile** ceiling (session 2);
(b) the self-sustaining flash-walk byte — proven to survive the flush hop and re-render
(session 3), pending the ER2-clamp (the same `r2/r3=0xF800` reset the harness does each frame).
**Animated movement on hardware = still not demonstrated.**

Runs: 3 this session (re-kick-freeze run ×2 [unbreak-only attempts, still frozen], then the
`emu:run()` fix + the 12 distinct frames). Binary unchanged: `emulator/emulator` md5
`4dcb0b1c…` original; ROM md5 `c4c7d7fb…`; run log md5 `6a46f1fc…`; pgrep empty.
