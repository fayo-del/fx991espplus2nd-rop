# More-bytes-08 — SFR storage (0xF000-0xFFFF) and DSR data-space banking on CY-845

Agent: `MB08SFRStore`. Question: can attacker-controlled bytes live in SFRs pre/post
trigger and be read back by the chain as content? Does DSR give a second view of RAM?

**Verdict: NO extra attacker-controlled bytes from SFRs (count = 0 beyond the 100
payload bytes), and NO — DSR does not alias RAM.** The strcpy flood never touches SFR
space (measured); the only large attacker-shaped SFR region (LCD display RAM
0xF800-0xF9FB, 384 B of rendered glyphs) is re-rendered by the firmware before the
first chain hop, so its pre-trigger content does not survive to chain-read time
(measured). BCD param SFRs are zero after entering a number (measured). With DSR≠0,
data accesses leave segment 0 and hit ROM windows only — RAM 0x8000-0x8DFF is
reachable **only** at segment 0 (CPU-level proven). Post-trigger the chain can
read **and** write all of 0xF000-0xFFFF (proven), which gives the chain 384 B of
scratch in DSPR plus config SFRs, but those values are chain-computed from the 100
payload bytes — not new attacker input (that is MB05ChainWrite's chain-store axis).

Scripts: `research/CasioEmuX/more08_sfr.lua` (run 1, typed trigger + SFR dumps +
chain read-back + MMU alias probes), `more08_dsr4.lua` (run 4, CPU-level DSR
read probes; runs 2-3 `more08_dsr*.lua` were address-debug iterations — the
`research/fxesplus/disasm/segment_*.txt` labels are NOT rom.bin file addrs; use
`/tmp/oki_b0.txt` / `/tmp/oki_b1.txt` where bank1 label L = file addr L+0x10000).
Dumps: `more08_sfr_pre.bin`, `more08_sfr_post.bin` (0xF000-0xFFFF), `more08_dspr_pre.bin`,
`more08_dspr_post.bin` (0xF800-0xF9FF) in `research/CasioEmuX/`. 4 emulator runs used.
ROM untouched; no emulator source changes.

## 1. SFR table (DCL `ML610904.DCL` #ACCESS + run-1 measurement + disasm)

Writable per DCL write-mask; "attacker value?" = does any reachable pre-trigger path
store attacker-chosen bytes there.

| Addr | Name | Writable | Attacker value? | Survives flood? (run 1) | Chain-readable? (run 1) |
|---|---|---|---|---|---|
| 0xF000 | DSR | bit0 only (silicon); emu masks 0xFF | no — ROM writes 0/1 (`ST R0,0F000h` @ bank0 0x4DDA); reads **01** pre-trigger (impl_last_dsr) | yes (unchanged by flood; F000=01 pre and post) | YES (`SRC12 base=F000 ... match=true`) |
| 0xF006-0xF00F | LTBADJ/STPACP/SBYCON/FCON/LTBR/HTBR/WDTCON | yes | no (clock/power config) | yes; LTBR 0xF00C/HTBR 0xF00D change = free-running counters, not flood | yes (part of dump; chain reads via [EA]) |
| 0xF010/0xF011/0xF014/0xF015/0xF018 | IE0/IE1/IRQ0/IRQ1/EXICON0 | yes (IE0 bit0 RO) | no (interrupt flags) | yes; IRQ0 0xF014 C0->E2 = IRQ activity, not flood | YES (`base=F000` row covers; flags) |
| 0xF020-0xF025 | TM0D/TM0C/TM0CON | yes | no (timers) | yes; TM0C 0xF022 changed = timer tick | yes |
| 0xF028 | BLKCON | yes | no | yes | yes |
| 0xF030-0xF034 | DSPMOD0/DSPCON0/DSPCNT/BIASCLK/DSPCLK | yes | only config bits (contrast 0xF032=0x11 via SETUP — a few bits, not bytes) | yes (F031=05, F032=11 unchanged) | YES (`base=F030`, `base=F032` match=true) |
| 0xF037 | screen select | yes (bit2) | no | — | yes |
| 0xF040 | KID (key input) | **read-only** (IgnoreWrite) | **YES — live key-matrix bits** (idle=0xFF; presence consumed by KEYSCAN r0, existing hard fact) | n/a (HW) | YES (`base=F040` readback `FF...` match=true) |
| 0xF041/0xF042/0xF044-0xF047 | KICON/KIMASK/KOMASK/KOD | yes | no — KOD 0xF046 written by scan with firmware constants (0x391A, 0x4D00-0x4D10, 0x6C06); post-trigger 00->7F = scan activity | yes (not flooded) | yes |
| 0xF048-0xF04C | P0D/P0MOD/P0CON/P0DIR | yes (masked 0x07) | no | yes (F04A=07, F04C=07 unchanged) | yes |
| 0xF050 | P2D | RO | no | — | yes |
| 0xF0C0-0xF0EF | RTC/BLD/Flash SFRs | yes | no (RTC counts) | yes | yes |
| 0xF220-0xF225 | P1D/P1DIR/P1CON/P1MOD | yes | no | yes (F220=01 F221=05 F222=06 F223=03 unchanged) | YES (`base=F220` match=true) |
| 0xF280-0xF2AD | SIO/I2C | yes (buf RO) | no | yes | yes |
| 0xF400-0xF4FF | BCDCalc ctrl + param1/2 + temp1/2 (12 B each) | yes (plain storage) | **measured NO**: after typing `129129129`+EXE, 0xF480-0xF4FF all `00` | yes (zeros) | YES (`base=F480`, `base=F4A0` match=true, all zero) |
| **0xF800-0xF9FB** | **DSPR000-383 LCD display RAM (384 B)** | **yes (RWRW)** | **YES pre-trigger** — rendered glyphs of the typed line: 153 nonzero bytes, **55 distinct values** (formula `X=Σ(X,1,1×10^9`) | **NO** — at first chain hop 249/384 bytes already changed (display refresh re-renders from flooded draw buffer 0x87D0) | **YES** (`base=F800`, `base=F8C0` match=true) and chain-**writable** (memcpy12 dst=ER2=0xF8xx; rop_e2e 0x35CC watch captured stores with ER2 in 0xF800-0xF8FF; run-1 diff shows chain/refresh writes at 0xF890 etc.) |

Run-1 SFR-DIFF post-vs-pre over all 0xF000-0xFFFF: only LTBR/HTBR (counters), IRQ0/1
(flags), TM0C (timer), KOD 0xF046 (scan), F80B (indicator bit) and the DSPR display
bytes changed — **the strcpy flood wrote zero SFR cells** (it stops at the RAM region
end 0x8DFF; 0x8E00+ unmapped → dropped).

## 2. Emulator evidence (verbatim key lines)

Run 1 (`more08_sfr.lua`, real typed trigger, first KEYSCAN hop):
```
SFR-PRE nonzero 0xF000-0xF2FF: F000=01 F00A=01 F00C=90 F00D=D1 F010=22 F014=C0 F018=03
  F020=9A F021=12 F022=6C F023=03 F024=01 F025=01 F031=05 F032=11 F040=FF F044=80 F045=03
  F04A=07 F04C=07 F0C3=01 F0D1=02 F220=01 F221=05 F222=06 F223=03
DSPR-pre: nonzero=153 distinct=55
BCD-SFR after typing 129129129 + EXE: F480..F4E0 all 00
SFR-DIFF post-vs-pre: [F00C F00D F014 F015 F022 F023 F046 F80B + DSPR bytes only]  (no flood damage)
DSPR-DIFF post-vs-pre: 249 of 384 bytes changed            (pre-trigger glyphs wiped before hop 1)
SRC12 base=F800 memread=000000000000002000004080 memcpy12=000000000000002000004080 match=true
SRC12 base=F040 ... match=true   base=F000 ... match=true   base=F030/F032/F220/F480/F4A0 ... match=true
SRC12 base=8154 memread=0E4D0E4D... memcpy12=0E4D0E4D... match=true   (control: RAM flood readable)
ALIAS: data[8154]=0E4D0E4D data[18154]=0A001190 (rom file 18154=0A001190)
       data[88154]=011481E8 (rom file 8154=011481E8) data[9800]=30303331 data[8D00]=0E4D0E4D
DSRWRITE: data[18154]=0xAA -> data[8154] unchanged=true, data[18154] readback=0A001190 (ROM, write dropped)
```
Run 4 (`more08_dsr4.lua`, CPU-level, bank1 real 0x12F8 copy loop `DSR<-001h; L R0,[ER2];
NOP; ST R0,[EA+]; ...; RT`, ER2=0x8154, EA=0x9800, R1=1):
```
PROBE-A (DSR<-1 prefix): data[9800]=0A | rom file 18154=0A | RAM data[8154]=5A => CPU read SEGMENT-1 (ROM bank1), NOT RAM
PROBE-B (no prefix control): data[9800]=5A | RAM data[8154]=5A => CPU read SEGMENT-0 RAM (as expected)
```

## 3. DSR aliasing verdict — NEGATIVE (no second RAM view)

- Emulator data-space map (HW_ES_PLUS, `Chipset.cpp:49-53` registers segments **0, 1, 8 only**;
  `ROMWindow.cpp` HW_ES_PLUS: seg0 0x00000-0x07FFF ROM0 window, seg1 0x10000-0x1FFFF ROM
  bank-1 window, seg8 0x80000-0x8FFFF ROM bank-0 window; `BatteryBackedRAM.cpp:48` RAM
  **only in seg0 at 0x8000-0x8DFF**; SFRs only in seg0 at 0xF000-0xFFFF).
- Every data load/store computes `(reg_dsr<<16)|EA16` (`CPULoadStore.cpp:61,82`,
  `CPUControl.cpp:98,106,112`); `reg_dsr` is 0 for each instruction unless a DSR prefix
  (`E3 xx` imm / `90 AF`-style reg; **zero `FE 9F` sites in either bank** — grepped
  `/tmp/oki_b0.txt`/`oki_b1.txt`) sets it for that one instruction (`CPU.cpp:391-396`,
  OP_DSR). Writing SFR 0xF000 only sets `impl_last_dsr` (used solely by the unused `FE 9F`
  form); it does not change addressing of normal instructions.
- Measured: DSR=1, EA=0x8154 → ROM file 0x18154 (bank 1); DSR=8, EA=0x8154 → ROM file
  0x8154 (bank 0); DSR=0 → RAM. A DSR=1 write to EA=0x8154 is dropped (ROM window RO)
  and leaves RAM untouched. Segments 2-7, 9+ unregistered → `HandleMemoryError`, return 0.
- ⇒ **With DSR≠0 the flooded RAM 0x8154-0x8DFF is unreachable; there is no alias with a
  different flood phase.** `CorruptByDSR`/fetch-skew remains ClassWiz-II-only
  (`MMU.cpp:242-246`, see sec-sfr-pc.md row 11). DSR SFR reads 01 pre-trigger but that
  only matters for `FE 9F`-prefixed code, which does not exist in this ROM.
- Side note: 0x9800-0x98FF reads a 256-byte page (content `30303331...`) that is **not**
  an alias of 0x8D00 on this model config — it is the emulator-only `!real_hardware`
  extra RAM page (`BatteryBackedRAM.cpp:33,57`, ram_size 0xF00); on silicon RAM ends at
  0x8DFF. Chain-readable (`SRC12 base=9800 match=true`) but emulator artifact, not a
  device surface.

## 4. Extra controlled bytes — count

- Pre-trigger attacker-shaped SFR content that the chain can still read post-trigger:
  **0 bytes** (DSPR glyph page wiped by display refresh before first hop — measured;
  BCD params zero — measured; KID = 8 live key bits, already the KEYSCAN input channel).
- Post-trigger, the chain can read/write all SFRs (proven for F000/F030/F032/F040/
  F220/F480/F4A0/F800/F8C0): this adds **384 B (DSPR 0xF800-0xF9FB) + ~50 config bytes**
  of chain-writable storage outside the flooded RAM, usable as extra content/scratch —
  but every byte there is chain-computed from the 100 payload bytes or keys, so it does
  **not** raise the >100 distinct *attacker-typed* ceiling by itself.
