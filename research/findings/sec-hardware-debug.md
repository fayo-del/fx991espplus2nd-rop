# CY-845 hardware-only debug/programming path — 2026-11-22

**(1) Pads/pins on the CY-845 package:** the ML610904 is a COB (die-on-board) Casio mask part;
no public pinout or photo of a marked package exists. The only connection surface reported is
LTVA's sighting of "groups of 3 small and 4 usual size contact plates" (forum #442, images now
dead — Discord/VK 404) plus 1st-gen GY evidence: pad P155 ≈ VDDL candidate, 3 vertical
PORT4-class pads (SFR 0xF221–0xF223) toggling during "Pd-Read OK" with a ~500 kHz clock,
and the battery/solar `Pd` sense pads (`P2D` SFR 0xF050, read-only per DCL comment).
No TEST/Vpp/RESET_N pin is defined in any ML610904 artifact; the .DCL defines only
ROM/RAM/SFR/ROMWINDOW ranges.

**(2) EASE/debug block present or deleted?** Almost certainly **deleted**, per OKI Technical
Review No.203 on ML610901 (the same Casio-ordered production core family): the debug and
tools-mode circuit blocks were removed from the CPU core to cut leakage, and no EASE/ICE/TEST
SFR or `TEST`/`Vpp` symbol appears in ML610904.DCL/.H. EASE1000 V2 targets only `ML610Q*`
flash parts. Verdict: **no halt, no PC set, no ROM dump over a debug port** — [INFERENCE],
consistent with mask-ROM economics (Casio has no reason to bond an EASE port).

**(3) Vpp/TEST programming of mask ROM / the 1 KB test area:** **impossible.** Mask ROM is
programmed at the factory by lithography; there is no write path in circuit. The in-ROM
"TEST area" (bank0 program-space 0xF800, vector/SP table — `a03_testarea.asm`) is code the
CPU *executes*, not writable flash; the ML610Q438's "1 KB TEST area" is a separate flash
block on Q-parts only. Vpp on EASE parts programs *flash* parts; ML610904 has no flash.

**(4) Mode 68 / reset race → test state?** No. Mode 68 (config byte 0x80F9 = 0x00) is an
unintended COMP-like mode reached by a reset race (`[SHIFT][9][3][=]` then `ON` during the
zero-fill, or destabilizing the supply while resetting — wiki/mode-68). It changes RAM state
(LineIO-only, history preserved), not CPU test logic. In-emulator the race did not split the
reset (V8, `/tmp/v8.log`); on hardware it is timing-dependent and untested.

**(5) SFR/pin that reads/writes PC:** **none.** CSR:PC is core state, not memory-mapped; the
reachable SFR map (0xF000–0xF2AD: DSR, SBYCON, FCON, timers, LCD, KI/KO, P0–P1, SIO, I2C)
neither reads nor writes it. Software PC control exists only via the ROP `POP PC` gadget
(`0x2B1E`, emulator-verified) plus reset/interrupt vectors (0x0008–0x0020).

## Realistic opened-device attack surface (ranked)

1. **Battery/solar `Pd` pads + the 3-small/4-normal contact-plate groups** — the only
   confirmed physical access points; voltage injection / matrix probing is safe (3.3 V on
   battery terminals verified non-destructive on 1st-gen).
2. **Factory test GPIOs (P0/P1-class pads, ~500 kHz clock on "Pd-Read OK")** — a production
   tester port of some kind is expected to exist; pinout undocumented for CY-845.
3. **Nothing else**: no JTAG/EASE/Vpp/TEST pin is bonded; firmware rewrite is impossible
   (mask ROM); persistence ceases at battery pull; an opened device offers no additional
   software attack surface beyond the keyboard-reachable states already mapped in
   `docs/vuln-search.md`.

Key sources: docs/jtag.md §§0–7; wiki memory-map/unknown-SFRs/mode-68 pages; forum p.12
#442/#444–#461; OKI Tech Review 203; EASE1000 V2 manual; ML610Q438/Q439 datasheet.
