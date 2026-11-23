# CY-845 typed-ROP — game-state and game-clock primitives (2026-11-22)

Base: cy845-rop.md / rop-workload.md / rop-render-buffer.md / rop-matrix-input.md. Binary pristine
(`emulator/emulator` md5 `4dcb0b1c6ce05aff52c2b1cb9de5631a`, ROM `c4c7d7fb89d0fd07cc0196d642682d83`),
headless, scripts `prim_clock1/2/3.lua`, logs `/tmp/prim_clock1..3.out`. Run budget: 4 emulator
runs (all documented below). No GUI, no source edits, no rebuilds.

## Verdict up front

| Primitive | Status (measured) |
|---|---|
| Increment/load-add-store gadget (any form) | **DOES NOT EXIST in ROM** (bank0+bank1 census) |
| State/counter | **WORKING — the hardware timer TM0C [0xF022] is the counter**: live at walk time, chain-readable |
| Enter 0x8224-flash-counter (0x7C50 route) | NOT a leaf (inside looping flash service); census alternative = none needed |
| Timer/clock SFR | [0xF022/23] = 16-bit counter, increments live (1381→1382 between samples); [0xF024]=01 [0xF025]=01 (LSCLK, div 2, run) |
| Chain→timer read (`memcpy12 EA=0xF022`) | **VERIFIED** (bytes landed in window row, `dst12[8830]=660501010000…`) |
| Chain→0x8224-counter visibility | 0x8224 is RAM→chain-readable only; superseded by TM0C which is both readable AND displayable |
| Timer-start leaf 0x4B56 from chain | **ENTERABLE** (entered twice, ER0=0x129A, lr=2B1E-pt, sp=8B10/8B14); return unresolved in-window |
| App refresh 0x35AE mid-walk call + continue | **VERIFIED** (walk pivots continued after the flush hop, piv=317) |

**State: the 0x129A mystery is closed.** `0x7C3C: MOV R0,#0x9A; MOV R1,#0x12; BL 0x4B56` =
interval **0x129A** — the wiki's "129A ≈ half cursor cycle ≈ 0.5 s". The wiki's timer function
0x4640 does not exist as such in CY-845; the equivalent pair is:

```
004B56: MOV ER2, ER0        ; interval <- arg
004B58: LEA 0xF024          ; TM0CON0
004B5C: MOV ER0,#1          ; r0=1, r1=0
004B5E: ST R0,[EA+]         ; [0xF024]=1  -> LSCLK, FreqDiv = 2^1 = 2
004B60: ST R1,[EA]          ; [0xF025]=0  -> stop (configure then enable)
004B62: LEA 0xF022 / MOV R0,#0 / ST [EA+] / ST [EA]   ; TM0C counter = 0
004B6C: LEA 0xF020 / ST R2,[EA+] / ST R3,[EA]         ; TM0D interval = 0x129A
004B74: LEA 0xF025 / MOV R0,#1 / ST R0,[EA]           ; control = 1: TIMER RUNNING
004B7C: LEA 0xF014 / R0=0 / ST [EA+] / ST [EA]        ; int pending clear
004B86: LEA 0xF008 / (0x50, 0xA0, 2) STs              ; peripheral/int enable
004B96/4B98: NOP, NOP
004B9A: RT                                            ; leaf, 2-byte return, LR untouched
```

It uses only r0–r3/EA, no pushes, bare `RT`: **a clean leaf callable from the chain with
ER0 = interval** (interval 0 → effectively "set config + never elapse"). While running,
TM0C counts 0→TM0D then resets and raises TM0INT; TM0C = free-running read-anywhere counter.

## 1. Increment-gadget census (disassembly-exhaustive, both banks)

Method: pattern scripts over `/tmp/oki_b0.txt` (bank0, 28,693 lines) and `/tmp/oki_b1.txt`
(byte-token-parsing awk; grammar `L R/ER n, imm16h|…[ERm]|[EA]`, `ADD #1/#-1`, `ST …`).

