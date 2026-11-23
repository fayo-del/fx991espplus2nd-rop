# rop-game.md — calling the app key service 0x8508 directly from the walk: NEGATIVE (1 run)

**Verdict: NEGATIVE — the key service cannot be called from the walk.** Entering 0x8508 via a
crafted POP-PC word (W(86)=0x8508 in the verified work1 payload) wrecks the chain exactly like
the 0x2ED8 BL-hijack did: the call never returns to the march (zero sampler hits), SP ends
outside RAM, and after 8 KEYSCAN hits the CPU drifts in ROM/RAM-code purgatory (pc≈0x8F46–8F54,
sp=0x4CF0). Per the task's stop-rule: reported with the observed sequence; no second run; the
marquee is not iterated on.

- Script: `rop_key1.lua` (from `rop_work1.lua`): kept the verified loop skeleton
  (W(66)=0x4CDC F80B-tracker, re-loader chain W(24)/W(28)/W(32)/W(34)/W(60), pivot
  W(36)/W(38)/W(42)=0x75DE, entry loader W(44)/W(48), W(40)=0x4EF2 insurance); replaced the
  work block with `W(86)=0x8508` → `W(90)=0x3136` (R0-loader) → `W(94)=0x4D01` (its ER0) →
  `W(98)=0x35BE` (memcpy) → `W(2)=0x8154` (src). Key phases: Right+EXE at the trigger, Left
  swap at ft=2,000,000, none at ft=4,000,000.
- Command: `cd /home/yoxu/Projects/fx991espplus2nd/research/CasioEmuX && SDL_VIDEODRIVER=dummy timeout 400 ./emulator/emulator model=models/fx991esplus2 script=rop_key1.lua > /tmp/rop_key1.out`
  (headless; `pgrep -af emulator` empty before and after; exit 124 = the wall cap after the
  emulator had already run the script's own NO-TRIGGER finish).

## Observed sequence (verbatim)

```
WATCH: t=7560001 pc=8F48 sp=4CF0 ER14=4CF6 tiles=776 hits=8 ... cdcw=6 piv=305
WATCH: t=7760001 pc=8F4E sp=4CF0 ER14=4CF6 tiles=776 hits=8 ...
PROTO: NO-TRIGGER hits=8 pc=8F46 sp=4CF0 ER14=4CF6 piv=305
PROTO: final-F80B=00 F80C=00
```
- `KEY85 #` sampler (break at 0x5238 gated on lr=0x8658, i.e. a genuine 0x8508 return): **0
  fires** — the service never returned to the march. (The 0x8508 tail `B 0x5238` does force
  the march's LR convention — but the walk was already wrecked before reaching any return.)
- Chain death = the identical signature as rop_move1's 0x2ED8 hijack (`pc≈8F4x sp=4CF0
  hits=8`): both 0x8508 and 0x2ED8 enter the app's normally-called function world
  (`PUSH LR / BL 0x5230 / ADD SP,#-16 / MOV ER0,ER14 / frame-pointer walk`), which assumes the
  app's call environment; entered raw from the march, its frame/stack arithmetic leaves SP at
  0x4CF0 (outside RAM) and pc executing garbage/RAM-code.
- LCD readback in the WATCH rows also confirms the memcpy never drew (rows all zero except the
  boot pattern), and `final-F80B=00` (the AC phase's quit-path cleared it; cdcw=6 = the early
  pass-1 CDC only).

## r0 per key (measured — but only via the app-level park, from rop-resume2.md)

| condition | 0x8508 return r0 |
|---|---|
| parked, no key | 2 (constant) |
| parked, any editor key 0x00–0x41,0x43–0x67 | 2 (constant — queued/ignored) |
| parked, AC (0x42) | 18 (then the spin exits via the quit-path and the walk dies) |
| walk→0x8508 direct call | never returns (this run) |

The codes therefore **do not differ per key through any reachable path**: the direct call (the
hypothesis under test) never returns, and the only observed key translation happens behind the
0x4EF2 filter that discards everything except AC → quit. 0x8508-from-walk = **blocks/wrecks**;
the r0-per-key comparison the task asked for is unreachable this way.

## Why 0x8508 cannot be called from the walk (mechanism)

0x8508 opens `PUSH LR / BL 0x5230 (PUSH QR8; PUSH XR4; MOV ER14,SP; RT) / ADD SP,#-16 / MOV
ER0,ER14 / ADD ER0,#-20 / BL 0x7902 / B 0x8644` — it builds its frame on **ER14** and runs
FP-relative loads (`L R0,-0Fh[FP]`, `-14h[FP]`, …) against a normal app frame. The march
entered it with ER14=0x8DAC (our pivot base) and SP deep in the walk window: the callee's
frame arithmetic and nested `B/BL 0x5230/0x5238` SP-forcing tails (the same SP,V=frame trick
the pivot uses) re-aim SP at ER14-derived addresses and the position-sensitive walk window is
left behind — pc drifts into 0x8F4x/0xCAxx garbage. Same root cause as the 0x2ED8 hijack
(rop-move.md run 1): **app-called functions are not ROP links; only their leaves with clean
RT/POP-PC tails are.**

## Game-input ceiling (updated)

| Capability | Status |
|---|---|
| Free-running loop, per-pass fixed render, F80B.4 key bit | VERIFIED (rop-workload.md) |
| Per-key r0 translation | **UNREACHABLE**: 0x8508-from-walk wrecks the walk (this run); the app-level park filters all keys but AC (rop-resume2.md), and AC ≠ the 230 gate |
| Two-pixel key-select demo (branch on r0 code) | **NOT BUILT — depends on per-key r0, which has no reachable path** |
| Marquee (scrolling content at fixed dst) | still the ceiling — see rop-workload/rop-move; unreachable here by the stop-rule |

Next parameter (for a future session, not run now): the only unexplored key-data path is
reading KID *without* 0x8508 — a leaf gadget doing `MOV ER0,#0; LEA 0xF040; L R2,[EA]; …` into
a **register the march can read later** does not exist in bank0 (the 0x4D0E poll itself is the
closest and its r0 is already harvested per pass — it returns only 0/1 by design). The emulator
harness could also write the key state byte directly into the payload via `Keyboard` state in
Lua (off-ROP), which changes the demo's honesty class and was not attempted.

## Baselines (md5, end of work — verified unchanged)

```
fed27f1a9b3e9a9c426160384bfc0b55  CasioEmuX/rop_draw3.lua
eaeaca418164a42fe63a3ce189a2feca  CasioEmuX/rop_br1.lua
af172e1421c9fa7d95ec46d54c42ea7a  CasioEmuX/rop_loop1.lua
fadf4c572f7537363c11f8c6158b9edf  CasioEmuX/rop_work1.lua
1454daa82c3574701ef925e6b24e423d  CasioEmuX/rop_move1.lua
5a57ffcac39827ca12cb587fa685da91  CasioEmuX/emulator/lua-common.lua
```
(rop_key1.lua = this milestone's script. Earlier: the marquee milestone left demo_marquee.lua
part-built and no demo report yet — explicitly not iterated on here per the stop-rule.)
