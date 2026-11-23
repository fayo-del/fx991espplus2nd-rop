# real02_framegen.md — FULL content freedom: the chain COMPUTES a frame and paints it on the LCD, pass after pass (2026-11-22)

Agent: `FrameGen`. Script: `research/CasioEmuX/real02_framegen.lua` (base: `game_snake.lua`
48-pass loop, VERIFIED). Logs: `/tmp/real02_run1.out` … `/tmp/real02_run4.out`.
Artifacts in `research/CasioEmuX/`: `real02_framegen_payload.bin` (md5-stable),
`real02_frame{1..8}.raw` + `.png` + `_x4.png` (16 PNG frames). No emulator source edits; `rom.bin` untouched.

## Verdict

**PROVEN — the content ceiling is broken.** From the typed hackstring alone, the ROP chain
now **computes 12 bytes per pass and stores them directly onto the LCD** (CPU `ST [EA+]`
into SFR 0xF83A-0xF845, i.e. 0xF8xx — the direct-LCD-store question of step 3 is answered
YES, LCD SFR is writable by plain CPU stores), while memcpy12 simultaneously renders a
12-byte window at `dst=ER2=0xF82E`. The computed byte values (`r0/r2 += 0xD0` per store)
**appear nowhere in the 100-byte payload** (payload distinct bytes: `01 0C 0E 10 1E 2B 30
31 35 36 38 4D 4E 54 66 75 85 8D 8E A8 AC BE DE F2 F8`; written bytes include `EC BC 8C
5C AE 7E 98 68 A4 74 B0 80` — all computed), and **change every pass** (`r0` base advances
+0x0C/pass, tracking the EA slot slide). 8 work passes rendered with a visibly changing
computed strip on LCD rows 3-4 (PNG frames), loop still healthy at the guard
(`PROTO: FRAMEGEN-LOOP hits=10 pc=35BE sp=8DDA ER14=8DA8 piv=327 wmbe=36 workpass=8
w3854=96`). Runs 3 and 4 produced **byte-identical payload and frames** (md5 diff empty) →
deterministic.

## What the chain does per pass (steady-state walk, from the POPPC trace)

Entry `sp=0x8D9C` (phase 44, 25 tiles = 100 B window), then every pass the pivot
`0x75DE` (`MOV SP,ER14; POP ER14; RT` with `word[0x8DA8]=0x8DA8` self-refresh) re-syncs
`sp=0x8DA8` and the walk re-reads the same flood tiles:

```
sp=8DAA tile=5438 8EF2  -> 0x3854  (W58)   ┐
sp=8DB0 tile=5438 0E4D  -> 0x3854  (W64)   │ 4x 0x3854: ADD R2,#208; ST R2,[EA+];
sp=8DB6 tile=5438 0E4D  -> 0x3854  (W70)   │   ADD R0,#208; ST R0,[EA+]; ST R3,[EA+];
sp=8DBC tile=5438 0E4D  -> 0x3854  (W76)   ┘   POP R4; RT   => 12 computed bytes at [EA..EA+11]
sp=8DC2 tile=3835 0E4D  -> 0x3538 head (POP ER2<-W86=0xF80C, POP ER8, MOV ER0,ER2, RT)
sp=8DCA tile=4D0E 0E4D  -> 0x4D0E KEYSCAN (r2<-KID, r0<-presence)   (W90)
sp=8DCE          -> 0x3136 R0-loader (W94/W98: r0=1)
sp=8DD6 tile=BE35 0E4D  -> 0x35BE memcpy12 (W2), POP EA<-word[8DDA]=W6=0x8510
sp=8DE8 tile=1E2B 0E4D  -> 0x2B1E passthrough (W20, replaces a keyscan hop)
sp=8DEC tile=6630 0E4D  -> 0x3066 re-loader (W24/W28) ... pivot 0x75DE (W36) -> sp=0x8DA8
```

Payload diff vs `game_snake.lua`: `W(58)=W(64)=W(70)=W(76)=0x3854`, `W(6)=0x8510`,
`W(20)=0x2B1E`, `W(90)=0x4D0E` (keyscan kept); the whole loop skeleton/tail is unchanged.
All 100 payload bytes zero-free (`PAYLOAD: len=100 zerofree=true`).

## Measured budget (the assignment's quantification)

- **Computed bytes per pass:** 12 B/pass from 4 tiles of `0x3854` (3 B each, 6 stack bytes
  per tile = 24 B = 6 of the ~25 tiles of the pass window). In the entry pass only, the
  MB05 ER14-loop variant gives 1 B per 3 tiles, ≤ ~6 stores in the 25-tile window (MB05 measured).
