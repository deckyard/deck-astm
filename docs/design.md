<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Design

## Scope

The deck implements the protocol most clinical analyzers speak to a
laboratory information system (LIS): ASTM™ E1381 / E1394, now published as
CLSI™ LIS01-A2 (the low-level link) and LIS02-A2 (the records). It serves both
ends: a LIS that receives results and answers host queries, and an instrument
simulator that sends them.

- **Records (LIS02):** any record type, delimiters read from each H record,
  escapes decoded and encoded, field / repeat / component access numbered as
  LIS02 numbers them. `results` reads P / O / R / C records into `Result`
  structs, `orders` and `queries` read O and Q records, `orderMessage` and
  `queryMessage` build the messages that send orders and answer queries.
- **Link (LIS01):** ENQ / ACK / NAK / EOT establishment, numbered frames with
  the modulo-256 checksum, records split into ETB pieces, NAK retries, busy
  NAK waits, the reply and frame timers, and contention. One `Link` type
  covers TCP (`connect`, `listen` / `accept`) and a serial port
  (`openSerial`).

The two layers stand alone: `parse` and `encode` work on record text from
any source, and `send` / `receive` move messages without the caller touching
frames.

Out of scope:

- ASTM E1238, the obsolete predecessor.
- The meaning of vendor-specific records and fields beyond pass-through:
  they are read and written as fields like any other.
- Unframed record streams over TCP, which some instruments send. Their text
  goes through `parse` directly.
- Named device profiles. The deck ships the two LIS01 profiles and nothing
  for specific products.

## Decisions

- **Strict, not lenient.** The first plan was a lenient reader that reports
  what it tolerated, because instrument interfaces deviate from their specs.
  The project stance is strict instead: a damaged frame (bad checksum, wrong
  number, wrong end, oversize, a control character in the text) is refused
  with NAK, because LIS01 says so, and records that break LIS02 are an
  error. There is no warnings list and no tolerated deviation. A device that
  differs from the standard in a documented way gets its own `Profile`.
- **`Profile` holds every device difference.** Encoding, frame size,
  retries, the reply / frame / busy / contention timers, the contention role
  and the largest transmission are fields of one struct. `profile()` gives
  LIS01's values for the computer system, `instrumentProfile()` for an
  instrument (it wins contention and waits 1 s after losing it). Values are
  range-checked when a link opens.
- **Records keep wire text.** A `Record` stores its fields as they appear on
  the wire; reading (`field`, `component`, `values`) unescapes, writing
  (`setField`, `setComponent`) escapes. An unchanged record re-encodes
  byte-identical. `field` refuses a field that has repeats or components, so
  a structured value is never silently flattened; `raw` and `setRaw` give
  access to the text as is.
- **Escapes.** `F R S E X` are decoded and encoded. `H` and `N`
  (highlighting) read as nothing. `Z` (local) has no meaning outside its
  system and throws on read; `raw` reads such a field. `setRaw` accepts every
  valid sequence.
- **Validation on output.** `message` and `encodeRecord` check each record,
  so a hand-built `Record` with a CR or a field delimiter in a field cannot
  inject records into a transmission.
- **One record per frame set.** A record longer than the frame size is split
  into ETB pieces of `frameSize` text bytes; frame numbers run across the
  whole transmission, from 1, modulo 8.
- **Contention.** When both sides send ENQ at once, the instrument wins. The
  computer side receives the instrument's transmission into an inbox, which
  the next `receive` returns, and then waits `contentionWaitMs` before its own
  ENQ. Contention counts toward `retries`.
- **EOT in reply to a frame** is taken as ACK, as LIS01 allows the sender to
  ignore the receiver's interrupt request.
- **No reader task.** The link reads a chunk under a read deadline, returns
  its first byte and queues the rest in a channel; a timeout is "no byte
  yet". Serial and TCP use the same path, with read and write deadlines on
  both. An earlier version spawned a reader task per link and paid for a task
  and channel round trip per byte.
- **Repeats are split once.** Reading every repeat of a field splits it a
  single time; calling `component` per repeat was quadratic (82 s for 16,000
  repeats). Escape decoding splits on the escape character for the same
  reason (string positions rescan non-ASCII text).
- **Pure `.j`, a deck and not core.** ASTM is a domain protocol; it builds on
  `net`, `serial`, `encoding` and `channel` and needs nothing new from the
  interpreter beyond the serial deadlines.

## Errors

Every failure is `Error{kind: "astm"}` with a message starting `astm: `,
except the kinds every library shares, which callers can handle the same way
whatever raised them:

- `"limit"`: `MAX_RECORDS` or `MAX_FIELDS` in `parse`, a transmission larger
  than the profile's `maxBytes`, too many bytes on the line while waiting for
  a frame, and a line that does not go quiet after a refused frame.
