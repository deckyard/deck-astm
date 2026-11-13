#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * lis example: a small LIS for one analyzer over TCP. It listens, takes the
 * analyzer's connection, prints every result it sends, and answers each
 * host query with the orders it knows for the specimen (or "no information"
 * when it knows none).
 *
 *   jennifer run examples/lis.j :4001
 *
 * Point the analyzer's LIS connection, in client mode, at this machine and
 * port. Without arguments it prints this usage, so CI runs it without an
 * analyzer.
 */

use io;
use maps;
use net;
use os;
use strings;

import "../src/astm.j" as astm;

def args as list of string init os.ARGS;
if (len($args) != 2) {
    io.printf("usage: jennifer run examples/lis.j <[host]:port>\n");
    exit 0;
}

# the tests this LIS orders, by specimen ID
def worklist as map of string to list of string init {
    "S-1001": ["GLU", "CREA"],
    "S-1002": ["K", "NA", "CL"]
};

/**
 * The reply to a query: the orders known for its specimens.
 *
 * @param q {astm.Query} the query
 * @return {astm.Message} the reply
 */
func answer(q as astm.Query) {
    def found as list of astm.Order init [];
    for (def id in $q.sampleIds) {
        if (maps.has($worklist, $id)) {
            def o as astm.Order init astm.order($id, $worklist[$id]);
            $o.reportType = "Q";
            $found[] = $o;
        }
    }
    if (len($found) == 0) {
        return astm.orderMessage("LIS", $found, "I");
    }
    return astm.orderMessage("LIS", $found, "F");
}

try {
    def server as net.Listener init astm.listen($args[1]);
    io.printf("waiting for the analyzer on %s\n", net.address($server));
    def link as astm.Link init astm.accept($server, astm.profile());
    io.printf("connected\n");
    while (true) { # a LIS serves until it is stopped # lint-disable: L105
        for (def m in astm.receive($link, 60000)) {
            for (def r in astm.results($m)) {
                io.printf("%s %s = %s %s\n", $r.sampleId, $r.test, $r.value, $r.units);
            }
            for (def q in astm.queries($m)) {
                io.printf("query for %s\n", strings.join($q.sampleIds, ", "));
                astm.send($link, [answer($q)]);
            }
        }
    }
} catch (e) {
    io.eprintf("%s\n", $e.message);
    exit 1;
}
