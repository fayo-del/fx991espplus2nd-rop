# keyboard → SETUP (SHIFT+MODE) — closure record (2026-11-21)

Status: **closed as emulator-fidelity-blocked.** SHIFT+MODE → SETUP could not
be verified to open on this ROM through the Casio-emulator keyboard shim, and
LineIO (Σ bare 69 B8, len=2) was never proven. Menus demonstrably render in
this environment (bare MODE opens the mode menu; see §2-session evidence),
so the failure is specific to the chord path, not to input delivery. The
finding is a **shim-protocol question, not evidence about the real
calculator** (the real fx-991ES PLUS 2nd uses the raw key matrix, where both
KO rows are driven and both KI bits go low in one scan; SHIFT+MODE/SETUP and
LineIO are assumed working on hardware).

Environment probes: freshly built `emulator/emulator.setup` (own binary;
`emulator/emulator`, `emulator/emulator.patched` never touched);
rom.bin untouched (md5 c4c7d7fb89d0fd07cc0196d642682d83). Probes:
`kyb_timA..timK.lua`, `kyb_timB2/B3` (+ `setup_test3.lua`, `rop_green2.lua`
traced variants). Source delta left in tree: **trace-only**.

## 1. Root cause (mechanism)

- The firmware's post-boot key input runs exclusively through the **Casio-emu
  keyboard handshake**: round = query (`ST 1 → 0x8E00`, pc=0x7C2E) → read KI
  (`0x8E01`, pc=0x7C4A) → read KO (`0x8E02`, pc=0x7C4C) → close (`ST 0`,
  pc=0x7C66, ready=0). Between rounds the flash-idle loop at 0x7C40-0x7C5E
  probes the same bytes (loop exit on `(KI|KO)!=0` → BL 0x7902 → dispatch);
  cadence ≈ 0.58 s/round (~79 rounds / 45 s run).
- The shim is **one-key-per-round**: `PressButton` (Keyboard.cpp press branch)
  overwrites `keyboard_in_emu/button.ki_bit; keyboard_out_emu/button.ko_bit`,
  each slot zeroed on its 2nd read (readcount). Every consumed report matched
  `(in=ki_bit, out=ko_bit)` of exactly one key:
  keycode `= ctz(in) | ctz(out)<<4` — verified on five fixtures:
  `(80,01)→0x07 SHIFT`, `(80,10)→0x47 MODE`, `(01,02)→0x10 K2`,
  `(40,20)→0x56 SIGMA`, `(04,10)→0x42 AC`.
- The raw matrix (0xF040 vector-read) is probed **only at boot** for a key
  **clear**: `KW 00F046=7F pc=4D14` → `KR 00F040 pc=4D1C` (KID=0xFF, no key),
  once, then never again in ≤110 s runs (getkeycode area 0x4D0E; app idle =
  pc=0x75C0; its 0x75C2 poll never appeared post-boot in any trace).

## 2. Negatives (each with capture)

| Probe | Delivery | Evidence | Result |
|---|---|---|---|
| setup_test3 | SHIFT held T=1, MODE held T=17001 (16000 ticks) | failed-baseline stdout: `AFTER-MODE KOD=11 KID=7F … SIGMA buf=69B821BA21BA21B9 len=8` | MODE consumed as bare key; mode menu; Σ leaves MathIO form |
| timA | SHIFT held; MODE 40-tick taps at 20000-80000 | no `(80,10)` report in traced rounds | taps shorter than one round are lost |
| timB/timB2/timB3 | both held T=1..120000 | `(80,10)` consumed | newest-press wins; screen stayed splash/home in this run |
| timE/timE2 | chord 1..20000, then K2/SHIFT/Σ | `KKI` only for the chord; presses at T≤75010 landed during ROM boot | boot window eats keys in these runs |
| timF | both held forever (110 s) | consumed at boot→idle transition; screen splash→blank→2px bar | no menu text within this run |
| timC/C2/D | (C0,21) report vs MODE-only control | different row0 bytes per state (ROM reacts) but no menu text in this window | accumulate wrong-key |
| timG (control) | single key `2` held forever | `KKI 01` consumed, screen changes, later `buf=32… len=1` proves apps accept single keys | key path works end-to-end |
| timH/timI/timJ | SEQUENTIAL SHIFT round then MODE round (both reports consumed: `KKI 80 n=1`, `KKI 80 n=2`) | `FINAL buf(8)=3200.. len=1 F9=C1` — `2` typed at home screen, MathIO unchanged | SETUP not observed on-screen; whether the chord engaged is ambiguous |
| timK | chord held through the boot key-clear probe | rendered screen = calculator home (control-matched) | boot probe clears, does not dispatch |
| accumulate-OR fix (Keyboard.cpp, reverted) | chord → `(in=0x80|0x80, out=0x01|0x10)` | `KKI C0` consumed once; ctz decode ⇒ wrong key (0x06/0x60 class) | OR-decode ambiguity |
| restored Sessions 11-12 + `/tmp/rop_e2e.now` (pristine binary) | double-SHIFT primer + [SHIFT][MODE]; /tmp/rop_e2e.now full pipeline | Session 11: LCD row2 `0000… → 10044840E38038040400038E` = rendered menu text only AFTER the primer (first [SHIFT][MODE] did not); Session 12: DOWN+EXE changed pages and cleared the input (selection applied), digit-2 inert; rop_e2e.now renders `setup1` near-blank rows then a FULL text page (`setup2 after 2`, `formula typed`, ~24 rows) | (a) bare MODE demonstrably opens and renders the mode menu; (b) the SHIFT+MODE chord → SETUP was never verified; Σ stayed boxed (LineIO unproven) |

