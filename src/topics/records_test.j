# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# astm - white-box tests for the records topic. Spliced into astm_test.j via
# include.

# a result message from an instrument, records joined by CR
def const SAMPLE as string init "H|\\^&|||Analyzer^A7^2.1|||||||P||20260312094500\r" +
    "P|1|PAT-1001|||Doe^Jane||19800214|F\r" +
    "O|1|S-2001^1^4||^^^GLU\\^^^CREA|R||20260312080000||||X||||1||||||||||F\r" +
    "R|1|^^^GLU^1|5.4|mmol/l|3.9^6.1|N||F\\R||auto||20260312094410|A7\r" +
    "C|1|I|21 Test limit high|I\r" +
    "R|2|^^^CREA^1|133|umol/l||H||F||auto||20260312094420|A7\r" +
    "L|1|N\r";

/**
 * The message of the error a parse throws.
 *
 * @param text {string} the text
 * @return {string} the error's message, `""` when it parsed
 */
func parseError(text as string) {
    try {
        parse($text);
    } catch (e) {
        testing.assertEqual($e.kind, "astm");
        return $e.message;
    }
    return "";
}

func testDelimitersAreReadFromTheHeader() {
    def ms as list of Message init parse("H!~*%\rP!1!A~B*C!x%F%y\rL!1\r");
    def d as Delimiters init $ms[0].delimiters;
    testing.assertEqual($d.field + $d.repetition + $d.component + $d.escape, "!~*%");
    def p as Record init $ms[0].records[1];
    testing.assertEqual(repeats($p, 3), 2);
    testing.assertEqual(component($p, 3, 2, 2), "C");
    testing.assertEqual(field($p, 4), "x!y");
    testing.assertEqual(field($ms[0].records[0], 2), "~*%");
}

func testDelimitersAreChecked() {
    for (def bad in ["|\\^", "||^&", "|\\^a", "| ^&", "|\\^&&", "|\\^é"]) {
        try {
            delimiters($bad);
            missed($bad);
        } catch (e) {
            testing.assertEqual($e.kind, "astm");
        }
    }
    testing.assertEqual(delimiters(DEFAULT_DELIMITERS).escape, "&");
}

func testParseSplitsMessages() {
    def ms as list of Message init parse(SAMPLE + "H|\\^&\rQ|1|^S-9||^^^ALL||||||||O\rL|1|N\r");
    testing.assertEqual(len($ms), 2);
    testing.assertEqual(len($ms[0].records), 7);
    testing.assertEqual(recordType($ms[1].records[1]), "Q");
    testing.assertEqual(encode($ms[0]), SAMPLE);
}

func testParseRefusesWhatBreaksTheRules() {
    testing.assertContains(parseError(""), "no records");
    testing.assertContains(parseError("H|\\^&\rL|1"), "does not end with a CR");
    testing.assertContains(parseError("P|1\rL|1\r"), "record 1: no header");
    testing.assertContains(parseError("H|\\^&\rH|\\^&\rL|1\r"), "record 2: a header before the L");
    testing.assertContains(parseError("H|\\^&\rP|1\r"), "has no L record");
    testing.assertContains(parseError("H|\\^&\r\rL|1\r"), "an empty record");
    testing.assertContains(parseError("H|\\^&\rP|1|a\nb\rL|1\r"), "control character");
    testing.assertContains(parseError("H|\\^&\rp|1\rL|1\r"), "one upper-case letter");
    testing.assertContains(parseError("H|\\^\rL|1\r"), "without its delimiters");
    testing.assertContains(parseError("H|\\^&\rL|1\rP|1\r"), "record 3: no header");
    testing.assertEqual(parseError(SAMPLE), "");
}

func testParseCapsWhatItHolds() {
    testing.assertEqual(
        parseError("H|\\^&\rP" + strings.repeat("|", MAX_FIELDS) + "\rL|1\r"),
        "astm: more than 65536 fields, repeats and components");
    testing.assertEqual(
        parseError(strings.repeat("\r", MAX_RECORDS + 1)),
        "astm: more than 4096 records");
    testing.assertEqual(
        parseError("H|\\^&\rP" + strings.repeat("|", MAX_FIELDS - 7) + "\rL|1\r"),
        "");
}

