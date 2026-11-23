# game-loop.md — self-sustaining INTERACTIVE render loop from the typed hackstring (SUCCESS, 3 runs)

**Verdict: SUCCESS (run 3 of 3; run 1 proved the loop+slide, run 2 added the pass-driven
key schedule, run 3 moved the dst off the branch bit).** The typed-ROP chain now runs a
closed loop that, **every pass**: polls the keyboard (KEYSCAN 0x4D0E → ER0 = key presence,
r2 = KID identity), branches on it (0x4CDC → F80B.4 = LCD row 0 byte 11 bit, visible on
screen), and renders a 12-byte frame to the LCD (memcpy12 0x35BE → dst 0xF80C) whose
**source window self-advances +12 bytes per pass inside the chain** (PUSH EA writeback),
so LCD content changes every pass without any harness write. A harness key schedule
(Right/Left/none/Down/Up, rotated every 4 passes at pass boundaries) makes ER0/r2 and the
on-LCD key bit differ across passes.

- Script: `research/CasioEmuX/game_loop.lua` (base: `rop_work1.lua` v11b — VERIFIED loop
  skeleton kept byte-identical: W(30/34/36/38/42/44/48/56/40) + re-loader chain (W(24/28/32/60))
  + branch W(66) + head W(86) + R0-loader W(94/98) + memcpy pc W(2); only W(90) and W(6)
  changed, plus harness logging/key schedule).
- Commands (headless, `SDL_VIDEODRIVER=dummy`, run from `research/CasioEmuX/`):
  `SDL_VIDEODRIVER=dummy timeout 40 ./emulator/emulator model=models/fx991esplus2 script=game_loop.lua`
  Logs: `/tmp/game_loop1.out` (loop+slide only), `/tmp/game_loop2.out` (key schedule),
  `/tmp/game_loop3.out` (decisive). No emulator source edits; `rom.bin` untouched.

## Payload (typed buffer at 0x8154, len=100, all words zero-free)

```
flood 0x4D0E everywhere, then:
W(30)=0x3066 W(34)=0x8DA8 W(36)=0x75DE W(38)=0x75DE W(42)=0x75DE W(44)=0x3066
W(48)=0x8DAC W(56)=0x8DA8 W(40)=0x4EF2            -- loop skeleton (proven, unchanged)
W(66)=0x4CDC                                   -- per-pass key branch (r0 from W(62) keyscan)
W(86)=0x3538 W(90)=0xF80C                      -- head: ER2 <- 0xF80C (row0 b12..15 + row1 b0..7;
                                               --   OFF 0xF80B so the key bit survives)
W(94)=0x3136 W(98)=0x4D01                      -- R0-loader: r0=1 (1 memcpy iteration), no keyscan between
W(2)=0x35BE  W(6)=0x8240                       -- memcpy12 pc; EA = tiled-flood base (self-slides)
W(24)=0x3066 W(28)=0x8DAC W(32)=0x8DAC W(60)=0xF28E   -- post-memcpy ER14 re-loader chain
```
Run-3 planted buffer (verbatim): `PROTO: final-buf 0E4DBE350E4D40820E4D…66300E4DAC8D6630AC8DA88DDE75DE75F24EDE7566300E4DAC8D0E4D0E4D0E4DA88D0E4D8EF20E4D0E4DDC4C0E4D…38350E4D01F80C0E4D36310E4D014D len=100`

## The in-chain src slide (mechanism, confirmed by code + measurement)

`0x35BE` = `POP EA; L XR4,[EA+]; L QR8,[EA+]; PUSH EA; …` — `Pop16` reads `word[sp]`,
`sp+=2`; `PUSH EA` does `sp-=2; word[sp]=EA` (emulator/src/Chipset/CPUPushPop.cpp:149-158,
135-147). After the two loads EA advanced +12, and the PUSH writes the advanced EA **back
into the same slot it was popped from**, so every pass pops `prev_EA + 12`. Measured
(`EA-POP`/`MBE-ENT` at sp=0x8DDA, once per work pass):