- `"timeout"`: a LIS01 timer that ran out (no reply to ENQ or to a frame
  within the reply timeout, no frame or no frame end within the frame
  timeout), and a connect or write past its deadline.
- `"closed"`: the other side closed the connection.
- `"net"`: a failed TCP connection (refused, reset, unreachable, a name
  that does not resolve) passes on unchanged as the `net.NetError` that
  `net` threw, so `op` and `reason` can be read once the kind matches.
- `"cancelled"`: a cancelled task passes on unchanged, so `task.cancel`
  stops a blocked `receive`.
- `"astm"`: everything else, including malformed records, protocol failures
  (refused more often than `retries` allows, a receiver that stays busy) and
  serial port failures that are not one of the kinds above. Messages that
  exceed the largest transmission on the way out stay `"astm"`: that is the
  caller's own input, not a cap reached on received data.

A wrapper around `net` or `serial` passes the shared kinds on as they were
thrown. Until 0.2.0 the timers and a closed connection were kind `"astm"`.

The deck throws plain `Error` values: there is no server status or code to
carry.

## Security and limits

The peer is treated as hostile; an instrument on a lab network is not trusted
to be well-formed.

- `parse` caps at `MAX_RECORDS` (4096) records and `MAX_FIELDS` (65536)
  fields, repeats and components. Uncapped, 1 MiB of empty fields took
  1.1 GB and 65,530 one-field records 656 MB, since each record is a struct
  carrying its delimiters. At the caps the worst case is roughly 70 to 130 MB.
- `DEFAULT_MAX_BYTES` (128 KiB) bounds a transmission read or sent, small
  enough that a dense legitimate transmission stays under the parse caps;
  `maxBytes` ranges from 1 KiB to 64 MiB.
- A transmission may put at most twice `maxBytes` on the line, and at most
  `retries + 1` frames in a row may be refused or repeated. The ENQ wait ends
  on time even under a stream of noise, and draining stale input drops at
  most `maxBytes`.
- STX, ENQ or EOT inside a frame cut it off, so a lost frame end cannot make
  the receiver swallow the next frame.
- A refused frame is resent only after the line has been quiet for 50 ms: a
  late ACK once shifted every following reply by one and lost a frame.
- Writes run under a deadline equal to the reply timeout, on TCP and serial.
- The deck has no credentials and no TLS: LIS01 has neither. Run it on a
  trusted segment or behind a tunnel.

## Testing and validation

- `jennifer test src/astm_test.j` runs offline. Link tests script a peer in a
  spawned task over an in-memory `pipe` link (a test-only link kind): it
  writes raw bytes, sends good final or ETB frames, logs the deck's replies
  and pauses, so damaged frames, busy NAKs, contention and timeouts are
  exercised byte by byte. One test runs a full exchange over loopback TCP.
- Frame checksums in the fixtures were computed apart from the deck, so a
  checksum bug cannot confirm itself.
- Serial has no automated test (it needs a pty pair). It was checked by hand
  through a pty null modem: a transmission arrives intact and an idle
  `receive` returns on time.
- Not tested against a real analyzer.
- Throughput over loopback TCP is about 60 KB/s on Jennifer 0.27.0, on one
  host (a 67 KB transmission of 1904 records), bounded by per-byte work and
  so machine-dependent; ample for serial at 9600 baud (about 1 KB/s).

## Known limitations and open questions

- No profiles for named analyzers; users build them from field
  documentation.
- Vendor record semantics are left to the caller.
- The cancel check still matches the old `"task cancelled"` message as a
  fallback for interpreters from before the `"cancelled"` kind; it goes at the
  next floor raise.
- Serial needs Linux™ and the default `jennifer` binary; `jennifer-tiny` lacks
  `net` and `serial`.

## Dependencies on the interpreter

Floor `>=0.27.0`, capability `net`, for the UTF-8 codecs of
`encoding.encode` / `decode` and `strings.replicate`. From `jennifer`'s
milestones:

- M28.46, serial read and write deadlines and a cancel that wakes a blocked
  `serial.read`: the LIS01 timers over serial rest on them. Found while
  writing this deck.
- M28.48, `channel.recvTimeout`, added after this deck's per-byte
  spawn-and-cancel workaround; the link no longer needs it for TCP or serial.
- M28.57, the error conventions (`"limit"` for caps, `"cancelled"` matched by
  kind), and M28.65, transport failures as `net.NetError` (kind `"net"`),
  which the link passes on.
- M29.13 and M29.11 (planned) record the costs found here: string positions
  rescanning non-ASCII text, and the size of every value, which drove the
  parse caps.
