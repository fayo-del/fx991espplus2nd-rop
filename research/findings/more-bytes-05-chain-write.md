# more-bytes-05 — Can the ROP chain COMPUTE and STORE new bytes? (2026-11-22)

Agent: `MB05ChainWrite`. Scripts: `research/CasioEmuX/more05_chainwrite.lua` (harness kick),
`research/CasioEmuX/more05_typed.lua` (typed-trigger variant of `rop_e2e.lua`).
Logs: `/tmp/more05_run2.log` (kick proof), `/tmp/more05_run4.log` (typed proof).
Dumps: `/tmp/oki_b0.txt`, `/tmp/oki_b1.txt` (bank1 real addr = file addr + 0x10000).

## Verdict

**YES — the chain has a general write-what-where primitive plus a computed-byte loop.**
Emulator-proven (harness kick, `/tmp/more05_run2.log`): a chain wrote the **computed ramp
`12 02 F2 E2 D2 C2 B2 A2` into RAM 0x8500-0x8507** (each byte = `r0 += 0xF0` per pass,
seed 0x22 — none of these bytes existed anywhere in the chain/stack), persisted at park:
`RAM-8500-8507: 1202F2E2D2C2B2A2`. Also proven: 1-byte stores at arbitrary `[ER2]`
(mem[0x8510]=0x77) and `[ER0]` (mem[0x8588]=0x88) paths. Typed-trigger run: see §4.
**Max bytes per pass: 1 byte per 12 stack bytes (3 tiles) in the ER14 loop
(`ADD R0,#0xF0` / `ST R0,[ER14]` / `ADD ER14,#1`), unbounded count while stack lasts;
in the typed trigger the reachable stack window is 0x8D9C-0x8DFF = 100 B = 25 tiles,
so ≤ ~6 computed stores per entry pass (measured).** Content delivery to the screen is
then just memcpy12 (0x35BE) from the written RAM region to LCD 0xF800 — so game content
is **not** capped at 100 distinct bytes: the chain can generate arbitrary frames.

## 1. Gadget inventory (categorized; addresses real, bank noted, ROM bytes)

### (a) ST with dst from a REGISTER, chain-continuing (the write primitives)
| addr | bytes | disasm | bank | status |
|---|---|---|---|---|
| **0x2B20** | `01 92 8E F2` | `ST R2,[ER0]; POP PC` | 0 | **VERIFIED** (run2: `ST-R2-ER0 #1: ER0=8588 r2=88 -> mem[8588]=88`) |
| 0x2F00 | `01 92 1F FE` | `ST R2,[ER0]; RT` | 0 | static (RT→lr) |
| **0x14CA2** | `21 90 00 00 8E F2` | `ST R0,[ER2]; MOV R0,#0; POP PC` | 1 | **VERIFIED** (run2: `ST-R0-ER2 #1: ER2=8130 -> mem[8130]=77`) |
| 0x15C66 | `21 90 00 02 8E F2` | `ST R0,[ER2]; MOV R2,#0; POP PC` | 1 | static |
| **0x10470C** | `E1 90 C1 D8 C2 D7 C3 D6 C4 D5 C5 D4 1F FE` | `ST R0,[ER14]; ST R8..R4,[FP+1..5]; RT` | 1 | **VERIFIED** (run2: 12 stores `mem[ER14]=r0`, ramp exact). FP=ER14 so +1..+5 side-stores are overwritten by later passes — final memory is the clean ramp |
| 0x490A | `83 92 2E F8 8E F2` | `ST ER2,[ER8]; POP XR8; POP PC` | 0 | static |
| 0x4898 | `C3 9E 2E F4 3E F8 8E F2` | `ST ER14,[ER12]; POP XR4; POP QR8; POP PC` | 0 | static |
| 0x15D26 | `C1 92 00 02 04 07 8E F2` | `ST R2,[ER12]; MOV R2,#0; MOV R7,#4; POP PC` | 1 | static |
| 0x4D48 | `41 92 00 80 1E F4 8E F2` | `ST R2,[ER4]; MOV R0,R0; POP ER4; POP PC` | 0 | static |

