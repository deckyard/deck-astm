<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Talking to an instrument

LIS01 moves messages over a serial line, and over TCP the same way: the
socket replaces the line, every byte of the protocol stays.

## Links

Over TCP either side may be the server. Most analyzers can be set to either
mode; the LIS usually listens:

```jennifer
def server as net.Listener init astm.listen(":4001");
def link as astm.Link init astm.accept($server, astm.profile());
```

or connects:

```jennifer
def link as astm.Link init astm.connect("10.0.0.20:4001", astm.profile());
```

A serial port needs Linux and the default `jennifer` binary. LIS01's line
settings are 9600 baud, 8 data bits, no parity, 1 stop bit, no flow
control:

```jennifer
def link as astm.Link init astm.openSerial(
    "/dev/ttyUSB0", serial.Options{baud: 9600}, astm.profile());
```

`close` ends a link. After any error from `send` or `receive` the state of
the line is unknown: close the link and open a new one.

## Receiving

`receive` waits for the other side's ENQ, answers ACK, takes frames until
EOT and returns the messages they carry. It returns an empty list when no
transmission began within the wait, so a LIS loops on it:

```jennifer
while (true) { # serves until the program is stopped # lint-disable: L105
    for (def m in astm.receive($link, 60000)) {
        for (def r in astm.results($m)) {
            io.printf("%s %s = %s\n", $r.sampleId, $r.test, $r.value);
        }
    }
}
```

Each frame is checked: its number, its ETX or ETB, its checksum (two
upper-case hex digits), its CR LF end, no control character in its text,
and its size. A frame that fails is answered with NAK and the sender sends
it again; a frame sent twice (its ACK was lost) is acknowledged and kept
once. Bytes outside frames are line noise and skipped; an STX, ENQ or EOT
inside a frame cuts it off. The wait for the ENQ ends on time whatever
noise arrives. The transmission fails when no frame follows within the
frame timeout (30 s), when it ends inside a record, when its text exceeds
`maxBytes` or the line carries more than twice that (noise, refused frames),
when more than `retries + 1` frames in a row are refused or repeated, or
when its records do not parse (more than `MAX_RECORDS` records or
`MAX_FIELDS` fields, repeats and components is refused too).

## Sending

`send` sends messages in one transmission: ENQ, a frame per record (a record
longer than the frame size is split into ETB frames), EOT.

```jennifer
astm.send($link, [astm.orderMessage("LIS", $orders, "N")]);
```

A frame answered with NAK, or with anything but ACK or EOT, is sent again,
up to `retries` (6) times, once the line has been quiet for 50 ms, so a
late ACK to the first copy is not taken as the reply to the second. A NAK
to the ENQ means the receiver is busy and is waited out (`busyWaitMs`,
10 s) as often. No reply within the reply
timeout (15 s) ends the transmission with EOT and fails with kind
`"timeout"`. An EOT in reply to
a frame is the receiver asking to stop; LIS01 lets a sender carry on, and
`send` does, taking it as the ACK.

## Contention

When both sides send ENQ at once, the instrument goes first. With
`profile()` (the LIS) `send` then receives the instrument's transmission,
keeps it for the next `receive`, waits `contentionWaitMs` (20 s) and sends.
With `instrumentProfile()` it waits 1 s and sends its ENQ again. Either
gives up after `retries` contentions in a row (a line that echoes, or two
instruments), sending EOT.

## Profiles

A `Profile` holds every setting of the link. `profile()` and
`instrumentProfile()` give LIS01's values; change a field to match a device
whose manual says otherwise:

```jennifer
def p as astm.Profile init astm.profile();
$p.encoding = "windows-1252";   # the analyzer sends 8-bit Windows text
$p.frameSize = 64000;           # it sends a whole record in one frame over TCP
def link as astm.Link init astm.connect("10.0.0.20:4001", $p);
```

| Field | LIS01 value | Matches |
|---|---|---|
| `encoding` | `iso-8859-1` | the character set of the text |
| `frameSize` | 240 | the largest frame text, both ways |
| `retries` | 6 | frames sent again, busy NAKs waited out |
| `replyTimeoutMs` | 15000 | how long a sender waits for a reply |
| `frameTimeoutMs` | 30000 | how long a receiver waits for a frame |
| `busyWaitMs` | 10000 | the pause after a busy NAK |
| `contentionWaitMs` | 20000 / 1000 | the pause after losing contention |
| `maxBytes` | 128 KiB | the largest transmission |

Everything else is LIS01 as written. The profile is checked when a link is
opened.