func testFieldsRepeatsAndComponents() {
    def m as Message init parse(SAMPLE)[0];
    def o as Record init $m.records[2];
    def r as Record init $m.records[3];
    testing.assertEqual(raw($o, 5), "^^^GLU\\^^^CREA");
    testing.assertEqual(repeats($o, 5), 2);
    testing.assertEqual(component($o, 5, 2, 4), "CREA");
    testing.assertEqual(components($o, 3, 1), ["S-2001", "1", "4"]);
    testing.assertEqual(components($o, 3, 2), []);
    testing.assertEqual(component($o, 3, 1, 9), "");
    testing.assertEqual(values($r, 9), ["F", "R"]);
    testing.assertEqual(values($r, 8), []);
    testing.assertEqual(field($r, 5), "mmol/l");
    testing.assertEqual(field($r, 40), "");
    testing.assertEqual(raw($r, 40), "");
    try {
        field($r, 6);
        missed("components through field");
    } catch (e) {
        testing.assertContains($e.message, "field 6 of the R record has repeats or components");
    }
    for (def n in [0, -1]) {
        try {
            raw($r, $n);
            missed("field " + convert.toString($n));
        } catch (e) {
            testing.assertContains($e.message, "fields are numbered from 1");
        }
    }
    try {
        components($m.records[0], 2, 1);
        missed("the definition");
    } catch (e) {
        testing.assertContains($e.message, "delimiter definition");
    }
}

func testEscapesAreDecoded() {
    def d as Delimiters init delimiters(DEFAULT_DELIMITERS);
    testing.assertEqual(unescaped("a&F&b&S&c&R&d&E&e", $d), "a|b^c\\d&e");
    testing.assertEqual(unescaped("line&X0D0A&next", $d), "line\r\nnext");
    testing.assertEqual(unescaped("&XB5&g", $d), "µg");
    for (def bad in ["a&F", "&Z12&", "&X1&", "&&", "&XGG&"]) {
        try {
            unescaped($bad, $d);
            missed($bad);
        } catch (e) {
            testing.assertEqual($e.kind, "astm");
        }
    }
}

func testValuesAreEscaped() {
    def d as Delimiters init delimiters(DEFAULT_DELIMITERS);
    def value as string init "a|b^c\\d&e\r" + convert.fromCodepoint(1) + "x";
    def r as Record init setField(record("C", $d), 4, $value);
    testing.assertEqual(raw($r, 4), "a&F&b&S&c&R&d&E&e&X0D&&X01&x");
    testing.assertEqual(field($r, 4), $value);
    testing.assertEqual(escaped("plain text", $d), "plain text");
}

func testRecordsAreBuilt() {
    def d as Delimiters init delimiters(DEFAULT_DELIMITERS);
    def h as Record init record("H", $d);
    testing.assertEqual(encodeRecord($h), "H|\\^&");
    def o as Record init setField(record("O", $d), 2, "1");
    $o = setComponent($o, 5, 2, 4, "CREA");
    $o = setComponent($o, 5, 1, 4, "GLU");
    $o = setComponent($o, 3, 1, 2, "a^b");
    testing.assertEqual(encodeRecord($o), "O|1|^a&S&b||^^^GLU\\^^^CREA");
    $o = setField($o, 30, "");
    testing.assertEqual(len($o.fields), 5);
    $o = setRaw($o, 6, "S\\R");
    testing.assertEqual(values($o, 6), ["S", "R"]);
    for (def bad in ["a|b", "a&Q&", "a\rb"]) {
        try {
            setRaw($o, 7, $bad);
            missed($bad);
        } catch (e) {
            testing.assertEqual($e.kind, "astm");
        }
    }
    try {
        setField($o, 1, "R");
        missed("field 1");
    } catch (e) {
        testing.assertContains($e.message, "field 1 is the record type");
    }
    try {
        setField($h, 2, "x");
        missed("the definition");
    } catch (e) {
        testing.assertContains($e.message, "delimiter definition");
    }
    try {
        record("Rx", $d);
        missed("Rx");
    } catch (e) {
        testing.assertContains($e.message, "one upper-case letter");
    }
}

