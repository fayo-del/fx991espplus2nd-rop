# Typed-ROP milestone 5: re-entry loop — the walk re-entered itself indefinitely (LOOP)

**Verdict: LOOP (run 1 of 3; runs 2–3 not needed).** The typed-ROP walk now re-enters itself
through a SP-pivot: KEYSCAN entries repeat in an exact cycle (`#21–#38` ≡ `#39–#50`+), SP cycles
`0x8DAE → 0x8DF2` (+4 per hop) and snaps back via the pivot, ER14 stays pinned at the replay
base `0x8DA8`, and net stack consumption per pass is **zero** — a closed, infinite loop. The
run ended on the script's own anti-runaway guard (`scan_hits >= 50`), not on a fault.

- Script: `rop_loop1.lua` (base `rop_br1.lua`, which is the verified-branch script; `rop_br1.lua` untouched).
- Command: `cd /home/yoxu/Projects/fx991espplus2nd/research/CasioEmuX && SDL_VIDEODRIVER=dummy timeout 240 ./emulator/emulator model=models/fx991esplus2 script=rop_loop1.lua` (headless; `pgrep -af emulator` empty before and after; exit 124 = the 240 s wall cap after `finish()` had already paused the CPU — all evidence is in `/tmp/rop_loop1.out`).

## Pivot / gadget encodings (bank 0, from `/tmp/oki_b0.txt`, oki-u8-disas dump)

| addr | bytes | disasm | role in the loop |
|---|---|---|---|
| 0x3066 | `1E FE 8E F2` | `POP ER14; POP PC` | loader: pops ER14 from the next payload word, then pops the next (pc, pad) pair — continues the march, loads ER14 in one gadget |
| 0x75DE | `EA A1 1E FE 1F FE` | `MOV SP,ER14; POP ER14; RT` | the pivot: SP := ER14 (replay base), re-plants ER14 from `word[SP]` for the next pass, `RT` jumps to lr (the march keeps lr = 0x2B1E-point throughout, and `RT` does not pop) |
| 0x2D5C | `EA A1 2E FC 8E F2` | `MOV SP,ER14; POP XR12; POP PC` | alternate pivot — rejected: its `POP XR12` clobbers r12–r15 (=ER14) and needs +8 of padding after every reset |
| 0x5238 | `EA A1 2E F4 3E F8 8E F2` | `MOV SP,ER14; POP XR4; POP QR8; POP PC` | alternate pivot — rejected: +16 consumption per pass and clobbers ER14 via QR8 |
| 0x10F4C | bank 1 (csr=1 → 0x0F4C) | `MOV SP,ER14; POP ER14; POP PC` | alternate — untested: requires a bank-1 csr word in the chain; unnecessary once 0x75DE closed the ledger |

Also observed: the app itself executes 0x75DE as its own stack-restore
(`PIV-PIVOT t=88678 sp=8DE6 ER14=8DE6 r0=00 lr=49C2`, likewise `lr=9D44`):
ER14=SP at entry, i.e. the firmware's own `MOV SP,ER14` convention — our use matches the ISA's intent.

## Measured march geometry (from rop_br1's runs, reused here)

- Walk entry: the 0x2B1E-point's pop runs at sp=0x8D9C (pc = `word[0x8D9C]`, second word discarded);
  `POP PC` pops 4 bytes and the CSR is never updated by the march (constant, bank 0).
- No-head walk: entries at sp = 0x8DA0 + 4k (benign ±2 slack observed), pc-slot word index
  `(addr − 0x8D70) mod 100` into the typed payload at 0x8154; flood word 0x4D0E = KEYSCAN + return-to-lr.
- 0x4CDC branch (verified last milestone): fires mid-march, `r0` = keyscan scan result; F80B bit4
  set with Right held / clear without.

## Payload (typed at 0x8154, len 100 — verbatim from the script)

```
W(30, 0x3066)   -- POP ER14; POP PC: pre-catch ER14 re-load (every pass)
W(34, 0x8DA8)   -- its ER14 value
W(36, 0x75DE)   -- MOV SP,ER14; POP ER14; RT: pivot (catches via the load's pop pc)
W(38, 0x75DE)   -- backup pivot catch at word[0x8DFA]
W(42, 0x75DE)   -- backup pivot catch at word[0x8DFE]
W(44, 0x3066)   -- pass-1 first pc-slot load (word[0x8D9C])
W(48, 0x8DA8)   -- its ER14 value (replay base 0x8DA8)
W(56, 0x8DA8)   -- pivot self-refresh: word[0x8DA8] = 0x8DA8
W(40, 0x4EF2)   -- park insurance for a +2-shifted phase (word[0x8DFC])
```
everything else = `0E 4D` flood. Final buffer confirms the crafts landed:
`PROTO: final-buf 0E4D…4D 6630 0E4D A88D DE75 DE75 F24E DE75 6630 0E4D len=100`
(W(30)=6630=0x3066, W(34)=A88D=0x8DA8, W(36)=W(38)=W(42)=DE75=0x75DE, W(40)=F24E=0x4EF2, W(44)=6630).

