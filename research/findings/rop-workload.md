# Typed-ROP milestone 6: useful work inside the loop — CDC branch + memcpy12 execute every pass (SUCCESS)

**Verdict: SUCCESS (run 3 of 3).** The re-entry loop now does real work per pass: the 0x4CDC
key-conditional branch fires once per pass with fresh r0 (key held → SB path, F80B bit4 set and
persisting across passes), and the 0x35BE memcpy12 executes once per pass with the **same
dst/src every pass** (ER2=0xF811, src=0x8154, r0=01), writing the payload bytes to LCD row 1 —
**visible in the LCD readback on every subsequent line**. KEYSCAN hits grew to the 400-hit
anti-runaway guard with a stable 11-beat cycle; no park, no chaos.

- Script: `rop_work1.lua` (from `rop_loop1.lua`); key held for the whole run (Right pressed at
  the trigger, never released — the sanctioned "held for the whole run" variant).
- Commands (all headless, `SDL_VIDEODRIVER=dummy`, positional args; `pgrep -af emulator` empty
  before/after each):
  1. `SDL_VIDEODRIVER=dummy timeout 240 ./emulator/emulator model=models/fx991esplus2 script=rop_work1.lua > /tmp/rop_work1.out`  — v10: loop ran 14 keyscans then derailed (data, see below)
  2. same command → `/tmp/rop_work1b.out` — v11a: **hits=0, len=99** — the `W(98,0x0001)` craft put a 0x00 byte into the typed buffer, truncating the input string and killing the trigger before the walk (setup bug, not a walk result)
  3. same command → `/tmp/rop_work1c.out` — v11b (W(98)=0x4D01): **SUCCESS**

## Gadget table (bank 0, `/tmp/oki_b0.txt`)

| addr | bytes | disasm | notes |
|---|---|---|---|
| 0x3066 | `1E FE 8E F2` | POP ER14; POP PC | loader: ER14←next word, continue at word+2 (used ×3 in the payload) |
| 0x75DE | `EA A1 1E FE 1F FE` | MOV SP,ER14; POP ER14; RT | pivot: SP:=ER14, ER14 reloaded (garbage ok — loaders re-plant before next pivot), RT→lr |
| 0x3538 | `1E F2 1E F8 25 F0 1F FE` | POP ER2; POP ER8; MOV ER0,ER2; RT | head: ER2=dest; **poisons R0 with the dest** — must be followed by an r0-fixer, not a keyscan |
| 0x3136 | `1E F0 1E F4 8E F2` | POP ER0; POP ER4; POP PC | **R0-loader**: ER0←next word (r0=low byte), ER4←next, continue — no side effects on ER2 |
| 0x35BE | `8E F1 54 94 56 98 CE F1 2A F0 55 94 57 98 90 E2 FF 10 F6 C8 1E F0 3E F8 2E F4 1F FE` | POP EA; L XR4,[EA+]; L QR8,[EA+]; PUSH EA; LEA [ER2]; ST XR4,[EA+]; ST QR8,[EA+]; ADD ER2,#16; ADD R0,#255; BC NE; POP ER0; POP QR8; POP XR4; RT | **QR8 = 8 bytes = r8–r15: clobbers ER14 on every run**; consumption ≡ +22 bytes (phase +2) |
| 0x4CDC | `?  ?` | CMP R0,#0; BC EQ→0x4CD6 (RB 0F80Bh.4; RT); else SB 0F80Bh.4; RT | verified branch; consumes one extra pc-pair (+8 vs +4, no phase flip) |
| 0x4D0E | `7F 00 11 90 46 F0 00 E0 0C F0 40 F0 30 92 FF 72 00 60 1F FE` | MOV R0,#127; ST R0,0F046h; MOV ER0,#0; LEA 0F040h; L R2,[EA]; CMP R2,#255; ADDC R0,#0; RT | the flood "KEYSCAN" is a **key poll**: r0 = carry (1 = key held); **clobbers r2 and EA** — never place between head and memcpy |

