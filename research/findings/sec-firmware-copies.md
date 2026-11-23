# CY-845 firmware copy/write census — stack-reaching copies with input/state-controlled dst or len (2026-11-22)

ROM: `research/CasioEmuX/models/fx991esplus2/rom.bin` (md5 c4c7d7fb89d0fd07cc0196d642682d83).
Disassembly: oki-u8-disas bank dumps `/tmp/oki_b0.txt` (bank0 0x00000-0x0FFFF) / `/tmp/oki_b1.txt`
(bank1 0x10000-0x1FFFF; printed 5-digit addrs below are prefixed bank0=/plain, bank1=0x1xxxx).
RAM 0x8000-0x8DFF (emulator `BatteryBackedRAM`, ram_size 0xE00); SFRs 0xF000+ (DSR=0xF000,
BLKCON=0xF028, KI/KO=0xF040/0xF046) — see `research/gyx-decomp/assets/ML610904.H/.DCL` and
`emulator/src/Chipset/MMU.cpp` (WriteData: unmapped/segment writes are dropped + HandleMemoryError;
peripheral regions intercept). Draw buffer 0x87D0 (384 B), input 0x8154 (100 B), cache 0x81B8,
journal/replay 0x8230+, firmware stack ~0x8C00-0x8D74 (idle wait-key sp=0x8D74, observed to 0x8C60).

## 1. The copy primitives in ROM (all of them)

| # | Primitive | Loop | dst | len | Bounds check | Notes |
|---|---|---|---|---|---|---|
| P1 | **strcpy** | 0x6B58 (`6B62: L R0,[ER10] / 6B64: ST R0,[ER12]`, NUL-terminated) | ER0 | `strlen(ER2)` — **unbounded** | none | `0x2B10` wrapper NUL-checks dst/src (empty src → `ST R2,[ER0]` single 0). 33 call sites. |
| P2 | **strcat** | 0xCB5E (`C968/CA3x class`: walks dst to NUL at 0xCB6A-0xCB6E, then appends from 0xCB72) | ER0 | `strlen(dst)+strlen(src)` — **unbounded, and grows with existing content** | none | `0x2B24` wrapper; 37 call sites (+direct `0x8BF6`). Never audited before this census. |
| P3 | **memmove** | 0x5108 (overlap-aware, fwd 0x5150 / bwd 0x5136) | ER0 | 3rd arg (stack word) | varies per caller | 6 call sites: 0x3178, 0x69EE, 0x7448, 0x7474, 0x7492, 0x74B0. |
| P4 | **memcpy12** | 0x35BE (`POP EA` src from stack, dst=ER2, r0 iterations × 16 B) | ER2 | r0 at entry | none (r0 unbounded) | Used by app screen refresh (r0=0x1F/0x20, dst=0xF800/0xF810) **and** it is the proven ROP gadget. |
| P5 | draw clear | 0x313C | ER0 (=0x87D0) | fixed 48×QR8=384 B | fixed | safe. |
| P6 | token→text insert | 0x7380/0x7402 family + memmove 0x7448s | input area (0x8154-origin) | token expansion; hard cap `CMP R0,#250` at 0x7402-0x7406 (else bail 0x74FA) | 250 B secondary cap | The editor's own len var 0x8114 (measured cap 99, vuln-search §0/§1) is the primary bound; 250 is a backstop that still allows 0x8154+250=0x824E to be touched if any state exceeds len≥100 (none found typing). |
| P7 | LCD row ops | 0x356A line set/CLR/XOR loops | ER12-based [EA] window | fixed row-walk | fixed | display-only (LCD status region). |
| P8 | BCD eval moves | bank1 0x5630, 0x89DC+, fixed `LEA 0x800x/0x802x` stores | fixed eval regs 0x8000-0x8060 | fixed | fixed | safe. |

## 2. strcpy (P1) caller classification — (dst src, len src)

All 33 `BL 00h:02B10h` sites (bank0 unless noted). ER0=dst, ER2=src at the `BL`.

