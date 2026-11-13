<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# @deckyard/astm

Clinical laboratory instruments (chemistry, hematology and immunoassay
analyzers) report results to a laboratory information system (LIS) and
take orders from it with the ASTM protocol: ASTM E1381 for the low-level
link, ASTM E1394 for the records, today published by CLSI as LIS01-A2 and
LIS02-A2. This deck speaks both, for either side: a LIS that collects
results and answers host queries, or an instrument simulator that tests one.

The two layers stand alone. `parse` and `encode` turn record text into
messages and back, wherever the text came from (a log, a file, a socket
without the low-level protocol). `send` and `receive` move messages over TCP
or a serial port with the LIS01 handshake, frames, checksums, retries and
timers.

- [Records and messages](records.md): delimiters, fields, escapes, results,
  orders and queries.
- [Talking to an instrument](link.md): links, profiles, sending, receiving,
  and what happens when the line misbehaves.
- [Cheatsheet](cheatsheet.md): every export.

## Conventions

Snippets assume this import:

```jennifer
import "@deckyard/astm/" as astm;
```

Every failure is `Error{kind: "astm"}` with a message that names what broke
the rules. The deck is strict: input that breaks LIS01 or LIS02 is refused,
never repaired. A damaged frame is answered with NAK, as LIS01 asks, so the
sender sends it again; a transmission whose records do not parse is thrown
by `receive`. Instruments that differ from the standard in a documented way
(a larger frame, another character set, other timers) are matched with a
`Profile`, not with leniency.

```jennifer
try {
    def messages as list of astm.Message init astm.parse($text);
} catch (e) {
    io.printf("%s\n", $e.message);
}
```

The deck needs the `net` capability (TCP) and, for a serial port, Linux and
the default `jennifer` binary. It does not run on `jennifer-tiny`.
