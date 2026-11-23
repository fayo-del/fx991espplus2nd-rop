# more-bytes-06 — Post-trigger key input: does any key press modify RAM/SFR, and is it chain-readable?

Agent: `MB06PostInput`. Date: 2026-11-22.
Scripts: `research/CasioEmuX/more06_postinput.lua` (run 1), `more06_hops_k9.lua` (run 2), `more06_hops_hold.lua` (run 3).
Logs: `/tmp/more06_run1.log`, `/tmp/more06_run2_k9.log`, `/tmp/more06_run3_hold.log`.

**Question:** rop_e2e.lua said "PROBE1 NOT-INSERTED (input locked)" post-trigger. While the chain runs (post AC,<-,EXE), do any key presses modify ANY RAM/SFR byte (0x8000-0x8DFF, 0xF000-0xF2FF)? Is KID (0xF040) usable as chain-readable content?

## Runs

| Run | Setup | Result |
|---|---|---|
| 1 (`more06_postinput.lua`) | rop_e2e trigger, but K9 pressed *after* EXE at t=40001 → Casio-emu path (0x8E01, last-press-wins) delivered K9 not EXE → **chain never fired (hits=0)**; app parked at its own wait-key spin pc=4B96. Then 13-key sweep with full RAM+SFR diffs. | sweep data valid for post-trigger parked state |
| 2 (`more06_hops_k9.lua`) | EXE pressed **last** at t=40001 with K9 held → **chain fired (20 hops)**, keys released at t=70001 before most hops; 13-key sweep after park | per-hop log + sweep repeat |
| 3 (`more06_hops_hold.lua`) | K9+EXE held **forever** through the hops | per-hop KID/r2 with keys held |

## Measured: per-hop during the chain (run 3, K9 0x22 + EXE 0x60 held)

Every one of the 20 KEYSCAN hops (`break_at(0x4D20)`):
```
HOP 1..20 pc=4D20 sp=8DA0..8DF8 lr=2B1E r0=01 r2=FA KID=FA KO=007F IM=00 KM=0380
```
- KEYSCAN (0x4D0E) itself drives KO=0x7F (ST R0,[0xF046]) and reads KID: `0x4D16 LEA 0xF040; 0x4D1A L R2,[EA]; 0x4D1C CMP R2,#255; 0x4D1E ADDC R0,#0; 0x4D20 RT`.
- **r2 = KID byte = 0xFA = 0xFF & ~(ki_EXE=0x01 | ki_K9=0x04)** — the held keys' KI bitmap is read into r2 by the default flood tile at every hop; r0=01 presence. KOMASK KM=0x0380 ⇒ KO rows 0-6 all live, so KID shows the OR of held keys' ki_bits.
- Run 2 (same trigger, keys released before the hops): all hops `r0=00 r2=FF KID=FF` — release is visible too.
- **KID is row-blind**: KO=0x7F drives all rows at once, so keys sharing a KI line (e.g. K1 0x00 / K2 0x10 / EXE 0x60 all have ki_bit=0x01, different ko_bits 0x01/0x02/0x40) give the same KID bit. KID yields 8 bits = which KI lines are active, not which key.

## Measured: post-park sweep, 13 keys one at a time (runs 1+2; full snapshot 0x8000-0x8DFF + 0xF000-0xF2FF + 0x8E00-0x8E02, drift-calibrated)

Drift with no key (60k ticks): only free-running timers/int-pending — `F00C(LTBR) +2, F014(intpend), F022/23(TM0C)` (run 2 also F023). No key involvement.

Per key press, **immediate** (runs 1+2, identical):
| Key (code) | 0x8E01 (KIemu) | 0x8E02 (KOemu) |
|---|---|---|
| LEFT 0x26 | 0x40 | 0x04 |
| RIGHT 0x37 | 0x80 | 0x08 |
| UP 0x27 | 0x80 | 0x04 |
| DOWN 0x36 | 0x40 | 0x08 |
| K1 0x00 | 0x01 | 0x01 |
| K2 0x10 | 0x01 | 0x02 |
| K9 0x22 | 0x04 | 0x04 |
| EXE 0x60 | 0x01 | 0x40 |
| DEL 0x32 | 0x04 | 0x08 |
| SHIFT 0x07 | 0x80 | 0x01 |
| ALPHA 0x17 | 0x80 | 0x02 |
| MODE 0x47 | 0x80 | 0x10 |
| AC 0x42 | 0x04 | 0x10 |

