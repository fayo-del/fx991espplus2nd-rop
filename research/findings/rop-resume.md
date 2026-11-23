# rop-resume.md — 0x8508 / 0x4EF2 key-gated resume: disassembly-only analysis (0 runs)

## 1) What 0x8508 returns in r0

0x8508 is the app's main key-wait handler; `r0` on return is the **translated key/event code
(r4)**, not the raw 0xF040 port byte. Return tails quoted (oki_b0.txt):

```
008656  40 80   MOV R0, R4          ; translated code in r0
008658  00 F0 38 52  B 00h:05238h   ; tail via 0x5238 = MOV ER14,SP; RT
```
and the 0x4EF2 gate:
```
004EF6  BL 00h:08508h
004EFA  E6 70   CMP R0, #230        ; 0xE6 = 230
004EFC  FB C8   BC NE, 04EF4h       ; spin in 0x8508 until r0 == 230
004EFE  8E F2   POP PC              ; resume walk
```
Translation path: raw 0xF040 port byte (0x8610 `L R0,080F9h` + 0x8682 area) → 0x8684 handler →
`BL 0x9586` (modifier-state XOR tables for codes 232–236: SHIFT/ALPHA toggles at 0x95A8–0x95D4)
→ `BL 0xB25E` (range check: `MOV R0,#232 / CMP R0,R2 / BC GT / CMP R2,#236 / BC GT / MOV R0,#1`
— i.e. "is code in 232..236 = modifier event", else 0). The settled pc=4B96 = inside 0x8508's
spin (0x8644 `B 0x851C` main loop).

## 2) What 0xE6 (230) is

**Unknown at the code level** whether 230 is a physical key's app code or a synthesized event:
the modifier branch (232–236) is disjoint, and no `CMP #230`-gated table row was found in
oki_b0.txt matching a measured token byte — the measured token table (keypress_table.md: 32 =
"2", 21BA = Σ box, EXE=0x60, Right=0x37) contains **no 0xE6 token**, and no keypress_table.md
row maps a physical key to event code 230. In rom context `0xBD78` (`L R0,080F5h; CMP R0,#230`)
reads a *state byte* (0x80F5), suggesting 230 is a system/event value, not a keycode — but this
is **[HW-unknown]**: not proven a physical key, not proven a timeout.

## 3) Fetch/bank model — correction

MMU.cpp (HW_ES_PLUS): `ReadCode(offset)` requires offset < 2^20, even; then **`offset &= 0x1FFFE`**
— the fetch address space is **0x000000–0x1FFFE (128 KB), mirrored**
(`(csr<<16)|pc & 0x1FFFE`; ROM smaller than the window reads 0).
**Therefore banks "2–3" beyond 0x1FFFF do not exist on ES_PLUS** — any `(csr<<16)|pc` with
bit17+ wraps: e.g. 0x2xxxx ≡ 0x0xxxx, 0x3xxxx ≡ 0x1xxxx. **rop-move2.md's "bank 2+ / banks 2–3
unexamined" next-parameter is a dead end — the full 128 KB is already covered by oki_b0.txt +
oki_b1.txt; no undiscovered bank exists.**

## 4) Verdict — key-gated resume as Snake-lite frame/input model

**TESTED AND REVERSED (rop_resume2, 1 run — see `rop-resume2.md` and
`/tmp/rop_resume2.out`): NOT usable as a frame/input model in the emulator.** The
104-code sweep 0x00–0x67 after the park (`SWEEP: parked t=1632048 pc=4B96 sp=8D7A
hits=20`) never made 0x8508 return 230: every non-AC key leaves r0=2/pc=4B96/hits=20
unchanged; the only key the spin registers is **AC (0x42 → translated code 18)**, whose
quit-path leaves the spin (`SWEEP: done 42 -> pc=CAF6 sp=4CCA hits=21`) and **derails
the walk** (no sustained hits; pc wanders 2F50/95EC/CA5C/…, sp outside RAM); raw
`PressKey(0xE6)` has no effect. ⇒ **230 is an internal app/system event, not a keyboard
key; 0x4EF2 = terminal park in-emulator**; frame-advance/input must be built from the
verified loop primitives (`rop-workload.md`: free-running re-entry loop + per-pass key
branch + fixed-dst render). **[HW-unknown]**: whether the 230 event is reachable on the
physical calculator (the emulator's translation layer never produces it from any of the
104 matrix codes).

*Pre-sweep analysis, kept for the mechanism (the ROM-side semantics stand; only the
input-reachability was reversed):* 0x4EF2 parks the walk in 0x8508 (measured: pc=4B96,
59 stable WATCH samples, rop_park1) and `POP PC` resumes it only when r0==230; the
resumed PC = the next payload word. The draw address (memcpy ER2) stays fixed — no
measured path moves it (rop-move.md: movement NEGATIVE).

## Baselines (md5, unchanged)

```
fed27f1a9b3e9a9c426160384bfc0b55  CasioEmuX/rop_draw3.lua
eaeaca418164a42fe63a3ce189a2feca  CasioEmuX/rop_br1.lua
af172e1421c9fa7d95ec46d54c42ea7a  CasioEmuX/rop_loop1.lua
fadf4c572f7537363c11f8c6158b9edf  CasioEmuX/rop_work1.lua
1454daa82c3574701ef925e6b24e423d  CasioEmuX/rop_move1.lua
5a57ffcac39827ca12cb587fa685da91  CasioEmuX/emulator/lua-common.lua
```
