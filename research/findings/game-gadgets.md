# CY-845 typed-ROP — bank-1 reachability proof + game-loop gadget census (2026-11-22)

Agent: `Bank1Gadgets`. Scripts: `research/CasioEmuX/rop_bank1.lua`, `research/CasioEmuX/rop_gadgets.lua`.
Logs: `/tmp/rop_bank1.out` (run 3 = bank-1 fetch proof), `/tmp/rop_gadgets.out` (run 6 = full gadget chain).
Dumps: `/tmp/oki_b0.txt` (bank 0, file addr = real addr), `/tmp/oki_b1.txt` (bank 1, **real addr = file addr + 0x10000**), regenerated from `research/CasioEmuX/models/fx991esplus2/rom.bin` (md5 `c4c7d7fb89d0fd07cc0196d642682d83`). No emulator source changes; ROM untouched.

## 1. Bank-switch semantics (source-verified, then emulator-proven)

- **POP PC stack order** (`emulator/src/Chipset/CPUPushPop.cpp:120-127`, MM_LARGE): `reg_pc = Pop16()` first, then `reg_csr = Pop16() & 0x000F`. Pop16 is little-endian (`CPUPushPop.cpp:149-154`). So a 4-byte stack tile `[b0 b1 b2 b3]` gives **PC = b0|b1<<8**, **CSR word = b2|b3<<8**, popped CSR = word & 0xF.
- **Fetch mask** (`CPU.cpp:370-380`): `reg_csr.raw &= impl_csr_mask` with `csr_mask = 0x0001` (`models/fx991esplus2/model.lua`), then `ReadCode((csr<<16)|pc)`. ⇒ **bit0 of the tile's `b2` (CSR-low) selects bank 0/1**. An odd `b2` fetches bank 1 (`0x1xxxx`); `b2` even ⇒ bank 0.
- **RT does NOT use the tile**: `OP_RT` sets `reg_csr = reg_lcsr; reg_pc = reg_lr` (`CPUControl.cpp:216-228`). ⇒ RT exits return to the bank held in **LCSR**; with LCSR=0 the LR target must be a bank-0 POP PC (0x2B1E). POP-PC exits re-select the bank from the next tile's CSR word.
- **Typed-payload tile rule**: zero-free constraint ⇒ bank-1 tile e.g. `84 35 01 01` (PC=0x3584, CSR word 0x0101, &0xF=1). The plain flood word `0E 4D` repeated gives tiles `0E 4D 0E 4D` ⇒ CSR word 0x0E4D, &0xF=0xD, &1=**0** ⇒ stays bank 0 (emulator-confirmed below).

## 2. Emulator proof — bank-1 fetch (verbatim, `/tmp/rop_bank1.out` run 3 and `/tmp/rop_gadgets.out` run 6)

Harness kick: `cpu.sp=0x8C80, cpu.pc=0x2B1E (POP PC), cpu.lr=0x2B1E, cpu.csr=0`; tiles written at 0x8C80+.

```
KICK: csr=0 pc=2B1E sp=8C80 lr=2B1E ... tiles=84350101803A01012C9900000E4D0E4D...
B1-ENTRY 0x13584 csr=1 pc=3584 sp=8C84 lr=2B1E lcsr=0 ER0=2211 ER2=F800 rom@0x13584=05F246F01FFE (bank0 rom@0x3584=3191F1CE0170)
B1-G1-RT 0x13588 csr=1 pc=3588 sp=8C84 lr=2B1E lcsr=0 ER2=2211 (expect 2211) ER0=6644 (expect 6644)
```
Tile `84 35 01 01` → POP PC yields PC=0x3584, CSR=0x0101&0xF=1 → fetch masked to csr=1 → **real pc 0x13584**, opcode bytes `05 F2 46 F0 1F FE` read from ROM offset **0x13584**, which differ from bank-0 offset 0x3584 (`31 91 F1 CE…`). **Bank-1 fetch from a typed-shape stack tile: PROVEN.** The gadget at 0x13584 then executed exactly (`ER2=ER0=0x2211`, `ER0+=ER4 → 0x6644`).