- **Stack consumption / re-arm:** the pivot **re-arms the walk every pass** — SP is reset
  to 0x8DA8 and the flood tiles there are re-read, so the stack is *never* consumed by the
  loop: passes are unbounded, limited only by the harness guard (here 8 work passes /
  36 memcpy walk-hits / 327 pivots within `final_t<=2.6M`; `game_snake` proved 48 loop
  passes in the same budget). The only stack mutation is the EA slot `word[8DDA]`, advanced
  +12/work-pass by memcpy12's `PUSH EA` writeback (by design): `easlot 8510→851C→8528→…→8564`.
- **EA behavior (key discovery):** every KEYSCAN pins `EA=0xF040` (keyboard KI region —
  writes there are IGNORED, `Keyboard.cpp:31`), and memcpy12 ends with `LEA [ER2]` leaving
  `EA = dst+12 = 0xF83A`. Consequence: the `0x3854` `[EA+]` stores of pass n land at
  **0xF83A-0xF845 = LCD row 3/4** — direct computed painting on the screen (this is why the
  literal "stage in 0x8500 then memcpy from there" of step 1 does not lockstep: EA is
  hijacked between passes; run 1/2 showed writes pinned at 0xF040 and dropped). Mid-RAM
  staging still works in the entry pass via the ER14 loop (MB05: computed bytes persisted at
  0x8511-0x8516), and the sliding memcpy window (W6=0x8510) reads mid-RAM flood content.
- **LCD writes:** both paths proven — memcpy12 `ST [ER2]` with `ER2=0xF82E` (sliding 12-B
  window, content changes per pass), and direct `ST Rn,[EA+]` with `EA=0xF83A..0xF845`
  (computed 12 B/pass). LCD SFR 0xF800-0xF8FF is CPU-store-writable.
- **Changing pattern:** computed strip values per pass (run 3, verbatim):
  pass2 `0E EC 00 | 00 00 00 | AE 8C F8 | 7E 5C F8`, pass3 `0E F8 00 | … | AE 98 F8 | 7E 68 F8`,
  pass4 `0E 04 00 | … | AE A4 F8 | 7E 74 F8`, pass5 `0E 10 00 | … | AE B0 F8 | 7E 80 F8`
  — the r0-stream advances +0x0C/pass, so the on-LCD sprite changes every pass.
  PNGs `real02_frame{1..8}.png` show rows 3-4 changing frame to frame.

## Verdict on content freedom (what graphics are now possible)

- The chain **synthesizes arbitrary bytes** (add/step accumulators) and **paints them on the
  LCD per pass** — game content is no longer capped at the 100 payload bytes. A 12-byte
  computed sprite per pass at a computed address (here 0xF83A = prev memcpy dst + 12),
  with per-pass evolving content, is PROVEN; combined with the entry-pass ER14 loop
  (MB05) and the sliding memcpy window, multi-row computed scenes (border box / glyph /
  diagonal = dst advancing per pass via `ADD ER2,#1` 0x992C) are reachable building blocks.
- Honest limits: per-pass register state is almost fully pinned by the walk (r0 from the
  memcpy exit pops, r2 reset by head/keyscan), so the *values* evolve by fixed strides
  (+0xD0/tile, +0x0C/pass) rather than arbitrary per-pass constants; arbitrary bytes are
  available in the entry pass (≤6 B) or by spending tiles on POP-value reloads. The
  memcpy dst stayed pinned at 0xF82E in this geometry (W90 keyscan reads KID=0x2E in this
  phase), so the strip position was fixed here; moving it needs the keyscan/KID path or
  0x992C (+1/pass). Writes past 0xF8FF were not exercised (guard stopped at 8 passes).

## Run budget / honesty

4/6 runs used. Run 1 = layout probe (loop healthy, 8 work passes, but discovered EA pinned
at 0xF040/KI-ignore so computed writes vanished; also caught a harness bug: `WMBE` was
local, crashing `finish`). Run 2 = W90 passthrough (EA still pinned — tail keyscan at W20
found via POPPC trace; bug fixed). Run 3 = **decisive**: W20 passthrough + W90 keyscan →
lockstep broken the right way, 12 computed bytes/pass land directly on LCD 0xF83A+, 8 work
passes, 8 PNG frames, changing pattern. Run 4 = determinism rerun (identical payload + frame
md5s). All runs `exit=124` (40 s timeout) but `finish()` fired before the timeout, so logs
are complete. Typed trigger provenance: same rop_e2e recipe (41-key head, AC/←/EXE via
PressKey at final_t 1/20001/40001), payload equipped pre-trigger as the documented
stand-in for the hardware autotyper delivery; after the trigger **zero data[] writes** —
the key schedule is PressKey only. In-emulator the flash-walk delivery remains the
documented stand-in (as in all prior milestones); every payload byte is zero-free and in
the proven typeable-token class.
