# game-snake.md — SNAKE-LITE (1-D arrow-mover) playable game, typed-hackstring ROP chain, PROVEN in emulator

Date: 2026-11-22. Agent: `GameBuild`. Script: `research/CasioEmuX/game_snake.lua`
(base: `game_loop.lua` = rop_work1 v11b skeleton, VERIFIED 48-pass loop). Logs:
`/tmp/game_snake1.out` … `/tmp/game_snake4.out` (run 4 = decisive). Artifacts in
`research/CasioEmuX/`: `game_snake_payload.bin`, `game_snake_frame{2,5,…,47}.raw/.png/_x4.png`.
No emulator source edits; `rom.bin` untouched.

## Verdict

**SUCCESS — 4 runs (budget ≤8), no blind tweaks, no divergence.** The typed-trigger
ROP chain runs a self-sustaining game loop for **48 passes** (`PROTO: SNAKE-LOOP
hits=53 pc=4CDC sp=8DB6 ER14=8DA8 piv=327 cdcw=48`). Every work pass renders a
12-byte cell to the LCD at **dst = ER2 = 0xF8\<KID\>** — i.e. **the held arrow key
selects the cell's row** (measured below) — while the sprite source self-slides
+12 B/pass and the F80B.4 pixel shows key-held. Two identical runs (2 and 3)
produced byte-identical evidence streams (md5 `b2289521b3c4940cff5b6e58900b9974`
over WMBE/KEYSCHED/PROTO lines) and identical payload md5 → **deterministic**.

## What the game is (honest statement)

- **Controls (hardware player):** hold **Right** (0x37) or **Up** (0x27) → cell on
  LCD **row 8**; hold **Left** (0x26) or **Down** (0x36) → cell on **row 12**;
  release all → cell on **row 16**. The chain polls the keyboard by itself every
  pass (in-loop KEYSCAN 0x4D0E); the player only holds/changes one arrow — **no
  per-pass keystroke needed**, one held arrow is the whole input.
- **Per pass (chain-only, no harness writes after the trigger):** KEYSCAN →
  r0=presence, r2=KID (7F=Right/Up, BF=Left/Down, FF=none) → 0x4CDC sets F80B.4
  (row-0 "button pressed" pixel, visible) → head 0x3538 sets r3=0xF8 → post-head
  KEYSCAN loads r2=KID → R0-loader sets r0=1 → memcpy12 0x35BE draws 12 B at
  dst=ER2=0xF8\<KID> (0xF87F/0xF8BF/0xF8FF = rows 8/12/16) from a src window that
  self-advances +12 B/pass (PUSH EA writeback) → sprite animates → pivot 0x75DE
  re-syncs SP → next pass.
- **Win/lose:** the chain has no compare gadget, so it does not score internally;
  the playable rule is judged on the LCD: move the cell onto a chosen target row
  (the cell leaves a persistent trail — the zero-byte ban forbids 0x00 erase
  bytes, so the "snake" grows and old cells stay lit). Score = passes survived,
  observable via F80B.4 and the pass counter.
- **Limits:** 2 effective directions (KID distinguishes ki7 vs ki6 only —
  4-way was proven impossible in-loop, rop-matrix-input.md §6); 3 discrete rows,
  no smooth accumulation (see budget below); no erase/collision/score in-chain;
  park 0x4EF2 is terminal in-emulator.

## Why 1-D (payload-budget justification)

