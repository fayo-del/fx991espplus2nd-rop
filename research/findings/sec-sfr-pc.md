# SecSFR — can PC/CSR be set from data, or can fetch leave ROM? (CY-845 / fx-991ES PLUS 2nd, ML610904)

Question: besides the known ROP-from-RAM-data, is there ANY path that sets PC/CSR from
data or makes the CPU fetch from non-ROM (RAM/MMIO)?

Model identity: `model.lua` `hardware_id = 3` = `HW_ES_PLUS` with `csr_mask = 0x0001`
(`models/fx991esplus2/model.lua:34-37`, `Data/HardwareId.hpp:7`), ROM = 128 KB mask image
(rom.bin md5 c4c7d7fb89d0fd07cc0196d642682d83). MMU model = MM_LARGE, CPU model = CM_NX_U8
(`Chipset.cpp:46-47`).

## Method

Enumerated every nX-U8/100 control-transfer instruction and its data source in the
emulator; enumerated the SFR map (`assets/ML610904.DCL` SFR 0xF000-0xFFFF, `ML610904.H`),
all exception/interrupt vector indices, and grepped the full-bank disassembly
(`research/fxesplus/disasm/segment_{0,1}.txt`; note `/tmp/oki_b0.txt`,`/tmp/oki_b1.txt`
are gone). Checked every writable surface for a route into the fetch path.

## Candidate table

| # | Surface | Writer (who can set it) | What it controls | Verdict |
|---|---------|--------------------------|------------------|---------|
| 1 | `POP PC` (0x8EF2 → POP-list bit PC) | CPU pops its own data stack | PC16 ← `[SP]`+2, CSR16 ← `[SP]`+4 (`CPUPushPop.cpp:120-133`) | ⚠ PC set from RAM **data** — this IS the known ROP. Fetch still via ReadCode (see next row). |
| 2 | `RT` / `RTI` termination | LR/LCSR via `PUSH LR`/`POP LR` through RAM (`CPUPushPop.cpp:44-55,105-110`) or `L ECSR/ELR, ERn` (`CPUControl.cpp:24-30` writes control regs from ER **register** values = RAM data) | PC ← LR/ELR, CSR ← LCSR/ECSR | Same class as #1: PC/CSR from register/RAM data. Known ROP mechanics. |
| 3 | Register/segment branches | `B ERn` (0xF002, found at ROM 0x5690, bytes `02 F0`: `rom.bin:0x5690`) sets **PC ← ERn** (16-bit register value = RAM data, `CPUControl.cpp:201-204`); far `B e`/`BL e` (H_TI, e.g. `BL 01h:00FB4h`) sets CSR ← 4-bit imm nibble and PC ← imm word from the code stream | Selects fetch target from a register; far form selects segment | ⚠ PC and CSR can both be sourced from register/RAM data (`B ER0`, `POP LR`+`RT`); but PC offset via far B always comes from ROM, and every value is clamped at `Fetch` (row 4) and `ReadCode` (row 5). |
| 4 | ALL opcode fetches | — (no writer) | `CPU::Fetch` masks `CSR &= csr_mask(0x0001)`, `PC &= ~1`, then `MMU::ReadCode((CSR<<16)|PC)` (`CPU.cpp:370-380`) | ✅ Fetch confined to banks 0/1 by construction. |
| 5 | Fetch target memory | — | HW_ES_PLUS `ReadCode` masks `offset &= 0x1FFFE` and serves `chipset.rom_data` (else 0) (`MMU.cpp:179-186`) | ✅ **Fetch can never leave the 128 KB mask ROM image**, for any PC/CSR combination. |
| 6 | Reset vector | hardware | `CPU::Reset`: SP ← word@0 (0x8DF2), PC/CSR = 0; entry via `AcceptInterrupt` `cpu.Raise(0,1)` → PC ← ROM word @`index*2` = 0x0002 (0x4D7E in image) (`CPU.cpp:500,548`, `Chipset.cpp:456-560`) | ✅ In mask ROM; not RAM-writable. |
| 7 | IRQ/SWI vectors | SWI n → index 0x40+n → word @`index*2` = 0x0080+2n; IRQs index ≤ 5 → words 0x0008-0x000A (`Chipset.hpp:26-35`, `CPUControl.cpp:173-176`, DCL `WDTINT 0008H … SWI_VECTOR 00080H,000FFH`) | Vector table = fixed code words at ROM 0x0000-0x00FE | ✅ Table is in mask ROM; contents point to ROM handlers. No RAM vector table on ES PLUS. |
| 8 | DSR SFR (0xF000) | ROM writes it directly: `0075D6: ST R0,0F000h` (segment_0.txt:13645); wiki: 4 LSB writable | `DSR<<16` widens **data-space** segment only (data loads/stores, `CPUControl.cpp:56-60`); never used by fetch | ✅ Data-space addressing only; no fetch effect. |
| 9 | ROM window (data 0:0000-0:7FFF) + data-space code copies (segments 1, 8) | CPU stores | SFR/ROM-window regions are read-only: write lambda drops/logs (`ROMWindow.cpp:19-29`); wiki memory-map confirms write has no effect | ✅ No writable alias of code space. Segments ≥2 unmapped → `HandleMemoryError`/0 (`MMU.cpp:406-411`). |
| 10 | Flash write of `rom_data` (`Flash.cpp:131-132`) | Flash-erase/program ops | Rewrites the **image that ReadCode serves** → would be true code exec on emulator | ✅ Not reachable on CY-845: Flash peripheral is not constructed for HW_ES_PLUS (`Chipset.cpp:309-311`); FX-5800P/ClassWiz only. On silicon, mask ROM is not writable. |
| 11 | `CorruptByDSR` / `fetch_addition = 0x0FF0` (PC runaway) | DSR-prefixed access to unmapped segment 0x10/0x18 | Skews PC by +0xFF0 per fetch | ✅ Gated to `HW_CLASSWIZ_II && real_hardware` (`MMU.cpp:242-246`, `CPU.cpp:551-554`); unreachable on ES PLUS; even there fetch stays inside `ReadCode`'s 0x1FFFE mask. |
| 12 | Coprocessor CR0-CR9 | `SET CRn, ERm` etc. | Arithmetic operands/flags only (`Coprocessor.cpp:12-90`); no alias of PC/CSR/E level | ✅ |
| 13 | 1 KB TEST area (bank 1 top, ~0x1FC00-0x1FFFF) | — masked at fab ("includes 1 KByte test area", flash sibling ML610Q438/9 spec, `docs/jtag.md:48`) | Last 2 KB+ of the dump are all 0x00 (measured; waiting: 0x1F800-0x1FFFF = all 0x00) | ✅ Mask ROM, not writable; opcode 0x0000 = `MOV R0,#0` → a pivot there is a harmless in-ROM slide to the segment top. ML610901 review: OKI **deleted** the debug/tools-mode core circuits for calculator parts (`docs/jtag.md:33-36`); beyond an EASE/debug session, no instruction-level PC redirect exists in the core. |
| 14 | All SFRs 0xF000-0xFFFF (DCL + wiki `unknown-sfrs`) | CPU stores | DSR 0xF000, LTBADJ/ clocks (0xF006-0xF00A), SBYCON HLT/STP (power-down → halts execution, no redirect), WDT (reset only), IE0/IE1/IRQ0/IRQ1 (ack flags), timers, LCD 0xF030-0xF034, KI/KO 0xF040-0xF04C, ports, SIO/I2C | ✅ No SFR holds or latches a jump target; no SFR enables code fetch from data space. |