Pointer setters (all POP-PC-continuing, values straight from stack tiles):
| addr | bytes | disasm | bank |
|---|---|---|---|
| **0x3722** | `1E F0 8E F2` | `POP ER0; POP PC` | 0 |
| **0x49C2** | `1E F2 8E F2` | `POP ER2; POP PC` | 0 |
| **0x3066** | `1E FE 8E F2` | `POP ER14; POP PC` | 0 |
| 0x3910 | `1E F2 1F FE` | `POP ER2; RT` | 0 |
| **0x15482** | `0E F0 8E F2` | `POP R0; POP PC` (value byte) | 1 |
| 0x157E4 / 0x15D4A / 0x17A92 / 0x17BB4 | `0E F0 8E F2` | `POP R0; POP PC` | 1 |
| 0x3E88 / 0x8ABA / 0x30A6 / 0x5FA8 / 0x9FBC | `1E FC/1E FA/0E F8/0E FC 8E F2` | `POP ER12/ER10/R8/R12; POP PC` | 0 |

**Register-overlap caveat (measured, run1→run2):** ER0 *is* r0:r1, so `POP R0` after
`POP ER0` clobbers the pointer low byte (run1 wrote to 0x8588 instead of 0x8511).
Rule: keep the pointer in ER14/ER2/ER0 and the value in r0/r2; never mix POP R0 with POP ER0.

### (b) LEA imm; ST QR0,[EA]; POP PC family (fixed-addr stores of 4 register bytes)
0x1894E `0C F0 02 80 37 90 8E F2` = `LEA 0x8002; ST QR0,[EA]; POP PC` + family 0x19EE8,
0x19F12, 0x19F3C, 0x19F66, 0x1A14A, 0x1A334, 0x1A614, 0x1ADB4 (bank 1). QR0 = r0-r3,
individually loadable (`POP R0` 0x15482, `MOV R2,R0` 0x4292, `MOV R1,#0; POP PC` 0x154A8,
`MOV R3,#0;...;POP PC` 0x113A4). Bank-1 post-inc variants write 8 B/hop at fixed base,
e.g. **0x184C8** `LEA 0x8000; ST QR0,[EA+]; ST ER8,[EA+]; POP PC`, 0x178E32/0x17E50/…
(`LEA 0x8000/0x8010/0x8030/0x803C/0x8046/0x8050; ST QR0,[EA+]; ST ER8,[EA+]; RT/POP PC`).
EA from a register: `LEA [ERn]` sites — b0 0x33F4 `LEA [ER0]`, b1 0x16AE6 `LEA [ER14];
ST QR0,[EA+]; ST ER8,[EA+]; POP QR8; POP XR4; POP PC`, b1 0x16C04 `LEA 0x32[ER14]; …`;
`POP EA` 0x3480/0x34D2/0x3520/0x35BE (bank 0, no clean continuation — use via memcpy12 entry).

### (c) Arithmetic census (both banks; counts of raw sites, then chain-clean ones)
- `ADD ER2,#imm8`: 175 (b0) + 144 (b1) raw; **clean POP PC: 0x992C** `ADD ER2,#1; POP XR8; POP PC` (VERIFIED earlier).
- `ADD ER0,#imm8`: 404 (b0) + 239 (b1) raw; clean: **0x9926** `ADD ER0,#1; XOR R2,#FF; XOR R3,#FF; ADD ER2,#1; POP XR8; POP PC` (b0); **0x1469C** (b1) `ADD ER0,#1; ADDC R2,#0; ADDC R3,#0; RT` — 32-bit-safe increment.
- `ADD R0,#imm8`: 231 (b0) + 79 (b1) raw; clean: **0x3B40** `F0 10 8E F2` `ADD R0,#240; POP PC` (**VERIFIED** — the ramp step), 0x2B02 `ADD R0,#248; RT`, 0x4964/0x2FBA `ADD R0,#1; RT` (b0); 0x144FC (b1) `ADD R0,#240; MOV R2,#120; MOV R3,#15; ADD R2,R0; ADDC R3,#0; L R0,[ER2]; POP PC`; 0x14512 `ADD R0,#214; RT`.
- `ADD ER14,#imm8`: 5 (b0) + 37 (b1); clean: **0x14690** (b1) `ADD ER14,#1; RT` (**VERIFIED** — the ramp pointer step), 0x155E8/0x15BD2 `ADD ER14,#-1; MOV R7,#4; MOV R2,#0; POP PC`, 0x15A42 `ADD ER14,#1; MOV R2,R0; ADD R2,#148; POP PC`.
- `ADD R2,#imm8`: 62+43 raw; clean: 0x3B4C/0x4328/0x3E98 `MOV R2,#2; POP PC`; **0x3854** `ADD R2,#208; ST R2,[EA+]; ADD R0,#208; ST R0,[EA+]; ST R3,[EA+]; POP R4; RT` (computed store!).
- `ADD R10,#1`: 0x1482A (b1) `ADD R10,#1; RT`; **0x153B0** (b1) `ADD R10,#1; ST R0,[ER2]; MOV R2,#0; RT` — store loop with computed dst; **0x153AA** (b1) `MOV R3,#128; ADD R2,R10; ADDC R3,#0; ADD R10,#1; ST R0,[ER2]; MOV R2,#0; RT` — dst = 0x8000+R10++ per pass.
- `SUB/SUBC` reg-reg: 238 (b0) + 155 (b1) raw (no imm forms); `MUL` 46+38 (e.g. 0x48BE `MUL ER2,R0`, b1 0x13580 `MUL ER0,R2`); `XOR/OR/AND Rn,#imm` numerous (e.g. 0x9928-0x992A `XOR R2/R3,#255`).
- Register moves: 0x4292 `MOV R2,R0; POP PC` (VERIFIED); 0x15A44 `MOV R2,R0; ADD R2,#148; POP PC` (b1); 0x13584 `MOV ER2,ER0; ADD ER0,ER4; RT` (b1, VERIFIED); 0x13A80 `MOV ER2,ER12; POP PC` (b1, VERIFIED).

