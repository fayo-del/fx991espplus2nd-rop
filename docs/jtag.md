# JTAG / ISP / reflash feasibility — Casio fx-991ES PLUS 2nd edition (CY-845)

**Status (2026-11-19):** desktop-research document. No step has been performed on a physical
CY-845; everything hardware-level below is either from public datasheets/manuals, from the
casiocalc forum thread, or marked `[INFERENCE]`. All local-ROM facts come from the
CY-845A dump already in this repo (`research/CasioEmuX/models/fx991esplus2/rom.bin`, 128 KB,
md5 `c4c7d7fb89d0fd07cc0196d642682d83`; see `research/findings/cy845-rop.md`).

## 0. Verdict up front

| Question | Answer |
|---|---|
| Standard JTAG on the MCU? | **No.** The nX-U8/100 family has no JTAG port; its on-chip debug is LAPIS' proprietary multi-wire serial "EASE" interface (VTref/Vpp/RST_OUT-SCK/SDATA/VDDL) — not Renesas E1/E8, not FlashPro. Worse: OKI **deleted the debug/test-mode circuits** from the equivalent production core (ML610901, see §1), so on the Casio part even the EASE interface may not exist in silicon. |
| ISP (field firmware update)? | **No.** There is no external storage to boot from and no bootloader; flash-family members are programmed *in production benches* over the same EASE pins (in-circuit, with Vpp). |
| Is the program store flash? | **No — mask ROM.** 64K × 16-bit words (128 KB byte image), factory-masked. **JTAG/debug can never rewrite firmware.** |
| Can the CPU execute code from RAM? | **No** — Harvard-style split spaces ([nX-U8/100 core manual](https://docs.alexrp.com/nx/nx_u8.pdf) §1.3). PC fetches only program space; data RAM is reached only through data-space instructions and the read-only ROM window. |
| What *can* on-chip debug do? | If such a session is possible at all (see previous row): halt/single-step, read/write RAM (0x8000–0x8DFF), SFRs and registers, set PC/SP/CSR — i.e. exactly what our Lua harness does. Planted ROP chains run ROM gadgets (emulator-proven: LCD writes to 0xF800, KEYSCAN at 0x4D0E). |
| Realistic path to Snake | **A replacement mainboard**: run the existing emulator core + CY-845A ROM on a modern MCU driving a suitable display. Snake already runs in `research/CasioEmuX/snake.lua`. In-firmware play (ROP with debug assists) = lab toy at ~fps rates. |

---

## 1. Which chip is actually inside

**Known with high confidence (family level), unverified at the marking level:**

* The fx-ES PLUS / GYX firmware generation runs on an **OKI/LAPIS nX-U8/100 8-bit RISC MCU**
  (gyx-decomp README: "All ES PLUS models use the nX-U8/100 architecture by ROHM Co., Ltd.").
* OKI Technical Review No. 203 (July 2005), *"Development of ultra-low power 8-bit
  microcomputer"* (Kazuhiro Tomita, OKI Micro Design) documents **ML610901** — an MCU
  developed for Casio, used in scientific calculators and the FC-200V, mass-produced June
  2004: nX-U8/100 core, integrated LCD driver, RAM 3.5 KB, internal logic supply VDDL
  reduced to **1.16 V**. Critically for this question, the review's power-reduction
  item ② states that in the conventional low-power core the **debug and tools-mode
  circuit blocks were mounted and drew excess current while the CPU ran**, and that
  **ML610901 deleted those circuit portions from the CPU core** to cut power
  ("deletion of unused circuit … debugging features, and tools mode function is mounted …
  Deletion of this circuit portion is effective as reducing power consumption").
  Sources: [translated copy](https://www.mikrocontroller.net/attachment/356611/203_R06.ja.en.pdf)
  (also [original JP](http://www.oki.com/jp/Home/JIS/Books/KENKAI/n203/pdf/203_R06.pdf)).
* For the 2nd edition (CY-845 board) the community working name **ML610904** appears in this
  repo's decomp infrastructure: `research/gyx-decomp/assets/ML610904.DCL` (#TARGET
  "ML610904", #REVISION "A3"), `assets/ML610904.H` (SFR header, authored by GamingWithEvets
  2026), and the linker project file `rom.pid` contains the literal string `ML610904`.
  **There is no public LAPIS/ROHM catalog page for ML610904** — like ML610901 it is a
  Casio custom part. Web-wide searches for `ML610904` return nothing beyond this project.
* The pin/function-compatible **flash sibling family** is
  **ML610Q438/ML610Q439** (LAPIS, FEDL610Q438/439): nX-U8/100, "Internal 128 KByte Flash
  ROM (64K×16 bits) (including unusable 1 KByte **TEST area**)", on-chip debug function,
  VPP pin, RESET_N, block-diagram "On-Chip ICE" module wired to a "RESET & TEST" block.
  This is exactly the spec text LTVA quoted into the hacking thread believing it described
  the calculator's part ([forum p.12 #450](https://community.casiocalc.org/topic/7583-fx-82-83gt-115-991es-plus-hacking/page-12)).
  [Datasheet (PDF)](https://mm.digikey.com/Volume0/opasdata/d220001/medias/docus/407/ML610Q438%2CQ439__DS.pdf)
* LAPIS ships **pin-compatible mask-ROM variants of Q-parts without the "Q"**
  (e.g. mask ML610482 ↔ flash ML610Q482; the mask models' program memory is labelled
  "(includes 1 KByte test area)" too, and LAPIS delivers "packaged or die format").
  [ML610400-series selection guide](https://www.jotrin.ru/userfiles/downloadfile/202002261240041518.pdf) (PDF).
  By this convention **ML610904 (no "Q") is a mask-ROM part**, made to Casio's ROM image —
  matching the community conclusion and the repo's emulator model ("Chain = data consumed
  by ROM gadget (never executed from RAM; mask ROM)", `research/CasioEmuX/rop_demo.lua`).
* The CY-845 memory map is confirmed from the dump: program = two 64K-word banks
  (emulator flat 0x0000–0x1FFFF, `csr_mask = 0x0001` in `model.lua`), data RAM =
  **0x8000–0x8DFF (3.5 KB)** (`ML610904.DCL`: `#RAM 0H, 0FFFFH / DATA 08000H, 08DFFH`),
  LCD/screen region 0xF800 (emulated; firmware draw buffer 0x87D0) — `cy845-rop.md`.
* 2nd edition background: the "2nd edition" line is Casio's **anti-counterfeit refresh**
  (production moved China → Thailand, QR-code + hologram genuine-product verification on
  packaging, functionality otherwise unchanged) — e-Gadget, *fx-991ES PLUS 2nd edition の概要*,
  2021-09-05: [egadget.blog.fc2.com/blog-entry-775.html](http://egadget.blog.fc2.com/blog-entry-775.html).

**Physical packaging on the calculator:** unknown from public sources. No photo of a CY-845
board showing a marked package has been found; the only first-hand description is LTVA's
*"Its PCB is a bit different from 991es's: (see groups of 3 small and 4 usual size contact
plates)"* [forum p.12 #442] — the follow-up images were moved to Discord and are gone.
[INFERENCE] Casio uses die/COB assembly on this product class, so "pads", not exposed IC
legs, is the realistic connection surface, consistent with LTVA's pad groups.

## 2. Interface: what debug technology exists, what it needs

### 2.1 No JTAG — LAPIS "EASE" on-chip debug

* The nX-U8/100 core provides **emulator/debug support** (dedicated emulator interrupts,
  in-circuit-emulator break structure) but **no JTAG TAP**. Family documentation never
  mentions JTAG; the vendor tool chain is LAPIS' proprietary **EASE1000 / EASE1000 V2**
  on-chip emulator over a multi-wire synchronous serial interface.
  [EASE1000 V2 User's Manual](https://fscdn.rohm.com/lapis/en/products/databook/applinote/ic/micon/FEXTEASE1000V2.pdf) (PDF),
  [EASE1000 User's Manual](https://fscdn.rohm.com/lapis/en/products/databook/applinote/ic/micon/FEXTEASE1000.pdf) (PDF).
* **EASE1000 V2 supported targets:** "ML62Q1000/Q2000 series, **ML610QXXX**, and ML620QXXX"
  — i.e. the whole U8 flash family that mirrors the calculator MCU. Used with a
  **LEXIDE-U16 or DTU8 debugger** plus the **EASE1000 V2 interface cable**;
  flash writing via the *MWU16 Flash Multi Writer* host program. (ROHM product page
  for family member ML610408 lists the same kit: "U8/U16 microcontroller with on-chip debug
  function — EASE1000 V2 — EASE1000 V2 interface cable — USB cable":
  [rohm.com](https://www.rohm.com/products/micon/low-voltage/ml610400-ml610q400/built-in-lcd-driver-segments-type-8bit/ml610408-product).)
  Note the plain-family member **ML610Q438/Q439** numbers match the calculator part's specs
  (128 KB code, on-chip debug) — this is the closest public stand-in for tooling.
* **Generation-1 EASE1000** wired to U8 parts through the dedicated test pins: on
  ML610Q100 the debug uses **TEST0** (data) and **TEST1_N** (clock) or a single **TEST**
  pin plus **RESET_N** (EASE1000 manual §2.5.1.2, Figs 2-5/2-6: RST_OUT/SCK → TEST/TEST1_N,
  SDATA → TEST0, 3.3VOUT/VDDL → target supply).
* **Interface connector pinout (EASE1000 V2, 14-pin)** — from EASE1000 V2 manual Table 1:
  1 `VTref` (target VDD sense) · 2/4/6/8/10/12 `Vss` · 3 `Vpp` (flash program voltage) ·
  5 `RST_OUT/SCK` (reset / comm clock) · 7 `SDATA` (comm data) · 9 `VDDL` — the debugger
  drives the internal logic rail, **outputs 1.45 V in debug mode** · 13 `3.3VOUT`
  (3.3 V/100 mA target supply) · 11/14 N.C.
* **Availability:** EASE1000 V2 itself superseded and the EASE1000/uEASE put on
  last-buy in [LAPIS news release March 2019](https://www.lapis-semi.com/en/company/news/news/r201903_2/)
  — hardware is discontinued/surplus only; DTU8 debuggers exist through LAPIS/ROHM channels
  and Chinese clones of the cable ("nano-EASE", described in the forum as cheap and able to
  indicate a failed handshake by blinking, [forum p.12 #459, cetus9](https://community.casiocalc.org/topic/7583-fx-82-83gt-115-991es-plus-hacking/page-12)).
* **Family vs. the actual part, kept separate:** everything above describes the *flash
  products ML610Q* (ML610Q438/Q439 etc.), which ship the on-chip ICE. The Casio production
  parts (ML610901-level, presumably ML610904) are mask ROM variants whose standard core had
  the debug/tools-mode blocks **deleted for power** (§1). It corresponds to cetus9's forum
  hedge — *"It seems like the CPU gets programmed trough the 'test' pin … but it can be
  that programming is locked"* — taken a step further: the hardware may be gone, not locked.

### 2.2 Voltage and supply

* Battery terminals nominal 1.5 V + solar; members reported the calculators **run fine at
  3.3 V on the battery terminals without damage** and that MCU pins do not tri-state on
  reset ([forum p.12 #460, #461](https://community.casiocalc.org/topic/7583-fx-82-83gt-115-991es-plus-hacking/page-12)).
* Die internals: VDDL (logic) ≈ **1.16 V** on the equivalent OKI part (OKI Tech Review 203);
  family VDD range 1.1–3.6 V (mask/flash selection guide). EASE debug sessions run the
  target VDDL at 1.45 V (EASE1000 V2 manual) — `[INFERENCE]` the CY-845 die's exact rails
  are undocumented; treat all pad voltages as unknown until probed passively.
* LCD drive is internal (the OKI part integrates the LCD driver with level generation —
  a user saw only ~0–1 V on the LCD bus, forum #461).

### 2.3 Which pads?

On **1st-generation** GY boards, cetus9 (forum p.12 #460, fx-85GT PLUS / fx-93GT PLUS) mapped:

* a pad **P155**, cap-to-GND, voltage tracks cell/solar conditions — *"probably VDDL"*;
* **3 vertical pads** = **PORT4**-class GPIO (SFRs `0xF221–0xF223`, cf. ML610Q438 manuals),
  observable flipping between Hi-Z and internal pull-down during the diagnostic
  **"Pd-Read OK"** screen, with a **~500 kHz clock** appearing on the bottom pad — his
  candidates for the retained production test/probe port (or merely a serial interface
  starting up — his own hedge of source).

For **CY-845 (2nd ed.)**: LTVA's sighting of *"groups of 3 small and 4 usual size contact
plates"* (#442) matches the same class of factory pads, but **no public CY-845 pad map
exists** — nobody has published continuity-to-die tracing or scope captures for this board.

[INFERENCE] Because the CY-845 part is a Casio-ordered **mask** device, Casio has no
incentive to bond an EASE port; the surviving pads are most plausibly those handheld
production testers need (battery/solar sense `Pd`, test GPIOs). Weigh §1's deletion of the
debug/test circuits from the ML610901 production core: on those predecessors JTAG/EASE-type
debug was likely not merely *disabled* but **absent in silicon**. Whether ML610904 differs
is unknown; the open question is thus not "where are the pins" but first "is there a debug
engine on the die at all." The pads also still carry the test GPIO/clock behavior seen on
1st-gen boards, so a factory-test access port of *some* kind is expected to exist.

## 3. Memory: mask ROM — plain conclusions

* **The CY-845 program store is mask ROM.** 128 KB byte image = 64K × 16-bit words × 2
  banks (`rom.bin`, emulator: `rom_path="rom.bin"`, bank1 = CSR=1). The part name without
  the LAPIS "Q" flash marker, the 2004 OKI article describing the same Casio part with
  multi-Vt-tuned ROM, and the wholly in-ROM design (vector table at 0x0000, the factory
  **TEST area at bank0 0xF800–0xFFFF** with its own SP/entry vector table —
  decomp `src/a03_testarea.asm`, matching the ML610Q438 "1 KByte TEST area" description)
  all agree. The 2 KB of *data flash* found on flash-family parts is **not** the program
  store and doesn't exist on the mask version.
* **Therefore: no JTAG/ISP/reflash can change the firmware. Not even partly.** The firmware
  executes from factory-deposited ROM; the checksum displayed by the diagnostic mode is
  computed on boot from that ROM (decomp `n34_diagnostic.asm` — display-only, no
  signature check, but also nothing to update). Any "reflash" claim is the wrong toolchain;
  the only legitimate external rewrite target would be RAM + SFR state.
* What an on-chip debug session **can** do (if the ICE survives on this part):
  * **Halt / step / run-halt** the core — DTU8/LEXIDE debug features: *"CPU status
    (register, Flash memory/Data memory, SFR) display/change; various Break"*
    (EASE1000 manual, feature list).
  * **Read everything**: program space via the debug read path and via the data-side ROM
    window; RAM 0x8000–0x8DFF; SFR register file 0xF000+ (KI/KO, LCD, FCON, timer/RTC, … —
    `ML610904.H`).
  * **Write RAM/SFR/registers** at an arbitrary moment: exactly the powers our Lua harness
    uses (`cpu.pc/sp/csr/lr/r0..`, `data[]`), so a session reproduces `rop_e2e.lua`
    end-to-end without any exploit: plant the chain at 0x8C80, kick with PC/SP, observe
    LCD and KEYSCAN results.
  * **Substitute for the missing payload loader**: CY-845 has **no typed-only hackstring**
    (the `0E 4D`/`10 F8`/`01` byte words are unreachable from the keypad with today's
    token maps — measured in `research/findings/cy845-rop.md` §2/§7) — a debug link is the
    natural loader, planting the 100-byte stack payload that the keypad cannot.
  * What it **cannot** do: write program memory; anything that persists across battery pull.

## 4. Execution model: no RAM code, ROP ceiling

Harvard, from the [nX-U8/100 core instruction manual](https://docs.alexrp.com/nx/nx_u8.pdf)
(§1.2–1.3, "Memory Spaces"):

* One-byte-wide **data space** (256 segments; CY-845 uses 0x8000–0x8DFF) and a separate
  **program space** of 32K-word segments, fetched only through `CSR:PC`. *"Physical
  segment #0 provides two sets of addresses … a 32-kiloword program/code memory segment
  accessed with the program counter (PC) and a 64-kilobyte data memory segment accessed
  with the address register (AR). If the address in AR is within the ROM window, however,
  the register accesses program/code memory, not the data memory."*
* Program space is reachable from data instructions **read-only** (that ROM window is the
  mechanism the ROM-dump hackstrings used on 1st-gen machines), and data space is never
  fetched by the decoder. **Self-modifying code / RAM-executing monitors are impossible on
  this architecture.** Code in RAM cannot even be expressed.
* Consequently the *only* program-control escape is what the decomp already builds:
  **stack-based ROP over factory ROM gadgets** (vectors/registers freely controllable by
  either an exploit or by a debug halt-and-kick). Gadget reality for CY-845 — measured and
  verified in the emulator (`research/findings/cy845-rop.md`, sessions 3–6):
  * `0x2B1E POP PC` chain-coupler (pops 4 bytes per entry), `RT` continues via planted `LR`;
  * `0x35BE` — RAM memcpy with counter (`EA` source, `ER2` destination, `R0` blocks) —
    **verified writing arbitrary payloads into the LCD region 0xF800**, pattern shows on
    the display (`rop_diag`, session 5: 12×0xFF lands instantly, visible pre-redraw);
  * `0x4D0E` — in-chain **key scan** (writes KOD 0xF046, reads KID 0xF040);
    returned `ER0=1` with a key held, 0 otherwise — key input to a ROP process works;
  * `0x4EF2` — park/wait loop as the terminal gadget.
* **Realistic ceiling with debug hardware + ROP** (honest ordering):
  1. **LCD pattern / free frame** — proven in emulator, trivial with debug kick. ✅
  2. **Reactive demos reading the keypad** (scrolling text, cursor, response to keys) — the
     1st-gen community's "demo chain" class; on CY-845 the gadget set exists (KEYSCAN + line
     printers at 0x327E/0x32BE in the ROM), and key input through a ROP chain is already
     green. Only needs the chain loop to survive the system refresh path (park problem
     solved by parking in ROM, as snake.lua does). ✅ [reasonable]
  3. **Snake** — needs a self-re-entering loop (the stack must be periodically rebuilt by a
     ROM `memcpy` gadget drawing the next state; the loop has to either re-arm itself with
     gadget-computed addresses or be re-armed externally **per frame** by the debugger).
     Self-re-entering ROP on this 4-byte-pop-PC terminal-park framework is convoluted;
     the expected product is a **1–2 fps toy with the calculator unusable as a calculator**,
     and every probe session so far has been emulator-only. `[INFERENCE]` Possible as an
     engineering stunt, never a shipping game.
  4. **Anything persistent** — impossible: mask ROM + RAM-only executability. Boot always
     returns Casio firmware.

## 5. Procedure — the realistic on-hardware path

This is original research (nobody has published a CY-845 debug port map). Sequence
de-risked from the 1st-gen findings:

### Step 0 — Skills/tools baseline
Read the nX-U8/100 core manual (this repo:
`research/fxesplus/docs/nX-U8100 Core Instruction Manual.pdf`) and the ML610Q438/Q439
datasheet + user's manual (closest public sibling) before touching anything.
Tooling that already exists here: `pyu8disasx` + `ML610904.DCL`, emulator + Lua.

### Step 1 — Bench recon (no risk)
1. Power the calculator normally: battery terminals **1.5 V**; document all board pads
   under a microscope (LTVA's **3 small + 4 normal pads** groups on CY-845) and photograph
   both sides.
2. Cold board, **no battery**, diode-mode / resistance measurement only from each pad to
   battery +, GND, and to neighbouring pads — build the net graph. Never inject current
   here.
3. With the board idling (battery only) and while booting, and inside diagnostics, capture
   each pad on a scope/scope-MCU (1st-gen tell: pads toggling on "Pd-Read OK", ~500 kHz
   clock — forum #460).
4. Candidate set is then a handful of pads. Everything so far is read-only/safe.

### Step 2 — Supply experiment (small risk, 1st-gen-verified)
Run the board at **3.3 V on the battery terminals** to simplify signaling (verified
harmless on 1st-gen calcs, forum #460/#461). Expect the die to regulate its own VDDL;
do **not** feed a pin guessing it's VDDL. `[INFERENCE]` The CY-845 die tolerances are
unpublished.

### Step 3 — Locate the debug/ISP pins
1. Refer to the EASE targets' pin discipline: on family parts the debug/program interface
   is `TEST`/`TEST0` + `TEST1_N` + `RESET_N` (+ Vpp) (EASE1000 manual §2.5.1.2;
   ML610Q438 diagram: RESET&TEST block + VPP pin). On the calculator, look for the pads
   that (a) behave like reset (breathes at power-on), (b) toggle during diagnostics.
2. `[INFERENCE]` If the CY-845 die kept the ICE and the factory tester aliases it onto the
   same *PORT4-class* pads seen on 1st gen (SFR 0xF221–0xF223, toggling with "Pd-Read OK"),
   those three vertical pads are the port to try **first**, with the RESET candidate from
   the 4-pad group.
3. Optionally narrow it in software: if code-exit is reached via ROP, drive raw pins from
   ROM gadgets and hunt the pair that responds to the debugger (forum #461's plan:
   push the candidate pins low from executing code, look for the 1–2 programming pins).
   On CY-845 this requires reaching ROP by emulator-only routes first — carry the
   debug-pads map before investing.

### Step 4 — Programmer
* Required kit (LAPIS docs): **EASE1000 V2** unit + **EASE1000 V2 interface cable** +
  **LEXIDE-U16 (IDE) or DTU8 debugger**, host program *LEXIDE-FS/MWU…*; flash writing via
  **MWU16 Flash Multi Writer** (EASE1000 V2 manual §2, Fig 2-1). Gen-1 **EASE1000** is the
  EOL-compatible alternative but formally only claims ML62Q1000/ML610Q100/ML620Q000.
* Renesas E1/E8, TI/FTDI-based "FlashPro", ST-Link, J-Link etc. — **not applicable**; they
  speak vendor protocols this family doesn't have. Any hobby success (forum #459's
  "nano-EASE") means an EASE-protocol clone; verify against the EASE1000 V2 manual's
  interface pin table before buying.
* Wire: `VTref`→ battery-line voltage you've chosen, `Vss`→ board GND,
  `RST_OUT/SCK`/`SDATA` → the two candidate pads, `VDDL`→ solder-trap VDDL if you have
  identified it (emulator will drive 1.45 V), `Vpp` → not connected if no Vpp pad is
  identified (never free-guess a Vpp net). 14-pin connector pin-map: Table 1 of the
  EASE1000 V2 manual, reproduced in §2.1 of this document.

### Step 5 — Attempt a session (part stays on the board; remove the battery first)
1. Power choice: feed the board from `3.3VOUT` on the battery terminals (deterministic
   supply, verified tolerable on 1st-gen boards), or keep the coin cell in and leave the
   debugger's `3.3VOUT` unconnected.
2. Start the debugger, target selection: any **ML610Q4xx-class ML610Q** device (the tool
   family-wide; there is no ML610904 entry in any public tool menu — `[INFERENCE]` pick
   the 128 KB/LCD twin and expect per-register differences).
3. If handshake succeeds: **first backup**, always: read the full program space (64K words
   × 2 banks) and the RAM — CY-845A dump exists here for cross-checking
   (`research/CasioEmuX/models/fx991esplus2/rom.bin`); any delta = evidence you are looking
   at a different firmware revision or at an unmapped read.
4. Then halt/run experiments:
   * halt mid-main-loop, read all CPU regs + SP;
   * write the rop_debug chain at 0x8C80 (`cy845-rop.md` "corrected chain",
     bank0-only `POP PC`≡`0x2B1E` + memcpy `0x35BE` + KEYSCAN `0x4D0E` + park `0x4EF2`),
     set `PC=0x2B1E`, `SP=0x8C80`, `CSR=0`, release — expect LCD row 0 = pattern, then
     press keys and read the chain's KEYSCAN result before removing power.
5. If handshake fails: revert to Step 3 with different pad pairing; after exhausting
   pairings with a scope on SDATA showing no meaningful activity, stop: given OKI's
   documented deletion of the debug circuits from the ML610901 production core, the ICE is
   plausibly **not in silicon** on ML610904 either, and there is nothing to hunt. The
   typed-hackstring loader route doesn't exist for 2nd ed either (measured dead ends:
   `docs/physical-calc.md` §2, §7) — in that case no external-control path remains at all,
   and the replacement-mainboard route (§6) is the only one.

### Bricking & recovery
* **Firmware-bricking is essentially impossible** — mask ROM has no write path; all
  firmware content survives any chaos state; power-cycling (remove coin cell) recovers a
  hung calculator every time (community verified on 1st gen: every wild state recovered on
  power cycle; in-repo emulator runs conclude the same).
* **What can really break it:** electrical damage — applying bench voltage to a pad that is
  actually battery/boost/LCD-drive; a COB die pad lift; cracked trace. On a unibody
  die-on-board assembly there is **no user repair**; donors are cheap, but mods should be
  done on sacrificial units.
* Keep Vpp disconnected until a Vpp net is positively identified: flash-write Vpp levels
  on the wrong net are the classic fatal mistake.

## 6. Alternatives (and the honest Snake verdict)

| Approach | Effort | Snake quality | Notes |
|---|---|---|---|
| **In-firmware ROP + debug loader** (§4-5) | month-scale, expert | ≈1–2 fps toy, calculator unusable while playing | Only path that runs *the original MCU* in-game. Needs the undocumented pad map plus a re-arm strategy; every prior stage emulated only. |
| **Replacement mainboard, emulator core** (recommended) | weeks, hobbyist | **Actual playable Snake** (snake.lua/flappy.lua already run on this ROM) | The community solution to the same wall: *"we have an emulator … so writing code for something like an stm32 or esp32 & emulating the cpu shouldn't be that hard. Driving the display and getting the keys is also not that hard"* — forum [p.12, entry #63587](https://community.casiocalc.org/topic/7583-fx-82-83gt-115-991es-plus-hacking/page-12) (Nov 2020 thread, DSch/cetus9/user202729 posts around #445–#456). Port the CasioEmuX core (+ CY-845A `rom.bin`) to an ESP32-S3/RP2040/STM32; key matrix = the verified 8×8 KI/KO scan map (`research/findings/cy845-rop.md`, Session 4); drive a 128×32 SSD1306/ST7565 display, or the bare 96×32 glass (bare glass needs multi-level AC waveforms — `[INFERENCE]` non-trivial; a cheap dot-compatible display swap is the sane route). Authenticity bonus: it runs Casio's own ROM. |
| **Flash-MCU swap on the original PCB** | high, microsoldering | n/a — the flash siblings are not pin-compatible | A LAPIS flash part with on-chip debug exists in the family (ML610Q438/Q439: 128 KB flash, LCD driver, same debug interface), but it is a different package/pinout than the Casio custom die; a swap is a board redesign, not a reflash. Also: there is no public flashing entry into a Casio-ordered mask part; you'd program the *new* part with a *modified* ROM image — i.e. this is variant "replacement mainboard" with extra soldering. |

**Concrete recommendation:** treat on-chip debug as a research probe (§5 steps 0–4), not a
Snake route. If the goal is Snake on an fx-991ES PLUS 2nd-edition shell, the deterministic
route is a replacement mainboard running the CasioEmuX core with the CY-845A ROM — code
that already exists in this repository.

---

## 7. Source list

**Vendor/technical (primary):**
1. nX-U8/100 Core Instruction Manual, FEUZ0317A0-U8-INST-05, 2011-10-11 — [docs.alexrp.com/nx/nx_u8.pdf](https://docs.alexrp.com/nx/nx_u8.pdf) (copy: `research/fxesplus/docs/`)
2. OKI Technical Review No.203 Vol.72 No.3, July 2005, *Development of ultra-low power 8-bit microcomputer* (ML610901 for Casio) — [www.mikrocontroller.net/attachment/356611/203_R06.ja.en.pdf](https://www.mikrocontroller.net/attachment/356611/203_R06.ja.en.pdf), original [www.oki.com/jp/Home/JIS/Books/KENKAI/n203/pdf/203_R06.pdf](http://www.oki.com/jp/Home/JIS/Books/KENKAI/n203/pdf/203_R06.pdf)
3. LAPIS ML610Q438/Q439 datasheet, FEDL610Q438/439 — [mm.digikey.com/…/ML610Q438,Q439__DS.pdf](https://mm.digikey.com/Volume0/opasdata/d220001/medias/docus/407/ML610Q438%2CQ439__DS.pdf)
4. LAPIS, EASE1000 V2 User's Manual — [fscdn.rohm.com/…/FEXTEASE1000V2.pdf](https://fscdn.rohm.com/lapis/en/products/databook/applinote/ic/micon/FEXTEASE1000V2.pdf)
5. LAPIS, EASE1000 User's Manual (incl. ML610Q100 TEST0/TEST1_N wiring) — [fscdn.rohm.com/…/FEXTEASE1000.pdf](https://fscdn.rohm.com/lapis/en/products/databook/applinote/ic/micon/FEXTEASE1000.pdf)
6. LAPIS news release 2019-03: EASE1000 V2 release, last-buy for EASE1000/uEASE — [www.lapis-semi.com/en/company/news/news/r201903_2/](https://www.lapis-semi.com/en/company/news/news/r201903_2/)
7. LAPIS ML610400-series selection guide (mask/flash split, die delivery, 1 KB TEST area on mask models) — [jotrin.ru/…/ML610400 selection guide](https://www.jotrin.ru/userfiles/downloadfile/202002261240041518.pdf) (PDF)
8. ROHM/LAPIS product page, family member ML610408 (kit contents: EASE1000 V2 + interface cable) — [www.rohm.com/products/…/ml610408-product](https://www.rohm.com/products/micon/low-voltage/ml610400-ml610q400/built-in-lcd-driver-segments-type-8bit/ml610408-product)

**Community (primary):**
9. Universal Casio Forum, *FX-82/-83GT/-115/-991ES PLUS Hacking*, page 12 — [community.casiocalc.org/topic/7583…/page-12](https://community.casiocalc.org/topic/7583-fx-82-83gt-115-991es-plus-hacking/page-12):
   #442 (LTVA, 2020-10-02, CY-845 PCB pad groups, JTAG/ISP goal), #450 (LTVA, ML610901/nX-U8/100 + on-chip debug + 128K flash quote), #452 (LTVA, "ROM … 0.(9) probability can't rewrite"), #454/456 (reprogramability + SFR gap), #459 (cetus9, nano-EASE, TEST/reset-pin reasoning), #460 (cetus9, P155 = VDDL candidate, 3 vertical PORT4-class pads, "Pd-Read OK", 500 kHz clock), #461 (DSch, 3.3 V non-destructive, ~1 V LCD bus)
10. e-Gadget, *fx-991ES PLUS 2nd edition の概要* (2021-09-05; anti-counterfeit 2nd-edition line, QR/hologram, Thailand production, function unchanged) — [egadget.blog.fc2.com/blog-entry-775.html](http://egadget.blog.fc2.com/blog-entry-775.html)
11. casiocalc.wikidot / fxesplus project — [research/fxesplus/](../research/fxesplus/) local mirror of user202729's docs (hardware description posts, hackstring tutorial, nX-U8 core manual)

**Local (this repo):**
12. `research/findings/cy845-rop.md` — CY-845A ROM analysis: bank/csr model, RAM map 0x8000–0x8DFF, verified gadget table (0x2B1E, 0x35BE, 0x4D0E, 0x4EF2, 0x327E…), emulator-verified ROP→LCD and ROP→key results, typed-payload dead end (§2/§7)
13. `research/gyx-decomp/assets/ML610904.DCL` + `ML610904.H` — community-authored chip descriptor (name origin, ROM/RAM ranges, SFR map); `rom.pid` contains `ML610904`
14. `research/gyx-decomp/src/a03_testarea.asm` — in-ROM TEST area at program-space 0xF800 (vector/SP table), matching the ML610Q438 "1 KByte TEST area" spec
15. `research/CasioEmuX/` — emulator + `models/fx991esplus2/rom.bin` (CY-845A dump), `model.lua` (hardware_id 3, csr_mask 0x0001), `snake.lua` / `flappy.lua` (ROM-level games), `rop_*.lua` probes
16. `docs/physical-calc.md`, `research/fxesplus/docs/known-exploits.md` — CY-845 exploit-terrain context; 1st-gen GYX ROM dump and diagnostic-mode facts