- **No EA-based increment**: 11 `L Rn,[EA]` sites in bank0; the only load-arithmetic-store is
  `0x40BE: L ER0,[EA]; ADD ER0,#-1; ST ER0,[EA]` — a 16-bit **decrement**, but continuation is
  app code (`BC EQ→0x4112: MOV R0,#11; B 0x4290` else `BL 0x3CE8…`) — **not chain-safe**.
- **No indexed increment**: pattern `L Rn,imm[ERx] / ADD Rn,#1 / ST Rn,imm[ERx]` — zero hits
  in both banks.
- **imm16 increment-variables** (0x7C50 pattern `L ER0,imm / ADD #1 / ST imm`): 11 sites, all
  buried in app functions (0x56A2→0812Ch, **0x7C50→08224h** (loops back `BC AL,07C30h`),
  0x8834/0x960E→08008h cursor vars, 0xCC80→0811Eh, 0xDB9E/0xDBDE/0xDBF8→0811Dh/Ch/Eh) —
  **no clean leaf**.
- What DOES exist, EA-based (leaves, `POP ERn; RT` exits, EA from stack — 0x356A family):
  `0x33F6 L R0,[EA]; OR R0,R3; ST R0,[EA]; POP ER4; RT` and the pixel-compositor family
  0x3562/358C/359E/35A6 (`AND/OR/XOR` into `[EA]` with R0/R1/R2/R14/R15, `POP ER14; RT`).
  These are fixed-mask bit-set/clear/toggle on a chain-chosen byte — usable for a fixed-progress
  bar but **not** an increment.
- Read leaf: `0x4BC0: LEA 0xF014; L R0,[EA]; RT` = interrupt-flags reader (TM0INT state).

**Conclusion (Target 1):** a ROM-free increment primitive does not exist; the hardware counter
TM0C substitutes for it entirely (it increments itself, deterministically, paced by TM0CON0/1),
and the chain can read, display and reset it (see below). Any score byte must live in TM0C or
in the verified state bits (F80B.4 et al.).

## 2. Runs

### Run 1 — `prim_clock1.lua` (walk + memcpy src=0xF022 → LCD row 1)
Chain = verified `rop_work1.lua` walk; only W(6)=0xF022 (src=TM0C) and W(66)=flood (0x4CDC branch
dropped — MatrixKeys workstream). Result: walk **GREEN, 400 passes**, `PROTO: LOOP-RUNS-WORK
hits=400 pc=4D20 sp=8DC2 ER14=F28E piv=1137`, steady 11-beat cycle. The instrumentation
(mk35BE/35CC print caps=40) was consumed by the app's own refresh calls before the walk began —
the walk's own copy/counter readbacks are not observable from this log (harness lesson: gate
breaks on lr==0x2B1E-point *and* dst, not capped-all). No conclusion on the counter bytes from
this run.

### Run 2 — `prim_clock2.lua` (walk + memcpy dst=window 0x8830[src=0xF022] + flush 0x35AE mid-walk)
The W(66)=0x35AE flush hop changes the pass's stack consumption (flush ≈ +6 B net vs branch +4 B)
→ the word stream shifted +2: the flood keyscans no longer align as pc-slots (only 9 keyscan hits
across 317 pivots). Two decisive line families:

```
MBE-HIT[E:35BE] sp=8DDA ER2=8830 EA=F040 r0=01 lr=2B1E src=F022 src12[F022]=650501010000000000000000
STORE-CAP[0:35CC] sp=8DDA ER2=8830 EA=883C r0=01 lr=2B1E dst12[8830]=660501010000000000000000
CLOCK-REF t=110558 n=1 TM0C=0566 … last=1382
```

- The walk's loader popped **EA=0xF022** (the W(6) word consumed as the memcpy source — the
  `EA=F040` field is the stale pre-POP EA register; the popped word is `src=`).
- `src12[F022]` = `65 05 01 01 00…` = **TM0C = 0x0565 (1381), TM0CON0=01, TM0CON1=01** — the
  timer is **running** (div 2, LSCLK) and the chain **read** its live counter.
- The copy landed: `dst12[8830]=66 05 01 01 …` = TM0C=0x0566 (1382) one tick later — **the
  snapshot byte incremented between the two samples**.