## 3. Conclusion

SHIFT+MODE → SETUP was **not verified through the 0x8E00 shim** — LineIO stayed
unproven (Σ boxed). The one-key-per-round + ctz codec explains *why* a chord
is hard to deliver (a held second press either overwrites the single-slot
report or decodes as one wrong key under OR-accumulation), but "impossible" is
**not established**: restored Sessions 11-12 show a menu rendered after a
double-SHIFT primer with a following [SHIFT][MODE] (row2 went to
`10044840E38038040400038E`) and the first chord alone did not — so the chord
path plausibly needs a primer/state precondition the probes here never
reproduced. What IS proven: the ROM never re-enters its 0xF040 vector scan
post-boot in any of my traced runs, the boot-time matrix probe is a state
clear rather than a dispatch, and all delivery strategies tried here
(single-slot overwrite, accumulate-OR, sequential rounds, boot-spanning hold,
long/short holds) failed to open SETUP on a rendered screen.

## 4. Regression / no-impact proof

- `rop_green2.lua` on the **pristine** binary — markers match the known
  baseline: `firmware idle pc=75C0 sp=8DDC`, `P1 kicked pc=2B1E sp=8C80`,
  `FRAME: P1+100 row0: FFFF…`, `@4D20 KEYSCAN RT ER0=0001`,
  `P1 done pc=4B96 sp=8C18 csr=0 ea=F009 lr=7C40`,
  `P2 firmware restored pc=75C0 sp=8DDC`.
- `setup_test3.lua` on the **pristine** binary — same failed baseline as
  pre-task (see §2 first row).
- rom.bin md5 unchanged (c4c7d7fb89d0fd07cc0196d642682d83);
  `emulator/emulator` md5 4dcb0b1c6ce05aff52c2b1cb9de5631a (untouched).

## 5. Files / tree

- `emulator/src/Chipset/MMU.cpp`: env-gated `CASIO_TRACE_KBD` KR/KW traces in
  ReadData/WriteData — the ONLY source delta (inert unless the env var is set;
  mirrors the existing CASIO_TRACE_CNT/CASIO_TRACE_WRITES pattern).
- `emulator/src/Peripheral/Keyboard.cpp`: experiment reverted; byte-identical
  to its pre-task state (dirty-tree matrix code `keyboard_out |= pressed`
  kept exactly as found). Pristine binary untouched (§4).
- Rebuilt my own build: `cd emulator && g++ -I/usr/include/SDL2 -I/usr/include/lua5.4 -std=c++2a src/*.cpp src/*/*.cpp src/Gui/imgui/*.cpp -lSDL2 -lSDL2_image -llua5.4 -lreadline -O2 -o emulator.setup` (clean, no errors).
- Probes left in place: `kyb_timA..kyb_timK.lua` (timB2/timB3 rendered-row
  variants) + the traced `setup_test3.lua`/`rop_green2.lua` are unchanged.

## 6. Recipe if anyone revisits

1. Break at the 0x7C44 idle-loop exit (`break_at` around `L R2,[ER12]` /
   `OR R2,R0` at 0x7C4A-0x7C4E) and single-step into BL 0x7902 → the rounds
   (0x7C2E-0x7C74): read pc + r-values per round as the MODE report is
   consumed. This locates the ROM's chord detect and whether it expects
   `(KI=0x7F, KO=0x11)` or a two-round sequence with a captured SHIFT latch.
2. Try a **write-hook chord emulation**: intercept stores to 0x8E00 at
   handover-window boundaries and force the report `(0x80, 0x11)` plus the
   right ready semantics, rather than mutating PressButton; keep the shim's
   two-read zeroing in mind (a chord has to survive exactly one full round).
3. Confirm runtime first on the pristine `emulator/emulator` binary: prior
   workers reached the app in ~10 s; my build runs the ROM ≈5× slower in
   script-ticks, so any timing-bound experiment needs proportionally longer
   runs (use `timeout 240` if re-built).
