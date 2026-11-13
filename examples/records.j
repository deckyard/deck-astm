#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * records example: the LIS02 record layer without a link. It reads the
 * results out of a message an analyzer sent, then builds the order message a
 * LIS answers a query with, and prints it one record per line.
 *
 *   jennifer run examples/records.j
 */

use io;
use strings;

import "../src/astm.j" as astm;

# what an analyzer sends for one specimen: header, patient, order, two
# results (the first with a comment), terminator; every record ends with CR
def text as string init "H|\\^&|||Analyzer^A7^2.1|||||||P||20260312094500\r" +
    "P|1|PAT-1001|||Doe^Jane||19800214|F\r" +
    "O|1|S-2001||^^^GLU\\^^^CREA|R||20260312080000||||X||||1||||||||||F\r" +
    "R|1|^^^GLU|5.4|mmol/l|3.9^6.1|N||F||auto||20260312094410|A7\r" +
    "C|1|I|21 Test limit high|I\r" +
    "R|2|^^^CREA|133|umol/l||H||F||auto||20260312094420|A7\r" +
    "L|1|N\r";

for (def m in astm.parse($text)) {
    io.printf("from %s\n", astm.component($m.records[0], 5, 1, 1));
    for (def r in astm.results($m)) {
        io.printf(
            "  %s %s: %s %s %s\n",
            $r.sampleId,
            $r.test,
            $r.value,
            $r.units,
            strings.join($r.flags, ","));
        for (def c in $r.comments) {
            io.printf("    comment: %s\n", astm.field($c, 4));
        }
    }
}

def o as astm.Order init astm.order("S-2002", ["GLU", "K"]);
$o.patientId = "PAT-1002";
$o.patientName = "Roe";
$o.priority = "S";
$o.reportType = "Q";
def reply as astm.Message init astm.orderMessage("LIS", [$o], "F");
io.printf("order reply:\n%s", strings.replace(astm.encode($reply), "\r", "\n"));