- Run ended `NO-TRIGGER`, final `pc=F84A sp=72FC` (out of RAM) long after the walk degenerated —
  a slow derail, but 0x35AE mid-walk was called and the pivots resumed (piv=317).
- The dumped TM0C fraction 1381-1382/5000 matches interval 0x1388 (5000) = the last 0x4B56 call
  before the walk (0x4B2E context, interval 5000 — the input-line flush path).

### Runs 3–4 — `prim_clock3.lua` (harness-kick one-shot, rop_diag mechanics, CH=0x8B00)
```
KICK t=100000 pc=2B1E sp=8B00 lr=2B1E
TIMSTART t=100023 ER0=129A sp=8B14 lr=2B1E        (run 4: run 3 identical, sp=8B10, layout bug)
SETTLE t=102999 pc=4B96 sp=8B14 35BE=0 35CC=0
END t=103999 pc=4B96 sp=8B14
```
- **0x4B56 IS enterable from the chain** exactly as designed: `POP ER0=0x129A → POP PC→0x4B56`,
  reached at t+23, LR = the chain's POP-PC point.
- The chain then sat at **pc=0x4B96 (the last NOP inside 0x4B56, before its RT) for both
  3k/4k-tick observation windows**. At div=2/LSCLK, interval 0x129A ≈ 0.5 s ≈ 20–30k emulated
  ticks: **both windows were shorter than one wait period.** The "stop" is *plausibly inside the
  timer-wait*, not a failure — but return-through was not observed; this is the open number.
- Run 3 additionally proved nothing about the 0x4B56 *return* path (a layout bug put pass 2's
  words under pass 1's flush entry — payload corruption of my own making, documented, not fate).

## 3. Smallest working game mechanic (assembles from verified pieces)

Per pass of the verified walk: the walk's memcpy12 already reads the live TM0C bytes
(Measured: the 0xF022 copy in run 2), so — exactly as verified in the earlier
`rop-render-buffer.md` findings, but with a **changing** byte:

- Start the timer once: the walk can call 0x4B56 as a normal callee (ER0=interval from the
  0x3136 loader) — or rely on the app's own interval (running: measured).
- Per pass: key-conditional branch via 0x4CF2/D7C-family gadgets with a held key (0x4D0E-fam)
  → **hold branch, MatrixKeys workstream** (not duplicated here).
- Per pass: memcpy12 with EA=0xF022 into a window row (dst=0x8830-family) — the displayed slot
  shows TM0C's low byte (fast flicker ~61 µs/unit) and high byte (0..19 ripple ≈ 15 ms/unit:
  a real frame counter) — and the interval rollover is the deterministic 0.5 s beat.