```
EA=8240 → 824C → 8258 → 8264 → 8270 → 827C → 8288 → 8294 → 82A0 → 82AC …   (+12 per pass)
src12: DE75DE75F24EDE7566300E4D → AC8D0E4D0E4D0E4DA88D0E4D → 8EF20E4D0E4DDC4C0E4D0E4D
      → 0E4D×6 → 0E4D38350E4D01F80E4D3631 → 0E4D014D0E4DBE350E4D4082 → 0E4D×6
```

## Decisive lines (run 3, /tmp/game_loop3.out, verbatim)

Finish (loop still running when the 48-pass guard fired):
```
PROTO: LOOP-INTERACTIVE hits=53 pc=4CDC sp=8DB6 ER14=8DA8 piv=402 cdcw=48
PROTO: final-F80B=90 F80C=00 rows01=000000000000002000004090|0E4D0E4D0E4D0E4D00000000
```
Per-pass key read + render (PASS lines; r0/ER0 = key presence, r2 = KID, lcd0|lcd1):
```
PASS#1  CDC r0=01 r2=7F ER0=0001 preF80B=80 key=Right lcd0=…4080|0000…      (boot frame)
PASS#7  CDC r0=01 r2=BF ER0=0001 preF80B=90 key=Left  lcd0=…4090|F24EDE7566300E4D00000000
PASS#13 CDC r0=01 r2=BF ER0=0001 preF80B=90 key=Down  lcd0=…4090|0E4D0E4DA88D0E4D00000000
PASS#19 CDC r0=01 r2=7F ER0=0001 preF80B=90 key=Up    lcd0=…4090|0E4DDC4C0E4D0E4D00000000
PASS#25 CDC r0=01 r2=BF ER0=0001 preF80B=90 key=Left  lcd0=…4090|0E4D0E4D0E4D0E4D00000000
PASS#31 CDC r0=00 r2=FF ER0=0000 preF80B=90 key=none  lcd0=…4090|0E4D0CF80E4D363100000000
PASS#36 RB  r0=00 r2=FF ER0=0000 preF80B=90 key=Up    lcd0=…4090|0E4D0CF80E4D363100000000
```
Key bit on the LCD flipping exactly at the key-phase boundary (CDC-AFTER = 1 tick after
the branch; SB = key held sets F80B.4, RB = none clears it):
```
CDC-AFTER pass#30 SB postF80B=90 bit4=1     (key held)
CDC-AFTER pass#39 CDC postF80B=80 bit4=0    (none phase -> RB cleared it)
CDC-AFTER pass#46 CDC postF80B=90 bit4=1    (key held again -> SB)
PROTO: final-F80B=90                        (Up held at pass 48)
```
Key schedule fired at pass boundaries: `KEYSCHED pass=4 key=Left`, `pass=8 key=none`,
`pass=12 key=Down`, `pass=16 key=Up`, `pass=20 key=Right`, … (every 4 passes).

## Acceptance mapping