### (d) Post-increment store loops `ST Rn,[EA+]`
28 (b0) + 90 (b1) raw sites. Chain-shaped ones:
- **0x2C0A** (b0) `51 92 2E F4 3E F8 8E F2` = `ST R2,[EA+]; POP XR4; POP QR8; POP PC` — stores r2 at [EA], EA+=1, continues (consumes 12 B stack).
- **0x3854** (b0) = `ADD R2,#208; ST R2,[EA+]; ADD R0,#208; ST R0,[EA+]; ST R3,[EA+]; POP R4; RT` — **3 computed bytes per pass at successive [EA+]**, RT-loops to lr=0x2B1E.
- 0x2C06 `ST R5,[EA+]; MOV R2,#0; ST R2,[EA+]; …` etc.
- EA setup: `LEA [ERn]` / `LEA disp[ER14]` (above) or `POP EA` at memcpy12 entry 0x35BE.

## 2. Emulator proof — harness kick (`more05_chainwrite.lua`, run `/tmp/more05_run2.log`)

Kick: `sp=0x8C80, pc=lr=0x2B1E, csr=lcsr=0`, chain tiles at 0x8C80 (all POP-PC/RT gadgets above).
Chain: `POP ER14=0x8500; POP R0=0x22;` then 8× [`ADD R0,#0xF0` @0x3B40 → `ST R0,[ER14]` @0x10470C
→ `ADD ER14,#1` @0x14690] `; POP ER2=0x8510; POP R0=0x77; ST R0,[ER2] @0x14CA2; POP ER0=0x8511;
POP R0=0x88; MOV R2,R0; ST R2,[ER0] @0x2B20; 4× ramp into 0x87D0; park @0x4EF2`.
Verbatim evidence:
```
ADD-R0 #1: r0=12 ... ST-R0-ER14 #1: ER14=8500 r0=12 -> mem[8500]=12
ADD-R0 #2: r0=02 ... ST-R0-ER14 #2: ER14=8501 r0=02 -> mem[8501]=02
... (#3 F2 @8502, #4 E2 @8503, #5 D2 @8504, #6 C2 @8505, #7 B2 @8506, #8 A2 @8507)
ST-R0-ER2 #1: ... -> mem[8510]=77            (0x14CA2 path; final dump below)
ST-R2-ER0 #1: ER0=8588 r2=88 -> mem[8588]=88 (0x2B20 path; ER0 low byte clobbered by POP R0 — caveat §1a)
DUMP[AT-PARK] / DUMP[SETTLE]:
RAM-8500-8507 (expect 12 02 F2 E2 D2 C2 B2 A2): 1202F2E2D2C2B2A2
RAM-8510-8511 (expect 77 88): 7700            (0x88 landed at 0x8588 per caveat)
DRAWBUF-87D0-87DF: 00000000000000000000000000000000  (park firmware clears 0x87D0 — stage content in 0x8500-0x8C00 instead)
```
The 8 stored bytes are **computed** (seed 0x22 + k·0xF0 mod 256 via `ADD R0,#240`), appear
nowhere in the chain, and persist in RAM. → **Chain write primitive: YES.**

