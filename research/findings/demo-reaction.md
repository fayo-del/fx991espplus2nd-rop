# demo-reaction.md — REAL capture of the verified ROP reactive-loop demo

**Verdict: SUCCESS.** The verified 11-beat ROP loop (rop_work1 payload, untouched) ran
free-running for 3 hold/release cycles (200k+200k ticks each); the KEYSCAN-driven 0x4CDC
branch toggled LCD bit F80B.4 per pass — `F80B=0x90` with Right held, `0x80` on release —
and the release WAS seen by the ROP KEYSCAN (not a static on-state). 179 real PPM frames
captured in-Lua; GIF + contact sheet assembled with PIL.

## Commands (headless, from `research/CasioEmuX/`, `pgrep -af emulator` empty before/after)
```
SDL_VIDEODRIVER=dummy ./emulator/emulator model=models/fx991esplus2 script=demo_reaction.lua > /tmp/demo_reaction2.out
python3 demo/make_gif.py        # PPM -> 4x nearest GIF + horizontal contact sheet
```
Two runs: run 1 (`/tmp/demo_reaction.out`, REACT_SAMPLE_EVERY=2500 → 17 frames, sparse)
verified the schedule; run 2 (`REACT_SAMPLE_EVERY=180`) is the deliverable. Run 2 reproduced
run 1 bit-exactly (same REACT-PHASE scan_hits, same finals) — deterministic capture.
`demo_reaction.lua` = copy of `rop_work1.lua` (base md5 fadf4c57… preserved; only additions:
print cap on the per-hit CHAIN line, key-phase scheduler, REACT sampler).

## Per-phase F80B (verbatim, run 2)
```
REACT-PHASE t=260002 holds=NONE scan_hits=5102 F80B=90    <- right before 1st release lands
REACT-PHASE t=460002 holds=RIGHT scan_hits=10605 F80B=80  <- right before 1st re-hold lands
REACT-PHASE t=660002 holds=NONE F80B=90 ... REACT-PHASE t=860002 holds=RIGHT F80B=80
REACT-PHASE t=1060002 holds=NONE scan_hits=26644 F80B=90
```
Sample tally: 87× `F80B=90 holds=RIGHT`, 87× `F80B=80 holds=NONE`, 5 boundary/lag samples
(F80B flips ~1-2 passes after the key change — exactly the KEYSCAN→0x4CDC pass latency).
Loop stayed alive: KEYSCAN hits grew monotonically to 31862, cdcw=37172 passes; end state
`PROTO: REACT-DEMO hits=31862 piv=79932` final-F80B=80; CHAIN #25000 proves steady geometry
(sp=8DB2 ER14=F28E lr=2B1E).

## Artifacts
- `demo/frames/r_c{1..3}{hold,rel}_NNN.ppm` — 179 frames, P6 96×32 maxval 255, in-Lua capture
- `demo/reaction.gif` — 384×128 (4× nearest), 103 stored frames @10 fps (PIL merged the
  many consecutive identical samples), loops forever
- `demo/contact.png` — 34368×64 horizontal sheet, all 179 frames at 2× (left→right = time)
- Log: `/tmp/demo_reaction2.out` (run 2 deliverable), `/tmp/demo_reaction.out` (run 1); assembler `demo/make_gif.py` (PIL)

## Mapping + verification
`data[0xF800+row*16+byte]`, bits 7..0, MSB-first → pixel; **set bit = dark (0,0,0)**, clear =
white — matches the harness's own `#`-renders (boot text/SIGMA screens read correctly).
Known-pattern check: c1hold-last vs c1rel-last frames differ in **exactly one pixel,
(row 0, col 91)** = F80B.4 (byte offset 11, bit 4), with F80B=0x80's own bit-7 pixel (col 88)
already on — precisely the verified branch semantics.

## Honest limits
- Static row content: **no scroll.** The source-advance idea failed before (0x2ED8 hijack,
  no carry/ER2-arith gadget) and was NOT retried; memcpy12 dst/src fixed (ER2=0xF811, src=0x8154).
- The ONLY key-reactive animation is the single F80B.4 pixel (row0 col91). Row 1 drifts
  slowly per pass in a key-independent way (walk-phase LCD tile writes) — NOT input-driven.
- No game logic, no player state, no movement, no scores — a state bit + fixed redraw only.
- Hardware caveat: emulator-only; payload planted by the harness (typed + flash-walk
  W()-writes). On real fx-991ES PLUS 2nd hardware it would have to be entered manually —
  the emulator is the testbed, not a hardware proof.

Baselines (md5, unchanged): rop_work1.lua fadf4c572f7537363c11f8c6158b9edf ·
rop_draw3.lua fed27f1a9b3e9a9c426160384bfc0b55 · rop_br1.lua eaeaca418164a42fe63a3ce189a2feca ·
rop_br1_hold.lua 2cea3804b6ba1f6f67f848a0e599cb4f · emulator/lua-common.lua 5a57ffcac39827ca12cb587fa685da91 ·
emulator/emulator 4dcb0b1c6ce05aff52c2b1cb9de5631a
