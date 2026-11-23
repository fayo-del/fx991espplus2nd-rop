# rop-resume2.md — empirical key sweep against the parked walk (1 run; verdict: NEGATIVE for input-resume; 230 = internal event)

**Verdict: NEGATIVE — no keyboard input resumes the parked walk.** The full sweep of
matrix-valid codes 0x00–0x67 (104 keys, 40k-tick holds / 15k-tick gaps, one at a time) never
made 0x8508 return 230; r0 stayed at its parked constant 2 for every non-AC key. The single
key that 0x8508 *did* register — **AC (0x42), returning the translated code 18** — does not
satisfy the gate (18 ≠ 230) and instead sends the spin out of its wait-loop into the app's
quit/handling paths, derailing the chain into ROM/RAM jungle. The parked walk also drifted out
of the spin *during* the late sweep (pc=2F68 = the number-format loop inside 0x8508's handler
tree) with hits frozen at 21 — the resumed-march blip then death, not a usable frame model.

- Script: `rop_resume2.lua` (from `rop_park1.lua`; park word 0x4EF2 doubled at W(36)/W(38)
  unchanged, PROBE1 NOT-INSERTED, hits=20 pre-sweep);
- Command: `cd /home/yoxu/Projects/fx991espplus2nd/research/CasioEmuX && timeout 300 ./emulator/emulator model=models/fx991esplus2 script=rop_resume2.lua > /tmp/rop_resume2.out`
  (headless, `pgrep -af emulator` empty before and after; exit 124 = the 300-and-420-s wall
  caps on two launches — the second launch carried the run to `SWEEP-DONE`; one earlier launch
  without `SDL_VIDEODRIVER=dummy` was killed at 5 s per the no-GUI rule, 134; counts as the setup
  error, the run data below is from the dummy launch);
- r0 evidence: sampled at press/mid-hold/gap-end from the posttick driver (a break at 0x8656 was
  rejected pre-run: it pauses on every 0x8508 spin pass — thousands/sec — and would crater the
  sweep; the parked loop leaves r0 = the last translated code between returns, so the free
  read is the faithful proxy).

## Verbatim decisive lines

```
SWEEP: parked at t=1632048 ft=160001 pc=4B96 sp=8D7A hits=20, starting sweep
SWEEP: press 00 (#1/104) pre pc=4B96 sp=8D7A hits=20 r0=2
SWEEP: mid   00 pc=4B96 r0=2 hits=20
... codes 01..41 identical: pre/mid/done pc=4B96 sp=8D7A hits=20 r0=2 ...
SWEEP: mid   42 pc=2F62 r0=3 hits=21          <-- during the AC (0x42) hold: pc LEFT the spin
SWEEP: done  42 -> pc=CAF6 sp=4CCA hits=21 r0=18 PC-LEFT!! RESUME?
SWEEP: press 43 (#68/104) pre pc=CAF6 sp=4CCA hits=21 r0=18
SWEEP: done  43 -> pc=2F68 sp=4CC8 hits=21 r0=3 PC-LEFT!! RESUME?
SWEEP: press 44 (#69/104) pre pc=2F6A sp=4CC8 hits=21 r0=3
... pc wanders: 2F50, 95EC, CA5C, 7820, 5234, CAE2 ... sp=4CC8/4CF8 (outside RAM stack) ...
SWEEP: press 4A (#75/104) pre pc=5234 sp=4CEC hits=21 r0=249
SWEEP: COMPLETE all 104 codes; final pc=2F68 sp=4CC8 hits=21
SWEEP: probe PressKey(0xE6) ok=true err=nil pc=2F68
SWEEP: probe done pc=CA42 sp=4CCA hits=21 PC-LEFT!! RESUME?
PROTO: SWEEP-DONE hits=21 pc=CA42 sp=4CCA
```

- `hits=21` appears exactly once (during the 0x42 hold) and never rises again: the one extra
  KEYSCAN = a single post-AC march blip, then the walk is lost in the jungle. **No clean resume
  (no sustained hit growth, no return to the payload march).**
- `r0=2` = the parked-loop constant (not the walk's key-poll 0/1 — 0x8508's translation layer);
  it only moved for AC (18) — i.e. **0x8508 queues/ignores all editor keys during the park; AC
  is handled by a special quit-path** — and the sweep's PC-LEFT was *that* quit path, not the
  r0==230 resume.
- The raw `PressKey(0xE6)` probe (`ok=true`) changed nothing: pc stayed in the jungle.

## Interpretation

1. **230 is an internal app/system event code, not a keyboard key in this emulator.** Coverage:
   all 104 matrix codes 0x00–0x67 plus the raw 0xE6 press; the only non-constant r0 observed
   was 18 (AC). 0x8508's spin left 4B96 once — via AC's quit-path — never via the r0==230 gate.
2. The early-window effect is confirmed empirically **for the parked app**: keys pressed after
   the park are invisible to the translator (r0 constant 2) except AC. This extends
   keypress_table.md's "after ~0.25–0.4 s the app enters the 0x4EF2 wait-key loop and discards
   other keys" with: *the discard happens inside the parked 0x8508 spin itself*.
3. Therefore the 0x4EF2 gate **cannot be driven by harvested input in this emulator**, and the
   key-gated resume is **not usable as a Snake-lite frame/input model** (the gate never opens;
   AC kills the walk). The emulator-level alternative remains: the harness presses keys during
   the typing window only; a frame-advance model must be built from the verified loop primitive
   (rop-workload.md), not from the park.

## Corrections to prior docs

- rop-resume.md §4 ("usable as a frame/input gate... test before building on it") → **tested:
  NOT usable** (this file). The 230 gate is unreachable by input; the AC hazard (walk death) is new.
- keypress_table.md's park entry ("key-gated resume, [HW-unknown] which key") → now measured:
  **no key in 0x00–0x67 delivers 230; AC (code 18) exits the spin via the quit path and derails;
  treat 0x4EF2 as a terminal park in-emulator.**

## Baselines (md5, end of work — unchanged from session start)

```
fed27f1a9b3e9a9c426160384bfc0b55  CasioEmuX/rop_draw3.lua
eaeaca418164a42fe63a3ce189a2feca  CasioEmuX/rop_br1.lua
af172e1421c9fa7d95ec46d54c42ea7a  CasioEmuX/rop_loop1.lua
fadf4c572f7537363c11f8c6158b9edf  CasioEmuX/rop_work1.lua
5a57ffcac39827ca12cb587fa685da91  CasioEmuX/emulator/lua-common.lua
```
(rop_resume2.lua = the sweep script; rop_move1/move2-era files untouched.)