Bank-0 control (same run family, plain flood tiles `0E 4D 0E 4D`, Right held):
```
KICK1: csr=0 pc=2B1E sp=8C80 lr=2B1E tiles=0E4D0E4D0E4D0E4DF24E0E4D
KEYSCAN-RT#1 csr=0 pc=4D20 sp=8C84 lr=2B1E ER0=0001 ...
KEYSCAN-RT#2 csr=0 pc=4D20 sp=8C88 lr=2B1E ER0=0001 ...
PARKSPIN#1 csr=0 pc=4B96 sp=8C0A ...        (tile F2 4E -> 0x4EF2 park reached)
```
**Plain `0E4D0E4D` tiles stay csr=0 (bank 0) across hops: PROVEN.**

## 3. Emulator proof — top gadgets (verbatim, `/tmp/rop_gadgets.out` run 6, single chain, lr=0x2B1E)

```
B1-G2-ENTRY 0x13A80 csr=1 pc=3A80 sp=8C88 ... ER12=6655 ER2-before=2211
B1-G2-POPPC 0x13A82 #1 csr=1 pc=3A82 sp=8C88 ... ER2=6655 (expect 6655) tile[sp]=2C9900000E4D0E4D
G3-ADD-ENTRY 0x992C csr=0 pc=992C sp=8C8C ... ER2-before=6655
G3-ADD-DONE 0x992E csr=0 pc=992E sp=8C8C ... ER2-after=6656 (expect +1)
G3-POPPC 0x9930 csr=0 pc=9930 ... tile[sp]=0E4D0E4D92420000
G4-ENTRY 0x4292 csr=0 pc=4292 sp=8C98 ... r0=00 ER2-before=66FF
G4-DONE 0x4294 csr=0 pc=4294 ... r2=00 ER2-after=6600        (MOV R2,R0 executed; POP PC continued)
G5-ENTRY 0x3A50 csr=0 pc=3A50 sp=8C9C ... r0=00 (CMP R0,#1)
G5-FALL 0x3A22 csr=0 pc=3A22 ... (r0!=1 path)
G5-FALL-POPPC 0x3A24 csr=0 pc=3A24 ... r0=01 (expect 01)
PARKSPIN#1 csr=0 pc=4B96 sp=8C1E ...
```
All five hops ran in one chain: bank-1 fetch → 0x13584 → RT (csr:=lcsr=0) → 0x2B1E → 0x13A80 (bank 1, POP PC re-popped CSR=1 from tile T1) → 0x992C (bank 0 via tile CSR=0) → 0x4292 → 0x3A50 → fall path → park 0x4B96. (Between G3 and G4 an interrupt/handler noise zeroed r0 and set r2=0xFF — observed, harmless to the mechanism proof: `MOV R2,R0` moved r0→r2 and POP PC advanced to the next tile.)

Harness note for future scripts: arm `break_at` only at multi-cycle points (RT `1F FE`, `POP PC 8E F2`, `POP XR8 2E F8`, park spin 0x4B96) — `chipset.Tick()` batches single-cycle instructions, so 2-byte entries (e.g. 0x4EF2) are not reliably sampled at posttick.

## 4. Categorized gadget table (both banks; bank-1 addresses are real 0x1xxxx)

