# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# astm - messages: the LIS02 meaning of the usual records. Results read from
# P / O / R / C, orders read and built, queries read and built. Field numbers
# follow LIS02-A2; a value is the field's first component where the field
# has components, and the record stays at hand for the rest. Spliced into
# astm.j via include.

# the termination codes of an L record
def const TERMINATIONS as list of string init ["N", "T", "R", "E", "Q", "I", "F"];

# the request information status codes of a Q record
def const QUERY_STATUSES as list of string init [
    "C",
    "P",
    "F",
    "X",
    "I",
    "S",
    "M",
    "R",
    "A",
    "N",
    "O",
    "D"
];

/**
 * A result, with the patient and order it belongs to.
 *
 * @field patientId {string} P-3, the practice-assigned patient ID; `""` without a P record
 * @field sampleId {string} O-3, the specimen ID (its first component)
 * @field test {string} R-3 component 4, the manufacturer's test code (`^^^GLU`)
 * @field value {string} R-4, the measurement
 * @field units {string} R-5
 * @field flags {list of string} R-7, the abnormal flags (`L`, `H`, `N`, ...)
 * @field status {list of string} R-9, the result status (`F`, `P`, `C`, `X`, ...)
 * @field completed {string} R-13, when the test completed, `YYYYMMDDHHMMSS`
 * @field instrument {string} R-14, the instrument that measured it
 * @field record {Record} the R record, for the other fields
 * @field order {Record} its O record
 * @field comments {list of Record} the C records that follow it
 */
export def struct Result {
    patientId as string,
    sampleId as string,
    test as string,
    value as string,
    units as string,
    flags as list of string,
    status as list of string,
    completed as string,
    instrument as string,
    record as Record,
    order as Record,
    comments as list of Record
};

/**
 * A test order with its patient: what `orders` reads and `orderMessage`
 * writes.
 *
 * @field patientId {string} P-3, the practice-assigned patient ID
 * @field patientName {string} P-6 component 1, the last name
 * @field birthDate {string} P-8, `YYYYMMDD`
 * @field sex {string} P-9, `M`, `F` or `U`
 * @field sampleId {string} O-3, the specimen ID
 * @field tests {list of string} O-5, the manufacturer's test codes, one repeat each
 * @field priority {string} O-6: `S` (stat), `A` (as soon as possible), `R` (routine)
 * @field collected {string} O-8, when the specimen was collected, `YYYYMMDDHHMMSS`
 * @field action {string} O-12, the action code: `N` (new), `A` (add), `C` (cancel), `Q` (QC), ...
 * @field specimen {string} O-16 component 1, the specimen type
 * @field reportType {string} O-26: `O` (order), `Q` (response to a query), `F` (final), `X` (cancelled), ...
 */
export def struct Order {
    patientId as string,
    patientName as string,
    birthDate as string,
    sex as string,
    sampleId as string,
    tests as list of string,
    priority as string,
    collected as string,
    action as string,
    specimen as string,
    reportType as string
};

/**
 * A request for information, from a Q record.
 *
 * @field patientIds {list of string} Q-3 component 1 of each repeat
 * @field sampleIds {list of string} Q-3 component 2 of each repeat, the specimen IDs
 * @field tests {list of string} Q-5 component 4 of each repeat, `ALL` for every test
 * @field begin {string} Q-7, the start of the date range
 * @field end {string} Q-8, its end
 * @field status {string} Q-13: `O` (orders only), `F` (final results), `N` (new results), ...
 * @field record {Record} the Q record
 */
export def struct Query {
    patientIds as list of string,
    sampleIds as list of string,
    tests as list of string,
    begin as string,
    end as string,
    status as string,
    record as Record
};

/**
 * Every result in a message, in order, with the patient and order above it
 * and the comments below it.
 *
 * @param m {Message} the message
 * @return {list of Result} the results
 * @throws {Error} kind "astm" when an R record comes before any O record of its patient, or a field it reads has an invalid escape sequence
 * @example
 *   for (def r in astm.results($m)) {
 *       io.printf("%s %s = %s %s\n", $r.sampleId, $r.test, $r.value, $r.units);
 *   }
 */
