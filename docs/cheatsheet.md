<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# astm cheatsheet

Every export of `@deckyard/astm`. Guides are listed in
[the introduction](index.md).

```jennifer
import "@deckyard/astm/" as astm;
```

Every failure is `Error{kind: "astm"}`, except the generic kinds: a reached
cap (more records, fields or bytes than the limits allow) is `"limit"`, a
LIS01 timer or write deadline that ran out `"timeout"`, a connection the other
side closed `"closed"`, a cancelled task `"cancelled"`, and a failed TCP
connection (refused, reset, unreachable) `net`'s `net.NetError` (kind
`"net"`, with `op` and `reason`). An `r` argument is a `Record`, an
`m` a `Message`, a `d` `Delimiters`, an `l` a `Link`, a `p` a `Profile`.
Fields, repeats and components are numbered from 1, as LIS02 numbers them:
field 1 is the record type.

## Constants

| Constant | Value | Meaning |
|---|---|---|
| `DEFAULT_DELIMITERS` | `'\|\^&'` | field `\|`, repeat `\`, component `^`, escape `&`: what most instruments use |
| `DEFAULT_FRAME_SIZE` | `240` | the most text bytes in a frame, as LIS01 sets it |
| `DEFAULT_REPLY_TIMEOUT_MS` | `15000` | how long a sender waits for a reply |
| `DEFAULT_FRAME_TIMEOUT_MS` | `30000` | how long a receiver waits for the next frame |
| `DEFAULT_MAX_BYTES` | `131072` | the largest transmission read or sent: 128 KiB, over a thousand results |
| `MAX_FIELDS` | `65536` | the most fields, repeats and components `parse` reads in one call |
| `MAX_RECORDS` | `4096` | the most records `parse` reads in one call |

## Records and messages

| Function | Returns | Does |
|---|---|---|
| `astm.delimiters(definition)` | `Delimiters` | the delimiters of a four-character definition such as `DEFAULT_DELIMITERS` |
| `astm.parse(text)` | `list of Message` | every message in record text, each from H to L, every record ended by CR; at most `MAX_RECORDS` records and `MAX_FIELDS` fields, repeats and components |
| `astm.message(records)` | `Message` | a message from records, checked: H first, L last, one set of delimiters, every record valid |
| `astm.encode(m)` | `string` | the message as text, every record followed by CR |
| `astm.encodeRecord(r)` | `string` | one record as text, without its CR; an invalid record is an error |
| `astm.record(type, d)` | `Record` | a new record of a type (`H` gets its delimiters as field 2) |
| `astm.recordType(r)` | `string` | the record's type, field 1 |

## Fields

| Function | Returns | Does |
|---|---|---|
| `astm.field(r, n)` | `string` | field n unescaped; a field with repeats or components is an error |
| `astm.raw(r, n)` | `string` | field n as on the wire, still escaped |
| `astm.repeats(r, n)` | `int` | how many repeats field n has, 0 when empty |
| `astm.components(r, n, rep)` | `list of string` | the components of one repeat, unescaped |
| `astm.component(r, n, rep, component)` | `string` | one component of one repeat, unescaped, `""` when absent |
| `astm.values(r, n)` | `list of string` | the first component of every repeat: a code field such as `F\R` |
| `astm.setField(r, n, value)` | `Record` | set field n to a value, escaping its delimiters |
| `astm.setComponent(r, n, rep, component, value)` | `Record` | set one component, escaping, adding empty repeats and components before it |
| `astm.setRaw(r, n, text)` | `Record` | set field n's wire text as given, checked |

## Results, orders, queries

| Function | Returns | Does |
|---|---|---|
| `astm.results(m)` | `list of Result` | every result, with its patient, order and comments |
| `astm.order(sampleId, tests)` | `Order` | a routine new order for a specimen, to fill in further |
| `astm.orders(m)` | `list of Order` | every order, with its patient |
| `astm.orderMessage(sender, orders, termination)` | `Message` | a message sending orders; the orders of one patient share a P record |
| `astm.queries(m)` | `list of Query` | every request for information |
| `astm.queryMessage(sender, sampleIds, tests, status)` | `Message` | a message asking about specimens |

## The link

| Function | Returns | Does |
|---|---|---|
| `astm.profile()` | `Profile` | LIS01's values for the computer system (the LIS) |
| `astm.instrumentProfile()` | `Profile` | LIS01's values for an instrument, which wins contention |
| `astm.connect(address, p)` | `Link` | connect over TCP as a client |
| `astm.listen(address)` | `net.Listener` | listen over TCP as a server |
| `astm.accept(listener, p)` | `Link` | wait for the other side to connect |
| `astm.openSerial(path, options, p)` | `Link` | open a serial port (Linux™, default `jennifer` binary) |
| `astm.send(l, messages)` | `null` | send messages in one transmission: ENQ, frames, EOT |
| `astm.receive(l, waitMs)` | `list of Message` | receive the next transmission; empty when none began in time |
| `astm.close(l)` | `null` | close the link |

## Types

### `Delimiters`

| Field | Meaning |
|---|---|
| `field as string` | between fields, usually `\|` |
| `repetition as string` | between repeats, usually `\` |
| `component as string` | between components, usually `^` |
| `escape as string` | opens and closes an escape sequence, usually `&` |

### `Record`

| Field | Meaning |
|---|---|
| `fields as list of string` | the fields as on the wire, field n at index n - 1 |
| `delimiters as Delimiters` | the delimiters of its message |

### `Message`

| Field | Meaning |
|---|---|
| `delimiters as Delimiters` | the delimiters its header declares |
| `records as list of Record` | every record, H first and L last |

### `Result`

| Field | Meaning |
|---|---|
| `patientId as string` | P-3, `""` without a P record |
| `sampleId as string` | O-3, the specimen ID |
| `test as string` | R-3 component 4, the manufacturer's test code |
| `value as string` | R-4, the measurement |
| `units as string` | R-5 |
| `flags as list of string` | R-7, the abnormal flags |
| `status as list of string` | R-9, the result status |
| `completed as string` | R-13, `YYYYMMDDHHMMSS` |
| `instrument as string` | R-14 |
| `record as Record` | the R record |
| `order as Record` | its O record |
| `comments as list of Record` | the C records after it |

### `Order`

| Field | Meaning |
|---|---|
| `patientId as string` | P-3 |
| `patientName as string` | P-6 component 1, the last name |
| `birthDate as string` | P-8, `YYYYMMDD` |
| `sex as string` | P-9 |
| `sampleId as string` | O-3 |
| `tests as list of string` | O-5 component 4, one repeat each |
| `priority as string` | O-6: `S`, `A` or `R` |
| `collected as string` | O-8, `YYYYMMDDHHMMSS` |
| `action as string` | O-12: `N`, `A`, `C`, `Q`, ... |
| `specimen as string` | O-16 component 1 |
| `reportType as string` | O-26: `O`, `Q`, `F`, `X`, ... |

### `Query`

| Field | Meaning |
|---|---|
| `patientIds as list of string` | Q-3 component 1 of each repeat |
| `sampleIds as list of string` | Q-3 component 2 of each repeat |
| `tests as list of string` | Q-5 component 4 of each repeat, `ALL` for every test |
| `begin as string` | Q-7 |
| `end as string` | Q-8 |
| `status as string` | Q-13 |
| `record as Record` | the Q record |

### `Profile`

| Field | Meaning |
|---|---|
| `instrument as bool` | this side is the instrument and wins contention |
| `encoding as string` | the character set: `iso-8859-1`, `windows-1252`, `ascii`, `utf-8`, ... |
| `frameSize as int` | the most text bytes in a frame, both ways, 1 to 64000 |
| `retries as int` | how often a refused frame is sent again, and busy NAKs waited out, 0 to 100 |
| `replyTimeoutMs as int` | how long a sender waits for a reply |
| `frameTimeoutMs as int` | how long a receiver waits for the next frame |
| `busyWaitMs as int` | how long a sender waits after a busy NAK |
| `contentionWaitMs as int` | how long the side that lost contention waits before its next ENQ |
| `maxBytes as int` | the largest transmission, 1024 to 67108864 bytes |

### `Link`

| Field | Meaning |
|---|---|
| `kind as string` | `tcp` or `serial` |
| `conn as net.Conn` | the socket of a `tcp` link |
| `port as serial.Port` | the port of a `serial` link |
| `input as channel of int` | the bytes read |
| `output as channel of int` | unused outside the tests |
| `inbox as channel of string` | transmissions received while sending |
| `profile as Profile` | how this side behaves |