## Payload (typed at 0x8154, len=100; W(off) ≙ word[0x8D70+off])

Loop skeleton (kept from rop_loop1): `W(30)=0x3066 W(34)=0x8DAC W(36)=0x75DE W(38)=0x75DE
W(42)=0x75DE W(44)=0x3066 W(48)=0x8DAC W(56)=0x8DAC(free) W(40)=0x4EF2` + flood elsewhere.
Work-block additions (v11b):

```
W(66, 0x4CDC)   -- branch; r0 fresh from the W(62) keyscan hop
W(86, 0x3538)   -- head: ER2 <- W(90)
W(90, 0xF811)   -- memcpy dest: LCD row 1 byte 1 (clear of F80B)
W(94, 0x3136)   -- R0-loader (POP ER0; POP ER4; POP PC) — no keyscan between head and memcpy
W(98, 0x4D01)   -- its ER0 value: r0=1, r1=0x4D junk — NO zero byte (0x0001 killed run 2)
W(2,  0x35BE)   -- memcpy12 pc (reached via the R0-loader's POP PC)
W(6,  0x8154)   -- its EA: source = the payload buffer itself
W(24, 0x3066)   -- odd-phase re-loader: restores ER14 after the memcpy's QR8 clobber
W(28, 0x8DAC)   -- its ER14 value = replay base
W(32, 0x8DAC)   -- old-loader's ER14 value (odd-phase 2nd load)
W(34, 0x8DAC)   -- old-loader's POP PC -> byte-opcode at 0x8DAC
W(60, 0xF28E)   -- bytes "8E F2" = POP PC at 0x8DAC -> chains into the pivot at W(36)
```

## Steady-state cycle (measured, verbatim sp sequence)

```
#10  sp=8DB2 ER14=F28E   (pass start; pc = word[0x8DAE], flood keyscan)
#11  sp=8DBA ER14=F28E
#12  sp=8DBE ER14=F28E
#13  sp=8DC2 ER14=F28E
#14  sp=8DC6 ER14=F28E   (its pop = W(86): head fires)
#15  sp=8DEC ER14=4D0E   (memcpy ran: +22 bytes, ER14 clobbered by QR8)
#16  sp=8DB2 ER14=F28E   (re-loader chain -> byte-opcode -> pivot -> next pass)
...identical through #399/#400...
PROTO: LOOP-RUNS-WORK hits=400 pc=4D20 sp=8DB2 ER14=F28E piv=1287
```

Pass period = **11 keyscan beats**: 5 flood hops, head, R0-loader, memcpy (+22 → odd phase),
1 flood hop (odd), re-loader chain (absorbs 2 slots) → pivot → next pass. Pass 1 was 9 beats
(entry loader starts at sp=0x8DA6). Net stack per pass = 0 (pivot re-syncs; the +22 memcpy
shift is absorbed by the re-loader chain exactly as predicted).

## Per-pass work — verbatim decisive lines

**CDC branch (34 walk-phase hits, one arrival per pass):**
```
CDC-WALK[lr=2B1E-point] t=1548566 sp=8DB6 r0=01 ER0=0001 preF80B=80 F80C=00 cnt=1
...
CDC-WALK[lr=2B1E-point] t=1549864 sp=8DB6 r0=01 ER0=0001 preF80B=90 F80C=00 cnt=39
CDC-WALK[lr=2B1E-point] t=1549865 sp=8DB6 r0=01 ER0=0001 preF80B=90 F80C=00 cnt=40
```
r0=01 at every hit (fresh from the preceding keyscan with Right held); preF80B transitions
`0x80 → 0x90` = the SB path fires and **F80B.4 persists across passes** (final-F80B=90).