export func results(m as Message) {
    def out as list of Result init [];
    def patientId as string init "";
    def order as Record init record("O", $m.delimiters);
    def haveOrder as bool init false;
    def inResult as bool init false;
    for (def r in $m.records) {
        def type as string init $r.fields[0];
        if ($type == "P") {
            $patientId = component($r, 3, 1, 1);
            $haveOrder = false;
            $inResult = false;
        } elseif ($type == "O") {
            $order = $r;
            $haveOrder = true;
            $inResult = false;
        } elseif ($type == "R") {
            if (not $haveOrder) {
                fail("an R record before any O record");
            }
            $out[] = Result{
                patientId: $patientId,
                sampleId: component($order, 3, 1, 1),
                test: component($r, 3, 1, 4),
                value: component($r, 4, 1, 1),
                units: component($r, 5, 1, 1),
                flags: values($r, 7),
                status: values($r, 9),
                completed: component($r, 13, 1, 1),
                instrument: component($r, 14, 1, 1),
                record: $r,
                order: $order,
                comments: []
            };
            $inResult = true;
        } elseif ($type == "C") {
            if ($inResult) {
                $out[len($out) - 1].comments[] = $r;
            }
        } else {
            $inResult = false;
        }
    }
    return $out;
}

/**
 * An order for a specimen, routine and new, to fill in further and pass to
 * `orderMessage`.
 *
 * @param sampleId {string} the specimen ID
 * @param tests {list of string} the manufacturer's test codes
 * @return {Order} the order, other fields empty
 * @example
 *   def o as astm.Order init astm.order("S-1001", ["GLU", "CREA"]);
 *   $o.patientId = "PAT-1";
 */
export func order(sampleId as string, tests as list of string) {
    return Order{
        patientId: "",
        patientName: "",
        birthDate: "",
        sex: "",
        sampleId: $sampleId,
        tests: $tests,
        priority: "R",
        collected: "",
        action: "N",
        specimen: "",
        reportType: "O"
    };
}

/**
 * Every order in a message, each with the patient above it.
 *
 * @param m {Message} the message
 * @return {list of Order} the orders
 * @throws {Error} kind "astm" when a field it reads has an invalid escape sequence
 */
export func orders(m as Message) {
    def out as list of Order init [];
    def p as Record init record("P", $m.delimiters);
    for (def r in $m.records) {
        def type as string init $r.fields[0];
        if ($type == "P") {
            $p = $r;
        } elseif ($type == "O") {
            $out[] = Order{
                patientId: component($p, 3, 1, 1),
                patientName: component($p, 6, 1, 1),
                birthDate: component($p, 8, 1, 1),
                sex: component($p, 9, 1, 1),
                sampleId: component($r, 3, 1, 1),
                tests: componentOfEach($r, 5, 4),
                priority: component($r, 6, 1, 1),
                collected: component($r, 8, 1, 1),
                action: component($r, 12, 1, 1),
                specimen: component($r, 16, 1, 1),
                reportType: component($r, 26, 1, 1)
            };
        }
    }
    return $out;
}

/**
 * A header record from a sender.
 *
 * @param sender {string} H-5 component 1, the sender's name
 * @param d {Delimiters} the delimiters
 * @return {Record} `H|\^&|||sender|||||||P`
 */
func headerFrom(sender as string, d as Delimiters) {
    def h as Record init record("H", $d);
    if ($sender != "") {
        $h = setComponent($h, 5, 1, 1, $sender);
    }
    return setField($h, 12, "P");
}

/**
 * A terminator record.
 *
 * @param termination {string} the termination code
 * @param d {Delimiters} the delimiters
 * @return {Record} `L|1|code`
 */
func terminatorFrom(termination as string, d as Delimiters) {
    if (not lists.contains(TERMINATIONS, $termination)) {
        fail("the termination code must be one of " + strings.join(TERMINATIONS, ", ") + ", got " +
            shown($termination));
    }
    return setField(setField(record("L", $d), 2, "1"), 3, $termination);
}

/**
 * A message that sends orders: a header, a P record for each patient (the
 * orders of one patient in a row share it) and an O record for each order.
 *
 * @param sender {string} the sender's name, H-5
 * @param orders {list of Order} the orders
 * @param termination {string} the L record's code: `N` (normal), `F` (last request for information processed), `I` (no information available), ...
 * @return {Message} the message, with the default delimiters
 * @throws {Error} kind "astm" when an order has no specimen ID or no test, or the termination code is unknown
 * @example
 *   def m as astm.Message init astm.orderMessage("LIS", [astm.order("S-1001", ["GLU"])], "N");
 */