The 100-byte payload is shared between chain-control words and content; the
per-pass PC stream has ~13 4-byte slots, all consumed by the proven skeleton
(loader/pivot/branch/head/R0-loader/memcpy/tail). 2-D movement would need either
a conditional dispatch on r2 (CMP R2,#imm with KID immediates + both paths ending
in POP PC — bank-0 census in rop-matrix-input.md §2 found NONE walk-safe; bank-1
sweep found only 0x3A50-class r0 tests) or an accumulator that survives the
per-pass keyscan — impossible: the keyscan owns r2 every pass (`L R2,[EA]`), so
any ER2 accumulator's low byte is overwritten by KID; ER2+=16 from memcpy is
likewise clobbered; an ER14 accumulator would need an extra reload slot per pass,
and the tail slots are phase-locked to the pivot (measured: shifting them breaks
the 0x75DE re-sync). The chosen design needs **zero extra slots**: the post-head
KEYSCAN simply reuses a flood slot (W(90)), and dst=0xF8\<KID\ falls out of
r3=0xF8 (head) + r2=KID (keyscan) for free. Hence the assignment's 1-D fallback
is what the 100-byte budget expresses.

## Payload (100 B at 0x8154, zero-free, floods 0x8154..0x8DFF period 100 phase 0)

md5 `e575f3f465dc832f16a7437c5a562e37` (artifact `game_snake_payload.bin`):
```
0E4DBE350E4D40820E4D0E4D0E4D0E4D0E4D0E4D0E4D0E4D66300E4DAC8D6630AC8DA88DDE75DE75F24EDE75
66300E4DAC8D0E4D0E4D0E4DA88D0E4D8EF20E4D0E4DDC4C0E4D0E4D0E4D0E4D0E4D0E4D0E4D38350E4D0CF80E
4D0E4D0E4D36310E4D014D
```
Distinct bytes (23): `01 0C 0E 30 31 35 36 38 40 4C 4D 4E 66 75 82 8D 8E A8 AC BE DC DE F2 F8` —
all zero-free. Plain-key tokens per `docs/typable-tokens.md` atlas: `30 31 35 36 38
4E 82 BE` (8 bytes); the other 15 bytes (`01 0C 0E 40 4C 4D 66 75 8D 8E A8 AC DC DE F2 F8`)
are delivered on hardware by the autotyper flash-walk (every non-null byte is
walk-reachable, `docs/esp-autotyper.md`; the walk is not emulator-reachable,
`kyb_h7findings.md`, so in-emulator the pre-trigger equip is the documented
stand-in, exactly as in the proven rop_e2e/game_loop scripts — the TRIGGER
(AC,←,EXE) and all PLAYER arrows are pure `Keyboard:PressKey`). EA src word
0x8240: high byte 0x82 ∈ hardware-typable set {81,82,84,85,89,8A,8B,8C} ✓
(game-content.md).

### Gadget words used (payload offset → word → role)

| off | word | role |
|---|---|---|
| 2 | 0x35BE | memcpy12 (dst=ER2, src=EA, 12 B × r0) |
| 6 | 0x8240 | EA src, self-slides +12/pass |
| 24/30/44 | 0x3066 | POP ER14; POP PC re-loader |
| 28/32/48 | 0x8DAC | ER14 replay base |
| 34/56 | 0x8DA8 | ER14 pivot value / self-refresh |
| 36/38/42 | 0x75DE | pivot MOV SP,ER14; POP ER14; RT |
| 40 | 0x4EF2 | park insurance (+2 phase) |
| 60 | 0xF28E | "8E F2" = POP PC at 0x8DAC → pivot |
| 66 | 0x4CDC | CMP R0,#0 → SB/RB F80B.4 (key-held pixel) |
| 82 | 0x3538 | head POP ER2; POP ER8; MOV ER0,ER2; RT (moved from W86) |
| 86 | 0xF80C | head ER2 operand → r3=0xF8 |
| 90 | 0x4D0E | KEYSCAN after head → r2=KID ⇒ dst=0xF8\<KID\ |
| 94 | 0x3136 | R0-loader POP ER0; POP ER4; POP PC (r0=1, r2 kept) |
| 98 | 0x4D01 | ER0 value (r0=1, r1=0x4D) |
| all other even offs | 0x4D0E | flood = KEYSCAN hops (r0=presence, r2=KID) |

## Decisive evidence (run 4, `/tmp/game_snake4.out`, 48 passes, 16 frames)

