# Ubermensch LMAOBox

[![CI](https://github.com/maloucaze/ubermensch-lmaobox/actions/workflows/ci.yml/badge.svg)](https://github.com/maloucaze/ubermensch-lmaobox/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/maloucaze/ubermensch-lmaobox?sort=semver)](https://github.com/maloucaze/ubermensch-lmaobox/releases/latest)
[![Lua](https://img.shields.io/badge/Lua-5.1%20%7C%205.4-2C2D72?logo=lua&logoColor=white)](https://www.lua.org/)
[![License: MIT](https://img.shields.io/github/license/maloucaze/ubermensch-lmaobox)](LICENSE)
![Platform: Windows](https://img.shields.io/badge/platform-Windows-0078D4?logo=windows&logoColor=white)

Ubermensch is a self-contained LMAOBox HUD for comparing the selected Stock or
Kritzkrieg charge on each TF2 team. It shows charge, whole-second time-to-ready,
the local team's Uber advantage, and the alive-player counts in a
compact four-line display:

```text
RED | 50% | 20s | STOCK
BLU | 50% | 20s | STOCK
EQL |  0% |  0s
12 vs. 12
```

Numeric columns are dynamically right-aligned and use whole numbers.
Approximate charge and readiness values use `~`; incomplete sides use `-` for
readiness. Confirmed absence and a retained known Medic death use compact gray
`TEAM | NO MED` and `TEAM | DEAD MED` lines. The full behavior is defined in
[`SPECIFICATION.md`](SPECIFICATION.md).

A thin separator divides the Uber information from the last line. That line is
always local-team first, remains white, and shows only `N vs. M` without
classifying the numerical difference. If authoritative roster data is
unavailable, it displays `- vs. -` rather than retaining potentially stale
counts.