## Decisive lines (verbatim, `/tmp/rop_loop1.out`)

```
CHAIN: KEYSCAN #1  ER0=0000 ER14=8DA8 pc=4D20 sp=8DA6 lr=2B1E words[sp-8..sp+7]=4D0E 8DA8 4D0E 4D0E 4D0E 8DA8 4D0E 4D0E lcd01=...
CHAIN: KEYSCAN #20 ER0=0000 ER14=8DA8 pc=4D20 sp=8DF2 lr=2B1E words[sp-8..sp+7]=4D0E 4D0E 4D0E 4D0E 3066 4D0E 8DA8 75DE lcd01=...
CHAIN: KEYSCAN #21 ER0=0000 ER14=8DA8 pc=4D20 sp=8DAE lr=2B1E words[sp-8..sp+7]=4D0E 8DA8 4D0E 4D0E 4D0E 4D0E 4D0E 4D0E lcd01=...
```

- `#20` at sp=0x8DF2 is the last keyscan of pass 1; the words ahead of it are exactly the crafted
  tail: `3066` (loader) `8DA8` (value) `75DE` (pivot) — the ledger the design predicted.
- `#21` at sp=**0x8DAE** = post-pivot restart (0x8DF2 → −0x44): **the pivot fired and reset SP.**
- Entries repeat exactly: `#21–#38` = `#39–#50`+ (sp pattern `8DAE 8DB2 … 8DF2` twice, third pass
  underway when the guard fired):

```
PROTO: TRIGGERED-CHAIN-RUNS hits=50 pc=4D20 sp=8DDA ER14=8DA8 piv=317
PROTO: final-F80B=80 F80C=00
```

- `hits=50` = the script's anti-runaway finish (`scan_hits >= 50`), taken mid-pass-3;
  pass 1 = 20 keyscans (entries 0x8DA6..0x8DF2), passes 2+ = 18 keyscans (0x8DAE..0x8DF2) + pivot.
- `ER14=8DA8` on every sampled line, including at the finish — the keyscan does **not** clobber
  r14/r15, and the pivot's self-refresh word (W(56)) keeps the base pinned.
- `piv=317` counts all 0x75DE executions (walk pivots + the app's own pre-walk uses; the
  print cap was consumed by the latter — the CHAIN sp sequence is the walk-phase proof).

## Loop measurements

| quantity | value |
|---|---|
| period | 19 beats = 18 KEYSCAN hops + loader + pivot (pass 1 = 20 hops: one extra from the W(44) entry loader) |
| SP cycle | 0x8DAE → 0x8DF2 step +4, then pivot reset to 0x8DA8 (next entry 0x8DAE) |
| stack consumed per pass | **0 net** (pivot resets SP; ER14 re-planted from word[0x8DA8]) |
| ER14 | pinned 0x8DA8 for the whole run |
| r0 at each keyscan | keyscan scan result (the per-pass input channel) |

## Status matrix (updated)

| Capability | Status |
|---|---|
| Typed chain: keyscan hop + return | SUPERSEDED |
| Typed chain: keyscan + RAM write / memcpy12 LCD draw | SUPERSEDED (draw3: VERIFIED) |
| Key-conditional branch inside the walk | **VERIFIED** (rop-branch.md) |
| **Re-entry loop (walk restarts itself; unbounded hits)** | **LOOP — VERIFIED (this run)** |
| Useful work *inside* the loop (draw + branch + input) | OPEN — next milestone |
| Snake-lite game loop | unblocked: the loop provides the frame beat + r0 input |

## Next step

The loop is a free-running frame beat with a key state (r0) sampled every pass. Next: place real
workload words at mid-cycle pc-slots — e.g. the 0x4CDC branch (key-conditional turn) at one
`0x8DAE+4k` slot and the 0x35BE memcpy12 (LCD row draw) at another, both now safe because the
loop geometry is measured and the pivot re-syncs any drift. Keep the payload's craft slots
disjoint from the loader/pivot words (offsets ≥ 100 wrap: stick to the measured window
`W(30)..W(56)`). Then diff LCD rows between passes to make a moving sprite — the Snake-lite core.