func testMessageChecksItsRecords() {
    def d as Delimiters init delimiters(DEFAULT_DELIMITERS);
    def h as Record init record("H", $d);
    def l as Record init setField(record("L", $d), 2, "1");
    def p as Record init record("P", $d);
    testing.assertEqual(encode(message([$h, $p, $l])), "H|\\^&\rP\rL|1\r");
    def other as Record init record("P", delimiters("!~*%"));
    for (def bad in [[$h], [$p, $l], [$h, $p], [$h, $h, $l], [$h, $l, $l], [$h, $other, $l]]) {
        try {
            message($bad);
            missed("a bad message");
        } catch (e) {
            testing.assertEqual($e.kind, "astm");
        }
    }
}

func testRepeatsAreReadInLinearTime() {
    def text as string init "H|\\^&\rO|1|S\rR|1|^^^A|1|u||N||" + strings.repeat("F\\", 50000) +
        "F\rL|1|N\r";
    def started as time.Time init time.now();
    def found as list of Result init results(parse($text)[0]);
    testing.assertEqual(len($found[0].status), 50001);
    testing.assertTrue(time.milliseconds(time.sub(time.now(), $started)) < 5000);
}

func testRecordsMustEncodeAsOne() {
    def d as Delimiters init delimiters(DEFAULT_DELIMITERS);
    def h as Record init record("H", $d);
    def l as Record init record("L", $d);
    for (def bad in [
        Record{fields: ["P", "a\rP|evil"], delimiters: $d},
        Record{fields: ["P", "x|y"], delimiters: $d},
        Record{fields: ["P", "&Q&"], delimiters: $d},
        Record{fields: ["p"], delimiters: $d},
        Record{fields: [], delimiters: $d}
    ]) {
        try {
            message([$h, $bad, $l]);
            missed("an invalid record");
        } catch (e) {
            testing.assertEqual($e.kind, "astm");
        }
        try {
            encodeRecord($bad);
            missed("an invalid record");
        } catch (e) {
            testing.assertEqual($e.kind, "astm");
        }
    }
    try {
        recordType(Record{fields: [], delimiters: $d});
        missed("no fields");
    } catch (e) {
        testing.assertContains($e.message, "a record without fields");
    }
}

func testHighlightAndLocalEscapes() {
    def r as Record init parse("H|\\^&\rC|1|I|&H&bold&N& text|I\rC|2|I|a&Z1b&c|I\rL|1\r")[0].records[1];
    testing.assertEqual(field($r, 4), "bold text");
    def local as Record init parse("H|\\^&\rC|2|I|a&Z1b&c|I\rL|1\r")[0].records[1];
    testing.assertEqual(raw($local, 4), "a&Z1b&c");
    try {
        field($local, 4);
        missed("a local escape");
    } catch (e) {
        testing.assertContains($e.message, "has no meaning outside its system");
    }
    def d as Delimiters init delimiters(DEFAULT_DELIMITERS);
    testing.assertEqual(raw(setRaw(record("C", $d), 4, "&H&x&N&&Zq&"), 4), "&H&x&N&&Zq&");
}

func testEmptyComponentsAddNothing() {
    def d as Delimiters init delimiters(DEFAULT_DELIMITERS);
    def r as Record init setComponent(record("O", $d), 5, 3, 1, "");
    testing.assertEqual(encodeRecord($r), "O");
}

func testParseRefusesInvalidEscapes() {
    for (def bad in ["C|1|I|&Q&", "C|1|I|a&b", "C|1|I|&Za^b&"]) {
        testing.assertContains(parseError("H|\\^&\r" + $bad + "\rL|1\r"), "escape sequence");
    }
    def started as time.Time init time.now();
    def r as Record init parse("H|\\^&\rC|1|I|" + strings.repeat("é&H&", 20000) + "|I\rL|1\r")[0].records[1];
    testing.assertEqual(len(field($r, 4)), 20000);
    testing.assertTrue(time.milliseconds(time.sub(time.now(), $started)) < 5000);
}