Walk memcpy (WMBE, walk-only lr==0x2B1E) — **dst follows the held arrow every time**:
```
pass= 6 key=none  r2=FF ER2(dst)=F8FF easlot=8240
pass=14 key=Up    r2=7F ER2(dst)=F87F easlot=824C
pass=20 key=Left  r2=BF ER2(dst)=F8BF easlot=8258
pass=26 key=Down  r2=BF ER2(dst)=F8BF easlot=8264
pass=32 key=Right r2=7F ER2(dst)=F87F easlot=8270
pass=38 key=none  r2=FF ER2(dst)=F8FF easlot=827C
pass=46 key=Right r2=7F ER2(dst)=F87F easlot=8288
```
EA slide +12/work-pass with distinct 12-B sprite windows:
`8240: DE75DE75F24EDE7566300E4D → 824C: AC8D0E4D0E4D0E4DA88D0E4D → 8258: 8EF20E4D0E4DDC4C0E4D0E4D → 8264: 0E4D0E4D0E4D0E4D0E4D3835 → 8270: 0E4D0CF80E4D0E4D0E4D3631 → 827C: 0E4D014D0E4DBE350E4D4082 → 8288: 0E4D×6`

PASS lines (per-pass key read at 0x4CDC, walk-only): r0/r2 follow the schedule —
`PASS#1..6 r0=01 r2=7F` (Right held), `PASS#7..14 r0=00 r2=FF` (none), then 7F
phases again; preF80B flips 0x80↔0x90 exactly at key boundaries (CDC-AFTER lines).

LCD frames (PNG `game_snake_frameN.png`, 96×32, ink rows): frame8–14 → cell on
**row 16** (44 px, key=none); frame17–20 → cell on **row 8** (35 px, key=Up);
frame23+ → cell on **row 12** (36 px, key=Left/Down); earlier cell rows stay lit
(trail); row 0 ink count 3↔4 = F80B.4 key-held pixel. Frame md5s differ per phase
(e.g. frame8 `c7996d6e…`, frame17 `52da7043…`, frame23 `0deb6afe…`).

Trigger provenance (run log): `PROBE1: before=2 after=2 NOT-INSERTED(good)`,
`PAYLOAD: len=100 zerofree=true`, 41-key typed head delivered at T=1 (rop_e2e
recipe), AC/←/EXE typed via PressKey at final_t 1/20001/40001 → strcpy tiler
flood → chain from the tiled stack; after the trigger **zero data[] writes** —
all state changes above come from the chain + held arrows (PressKey only).

Determinism: runs 2 and 3 (identical script+schedule) → identical payload md5
`e575f3f4…` and identical WMBE/KEYSCHED/PROTO stream md5
`b2289521b3c4940cff5b6e58900b9974`.

## Hardware keypress list (minimal)

1. One-time hackstring (see `docs/esp-autotyper.md` / `keypress_table.md`): 41-key
   typed head (warm-up, SETUP, formula `X=Σ(X,1,1×10⁹`, CALC EXE AC ← DEL DEL DEL 2
   CALC EXE ← 1), then the 100 payload bytes (8 plain-key tokens direct; 15
   walk-shaped bytes via type-`5` + ◀/▶ walk counts per `hardware-procedure.md`),
   then **AC, ←, EXE** — that fires the flood and starts the game.
2. Playing: **hold one arrow** — Right/Up → cell row 8, Left/Down → cell row 12,
   none → row 16. The chain samples it every pass by itself; changing the held
   arrow mid-run moves the cell on the next work pass (≈ every 6–8 CDC passes).
   No other keypresses are needed to play.

## Run budget / honesty

4/8 runs used: run 1 = layout probe (loop healthy, first dst hit F8BF@r2=BF seen
immediately — no divergence to log), runs 2+3 = evidence + determinism pair,
run 4 = decisive 48-pass run. In-emulator the payload equip at 0x8154 pre-trigger
is the documented stand-in for the hardware autotyper delivery (flash-walk
unreachable in the emulator); the trigger and player input are typed keys only.
