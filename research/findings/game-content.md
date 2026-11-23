# Game content map — which RAM bytes are attacker-controlled after the typed overflow, and which memcpy12 can read as render source

Date: 2026-11-22. Measurement: **one** emulator run (`research/CasioEmuX/content_map.lua`,
model `fx991esplus2`, the `rop_e2e.lua` typed recipe verbatim: keys from T=1, payload planted
at 0x8154, AC,<-,EXE trigger). RAM 0x8100–0x8DFF dumped from Lua (`io.open` binary writes) at
four moments; memcpy12 (0x35BE) src EA forced to 18 region bases by register teleport
(`cpu.pc=0x35BE, cpu.sp=scratch, word[scratch]=EA, cpu.r0=1, ER2=0x8C00, cpu.lr=0x4D0E`) with
the 12-byte copy read back from 0x8C00 on the next KEYSCAN hop.

Artifacts (in `research/CasioEmuX/`):
- `content_map.lua` — the script
- `content_map_dump0.bin` — pre-trigger snapshot (final_t==1)
- `content_map_dump1.bin` — at first chain hop (0x4D20 hit #1, sp=0x8DA0, dsr=0)
- `content_map_dump2.bin` — hit #8; `content_map_dump3.bin` — hit #20
- `content_map_payload.bin` — the 100 typed bytes at 0x8154

Stability: dump1 == dump2 == dump3 except 0x8C80–0x8C81 (the test scratch word itself) → the
flood is final and static while the chain runs.

## Headline measurement: the flood is the payload repeated over the whole upper RAM

`dump1[a] == payload[(a - 0x8154) % 100]` holds for **every** `a` in **0x8154..0x8DFF**
(verified byte-for-byte over the full span; RAM ends at 0x8DFF, byte there = 0x4D = expected).
The earlier "0x8240..0x8E00 tiling" description was approximate — the tiler actually anchors
the payload at the input buffer itself:

- **Total span filled with the repeated payload: 0x8154..0x8DFF = 3244 bytes** (md5
  `8abf86552780f6f88d567072d5107960`), **repeat period = 100 bytes**, **phase 0 at 0x8154**
  (payload offset 0 sits at 0x8154 + 100·k; e.g. the W-word block at payload offset 48 appears
  at 0x8184, 0x81E8, …, 0x8C74 — confirmed by `SRC12 base=8C74 memread=3835383501F8BE3554810E4D`).
- 1462 `0E 4D` tile pairs inside the span (Lua counter over 0x8240..0x8DF8 at hop #1: 1350).
- 0x8100..0x8153 (84 bytes, md5 `027022947743d81ae774ae99c110a11b`) is **not** flooded:
  firmware/key-derived bytes; only 6 bytes (0x8114–0x8149) changed vs the pre-trigger dump0
  (formula typing), so this region is *not* payload-controlled.

Payload (md5 `5faa9fe7249d21d1dc6c6fde2fcf4c74`, 100 bytes, minimal period 100 — the W-word
block at offsets 48–57 breaks any shorter period):
`0E4D`×24 + LE16 words `3538 3538 F801 35BE 8154` + `0E4D`×21.

## Answers (i)–(iii)

- **(i) Max distinct attacker-controlled bytes in RAM, repeats counted once = 100** — the
  payload itself (0x8154–0x81B7). All other controlled locations are replicas of these same
  100 bytes (9 distinct byte *values* in this particular payload: 01 0E 35 38 4D 54 81 BE F8).
- **(ii) Max contiguous distinct block = 100 bytes at 0x8154–0x81B7** (the input buffer). No
  longer distinct block exists: everywhere else the content is periodic with period 100.
- **(iii) Span filled with the repeated payload = 0x8154..0x8DFF (3244 bytes), repeat period
  100 bytes, phase 0 at 0x8154.**
- **(iv) Alignments matter, but only even ones are reachable by memcpy12.** Over the span there
  are **23 distinct 12-byte windows** (11 even-aligned) for this payload, and **100 distinct
  384-byte windows (50 even-aligned)** = exactly the 100 rotations of the payload. `MMU::ReadWord`
  masks bit 0 (`offset &= 0xFFFFFE`, MMU.cpp:302) and memcpy12 reads via EA word reads, so an
  **odd EA aliases to EA&~1**: proven by `SRC12 base=8155 … memcpy12=0E4D… match=false` (copy
  returned the 0x8154 window) and `SRC12 base=8241 … match=false` (returned the 0x8240 window).

## Region table (post-trigger dump1) — provenance and memcpy12 src usability

Every region ≥ 0x8154 is byte-identical to the payload periodic extension
(`dump1[a]==payload[(a-0x8154)%100]`), i.e. a full or partial replica of the typed 100 bytes —
history, cache, editor, journal, draw buffer and stack frames are all overwritten by the flood.

| Region | Range | Len | Provenance (measured) | md5 (dump1) | memcpy12 src? (proof line from the run) |
|---|---|---|---|---|---|
| pre-input | 0x8100–0x8153 | 84 | firmware/key-derived, NOT payload (6B changed vs dump0) | 027022947743d81ae774ae99c110a11b | Y — `SRC12 base=8100 memread=000000000104010001000000 memcpy12=… match=true` |
| input buffer | 0x8154–0x81B7 | 100 | the typed payload itself | 5faa9fe7249d21d1dc6c6fde2fcf4c74 | Y — `SRC12 base=8154 … memcpy12=0E4D0E4D0E4D0E4D0E4D0E4D match=true` |
| history | 0x8184–0x81B7 | 52 | payload replica (offset 48+, W-words) | 38d6d6f34bb5017abbf803b6f1fe947f | Y — `SRC12 base=8184 memread=3835383501F8BE3554810E4D memcpy12=same match=true` |
| cache | 0x81B8–0x85A9 | 1010 | payload replica | 30ed441036fbe4aac354c96d48de602d | Y — `SRC12 base=81B8 … match=true` |
| 0x85AA area | 0x85AA–0x829D | — | payload replica | (subset of span) | Y — `SRC12 base=85AA … match=true` |
| editor buf | 0x829E–0x82CE | 49 | payload replica | 677c3a57cb711ea0c8f4b399b56ea0a2 | Y — `SRC12 base=829E / 82CE … match=true` |
| journal head | 0x8230–0x823F | 16 | payload replica | 5da29370d01f260101f5cdd577bb0375 | Y — `SRC12 base=8230 … match=true` |
| flood lower | 0x8240–0x87CF | 1424 | payload replica | 7312c138e65dbffa55a8502df415add3 | Y — `SRC12 base=8240/8242/8270 … match=true`; base=8241 (odd) aliases 0x8240 |
| draw buffer | 0x87D0–0x894F | 384 | payload replica (harness pattern planted pre-trigger was overwritten) | 3b7e6d661156828a64522f1d805a9f9b | Y — `SRC12 base=87D0 … match=true` |
| flood mid | 0x8950–0x8C5F | 784 | payload replica | 490b3732fd411b409bd9355062cd8e81 | Y (covered by 8C60/8D74 reads) |
| stack frames | 0x8C60–0x8D74 | 277 | payload replica (harness marker at 0x8C71 was overwritten) | d647c548baa815e94f772e95c0ed83e9 | Y — `SRC12 base=8C60 / 8C74 / 8D74 … match=true` |
| top stack | 0x8D75–0x8DFF | 139 | payload replica | 1dddbefdcd0732821ba31f24694bed58 | Y — `SRC12 base=8DF0 … match=true` |
| whole span | 0x8154–0x8DFF | 3244 | payload repeated, period 100, phase 0 @0x8154 | 8abf86552780f6f88d567072d5107960 | Y everywhere (18/18 forced-EA tests copied correctly) |

All 18 forced-EA memcpy12 tests returned the exact 12 bytes at the even-aligned src
(`match=true`), except the two odd bases which returned the even neighbour's window
(ReadWord bit-0 mask). Conclusion: **any even address in 0x8154..0x8DFF is a valid memcpy12
render source; odd EA silently reads EA&~1.**

## EA plantability (what the chain can actually pop as src)

`POP EA` at 0x35BE pops a 16-bit word from the walked stack, which is flood = replicas of the
payload, so **EA must equal one of the payload's words**. Even-offset LE words of this payload:
`{0x3538, 0x35BE, 0x4D0E, 0x8154, 0xF801}` (5 distinct); odd-offset words alias after the
bit-0 mask. The attacker types all 50 even-offset words → **up to 50 distinct EA values per
100-byte hackstring**, shared with the chain-control words (KEYSCAN/gadget addresses), so the
practical count is 50 minus the control words. On hardware the EA bytes must be zero-free
typeable: high byte of a RAM src must be in {0x81,0x82,0x84,0x85,0x89,0x8A,0x8B,0x8C}
(0x83, 0x86, 0x87, 0x88, 0x8D are not typeable per base/alpha/shift_keycodes.txt) → typed-EA src
banks on hardware: 0x81xx, 0x82xx, 0x84xx, 0x85xx, 0x89xx, 0x8Axx, 0x8Bxx, 0x8Cxx (in-emulator
any EA works, as measured). Note 0x87D0 (draw buffer) is readable but its address is not a
typeable word on hardware.

## Max frame budget for a game

- **12-byte frames** (one memcpy12, r0=1, dst=one 16-byte LCD row): the span offers up to
  **100 distinct byte-aligned / 50 even-aligned 12-byte windows** per payload period
  (measured 23/11 for the e2e payload, whose bytes are mostly the 0E4D flood; a maximally
  diverse 100-byte payload reaches the 100/50 cap). The binding constraint is EA plantability:
  **≤ ~50 distinct src addresses per typed payload** (one per even-offset word, minus
  chain-control words).
- **384-byte full-screen frames** (memcpy12 with r0=32 copies 32×12 bytes, dst stride 16 =
  the whole 96×32 LCD): the 3244-byte span easily covers 384 contiguous bytes; a frame starting
  at even src is one rotation of the payload → **up to 50 distinct full-screen frames per
  100-byte hackstring** (measured: exactly 50 even-aligned / 100 byte-aligned distinct 384-byte
  windows exist in RAM; payload minimal period 100 ⇒ all 100 rotations distinct).
- Within each frame, all 384 bytes come from the same 100-byte payload, so **frame content is
  limited to rotations of one 100-byte pattern** — a game can have ≤50 distinct screens (or
  ≤50 distinct row-segments) per hackstring, each screen being the 100-byte payload tiled
  3.84×. More frames would require re-typing (new trigger) or computing bytes in RAM via
  gadgets (out of scope for the typed payload alone).