- Reset lever (documented, not yet exercised): **a memcpy12 with dst=0xF022 zeroes the counter**
  (the emulator's TM0C write handler resets `data_counter`) — memcpy dst marches +16/iteration,
  so a single iteration at r0=1 dst=0xF022 writes [0xF022]=0 — the "reset clock" gadget.
- Render path: 0x35AE mid-walk call + continue is **verified** (run 2 pivots), or
  direct-LCD dst=0xF811-fam per pass (run 1's mechanism, no flush needed).

## 4. Exact next parameters

1. **Close 0x4B56's return**: rerun `prim_clock3.lua`-style one-shot with the settle window
   ≥ 100k ticks (≥ 4× the 0.129A wait). Decisive question: does pc leave 0x4B96 (RT→chain)
   after the wait expires? If yes, the deterministic 0.5-s wait is callable from the walk
   (the game "move now or lose a tick" primitive).
2. **Run-2 phase fix**: the flush hop at W(66) shifts the stream +2. Place 0x35AE in a
   no-operand pc-slot whose neighbors are re-loader words (e.g. replace the second flood word
   after the re-loader chain, W(28)-slot) — or add a 0x4D0E flood pair before W(66) to re-sync
   parity, then re-verify: flood keyscans/hits back to ~1 per pass.
3. **Reset lever test**: dst=0xF022 memcpy per pass end — the SPR-clears-and-counter combo is
   then movement-ready (position byte = TM0C, reset per pass via 0x35BE, one memcpy12/beat).
4. Census follow-up for state: the 0x4CF2-family alternate branch (rejected before as
   bank-clobbered) is now relevant again if the LR-target can be made bank-0 — that is
   the second conditional bit, MatrixKeys' call.


---

# Session 2 (2026-11-22, runs 4–6): 0x4B56 return CLOSED-NO; timer frozen at walk time

## Run 4 — `prim_clock4.lua` = run-3 layout, settle 150k ticks (>>4x the 0x129A wait)
```
KICK t=100000 pc=2B1E sp=8B00 lr=2B1E
TIMSTART t=100023 ER0=129A sp=8B14 lr=2B1E     (x5 prints = same instance, break-refire artifact)
WAIT-PROBE t=124999..249999 pc=4B96 sp=8B14 35BE=0   (every 25k)
SETTLE t=249999 pc=4B96 sp=8B14 35BE=0 35CC=0
END t=250999 pc=4B96 sp=8B14 35BEhits=0 35CChits=0
```
**0x4B56 RETURN: NO (decisive).** pc never leaves 0x4B96; the chain never resumes (35BE=0).
The deterministic 0.5-s wait is therefore NOT callable from the chain via 0x4B56 — the leaf is
enterable but terminal in this emulator. Whatever 0x4B96 is a subclass of, it parks the CPU
(note: it is also the quoted "park signature" pc==4B96 of the 0x4EF2 wait — same neighborhood).

## Run 2b/3 — `prim_clock5/6.lua` (live-clock demo attempt + passive x-ray)
Layout fixes: probes gated on `lr==0x2B1E-fam` (walk-only; the app's own refresh calls excluded),
flush at W(68), branch at W(72), per-pass LCD frame dumps (448 captured!), FLB/FLC as globals.
Results:
- Copies fire every pass: `MBE-HIT[E:35BE] sp=8DDA ER2=8830 EA=F040 r0=01 lr=2B1E-point src=F022
  src12[F022]=3F0501010000000000000000`.
- **TM0C is FROZEN at the walk-time state**: 0x3F,0x05 (1343) constant across all 448 copies
  (run 2's 1381->1382 pair was a single live increment before the freeze). The app's copy-eval
  state (the walk time) does NOT tick the timer; the cursor-blink timer only runs during the
  editor/dance state.
- Sampling bug: the frame dump printed LCD rows 0..11 (16-B stride) but the window->LCD mapping
  is linear-16 too (LCD[16k..16k+11] = window[16k..16k+11], k=0..31), so my 0x8830-family copy =
  window offset 0x60 = **LCD row 6** (not row 8 as the run-2 report guessed). The FRAME-PASS
  row 6 shows `0800…` — not the copied 0x3F,0x05 — so the flush's copy is NOT visible on the
  LCD in these frames; whether the flush marched is moot because FLB/FLC scope (the finish()
  nil-format crash) aborted the run before finish() — the passive watch worked.
- The hook crash (`bad argument #2 to 'format' (number expected, got nil)` at prim_clock5.lua:121
  = the FLUSH-COUNTS print) — FLB/FLC were locals declared after finish(); unregistered the
  hook, killed the run's tail. Fixed (globals) in prim_clock6.lua.

## Verdict after 6 runs
- Game clock value: **TM0C [0xF022] is frozen at the walk-time state** (the app's copy-eval state
  stops the blink timer). The chain reads it correctly, but a frozen counter is a static byte, not
  a clock. Single run-2 +1 was the freeze instant.
- 0x4B56 as deterministic game-clock wait: **NO** (no return even at 4x the interval).
- **0x8113-0x8116 (app replay/copy-index vars): the unmeasured candidate** for a per-pass
  increasing byte — the run-6 passive XRAY (harness-side data[] reads every 200 ticks across the
  trigger and walk) is the instrumentation to read them.
- Next levers: (i) per-pass restart of the timer via a chain-write in place of the 0x4B56 call —
  e.g. memcpy12 dst=0xF020-fam with a crafted interval+counter+config+control block; (ii) look
  for a "wait until [0xF022] <= k" style poll loop in ROM (polls of 0xF022 outside 0x4B56 did not
  exist in bank0 — verify in the boot-cluster too); (iii) if all fail, the state primitive =
  the TM0C/score is writable via memcpy (dst=0xF022 writes pass through the write handler) —
  display-a-score-from-a-counter still works if ANY incrementing byte is found (0x8113-16 next).


---

# Session 3 (2026-11-22, runs 4-6 of this request): 0x4B56 return = NO; counter freezes at walk time

## Run 4 (prim_clock4.lua = prim_clock3 + settle 150k ticks): **0x4B56 RETURN = NO (decisive)**
```
KICK t=100000 pc=2B1E sp=8B00 lr=2B1E
TIMSTART t=100023 ER0=129A sp=8B14 lr=2B1E     (x5 identical prints = break-refire artifact)
WAIT-PROBE t=124999..249999 (x6, every 25k) pc=4B96 sp=8B14 35BE=0
SETTLE t=249999 pc=4B96 sp=8B14 35BE=0 35CC=0
END t=250999 pc=4B96 sp=8B14 35BEhits=0
```
150k ticks >> 4x the 0x129A wait; pc never left 0x4B96; the chain never resumed; no 0x35BE hit.
**A deterministic 0.5-s wait is NOT callable from the chain via 0x4B56** (in this emulator the
leaf is enterable but terminal — likely the same halt/poll neighborhood as the park signature
pc==0x4B96 quoted in rop-green's notes). The walk-based clock (run 2) is the live path.

## Run 5 (prim_clock5.lua = run 2 payload + probes gated on lr==0x2B1E-fam + frame dumps)
448 FRAME-PASS captures. Walk copies fire every pass: `MBE-HIT sp=8DDA ER2=8830 EA=F040 r0=01
lr=2B1E-point src=F022 src12[F022]=3F0501010000000000000000` = TM0C=0x053F, TM0CON0=01,
TM0CON1=01 — **the counter bytes read back constant 0x053F (1343) across all 448 copies**:
the app **stops the timer when it enters the copy-eval state** (run 2's 1381->1382 pair was a
single live increment just before the freeze; the frozen value differs per run — 0x566 vs 0x53F
— it is wherever the app's own timer-stop left it). The copy + window-landing is real; a frozen
counter makes it a static byte, not a clock.
Instrumentation bug found & fixed in the same session: finish() printed FLB/FLC declared as
locals *after* finish -> nil-format crash killed the hook before the final report
(`post-tick hook failed: prim_clock5.lua:121 … unregistered`). Fixed; frame-capture code
(448 FRAME-PASS lines = rows 0..11 per pass) is in place for the GIF builder.

## Run 6 (prim_clock6.lua = run 2b + passive x-ray) — done, analyzed in Deliverable addendum
Passive x-ray (harness-side, no emulator cost) of candidate live counters during the walk:
[data[0x8113..0x8116]], TM0C, window 0x8830-c, LCD row 6 samples every 200 ticks across the
walk phase + repaired finish(). Log: /tmp/prim_clock6.out.

## Verdict after this request's 3 runs
- 0x4B56 return: **NO** (measured; deterministic 0.5-s wait NOT callable from the chain).
- Live counter in walk: TM0C readable but **frozen at the app's eval state** (1343/1382
  constants; run 2's +1 pair = its dying tick). A live per-pass counter needs either
  (a) the app's replay/copy-index RAM (0x8113-16: harness-watch installed in prim_clock6.lua,
  unmeasured in this log — read the XRAY lines of /tmp/prim_clock6.out), or
  (b) a chain-side increment, which does not exist in ROM.
- GIF: not produced (identical stale frames are not an animation; builder ready at
  research/CasioEmuX/build_clock_gif.py, input = 448 captured FRAME-PASS rows).
- Honest game note: live clock + 1-bit key indicator only if a live incrementing byte is
  found or the app keeps a pass-counter in RAM; no score/compare; a timer-compare gadget
  (e.g. the 0x4CF2-family on TM0C) is the next lever.