- (a) **ER0 differs across passes per the key schedule** — measured: ER0=0001/r2=0x7F
  (Right, Up), ER0=0001/r2=0xBF (Left, Down), ER0=0000/r2=0xFF (none, PASS#31–38).
- (b) **LCD row content differs across passes** — measured: row 1 frame slides
  (F24EDE75… → 0E4D0E4DA88D… → 0E4DDC4C… → 0E4D0CF80E4D3631…) via the in-chain
  +12/pass EA advance; row 0 byte 11 carries the per-pass key bit (0x80↔0x90).
- ≥3 chain passes: 48 passes in one run, loop still healthy at the guard.

## Key→content coupling: what works now, what is missing

WORKS (verified this run): the pressed key is sampled every pass into ER0 (presence)
and r2 (KID: 7F=Right/Up, BF=Left/Down, FF=none); the 0x4CDC branch turns it into a
persistent on-LCD pixel (row 0 byte 11 bit 4: 0x90 key held / 0x80 none) — i.e. **the
key changes what is drawn, every pass**; the frame content auto-advances per pass.

MISSING for full key→address coupling (key picks dst/src of the memcpy): no walk-safe
conditional dispatch exists — `CMP R0,#imm; BC` gadgets in bank 0 end in SB/RB state
bits (0x4CDC), not path selection, and the `BC`-adjacent-to-`POP PC` search found only
loop-body hits (rop-move.md §5); and no clean `ADD ER2,ER0`/`MOV ER2,Rx` exists — the
only register-adder 0x2ED8 is wrapped in `BL 0x327E` (hijacks the walk, measured), the
const "movers" 0x2D9E/0x2DE0/0x2E1E are mid-function `ADD ER2,#imm`. Precisely what
would close it: a `MOV R2,R0`-with-RT-tail or a conditional `POP PC`, which would let
dst = 0xF8<KID> (Right/Up → row 7 @0xF87F, Left/Down → row 11 @0xF8BF) — a one-gadget
1-cell move. (Bank-1 sweep is the open lead; see Bank1Gadgets / cy845-rop.md matrix.)

## Is this enough for a playable game?

**Yes — for a reaction/timing game, today, on this engine as proven.** The loop is a
free-running frame beat: every pass renders a new frame (auto-sliding src) and samples
the key; the key bit lands on the LCD (row 0 byte 11) and F80B.4 persists, so
"press within frame N" / "press the same key as last frame" (Simon) / reaction games are
playable: input (ER0/r2 per pass) + state bit (F80B.4) + auto-advancing frames are all
in-chain. The simplest concrete game on this engine: **Simon-lite / reaction** — each
pass lights a new frame and the player must press (bit4=1) or not (bit4=0) to match a
pattern; score = consecutive matching passes. A **movement game (1-cell move = which row
lights up, 0xF87F vs 0xF8BF by arrow)** needs exactly one more gadget (conditional POP PC
or clean ER2←r0/r2 arithmetic, bank 0 searched negative, bank 1 open) — that is the
single blocking item, not the loop or the render.

## Status matrix (appended)

| Capability | Status |
|---|---|
| Self-sustaining render loop from typed hackstring (KEYSCAN→branch→memcpy12→LCD per pass) | **VERIFIED (this file, 48 passes, 1 run)** |
| Per-pass LCD frame change, fully in-chain (src self-advance +12/pass via PUSH EA writeback) | **VERIFIED (this file)** |
| ER0/r2 per pass following a scheduled key (presence + KID identity) | **VERIFIED (this file)** |
| Key→on-LCD pixel per pass (F80B.4 = row0 byte11 bit4, SB/RB per pass, persists) | **VERIFIED (this file)** |
| Key-chosen dst/src (movement; needs conditional POP PC or clean ER2←r0/r2 gadget) | OPEN — bank-0 negative (rop-move.md), bank-1 sweep pending |
| Simplest playable game now | reaction/timing + Simon-lite (input bit + auto frames + state bit) |

## Notes / honesty

- The payload is planted into 0x8154 by the harness in these scripts (as in all prior
  milestones); every payload word is zero-free and in the same token-byte class as the
  proven typed flood (0x0E/0x4D etc.), so the typed-hackstring delivery path
  (keypress_table.md) carries over; W(90)=0xF80C and W(6)=0x8240 are zero-free (0xF800
  would truncate the string — that is why work1 used 0xF811).
- memcpy fires once per work pass (every ~6–8 CDC passes in the measured geometry);
  each firing draws 12 bytes at 0xF80C and advances the src slot +12.
- Run budget: 3/3 used (run 1 = layout probe, run 2 = key schedule, run 3 = decisive).
