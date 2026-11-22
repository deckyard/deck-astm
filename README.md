# @deckyard/astm

[![test](https://github.com/deckyard/deck-astm/actions/workflows/test.yml/badge.svg)](https://github.com/deckyard/deck-astm/actions/workflows/test.yml)
[![Documentation](https://img.shields.io/badge/docs-github%20pages-blue)](https://deckyard.github.io/deck-astm/)
[![release](https://img.shields.io/github/v/release/deckyard/deck-astm)](https://github.com/deckyard/deck-astm/releases/latest)

The ASTM protocol of clinical laboratory instruments for
[Jennifer](https://jennifer-lang.dev/) programs: ASTM E1381 / E1394, now
CLSI LIS01-A2 (the low-level link) and LIS02-A2 (the records). Parse and
build records and messages; read results, orders and host queries; answer
queries with orders; and move messages over TCP or a serial port with the
LIS01 handshake, framing, checksums, retries, timers and contention, for a
LIS or for an instrument simulator. Strict: a damaged frame is refused with
NAK, records that break LIS02 are an error, and a device that differs from
the standard in a documented way gets a `Profile`, not leniency.

**[Documentation](https://deckyard.github.io/deck-astm/)**

## Install

```sh
jvc add @deckyard/astm
```

This vendors the deck to `vendor/<scope>/astm/`. Without `jvc`, unpack the
`src/` subtree of a release archive (`<scope>-astm-<version>.tar.gz`) there.

## Usage

```jennifer
use io;

import "@deckyard/astm/" as astm;

def link as astm.Link init astm.accept(astm.listen(":4001"), astm.profile());
for (def m in astm.receive($link, 60000)) {
    for (def r in astm.results($m)) {
        io.printf("%s %s = %s %s\n", $r.sampleId, $r.test, $r.value, $r.units);
    }
}
astm.close($link);
```

## Requirements

Jennifer 0.27.0 or newer and the default `jennifer` binary: the deck needs
`net`, which the stock `jennifer-tiny` lacks. A serial port needs Linux.

## Development

```sh
tools/check-all.sh                   # the full gate, as CI runs it
jennifer test src/astm_test.j        # the tests, against a scripted peer
tools/check-docs.sh                  # docs against the code
tools/pack.sh dist                   # build the release archive
```

## Licence

LGPL-3.0-only, see [LICENSE](LICENSE). Copyright (C) 2026 mplx &lt;mplx@jennifer-lang.dev&gt;.

`tools/check-headers.sh` checks every source file's SPDX header against
`deck.toml`.
