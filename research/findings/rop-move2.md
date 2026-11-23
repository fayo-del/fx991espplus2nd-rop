# Typed-ROP milestone 8: movement via bank-1 sweep — NEGATIVE (no closable arithmetic chain); bank-1 gadget table delivered

**Verdict: NEGATIVE (0 additional runs used; analysis-conclusive per the task's step 4 exit: "if
no candidate: report the byte-level search coverage and stop").** Bank 1 (csr=1) **does contain
the gadget classes missing from bank 0** — the sweep succeeded — but no composition closes the
chain {keyscan → carry/add → memcpy} with a key-dependent dst, because every candidate either
accumulates in the wrong register, corrupts ER2's low byte in its tail, or needs a small exact
constant that cannot live in the typed payload (the zero-byte wall: any `0x00xx` word truncates
the typed string and kills the trigger — measured in the workload milestone's run 2).

- Method: full-scan of `/tmp/oki_b1.txt` (bank-1 window 0x0000–0xFFFE, 28,217 instruction lines;
  real address = 0x10000 + file offset; reached with a crafted word whose low nibble = 1 — the
  walk's popped-CSR semantics measured in the loop milestone). Every candidate's tail was
  verified by reading the surrounding disassembly, not the first match.
- No emulator run was spent: no candidate composition closes the chain within the 2-run budget;
  burning a run on a known-open chain would produce no decision-relevant data.

## Bank-1 gadget table (csr=1; pc = the file address)

| pc | bytes | disasm | verdict |
|---|---|---|---|
| 0x3584 | `05 F2 46 F0 1F FE` | `MOV ER2,ER0; ADD ER0,ER4; RT` | **CLEAN — the missing ER2-load!** But it copies ER0 (not accumulates into ER2) and accumulates into ER0 (not the dst) |
| 0x3590 | `06 F2 22 90 09 02 1F FE` | `ADD ER2,ER0; L ER0,[ER2]; MOV R2,#9; RT` | the add exists but the tail sets r2=9 → ER2 = (r3<<8)&#124;9: the dst's low byte is destroyed after every use (r3 = the only survivor register is the page) |
| 0x3A80 | `C5 F2 8E F2` | `MOV ER2,ER12; POP PC` | clean copy from ER12 — but ER12 never survives the memcpy (QR8 clobbers r8–r15) and nothing loads ER12 cleanly |
| 0x4790 | `25 F2 02 C8 05 F8 8E F2` | `MOV ER2,ER2; BC NE,+2; MOV ER8,ER0; POP PC` | conditional side-load only; both paths Pop-PC to the same next word — no flow divergence |
| 0x4820 | `C5 F2 A1 82 00 63 29 90 28 00 01 1A 1F FE` | `MOV ER2,ER12; ADD R2,R10; ADDC R3,#0; ST R0,28h[ER2]; ADD R10,#1; RT` | **`ADD R2,R10` — a real r10-accumulated add with RT!** but r10 dies in the memcpy's QR8 pop and nothing increments r10 standalone (`ADD R10,#1` here is mid-function); also performs an extra store to [ER2+0x28] |
| 0x4B7E | `00 82 0E F6 1E FC 8E F2` | `MOV R2,R0; POP R6; POP ER12; POP PC` | carry r2←r0 then continue — but it *overwrites* r2 (the dst low byte) rather than adding; the dst becomes (r3<<8)&#124;key |
| 0x4EAE | `00 81 C0 CE 02 00 8E F2` | `MOV R1,R0; BC AL,…; MOV R0,#2; POP PC` | unconditional branch — no dispatch value |
| 0x5A44 | `00 82 94 12 8E F2` | `MOV R2,R0; ADD R2,#148; POP PC` | r2 = key + 0x94: arithmetic on the key with a clean tail! — but it *overwrites* the dst low byte (dst = (r3<<8)&#124;(key+0x94)) and needs r3 = the page pre-seeded |
| 0x0742 | `FF 03 E6 F2 01 F0 5E 4A 8E F2` | `MOV R3,#255; ADD ER2,ER14; BL 0x4A5E; POP PC` | `R3` setter + `ADD ER2,ER14` — but the BL kills it (same failure class as bank 0's 0x2ED8, measured in rop-move.md) |

Also confirmed: **no `MOV R3,#0xF8`-style page setter with a clean tail exists in bank 1** (the
candidates set r3=0/17/255 or route into `BL`s).

## Why the chain still doesn't close (the precise blocker)

The working pieces exist individually:
- The key poll normalizes **ER0 = {0x0000, 0x0001}** exactly (`MOV ER0,#0; …; ADDC R0,#0`).
- **0x13584** (`MOV ER2,ER0; ADD ER0,ER4; RT`) is a clean bridge that keeps ER2 = the head's
  fresh base and accumulates ER0 += ER4.
- The head (0x3538) seeds ER2 = 0xF811-fresh each pass (r0 = the copy — harmless if nothing
  reads r0 until the next key poll).

What fails is the last mile: the accumulated value lands in **ER0**, but the memcpy's
destination register is hardwired to **ER2**, and the only `ADD ER2,ER0`-with-a-tail (0x13590)
destroys the dst low byte (`MOV R2,#9`) — reducing every path to a fixed dst again. Accumulating
in r2/r3/r10 directly fails because r2 is clobbered by every key poll and r3/r10 are unreloadable
(no clean page-setter; r10 dies in the memcpy's QR8). An exact small constant (0x0001) in the
payload is impossible without a 0x00 byte, which truncates the typed string and kills the
(trigger) pipeline — measured.

## Verdict per the task's criteria

- Bank-1 dump: full (0x0000–0xFFFE = 0x10000–0x1FFFF real). ✅
- Missing classes searched: (a) `ADD ER2,ERn` clean-tail — **found but dst-corrupting**;
  (b) standalone carry — **absent in both banks**; (c) clean `POP ER2`/`MOV ER2,ERn` — **found
  (0x13584/0x13A80), insufficient alone**; (d) conditional dispatch — **absent as a gadget**
  (only inside function bodies).
- No candidate composition closes `KEYSCAN → carry/add → memcpy` with a key-advancing dst →
  **stop, report, no runs burned.**

## Exact next parameter (for the next session)

**Hunt one of these two specific gadgets; either one closes the chain immediately:**
1. **`ADD ER2,Rn` (any n) whose tail reaches `RT`/`POP PC` within ≤2 instructions without touching
   r2, r3, or calling `BL`** — scan pattern: `ADD ER2, ER` followed by ≤2 lines then `1F FE|8E F2`
   (bank 1 has zero such; bank 0 has zero such). ~~bank 2+ unexamined~~ **CORRECTED
   (rop-resume.md): dead end — the ES_PLUS fetch mask is `offset &= 0x1FFFE` (MMU.cpp), so the
   reachable ROM is exactly banks 0–1, both already dumped; no banks 2–3 exist.**
2. **A game-changer already in hand: the key-gated resume** (`rop-move.md`, discovery #1):
   0x4EF2 = `PUSH LR; MOV R0,#1; BL 0x8508; CMP R0,#230; BC NE,0x4EF4; POP PC` — the walk parks
   inside 0x8508 (the observed pc=4B96 spin) until the key producing 230 (0xE6) is pressed, then
   `POP PC` resumes at the next payload word. **Next step: identify the physical key whose scan
   code makes 0x8508 return 0xE6 (disassemble 0x8508, cross-reference the key matrix table in
   `findings/keypress_table.md`), then build the Snake-lite loop as walk → park (await key) →
   resume → branch on the key using the ALREADY-VERIFIED 0x4CDC → adjust the continuation word.**
   This sidesteps arithmetic entirely: the *continuation*, not the address, is key-dependent.

## Scope/status

| Capability | Status |
|---|---|
| Re-entry loop | VERIFIED (rop-loop.md) |
| Per-pass key branch + fixed render | VERIFIED (rop-workload.md) |
| Key-dependent draw address | **NEGATIVE (this milestone) — blocker precisely characterized** |
| Key-gated run/pause (0x4EF2/0x8508) | **DISCOVERED, mechanism mapped, resume untested** |
| Snake-lite | blocked on movement; recommended path = the key-gated-resume model |

## Baselines (md5, end of work — unchanged)

```
fed27f1a9b3e9a9c426160384bfc0b55  CasioEmuX/rop_draw3.lua
eaeaca418164a42fe63a3ce189a2feca  CasioEmuX/rop_br1.lua
af172e1421c9fa7d95ec46d54c42ea7a  CasioEmuX/rop_loop1.lua
fadf4c572f7537363c11f8c6158b9edf  CasioEmuX/rop_work1.lua
5a57ffcac39827ca12cb587fa685da91  CasioEmuX/emulator/lua-common.lua
```
(rop_move1.lua = `1454daa82c3574701ef925e6b24e423d`, the movement milestone's script, kept as the
v13b record.)