## 3. Typed-trigger proof (`more05_typed.lua`, log `/tmp/more05_run4.log`)

Same trigger pipeline as `rop_e2e.lua` (formula → AC ← EXE → strcpy flood). Entry phase
measured in run 3: first POP PC after the smash at `sp=0x8D9C` ⇒ payload phase
`(0x8D9C-0x8154)%100 = 44`, and only 0x8D9C-0x8DFF (100 B = 25 tiles) of stack remains.
Payload = 100 zero-free bytes parse-aligned at off 44: setup `POP ER14=0x8511; POP R0=0x55`
then 6× [`ADD R0,#0xF0` / `ST R0,[ER14]` / `ADD ER14,#1`] then park tiles — all tile bytes
zero-free (`66 30 0E 4D 11 85 82 54 01 01 55 4D 40 3B 0E 4D 0C 47 01 01 90 46 01 01 F2 4E`).

## 4. Typed run result (`/tmp/more05_run4.log`, VERBATIM)

```
POPPC#1 sp=8D9C (mod100=44) tile=66300E4D pc=2B1E      <- entry phase 44, setup tile POP ER14
MB05-ADD #1: r0=45 sp=8DAC                             <- setup ADD R0,#0xF0 (0x55+0xF0)
MB05-ADD #2: r0=35 sp=8DB0
MB05-ST #1: ER14=8511 r0=35 -> mem[8511]=35 sp=8DB4
MB05-ADD #3: r0=25 ... MB05-ST #2: ER14=8512 -> mem[8512]=25
MB05-ADD #4: r0=15 ... MB05-ST #3: ER14=8513 -> mem[8513]=15
MB05-ADD #5: r0=05 ... MB05-ST #4: ER14=8514 -> mem[8514]=05
MB05-ADD #6: r0=F5 ... MB05-ST #5: ER14=8515 -> mem[8515]=F5
MB05-ADD #7: r0=E5 ... MB05-ST #6: ER14=8516 -> mem[8516]=E5
PARK-REACHED #1 sp=8D76 pc=4B96
PROTO: PARKED-AFTER-WRITES hits=0 pc=4B96 sp=8D76
PROTO: RAM-8500-8520: F24E0E4D 66300E4D 11858254 0101554D 40 35 25 15 05 F5 E5 F2 00 ...
                                                   ^0x8511..0x8516 = 35 25 15 05 F5 E5
```
Six bytes **computed in-chain** (`r0 = 0x55 + k·0xF0 mod 256`) from a 100-byte typed
zero-free payload landed in RAM 0x8511-0x8516 and persisted after the trigger; none of
`35 25 15 05 F5 E5` appears anywhere in the payload bytes
(`66 30 0E 4D 11 85 82 54 01 55 40 3B 0C 47 90 46 F2 4E 4D`). **Typed chain-write: PROVEN.**


## 5. Implications for the 100-byte ceiling

- The chain can write **arbitrary computed bytes to any RAM address** (1 byte / 3 tiles in
  the ER14 loop; 1 byte / ~6 tiles via explicit POP ER0 per store; memcpy12 then moves
  12 B/hop from any even 0x8154-0x8DFF source to ER2 dst, e.g. LCD 0xF800).
- Typed-trigger budget per entry pass: 25 tiles → ~6 computed stores (measured layout);
  the flood itself already gives 100 distinct bytes; combining both, **game content is no
  longer limited to the 100 payload bytes** — a frame can be synthesized byte-by-byte
  (e.g. diagonal: dst=base+row*16+col computed via ADD ER14/R10 steps, value via ADD R0).
- Watch-outs (measured): 0x87D0 draw buffer and 0xF800 LCD SFR get refreshed/cleared by the
  parked firmware (run 2: 0x87D0 zeroed at park) — stage computed content in mid-RAM
  (0x8500-0x8C00 worked, persistent) and copy to LCD via memcpy12 inside the chain, not at park.
- Register-overlap caveat §1a; RT exits need lr=0x2B1E (lcsr=0) — held in the typed trigger
  (observed: chain hopped through RT gadgets and parked correctly).