## Final verdict

- **PC from data: YES — already known.** `POP PC` (PC16+CSR16 from the RAM stack),
  `POP LR`+`RT`, the register-indirect branch `B ERn` (PC ← ERn; one instance at ROM
  0x5690), and control-reg loads from ER registers (`POP {LR,PC}` family,
  `nX-U8_is.txt:178-179` — the only ISA forms that load PC) let RAM data drive PC/CSR.
  **CSR from data: YES** (bounded): `POP PC` pops CSR (`CPUPushPop.cpp:126`), `POP LR`
  pops LCSR (`CPUPushPop.cpp:105-110`), and `ST ECSRn, ERm` loads ECSR from a register
  (`CPUControl.cpp:24-27`); values are then clamped to `csr_mask` (0x0001 → banks 0/1)
  at first use (`CPU.cpp:371-373`).
- **Fetch outside ROM: NO.** Every control path (fetch, RT/RTI, POP PC, vectors, reset)
  terminates in `MMU::ReadCode`, which on HW_ES_PLUS masks the address to 0x0-0x1FFFE and
  serves only the 128 KB mask-ROM image (`MMU.cpp:179-186`). There is no RAM vector table,
  no PC-controlling SFR, no writable code alias, no flash surface on this model, and the
  DSR/fetch-skew paths (`CorruptByDSR`) exist only on ClassWiz II. Code execution on CY-845
  is therefore chained **within** mask ROM (gadget ROP), never "new code from data".
- Emulator-only caveat: the Lua `cpu.pc=` / `cpu.csr=` proxies used by our harness k punches
  are a host-side debug surface, not a device path.