export func orderMessage(sender as string, orders as list of Order, termination as string) {
    def d as Delimiters init delimiters(DEFAULT_DELIMITERS);
    def records as list of Record init [headerFrom($sender, $d)];
    def patients as int init 0;
    def seq as int init 0;
    def last as list of string init [];
    for (def o in $orders) {
        if ($o.sampleId == "" or len($o.tests) == 0 or lists.contains($o.tests, "")) {
            fail("an order needs a specimen ID and a test, and no empty test code");
        }
        def who as list of string init [$o.patientId, $o.patientName, $o.birthDate, $o.sex];
        if ($patients == 0 or $who != $last) {
            $patients = $patients + 1;
            $seq = 0;
            $last = $who;
            def p as Record init setField(record("P", $d), 2, convert.toString($patients));
            $p = setField($p, 3, $o.patientId);
            if ($o.patientName != "") {
                $p = setComponent($p, 6, 1, 1, $o.patientName);
            }
            $p = setField($p, 8, $o.birthDate);
            $p = setField($p, 9, $o.sex);
            $records[] = $p;
        }
        $seq = $seq + 1;
        def r as Record init setField(record("O", $d), 2, convert.toString($seq));
        $r = setField($r, 3, $o.sampleId);
        for (def i in 0..len($o.tests)) {
            $r = setComponent($r, 5, $i + 1, 4, $o.tests[$i]);
        }
        $r = setField($r, 6, $o.priority);
        $r = setField($r, 8, $o.collected);
        $r = setField($r, 12, $o.action);
        $r = setField($r, 16, $o.specimen);
        $r = setField($r, 26, $o.reportType);
        $records[] = $r;
    }
    $records[] = terminatorFrom($termination, $d);
    return message($records);
}

/**
 * Every query in a message.
 *
 * @param m {Message} the message
 * @return {list of Query} the queries
 * @throws {Error} kind "astm" when a field it reads has an invalid escape sequence
 * @example
 *   for (def q in astm.queries($m)) {
 *       io.printf("orders asked for %s\n", strings.join($q.sampleIds, ", "));
 *   }
 */
export func queries(m as Message) {
    def out as list of Query init [];
    for (def r in $m.records) {
        if ($r.fields[0] == "Q") {
            $out[] = Query{
                patientIds: componentOfEach($r, 3, 1),
                sampleIds: componentOfEach($r, 3, 2),
                tests: componentOfEach($r, 5, 4),
                begin: component($r, 7, 1, 1),
                end: component($r, 8, 1, 1),
                status: component($r, 13, 1, 1),
                record: $r
            };
        }
    }
    return $out;
}

/**
 * A message that asks for information about specimens: a header, one Q
 * record with a repeat per specimen, and a terminator.
 *
 * @param sender {string} the sender's name, H-5
 * @param sampleIds {list of string} the specimen IDs
 * @param tests {list of string} the test codes, `["ALL"]` for every test
 * @param status {string} Q-13: `O` (orders only), `F` (final results), `N` (new results), ...
 * @return {Message} the message, with the default delimiters
 * @throws {Error} kind "astm" when no specimen or test is given, or the status is unknown
 * @example
 *   def m as astm.Message init astm.queryMessage("LIS", ["S-1001"], ["ALL"], "O");
 */
export func queryMessage(
    sender as string,
    sampleIds as list of string,
    tests as list of string,
    status as string) {
    if (len($sampleIds) == 0 or len($tests) == 0) {
        fail("a query needs a specimen ID and a test");
    }
    if (not lists.contains(QUERY_STATUSES, $status)) {
        fail("the query status must be one of " + strings.join(QUERY_STATUSES, ", ") + ", got " +
            shown($status));
    }
    def d as Delimiters init delimiters(DEFAULT_DELIMITERS);
    def q as Record init setField(record("Q", $d), 2, "1");
    for (def i in 0..len($sampleIds)) {
        $q = setComponent($q, 3, $i + 1, 2, $sampleIds[$i]);
    }
    for (def i in 0..len($tests)) {
        $q = setComponent($q, 5, $i + 1, 4, $tests[$i]);
    }
    $q = setField($q, 13, $status);
    return message([headerFrom($sender, $d), $q, terminatorFrom("N", $d)]);
}