**memcpy12 (≥40 walk-phase hits — print cap reached — identical every pass):**
```
MBE-HIT[E:35BE] sp=8DDA ER2=F811 EA=F040 r0=01 lr=2B1E-point src=8154 src12[8154]=0E4DBE350E4D54810E4D0E4D
```
Same dst (ER2=F811), same src (8154), r0=01 (single 12-byte copy) every pass. EA=F040 is the
stale pre-POP-EA value (as in draw3). CSR=0xE confirmed (the flood words' low nibble).

**LCD readback (the copy is visible in every post-copy CHAIN line):**
```
CHAIN: KEYSCAN #11 ER0=0001 ER14=4D0E pc=4D20 sp=8DEC lr=2B1E-point ... lcd01=...4090...0E4DBE35...
```
F811=0E F812=4D F813=BE F814=35 … = payload bytes 0..3 landed at the dst — **the row-1 write
is real and refreshed per pass**. F80B (0x90) untouched by the copy, as designed.

## Run 1 forensics (v10 → the ER14 lesson)

v10 relied on two keyscan hops to set r0=1 between head and memcpy. Those hops clobber r2
(half of ER2) — the memcpy then ran with a garbage destination: consumption +22 bytes
(0x8DD6→0x8DEC) and ER14←0x4D0E (the QR8 side-effect) are its fingerprints; the LCD stayed
clear, no MBE-HIT printed (break raced the multi-cycle instruction), and the pivot's
`MOV SP,ER14` with the clobbered base sent the walk to pc=CAD0/sp=4CE2 (final:
`PROTO: NO-TRIGGER hits=14 pc=CAD0 sp=4CE2 ER14=4D04 piv=302`, final-F80B=90 — the CDC had
already fired). Fix: the 0x3136 R0-loader directly after the head (no keyscan between) +
the W(24) re-loader chain restoring ER14 after every memcpy.

## Status matrix

| Capability | Status |
|---|---|
| Re-entry loop (walk restarts itself) | VERIFIED (rop-loop.md) |
| Per-pass work: key-conditional branch (state bit) | **VERIFIED** |
| Per-pass work: memcpy12 LCD row write, same dst/src | **VERIFIED** |
| Persistent state bit across passes (F80B.4) | **VERIFIED** |
| Stable geometry (11-beat cycle, Phase-recovery) | **VERIFIED** |
| Snake-lite game loop | unblocked: r0 = per-pass input, F80B/LCD = state+render |

## Next step

Snake-lite: keep the 11-beat skeleton; per pass use r0 (the key poll) through a 0x4CDC-style
branch to update a "snake position" byte in RAM, and per pass run the memcpy with a
position-dependent source (an ER-arith gadget or a small set of pre-built row images) to move
the sprite on the LCD. The pivot/loader skeleton is proven robust to +2 phase shifts, so
variable-length work blocks are safe as long as a re-loader chain precedes every pivot.

## Scope note (added by the movement milestone)

Verified in this file: the re-entry loop, the per-pass key branch (0x4CDC → F80B.4), and the
per-pass fixed-render (memcpy12 at a constant dst/src). Movement — a *draw address that follows
the per-pass key* — is the next milestone (`rop-move.md`): **NEGATIVE**; the only ER2-arithmetic
gadget (0x2ED8) is sabotaged by its embedded `BL 0x327E` call (the walk is hijacked — measured),
no carry gadget exists in bank 0, and {ER2 fresh, r0 fresh, ER2 persistent} is unsatisfiable with
the current inventory. Bonus discovery there: the "park" word 0x4EF2 is actually a key-gated
resume (`PUSH LR; mov r0,#1; BL 0x8508; cmp r0,#230; BC NE; POP PC`) — a candidate replacement
for the movement mechanism via key-gated continuations.

## Baselines (md5, end of work — all unchanged from session start)

```
fed27f1a9b3e9a9c426160384bfc0b55  CasioEmuX/rop_draw3.lua   (original base)
eaeaca418164a42fe63a3ce189a2feca  CasioEmuX/rop_br1.lua      (verified-branch script)
2cea3804b6ba1f6f67f848a0e599cb4f  CasioEmuX/rop_br1_hold.lua (test-1 shim)
5a57ffcac39827ca12cb587fa685da91  CasioEmuX/emulator/lua-common.lua (harness, untouched)
```
