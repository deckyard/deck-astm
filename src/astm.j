# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0
# pragma-jennifer-capability: net

/**
 * The protocol clinical laboratory instruments speak to a laboratory
 * information system (LIS): ASTM E1381 / E1394, now CLSI LIS01-A2 (the
 * low-level protocol) and LIS02-A2 (the records). Both layers stand alone:
 * `parse` and `encode` work on record text from anywhere, `send` and
 * `receive` move messages over TCP or a serial port.
 *
 * Records keep their fields as they are on the wire; `field`, `component`
 * and `values` read them unescaped, `setField` and `setComponent` write
 * them escaped. `results`, `orders` and `queries` read the usual records
 * into structs, `orderMessage` and `queryMessage` build messages. The link
 * follows LIS01: ENQ / ACK establishment, numbered frames with checksums,
 * NAK and retries, the 15 s and 30 s timers, and contention, all set in a
 * `Profile` for devices that differ. Input that breaks the rules is an
 * error, never repaired: a damaged frame is refused with NAK, as LIS01 asks,
 * and a transmission that does not parse is thrown. Every failure is
 * `Error{kind: "astm"}`.
 *
 * | topic | covers |
 * | --- | --- |
 * | `core` | errors, the control characters |
 * | `records` | delimiters, escapes, fields, records, messages |
 * | `messages` | results, orders, queries |
 * | `link` | profiles, TCP and serial links, sending and receiving |
 *
 * @module astm
 * @see https://clsi.org/standards/products/automation-and-informatics/documents/lis01/
 * @see https://clsi.org/standards/products/automation-and-informatics/documents/lis02/
 * @example
 *   def link as astm.Link init astm.accept(astm.listen(":4001"), astm.profile());
 *   while (true) {
 *       for (def m in astm.receive($link, 60000)) {
 *           for (def r in astm.results($m)) {
 *               io.printf("%s %s = %s %s\n", $r.sampleId, $r.test, $r.value, $r.units);
 *           }
 *       }
 *   }
 */
use binary;
use channel;
use convert;
use encoding;
use io;
use lists;
use net;
use regex;
use serial;
use strings;
use task;
use time;

include "topics/core.j";
include "topics/records.j";
include "topics/messages.j";
include "topics/link.j";