(ki_bit = 1<<(code&0xF), ko_bit = 1<<((code>>4)&0xF); ki+ko together **uniquely identify the last-pressed key** — 8+10 bits.)
Held 20k, every key changes the same identity-free bytes (values differ per run because sp differed 8D74 vs 8D7A):
- RAM `0x8224` +1 per press (press counter); `0x8DB2`/`0x8DB8` toggle; `0x8DBA`/`0x8DBE`/`0x8DC0` ±1 (scratch near stack). **No key identity** — only counts.
- SFR `0x8E01`/`0x8E02` read back 0x00 by held+20k: the ROM's poll consumed them (emulator clears `keyboard_in_emu`/`keyboard_out_emu` after >1 read — `Keyboard.cpp:122-135`). **Transient.**
- SFR `0xF00D` (HTBR clock), `0xF014` (int pending EXI0 flicker) — timers/interrupts, not key data.
- **KID stays 0xFF in the parked state** (KO readback 0x7F stale from the last KEYSCAN / 0x0000; the parked app does not drive KO rows — it polls the 0x8E00/0x8E01 emu protocol, RDY=01). IM=0x00.
- RELEASED 8k: no persistent RAM change (only F014 flicker). **PROBE1 NOT-INSERTED confirmed again**: the edit buffer 0x8154 does not grow — post-trigger typing is locked. The hypothesized last-key byte **0x80F5 does NOT change** post-trigger (absent from every diff).

## Chain readability of each changed byte

| Address | Changed by key? | Chain-readable? |
|---|---|---|
| 0xF040 KID | **Yes while held, during hops** (run 3: KID=0xFA) | **YES — verified**: the 0x4D0E flood tile itself does `LEA 0xF040; L R2,[EA]` → **r2 = KID byte every hop** (measured r2=0xFA), r0 = presence bit |
| 0xF046/47 KO | written by KEYSCAN itself (0x7F), not by keys | readable via POP-EA gadget 0x3520 [INFERENCE] |
| 0x8E01 / 0x8E02 | yes, transient (ki_bit/ko_bit of last press) | readable via `0x3520 POP EA; L R0,[EA+]` (EA from stack tile, any segment-0 addr) [INFERENCE: read path source-verified at 0x3520-0x3524 + MMU region; **the chain read itself consumes the event** (readcount>1 clears), and odd EA aliases even so 0x8E01 needs EA=0x8E00/02 pairing] |
| RAM 0x8224, 0x8DBx | yes, per-press counters (no identity) | YES trivially (RAM; memcpy12 src / LEA [ER0]+L R0,[EA] 0x33F6) |
| 0xF00C/D, F022/23, F014 | timers/int-pending only | 0xF014 via 0x4BBC `LEA 0xF014; L R0,[EA]; RT` (verified gadget); others via POP-EA [INFERENCE] |
| 0x80F5, edit buffer 0x8154+ | **no** (PROBE1 NOT-INSERTED) | — |

## Verdict

**Post-trigger, keys give NO new persistent content bytes — the 100-byte ceiling stands.** Measured extra chain-readable state from keys:

- **8 bits live** (KID KI-bitmap of currently held keys, row-blind) + **1 presence bit** (r0), read into r2/r0 at every KEYSCAN hop by the default 0x4D0E tile — verified in-emulator (run 3: r2=0xFA with EXE+K9 held; r2=0xFF/r0=0 when released, run 2). This is a ~9-bit **control channel**, not content: it cannot distinguish keys sharing a KI line and only lasts while the key is held.
- **2 transient bytes** (0x8E01 ki_bit + 0x8E02 ko_bit) uniquely identify the last-pressed key, but exist only until read twice (ROM or chain), and a chain read consumes them.
- 4 RAM counter bytes (0x8224, 0x8DBx) change per press but carry no key identity.

So: **N extra readable bytes ≈ 1 (KID, 8 bits, held-only) + 2 transient identity bytes; 0 persistent**. No path to >100 distinct controlled bytes via post-trigger key input. The only way to more distinct bytes remains a second pre-trigger input (other agents' files) or chain-computed stores of the existing 100.

Emulator proof notes: run 1 log `/tmp/more06_run1.log` (sweep, 13 keys), run 2 `/tmp/more06_run2_k9.log` (20 hops with released keys + sweep), run 3 `/tmp/more06_run3_hold.log` (20 hops, K9+EXE held, r2=KID=0xFA every hop). [INFERENCE] marks the 0x3520 POP-EA read of 0x8E0x — not chain-executed in these runs.
