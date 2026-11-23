# Typed-ROP milestone 7: movement primitive (key-dependent draw address) — NEGATIVE; two decisive side-discoveries

**Verdict: NEGATIVE (1 run used of 3; stopped per the task's own exit clause "if no usable
arithmetic gadget exists, report the search coverage and stop").** The blocker is architectural,
not tuning: with the current gadget inventory, **{ER2 fresh, r0 fresh, ER2 persistent across
passes} is unsatisfiable** — a cyclic dependency no searched gadget breaks. The run also
**disproves the 0x2ED8 adder path empirically** (the walk is hijacked by its internal call) and
**uncovers two high-value primitives** for the next milestone (below).

- Script: `rop_move1.lua` (from `rop_work1.lua`), design v13b: drop the head from the steady
  pass so ER2 persists as the accumulator; per pass `[keyscan r0=1] → 0x2ED8 (ADD ER2,ER0) →
  0x3136 (r0 loader) → 0x35BE memcpy`; kept the W(66)=0x4CDC tracker and the whole
  re-loader/pivot skeleton from the workload milestone.
- Command: `cd /home/yoxu/Projects/fx991espplus2nd/research/CasioEmuX && SDL_VIDEODRIVER=dummy timeout 240 ./emulator/emulator model=models/fx991esplus2 script=rop_move1.lua`
  (headless; `pgrep -af emulator` empty before/after; exit 124 = the 240 s cap; log
  `/tmp/rop_move1.out`).

## Run 1 forensics (verbatim)

```
CHAIN: KEYSCAN #4 ER0=0001 ER14=8DAC pc=4D20 sp=8DB2 lr=2B1E-point words[sp-8..sp+7]=4D0E F28E 4D0E 4D0E 4CDC 4D0E 4D0E 4D0E lcd01=...4080...
CDC-WALK[lr=2B1E-point] t=1548566 sp=8DB6 r0=01 ER0=0001 preF80B=80 F80C=00 cnt=1        (×5, one arrival)
CHAIN: KEYSCAN #5 ... sp=8DBA ... lcd01=...4090...                                       (SB fired: F80B.4 set)
CHAIN: KEYSCAN #7 ... sp=8DC2 ... words=...4D0E 4D0E 4D0E 4D0E lcd01=...4090...          (approaching the adder)
CHAIN: KEYSCAN #8 ... sp=8DC6 ... words=4D0E 4D0E 4D0E 4D0E 2ED8 4D0E 3136 4D0E ...      (adder slot reached)
MBE-HIT[E:35BE] sp=8DD6 ER2=8182 EA=88D7 r0=01 lr=337E src=8154 src12[8154]=0E4D54810E4D  (×5)
CHAIN: KEYSCAN #8 is the last: PROTO: NO-TRIGGER hits=8 pc=8F4A sp=4CF0 ER14=4CF6 piv=297
```

**The kill chain:** the 0x2ED8 gadget (at word[0x8DC6] = W(86), exactly where placed) executed
`ADD ER2,ER0` and then its embedded `BL 0x327E`. The 0x327E function is the app's own
draw/glyph routine that internally calls the 0x35BE memcpy (the `lr=337E` MBE-HITs with
ER2=8182 = its own scratch destination prove the hijack). Control never returned to the march:
final `pc=8F4A` = deep inside the callee tree, `sp=4CF0` = outside RAM. The walk's own memcpy
never executed.

## Search coverage (bank 0, exhaustive over `/tmp/oki_b0.txt`; bank 1 unsearched — noted below)

1. **`ADD ER2,<x>`** — 17 sites: 0x72E, 0x18F6, 0x1AA2, 0x1F30, 0x1FF4, 0x206E, 0x2400, 0x2A1A,
   0x2D9E, 0x2DE0, 0x2E1E (all `#imm` — constant, no key input); **0x2ED8 (`ADD ER2,ER0`)** — the
   only register-add: wrapped as `ADD ER2,ER0; MOV R1,#12; MOV R0,#78; BL 0x327E; POP PC` —
   **empirically fatal (run 1: the BL hijack)**; 0x2F66 (`ADD ER2,ER4`) and 0x2FAE
   (`ADD ER2,ER0`) — mid-function, uncontrolled tails.
2. **Carry gadgets (`MOV Rn,R0` with RT/POP-PC tail)** — 11 sites checked (0x606, 0x1B74, 0x2B60,
   0x2BE8, 0x2DF6, 0x2F58, 0x37FC, 0x4A08, 0x4E6E, 0x4EA6, 0x4FDC, 0x545E): **all mid-function**;
   no standalone `MOV Rn,R0; RT/POP PC` exists in bank 0.
3. **Memory arithmetic (`ADD [mem],…` / load-add-store counter idiom)** — none: the nX-U8/100 ALU
   is register-only; every `L`/`ST` pair lives inside a function. Closest: the 0x8100-cell
   accessors at 0x2E60–0x2EA0 (load/merge/store nibbles) — `OR`-merge only, no increment; all
   end in `RT` but pass through function bodies with side effects.
4. **8-bit adds (`ADD R2,R0`)** — 0x1730, 0x2A38: both mid-function (0x2A38 continues into a
   nibble-reader that destroys r0).
5. **Conditional `POP PC`** (branch skips/takes a stack-fed jump) — searched `BC` adjacent to
   `8E F2`: only hits are inside loop bodies (e.g. 0x4EFC inside the park gadget); no clean
   conditional-dispatch gadget.

### The blocking chain (why no arrangement works)

- **ER2 fresh** ⟸ the 0x3538 head (`POP ER2; POP ER8; MOV ER0,ER2; RT`) ⟹ **r0 poisoned** with
  the dest value (measured in rop_work1 run 1).
- **r0/ER0 fresh** ⟸ the 0x4D0E key poll (sets ER0 = {0x0000, 0x0001} exactly — `MOV ER0,#0; …;
  ADDC R0,#0` — this part is ideal) ⟹ **clobbers r2 = half of ER2** (`L R2,[EA]`) and EA.
- The 0x3136 loader sets r0 = 1 **statically** (no key dependence).
- Therefore the only adder (0x2ED8) never sees {fresh ER2 ∧ fresh key-r0} simultaneously, and
  carrying the key in a register is impossible (no carry gadget; r4–r15 are all destroyed by the
  memcpy's exit pops ER0/QR8(r8–r15)/XR4(r4–r7) anyway).

## Side-discoveries (the payload for the next milestone)

1. **The "park" at 0x4EF2 is not a park — it is a key-gated resume:**
   ```
   004EF2  CE F8        PUSH LR
   004EF4  01 00        MOV R0, #1
   004EF6  01 F0 08 85  BL 00h:08508h     ; wait/scan routine (spins at pc=4B96 = the observed "park")
   004EFA  E6 70        CMP R0, #230      ; 230 = 0xE6 = the awaited key code
   004EFC  FB C8        BC NE, 04EF4h     ; loop until the key arrives
   004EFE  8E F2        POP PC            ; resume the walk from the stack!
   ```
   The observed park (`pc=4B96 sp=8D7A`) is the spin inside 0x8508. **Pressing the awaited key
   (the 0xE6 code — identify which physical key maps to it) resumes the walk via `POP PC`.**
   This is a key-gated *continuation* primitive — likely the intended interaction model for
   Snake-lite (frame-advance gated on input), and it explains the "park" of every prior run.
2. **0x3540 is a guarded ER14 arithmetic gadget:** `PUSH ER14; ER14 ← 0x7824; ER14 += ER0;
   BC GE,0x356A (POP ER14; RT)…` — the adder + bounds-check pattern exists but is inline in a
   function; a cleaner cut may exist in bank 1.
3. **The memcpy's `PUSH EA` writes the advanced source pointer back at word[sp−2]** — in the
   v11b layout it lands on an inert flood slot (measured: src stayed 0x8154 across all passes).
   Moving the source craft to the exact EA slot (W(8) = 0x8DDC in that layout) would make the
   *source* window advance +12 per pass — a scrolling-memory-window effect, but unconditional
   (not key-gated); not tested (out of budget priority).

## Status matrix

| Capability | Status |
|---|---|
| Re-entry loop | VERIFIED (rop-loop.md) |
| Per-pass key branch (F80B.4) | VERIFIED (rop-workload.md) |
| Per-pass fixed-dst render (memcpy12) | VERIFIED (rop-workload.md) |
| **Key-dependent draw address (movement)** | **NEGATIVE — no usable arithmetic gadget; blocker documented** |
| Key-gated run/pause of the whole walk (0x4EF2 park) | **DISCOVERED — untested for resume** |
| Snake-lite game loop | blocked on movement; alternative path = use the 0x4EF2 key-gated resume as the frame/input model |

## Next parameter (for the next attempt)

1. **Bank 1 sweep** for the missing classes (`MOV ER2,ERx` clean copies, `ADD ER2,ERn` with
   clean tails, standalone `MOV Rn,R0`) — bank 1 = 0x10000–0x1FFFF, csr=1; the walk's CSR is
   settable via crafted csr words if a bank-1 gadget is found (the walk's CSR = the flood's low
   nibble = 0xE ⇒ bank-0; a crafted word with low nibble 1 switches the fetch bank).
2. **The 0x2ED8 bypass**: a gadget that performs `ADD ER2,ER0` *without* the trailing call does
   not exist in bank 0; check whether some `ADD ER2,ER0` site sits ≤2 instructions before a
   `POP PC`/`RT` (0x2FAE's tail needs re-reading with fresh eyes — it continues into a
   nibble-reader, but a mid-entry point *after* the nibble logic may return cleanly).
3. **The 0x4EF2 key-gated resume**: identify the physical key whose scan makes 0x8508 return
   230 (0xE6); if it is a usable key, the Snake-lite loop becomes: walk → park (wait for key) →
   resume with a *different* continuation word (loaded by the key-handling path) — sidestepping
   the arithmetic blocker entirely by making the *continuation*, not the address, key-dependent.

## Scope note

Appended to `rop-workload.md`: verified = re-entry loop + per-pass key branch + per-pass fixed
render; movement (key-dependent draw address) = this milestone, NEGATIVE with the blocker
documented above.

## Baselines (md5, end of work — all unchanged)

```
fed27f1a9b3e9a9c426160384bfc0b55  CasioEmuX/rop_draw3.lua
eaeaca418164a42fe63a3ce189a2feca  CasioEmuX/rop_br1.lua
af172e1421c9fa7d95ec46d54c42ea7a  CasioEmuX/rop_loop1.lua
5a57ffcac39827ca12cb587fa685da91  CasioEmuX/emulator/lua-common.lua
```
