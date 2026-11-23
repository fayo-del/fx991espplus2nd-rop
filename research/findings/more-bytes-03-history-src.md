# more-bytes-03 — can a non-0x8154 src buffer (history/cache/echo/journal) deliver more distinct attacker bytes?

Date: 2026-11-22. Question (assignment more-bytes-03-history-src.md): the 33 strcpy + 37 strcat
sites were classified (sec-firmware-copies.md) but only the 0x8154 one was weaponized. Can any
KEYBOARD-REACHABLE copy use a DIFFERENT src buffer (history 0x8184, 0x85AA echo, multi-line,
RCL'd entries, STAT/matrix/EQN) with dst reaching stack/SFR, or build a longer string via
strcat chains?

Emulator: `research/CasioEmuX`, model fx991esplus2, headless, 4 runs (budget respected):
`more03_map.lua` (run 1), `more03_chain.lua` (run 2), `more03_census.lua` (run 3),
`more03_floodstamps.lua` (run 4). Scripts in `research/CasioEmuX/more03_*.lua`.

## Run 1 — pre-trigger coexistence map (`more03_map.lua`, dump `more03_map_dump.bin`)

Session: warm-up, then 20×'1' EXE, AC, 20×'2' EXE, AC, 20×'9' EXE, AC, RCL, UP, UP.
Measured (keys partially eaten; 14 of 20 landed):

| Buffer | Addr | Holds (measured) | strlen |
|---|---|---|---|
| input | 0x8154 | last typed/recalled string (14×0x32) | 14 (cap 99 typed) |
| cache | 0x81B8 | **last EXE'd input stashed here; survives AC** (14×0x32 after exeB, still there after acC/acR) | 14 |
| history slot | 0x8184 | 0 in this flow (overlaps input tail 0x8154+48) | 0 |
| echo | 0x85AA | 0 in this flow | 0 |
| editor buf | 0x829E–0x82CE | `00 0D 00 02 22… 01 30 13 32…3A` (header+string) | 0 (NUL at start) |
| journal slots | 0x8230 (len 10), 0x8398 (len 15) | entry header `02 22…01 30` + string + NUL; 0x812C walks 0x8154→0x8398 | ≤99+header each |
| pre-input | 0x8100–0x8153 | firmware; 0x8140–0x8149 = copy of journal header (changed by typing) | — |

- **UP (0x27) recalls the cache content into 0x8154** (after up1: in.len=14, buf=14×0x32, 0x8113=01).
- **RCL (0x17) did nothing observable in this flow** (in.len stayed 0).
- **AC clears 0x8154 but NOT the cache 0x81B8.**
- All attacker strings are NUL-separated: nonzero runs at 0x8154–0x8161, 0x81B8–0x81C5,
  0x8230–0x8239, 0x82A1–0x82B9, 0x8398–0x83A6, then firmware (0x860E countdown, draw buffer
  0x87D0+, stack 0x8A18+). Max contiguous attacker run from 0x8154 = input + cache = ≤ 100+99.

## Run 2 — does a non-zero cache extend the flood unit? (`more03_chain.lua`)

Recipe: type 70 cycling digits (28 landed, tokens 0x31–0x39) → EXE (cache 0x81B8 = 28B string,
measured) → AC (cache survives, measured) → final phase Right/Left, plant 100-byte zero-free
payload B at 0x8154–0x81B7, EXE trigger.

Measured:
- `PLANT: strlen(0x8154)=128` — the run bridges 0x81B7 into the cache (100 payload + 28 cache).
- Trigger fired: `pc=6B62` (strcpy loop), strlen grew 128→1792→**3244** (whole span, 0 NULs),
  chain ran (10 KEYSCAN hops at 0x4D20, sp 0x8DA0→0x8DD0).
- Final dump (`more03_chain_dump.bin`): **minimal period = 100 over all 0x8154–0x8DFF**,
  unit = the planted payload B exactly, distinct byte values = 9 {01,0E,35,38,4D,54,81,BE,F8},
  **cache content A (tokens 0x31–0x39 except 35/38 which are payload W-word bytes) fully wiped** —
  no A byte survives anywhere in the span.

**NEGATIVE, measured:** bridging strlen into the cache does NOT add distinct bytes to the flood.
Mechanism (static + measured): the flood's first stamp is the overlapping `strcpy(0x81B8 ← 0x8154)`
(dst = src+100); each propagation step maps byte at p to the old byte at p−100, so every flooded
address converges to `payload[(a−0x8154) mod 100]` — the flood can never contain more than the
first 100 bytes of 0x8154 at trigger time, no matter how long strlen runs into cache/journal.

## Run 3 — copy-primitive census in a history-rich session (`more03_census.lua`)

Session: 12×'1' EXE, AC, 12×'2' EXE, AC, 12×'3' EXE, AC, UP, UP, RCL, DOWN, LEFT,
SHIFT+Σ (template path), AC, 12×'9' EXE. Breakpoints on 0x2B10 (strcpy), 0x2B24/0xCB5E
(strcat), 0x5108 (memmove), 0x35BE (memcpy12), logging site(LR)/dst=ER0/src=ER2/len/key.

Measured events (all of them):

| site (LR) | prim | dst | src | max len | key |
|---|---|---|---|---|---|
| 0x50A0 | strcpy | **0x81B8 cache** | 0x8154 input | 8 | exeB |
| 0xC6B8 | strcpy | 0x8398 journal slot | 0x8154 input | 0 | A4 |
| 0x7478/0x7496/0x74B4 | memmove | 0x829E–0x82CC editor | 0x8D9F stack temp (1B insert) | — | exeB/C/D |
| 0x39B6 | memcpy12 | 0x8701–0x8720 draw area | 0xF800–0xF9F0 LCD | — | A3 |
| 0x2B32, 0xC892, 0xC8A6 | strcat | **0x8D62 (stack region!)** | **0x0A09, 0x2738 (ROM)** | ≤2 | sigma |

HOT filter (dst ≥ 0x8C00 or ≥ 0xF000, or RAM src with len > 100): only the strcat→0x8D62
events, **all with ROM-fixed src**. No copy with attacker src wrote ≥ 0x8C00 or any SFR.
No strcat chain built an attacker-derived string (all strcat srcs ROM, len ≤ 2).

## Per-site table — the named candidate sites (static from disasm + measured above)

| Site | Copy | dst | src | max len reachable | dst reaches stack/SFR? | Key seq | Measured |
|---|---|---|---|---|---|---|---|
| 0x5C9E | strcpy | 0x8154 input | 0x81B8 cache | ≤99 (typed cap) | no | mode 0x80F9==0x88 restore (UP-recall path) | run 1 UP→0x8154 recall |
| 0x755A | strcpy | 0x8184 | 0x85AA echo | ≤ strlen(echo) | no | RCL | not fired in run 1/3 [static] |
| 0x756A | strcpy | [ER8] | 0x8184 | ≤99 | no ([ER8]∈{0x8154,0x8398}) | RCL | [static] |
| 0x99E0 | strcpy | 0x85AA echo | [ER8] journal entry | ≤99+header | no (overrun → draw buf only) | EXE/history | run 1: 0x85AA stayed 0 |
| 0x99A8/0x99B8/0x99EC | strcpy | 0x8184 / 0x85AA | [ER8] | ≤99+header | no | EXE/history stash | run 1 dump |
| 0x6E26 / 0x7CFA / 0x8A04 | strcpy | [ER8] journal ptr | 0x81B8 cache | ≤99 | **no** — [ER8] is a data pointer (0x812C observed 0x8154/0x8398), never 0x8Cxx | journal restore | run 3: 0xC6B8 dst=0x8398 |
| 0x507E | strcpy | 0x8184 | 0x81B8 | ≤99 | no | restore (0x80FC==6,0x80FD==4) | [static] |
| 0x509C | strcpy | 0x81B8 | 0x8184 | ≤99 | no | restore | run 3 site 0x50A0 fired |
| 0x50AC | strcpy | [ER8] | 0x8184 | ≤99 | no | restore | [static] |
| 0x8C06 | strcpy | 0x8154 input | ER14−18 stack buf (←0x8140 hdr + strcat 0x8BF6) | template-bounded | no | Σ(/template keys | run 3 sigma events |
| 0x8BF6 | strcat direct | ER14−18 stack = **0x8D62** | ER14−22 stack temp | grows, but src ROM-only | **dst IS in stack region (0x8D62), src never attacker** | sigma/template | run 3: src={0x0A09,0x2738} ROM, len≤2 |
| 0xBB42 | strcpy | 0x81B8 cache | 0x8154 | strlen(0x8154) — **the flood entry** | via self-propagation only | AC/EXE trigger | run 2: period-100 flood |
| 0xCEEC | strcpy | 0x8154 | 0x8184 | ≤99 | no | mode restore | [static] |
| 0xA490–0xA514 | strcat | [ER12] ptr var | ER4 / ROM 0x17E2 | bounded temps | no (display compose) | msg render | [static, census §3] |
| STAT/matrix/EQN | — | — | **no copy site has src there** (all 33 strcpy + 37 strcat srcs enumerated in census §2/§3: 0x8154-family, 0x8184, 0x81B8, 0x85AA, [ER8], ROM, stack temps) | — | — | — | [static] |

## Run 4 — flood stamp census attempt (`more03_floodstamps.lua`)

Attempted to log every copy's (site, dst, src, slen(src)) during the trigger with no typed
preamble. Result: the trigger did NOT fire without the typed preamble (`hits=0`, pc=4B96 idle,
strlen(0x8154) back to 0 — the EXE cleared the planted buffer); only the render memcpy12 stamps
were logged (site 0x39B6, dst 0x8701–0x8720 draw area ← src 0xF800–0xF9F0 LCD — display path,
dst < 0x8C60). **Not needed for the verdict**: run 2 already measured the flood's final state
directly (period 100 over the full span, cache bytes wiped). Run 4 counted against the ≤4-run
budget; no 5th run taken.

## Verdict

1. **Max distinct bytes any non-0x8154-src path delivers: 0 to control data.** No
   keyboard-reachable strcpy/strcat/memmove/memcpy12 with src in history 0x8184, cache 0x81B8,
   echo 0x85AA, journal slots, editor 0x829E, or STAT/matrix/EQN storage has dst ≥ 0x8C60 (stack)
   or ≥ 0xF000 (SFR). Measured (run 3): the only stack-region dst is the strcat into 0x8D62,
   and its src is always ROM (0x0A09/0x2738, len ≤ 2) — no attacker bytes ever reach it.
2. **The 0x8154-src flood is hard-capped at 100 distinct bytes** = the first 100 bytes of the
   input buffer at trigger time. Measured (run 2): with the cache pre-filled so
   strlen(0x8154)=128 at trigger, the final flood over 0x8154–0x8DFF is still period 100 with
   the cache bytes wiped. The overlapping stamp dst=src+100 makes every flooded byte converge
   to `payload[(a−0x8154) mod 100]`. History/cache/echo/journal strings (each ≤ 99, NUL-separated,
   coexisting as mapped in run 1) can extend strlen but never the distinct-byte count of the flood.
3. No strcat chain builds a longer attacker string: all 37 strcat sites copy ROM-fixed or
   render-bounded temps (run 3 measured; census §3 static).

**Answer to the headline question: NO keyboard-reachable copy path beats the 100-distinct-byte
ceiling; the ceiling is structural (flood = first 100 bytes of 0x8154), not a limitation of the
src buffer choice.** More distinct bytes would have to come from chain-computed stores
(gadget-written content), which is outside the copy-site scope of this ticket.