| Site | Caller class | dst source | len source | Overflow target | Keyboard reach | Verdict |
|---|---|---|---|---|---|---|
| 0x507E | input restore #1 | ER4 (caller var) | strlen(0x8184 content) | input area | mode/history restore | display-only/safe [INFERENCE: src ROM-adjacent state] |
| 0x509C | input restore #2 | 0x8184 | strlen(ER4) | 0x8184+ region | same | same |
| 0x50AC | save into ptr | [ER8] (RAM pointer from caller) | strlen(ER4) | wherever [ER8] points | same | pointer is firmware-set |
| 0x5C9E | input ⊢ 0x8154 | **0x8154** | strlen(ER4) | cache 0x81B8 | history/RCL path | bounded by src (<100 typed) |
| 0x6304 | message render | ER4 | strlen(ret of BL 0x10044) | caller buffer (stack) | calculator UI | ROM-string bounded |
| 0x6E26 | journal restore | **[ER8]** (RAM ptr) | strlen(unknown) | wherever the journal entry points | journal/replay | **stack-reaching class** (see §4) |
| 0x755A | RCL/history | ER4(→0x8154 set at 0x7544) | strlen(0x85AA) | input→cache | **RCL key** | bounded by cached (≤ typed) |
| 0x756A | RCL/history #2 | [ER8] | strlen(ER4) | ptr target | RCL | as 0x50AC |
| 0x7CFA | journal restore | [ER8] | strlen(src of caller) | ptr target | journal | as 0x6E26 |
| 0x8A04 | restore | [ER8] | strlen(0x8184) | ptr target | menu/mode | as 0x6E26 |
| 0x8C06 | **template insert** | **0x8154** | strlen([ER14-18]) — stack buffer pre-filled 0x8BBE (strcpy 0x1782) / 0x8BB6 (strcpy [strcat 0x8BF6]) | input area | Σ(/template keys | stack-buffer src bounded by the earlier strcpy of a ROM string → bounded; **but src itself starts as strcat output** (see §3 site S-BF6) |
| 0x984C | input write | **0x8154** | strlen(?) | cache | mode-state machine | bounded by src |
| 0x99A8/0x99B8 | history stash | **0x8184** | strlen([ER8]) | 0x8184+ | history | bounded |
| 0x99E0 | history echo | **0x85AA** | strlen(ER12) | 0x85AA..0x86xx | history | bounded; 0x85AA+len overrun hits 0x87D0 draw buffer only (display) |
| 0x99EC | stash #4 | **0x8184** | strlen([ER8]) | 0x8184+ | history | bounded |
| 0xA33A | render echo | **ER14-112** (`ADD R0,#144; ADDC R1,#255` ⇒ ER14-112) then used downstream | strlen(ER4) | stack scratch | line render | stack-local, src bounded |
| 0xBA2A/0xBA52/0xBA86 | msg compose | ER4 / ER4 / ER4 | strlen(0x1E48) / strlen(-0x11C[ER12]) / strlen(0x0874) | caller stack buf | calc UI | ROM/bounded |
| 0xBB42 | input stash | **0x8184** | strlen(**0x8154**) | 0x8184+ | AC/history | bounded by typed len (≤99; the ≥100 gate lives in the AC handler, not here) |
| 0xBB8E/0xBBA8/0xBBC2 | multi-line render | **ER14-46** | strlen(ER14-10/-20/-30) | 46-byte stack buffer | long-line render | [INFERENCE] bounded by the template inserts preceding (fixed template sizes 25/17) |
| 0xC36C/0xC6B4 | misc state | caller var | strlen(ER6) | caller buffer | — | bounded |
| 0xC778 | msg | ER10 | strlen(0x25A8) | caller buf | tables | ROM-fixed |
| 0xCEEC | input restore | **0x8154** | strlen(0x8184) | cache | mode restore | bounded |
| 0x10E2C (bk1) | msg | ER8 | strlen(0x09E2 ROM) | caller buf | solver | fixed |
| 0x10F3A (bk1) | msg render | **ER14-6** (stack) | strlen(0x09F1+4·idx ROM table) | 6-byte stack slot → saved regs | solver errors | ROM strings are short (fixed table) → safe [INFERENCE] |
| 0x13292/0x14406 (bk1) | clear input | 0x8154 | src=0 → ST R2,[ER0] | 1 byte | menu ops | safe |

## 3. strcat (P2) caller classification — the un-audited family

`BL 00h:02B24h` → 0xCB5E. dst=ER0, src=ER2. Append semantics ⇒ effective length =
existing dst content + src; **no bound check anywhere in 0xCB5E**.

| Site | dst source | src source | Bounds | Verdict |
|---|---|---|---|---|
| 0x2E22 | ER10 (caller var) | ER14-42 (stack temp, filled by bounded token-render 0x2C12) | temp bounded by render | display-only [measured §5] |
| 0x5292 | ER8 (=0x8154-family) | ER14-20 stack temp | temp bounded | same |
| 0x5AE4 | ER8 | **0x2208 (ROM)** | fixed | safe |
| 0x5B00 | ER8 | ER10 (bounded by preceding zero-terminator fill `SUB R0,R2; ST R2,[ER0]` 16-slot) | 16-slot | safe |
| 0x671C/0x72B4/0x72BE/0x7304/0x730E/0x7368/0x7372 | ER10/ER10/ER10/ER10/ER10/ER10/ER10 | ROM strings (0x7F.. 0x98xx tables) | fixed | safe |
| 0x8BF6 (direct BL 0xCB5E) | **ER14-18 stack buffer** | **ER14-22 stack buffer** | **none — pure stack append** | see census §5 |
| 0x9066/0x909A | ER14-52 stack buf | ER14-46 / ER14-2 stack temps | render loop counters (6-byte MUL stride) | safe [INFERENCE] |
| 0x92E6 | ER10 | ER14-42 temp | bounded temp | safe |
| 0xA490/0xA49A/0xA4A6/0xA4C6/0xA514 | **[ER12] pointer** (caller-provided RAM ptr) / [ER12] / **ER14+144-boundary class (ER14-112)** / ER4 / [ER12] | ER4 / 0x17E2 ROM / ER14-112 / ER14-112 / ER4 | unbounded append into a caller pointer target | **this is the only strcat class whose dst is an unchecked RAM pointer** |
| 0xBA66 | ER4 | 0x28F4 ROM | fixed | safe |
| 0xC700/0xC7B4/0xC7C4/0xC7D4/0xC802+/0xC814/0xC84A/0xC858/0xC8A2/0xC916 | ER10 | ROM tables (0x188A/0x262A/0x26B4/0x2552/…) | fixed | safe |
| 0xD872/0xD9E0/0xDA36/0xDA94 | ER10-family | ROM/temp | bounded | safe |

The `0xA4xx` group: dst = `[ER12]` where ER12 = L [ER14-2]` (a pointer variable), first
`ST R0,[ER12]` initializes it to empty string; then append ROM strings (0x17E2) and
frame temps. The pointer itself is firmware data; the only input influence is via the
ER14-112 stack temps (bounded by preceding bounded copies). Class verdict: display-only.

## 4. Copies that reach CONTROL data

The only control data in RAM = firmware stack (0x8C00-0x8D74: saved LR/PC/ER14 frames —
`RT` uses LR, `POP PC` pops 4 bytes; combined with the wait-key PC) **plus** the DSR/SFR
window (0xF000, incl. DSR=0xF000 that banks address space) and the LCD window 0xF800.

- **No named copy site computes dst in 0xF000+ from input** (all replicas of the echo
  family use RAM immediates: 0x81x/0x83x/0x85AA/0x87D0). SFR writes from copies are not
  observed; screen-region writes (0xF800+) are display-only.
- **The stack is reached only through the journal/cache tiling engine**: the AC-stamp
  `strcpy(0x81B8←0x8154)` with `strlen ≥ 100` (gate proven differentially, vuln-search §3
  V1-vs-V5) plus the journal-replay stamps (`dst=0x830E/0x8311/0x834D/0x8398…, src=0x8154,
  len=101`) flood RAM with repeated payload tiles (measured: 1499 tiles, vuln-search runs
  e2e/S15-16) which land over frames at 0x8C60..0x8D74; return paths then `POP PC`/
  `POP LR; RT` from attacker bytes. That is the known `0x6B62` path — no *second*
  independent copy routine reaches the stack.

## 5. Census run — MEASURED (1 emulator run, `sec_strcat_census.lua`, headless, pristine emulator md5 4dcb0b1c6ce05aff52c2b1cb9de5631a)

Session: typing from T=1 (`SHIFT AC1 X=123 EXE1 AC2 ← EXE2 AC3 ← EXE3 Σ( X ×10 9 CALC EXE4 AC4 ← EXE5`), then 2M-tick watch. Log `/tmp/sec_census.log`.

- **strcat (0xCB5E) fired only via the 0x2B24 wrapper into a stack temp at `dst=0x8D62`**
  (2+2 hits), appends of ROM strings (`src=0x2738`, dlen 1→3). dst sits in the stack
  region near top (0x8D62; stack top 0x8D74) — **unbounded append into a stack buffer
  structurally exists**, but every observed src is ROM-fixed; no input-derived src seen.
- **memmove (0x5108) = the token-insert engine** (`lr=0x744C/0x7478/0x7496/0x74B4`,
  the 0x7402 `#250`-capped family): `dst=0x829E..0x82D0` (a second 48-byte editor
  buffer 0x829E-0x82CE, shift len 0/1/32/48), inserted byte `src=0x8D9F` (stack temp).
  With cap 250 the insert could reach 0x839C (journal, data-only region); the editor
  len var (measured cap 99) stays the primary bound. **No stack-control write.**
- No STRCAT/MEMMOVE site wrote ≥0x8900 with input-derived content; watch stayed
  `pc=0x4B96` (idle wait-key), `str8154=9`, no tiling (expected: no overflow state).

## 6. Final answer

**Does any copy give PC control?** Yes — the known input-area strcpy family
(0x2B10 → 0x6B58 loop at 0x6B62) gated by `strlen(0x8154) ≥ 100` on `AC←EXE`,
feeding the journal-stamp tiler that overwrites the firmware stack; repo
sessions 15/16/18-19 already executed ROM gadget chains from the tiled stack
(repro: `rop_e2e.lua`, 25 KEYSCAN hops from 0x8DA0→0x8E00, 1499 tiles).
**No NEW independent code-exec path found**: strcat (0xCB5E) has no bound check,
but all key-reachable sites copy ROM-fixed or render-bounded temporaries into
firmware-chosen targets; memmove (0x5108) callers carry bounds (250-cap insert
family, fixed draw-scroll); memcpy12 (0x35BE) reaches the LCD with r0
unbounded only via ROP (already part of the known chain).