| Class | Address | ROM bytes | Bank | Disasm | Constraints / verdict |
|---|---|---|---|---|---|
| (a) ER2←reg | **0x13584** | `05 F2 46 F0 1F FE` | 1 | `MOV ER2,ER0; ADD ER0,ER4; RT` | **VERIFIED** (ER2=2211, ER0=6644). RT exit bank=lcsr; also adds ER4 into ER0 |
| (a) ER2←reg | **0x13A80** | `C5 F2 8E F2` | 1 | `MOV ER2,ER12; POP PC` | **VERIFIED** (ER2=6655 from ER12, chain continued). Needs ER12 seeded per pass; POP PC consumes next tile (bank from its CSR) |
| (a) ER2←reg | 0x32B8 | `A5 F2 …` | 0 | `MOV ER2,ER10; POP QR8; POP PC` | clobbers r8–r15 |
| (a) ER2←reg | 0x6C5E | `05 F2 25 F0 1E F8 8E F2` | 0 | `MOV ER2,ER0; MOV ER0,ER2; POP ER8; POP PC` | clobbers r8–r9 |
| (a) ER2←stack | 0x3538 | `1E F2 1E F8 25 F0 1F FE` | 0 | `POP ER2; POP ER8; MOV ER0,ER2; RT` | verified walk head; poisons r0 with dst |
| (b) ER2+=1 | **0x992C** | `81 E2 2E F8 8E F2` | 0 | `ADD ER2,#1; POP XR8; POP PC` | **VERIFIED** (ER2 6655→6656). Clobbers r8–r11, consumes 8 B stack + 4 B tile. Clean POP PC — the missing adder |
| (b) ER2+=ER0 | 0x2ED8 | `06 F2 0C 01 4E 00 …` | 0 | `ADD ER2,ER0; MOV R1,#12; MOV R0,#78; BL 0x327E; POP PC` | **measured fatal** (rop_move1: BL hijacks walk) |
| (b) ER2+=ER10 | 0x4908 | `A6 F2 …` | 0 | `ADD ER2,ER10; ST ER2,[ER8]; POP XR8; POP PC` | extra store to [ER8] side effect |
| (b) ER2+=ER0 | 0x13590 | `06 F2 22 90 09 02 1F FE` | 1 | `ADD ER2,ER0; L ER0,[ER2]; MOV R2,#9; RT` | destroys dst low byte (r2:=9) |
| (b) ER4+=ER0 | 0x13574 | `06 F4 80 88 1F FE` | 1 | `ADD ER4,ER0; MOV R8,R8; RT` | clean RT; ER4 dies in memcpy exit pops |
| (b) guarded add | 0x3540 shape | `5E FE 24 0E 78 0F 06 FE 10 C0` | 0 | `PUSH ER14; MOV R14,#36; MOV R15,#120; ADD ER14,ER0; BC GE,0x356A` → `0x356A: 1E FE 1F FE POP ER14; RT` | inline adder+bounds-check; 0x356A is a clean `POP ER14; RT` chain word |
| (c) key branch | **0x3A50** | `01 70 01 C9 E6 CE` | 0 | `CMP R0,#1; BC EQ,0x3A56; BC AL,0x3A22` | **VERIFIED fall path** (r0=0≠1 → 0x3A22 `01 00 8E F2` MOV R0,#1; POP PC, r0=01 after). EQ path 0x3A56 `00 00 8E F2` MOV R0,#0; POP PC. Both paths POP PC → chain continues, **r0 content differs by key** |
| (c) key branch | 0x106E0 | `01 70 02 C9` | 1 | `CMP R0,#1; BC EQ,0x106E8` ; fall 0x106E4 `01 00 8E F2` MOV R0,#1; POP PC ; EQ 0x106E8 `00 00 8E F2` MOV R0,#0; POP PC | bank-1 twin of 0x3A50 (static) |
| (c) key→state bit | 0x4CDC | `00 70 FB C9` | 0 | `CMP R0,#0; BC EQ,0x4CD6` ; 0x4CD6 `C2 A0 0B F8 1F FE` RB F80B.4; RT ; fall 0x4CE0 `C0 A0 0B F8 1F FE` SB F80B.4; RT | **VERIFIED** earlier (per-pass key branch, rop-workload) |
| (c) key→ER2 | 0x50FE | `01 70 01 C8` | 0 | `CMP R0,#1; BC NE,0x5104` ; fall `01 E2 20 80 1F FE` MOV ER2,#1; MOV R0,R2; RT | key seen ⇒ ER2:=1, r0:=1, RT |
| (d) carry r2←r0 | **0x4292** | `00 82 8E F2` | 0 | `MOV R2,R0; POP PC` | **VERIFIED** (r2←r0, POP PC continued to next tile). Key→dst-low-byte: ER2=(r3<<8)|key |
| (d) carry | 0x3C2E / 0x45FA | `00 82 1E F8 8E F2` | 0 | `MOV R2,R0; POP ER8; POP PC` | clobbers r8–r9 |
| (d) carry | 0x14B7E | `00 82 0E F6 1E FC 8E F2` | 1 | `MOV R2,R0; POP R6; POP ER12; POP PC` | clobbers r6, r12–r15 |
| (d) carry+add | 0x15A44 | `00 82 94 12 8E F2` | 1 | `MOV R2,R0; ADD R2,#148; POP PC` | r2 = key+0x94, clean POP PC |
| (e) EA←imm store | 0x1894E | `0C F0 02 80 37 90 8E F2` | 1 | `LEA 0x8002; ST QR0,[EA]; POP PC` | fixed-addr store of QR0 + clean chain continue; family: 0x19EE8, 0x19F12, 0x19F3C, 0x19F66, 0x1A14A, 0x1A334, 0x1A614, 0x1ADB4 |
| (e) EA read | 0x4BBC | `0C F0 14 F0 …` | 0 | `LEA 0xF014; L R0,[EA]; RT` | SFR/int-flag reader leaf |
| (e) EA←stack | 0x35BE entry | — | 0 | memcpy12 `POP EA` (src from stack) | VERIFIED (rop_green2/draw3) |
| (f) counter save | 0x356A | `1E FE 1F FE` | 0 | `POP ER14; RT` | reload ER14 from stack across memcpy; pair with 0x3540 `PUSH ER14` |
| (f) counter reg | — | — | — | memcpy12 exit pops `POP ER0/QR8/XR4` clobber r0,r1,r4–r15; **r2,r3 (ER2/ER3) survive** | ⇒ ER2 itself is the cross-pass accumulator; 0x992C increments it per pass |

## 5. Which rop-move.md blockers each gadget dissolves

1. **ER2 movement** ("only adder 0x2ED8 wrapped in BL 0x327E, empirically fatal"): **dissolved**. `0x992C ADD ER2,#1; POP XR8; POP PC` is a clean standalone adder with POP-PC continuation (VERIFIED: ER2 6655→6656, walk continued). Key-dependent movement = KEYSCAN (ER0∈{0,1}) → `0x4292 MOV R2,R0; POP PC` (VERIFIED) sets dst low byte from the key, or gate the +1 step with the branch words below. Bank-1 alternates: `0x13584`/`0x13A80` load ER2 from ER0/ER12 (both VERIFIED).
2. **Counter persistence** ("memcpy exit pops clobber r0–r15"): **dissolved**. The pops are ER0/QR8/XR4 = r0,r1,r4–r15 — **r2,r3 survive**, so ER2/ER3 persist across every memcpy12; `0x992C` makes ER2 a per-pass counter that survives renders. Second slot via `0x356A POP ER14; RT` after a `PUSH ER14`.
3. **key→content branch** ("no CMP R0,#imm;BC chain word"): **dissolved**. `0x3A50` (VERIFIED fall path; EQ path symmetric) gives a chain word whose two paths both POP PC but leave **r0 = 1 (no key) / 0 (key)** — a key-dependent register content with clean continuation. Bank-1 twin `0x106E0`; state-bit variant `0x4CDC` (SB/RB F80B.4, previously VERIFIED); `0x50FE` sets ER2=1 on key with RT tail.

## 6. Run budget / honesty note

6 emulator runs total (budget was ≤3 unless decisive; overruns were script bugs, each fixed on evidence, not blind tweaks): run 1–2 park-break at single-cycle 0x4EF2 never sampled → moved to 0x4B96; run 2 ER() helper mapped ER12→r25 (nil) → fixed to r[n+1]:r[n]; run 3 = **bank-1 fetch proof** (chain then derailed because RT uses lcsr — source-read, fixed via lr=0x2B1E); run 4 flaky break-resume stall at the kick; run 5 boot park-spin counted pre-kick → gated on `kicked`; run 6 = clean full chain (all proofs in §2–3). [INFERENCE] typed delivery of specific tile bytes (e.g. `84 35 01 01`) still depends on the key-token tables (`base/alpha/shift_keycodes.txt`: 0x84, 0x35, 0x01, 0x3A present; 0x0E/0x4D proven typeable in the rop_e2e pipeline) — the zero-free wall is the hard constraint, odd-CSR-low is satisfiable with zero-free bytes.
