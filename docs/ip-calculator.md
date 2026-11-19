# IPv4 Subnet Calculator for fx-991ES PLUS 2nd Edition

This guide explains how to compute network, broadcast, subnet mask, and usable host count on the Casio fx-991ES PLUS using only stock keys.

## Setup
1. **LineIO mode**: Press `SHIFT` `MODE`, select `2` (LineIO).
2. **Fix 0**: Press `SHIFT` `MODE`, select `6` (Fix), then `0`. This enables `Rnd(x-.5)` for integer floor.
3. Enter the program via `CALC` and answer prompts.
4. Press `=` to compute each result.
5. Restore `Norm` mode: `SHIFT` `MODE`, select `8` (Norm), then `1`.

## Programs

### P1: Integer Subnet Values
**Key Sequence**:
```
Rnd((16777216A+65536B+256C+D)÷2^(32-X)-.5)2^(32-X):Ans+2^(32-X)-1:2^32-2^(32-X):2^(32-X)-2
```

**Outputs**: Network, broadcast, subnet mask, and usable hosts as integers.
**Size**: ~87 bytes.
**Usage**: Enter `A`, `B`, `C`, `D` (octets), and `X` (prefix).

### P2: Network Octets (for `/24`–`/32`)
**Key Sequence**:
```
A:B:C:Rnd(D÷2^(32-X)-.5)2^(32-X)
```

**Outputs**: Four octets of the network address.
**Size**: ~29 bytes.
**Limit**: Only works for `/24`–`/32`.

### P3: Octets from Any 32-bit Integer
**Key Sequence**:
```
Rnd(T÷2^24-.5):Rnd(T÷2^16-.5)-256Rnd(T÷2^24-.5):Rnd(T÷2^8-.5)-256Rnd(T÷2^16-.5):T-256Rnd(T÷2^8-.5)
```

**Inputs**: Feed any integer from P1 (network, broadcast, or mask).
**Outputs**: Four octets.
**Size**: ~80 bytes.

## Worked Examples

| Input          | P1 Output (net, bc, mask, hosts) | Dotted Decimal          |
|----------------|----------------------------------|-------------------------|
| `192.168.1.10/24` | 3232235776, 3232236031, 4294967040, 254 | `192.168.1.0`, `192.168.1.255`, `255.255.255.0`, 254 hosts
| `10.0.0.1/8`   | 167772160, 184549375, 4278190080, 16777214 | `10.0.0.0`, `10.255.255.255`, `255.0.0.0`, 16777214 hosts
| `172.16.5.130/26` | 2886731136, 2886731199, 4294967232, 62 | `172.16.5.128`, `172.16.5.191`, `255.255.255.192`, 62 hosts
| `203.0.113.7/13` | 3405774848, 3406299135, 4294443008, 524286 | `203.0.0.0`, `203.7.255.255`, `255.248.0.0`, 524286 hosts
| `192.168.100.200/22` | 3232261120, 3232262143, 4294966272, 1022 | `192.168.100.0`, `192.168.103.255`, `255.255.252.0`, 1022 hosts
| `8.8.8.8/29`   | 134744072, 134744079, 4294967288, 6 | `8.8.8.8`, `8.8.8.15`, `255.255.255.248`, 6 hosts
| `1.2.3.4/30`   | 16909060, 16909063, 4294967292, 2 | `1.2.3.4`, `1.2.3.7`, `255.255.255.252`, 2 hosts
| `255.255.255.255/32` | 4294967295, 4294967295, 4294967295, -1 | `255.255.255.255`, `255.255.255.255`, `255.255.255.255`, -1 hosts

## Repository Map

- **README.md**: Full documentation and formulas.
- **research/findings/**: Contains findings and experimental results.
- **research/CasioEmuX/**: Scripts and tools for emulating the Casio fx-991ES PLUS.
- **docs/**: Documentation files, including this guide.

## Notes
- **Edge Cases**: `/32` yields `-1` hosts (only one address). `/31` yields `0` hosts (RFC 3021 allows 2).
- **Rounding**: Assumes `Rnd(x)` rounds half-up (away from zero). Test `Rnd(2.5)` with `Fix 0` to confirm.
- **CALC Prompts**: Order follows the first appearance of variables in the program.