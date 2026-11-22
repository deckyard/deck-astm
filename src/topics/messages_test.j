# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# astm - white-box tests for the messages topic. Spliced into astm_test.j via
# include.

func testResultsCarryTheirPatientOrderAndComments() {
    def found as list of Result init results(parse(SAMPLE)[0]);
    testing.assertEqual(len($found), 2);
    def glu as Result init $found[0];
    testing.assertEqual($glu.patientId, "PAT-1001");
    testing.assertEqual($glu.sampleId, "S-2001");
    testing.assertEqual($glu.test, "GLU");
    testing.assertEqual($glu.value, "5.4");
    testing.assertEqual($glu.units, "mmol/l");
    testing.assertEqual($glu.flags, ["N"]);
    testing.assertEqual($glu.status, ["F", "R"]);
    testing.assertEqual($glu.completed, "20260312094410");
    testing.assertEqual($glu.instrument, "A7");
    testing.assertEqual(component($glu.record, 6, 1, 2), "6.1");
    testing.assertEqual(len($glu.comments), 1);
    testing.assertEqual(field($glu.comments[0], 4), "21 Test limit high");
    testing.assertEqual($found[1].test, "CREA");
    testing.assertEqual($found[1].flags, ["H"]);
    testing.assertEqual(len($found[1].comments), 0);
    testing.assertEqual(component($found[1].order, 3, 1, 3), "4");
}

func testResultsFollowEachPatient() {
    def text as string init "H|\\^&\rP|1|A\rO|1|S1\rR|1|^^^K|4.1\rP|2|B\rO|1|S2\rR|1|^^^NA|140\r" +
        "C|1|I|x|I\rL|1|N\r";
    def found as list of Result init results(parse($text)[0]);
    testing.assertEqual(len($found), 2);
    testing.assertEqual($found[0].patientId + "/" + $found[0].sampleId, "A/S1");
    testing.assertEqual($found[1].patientId + "/" + $found[1].sampleId, "B/S2");
    testing.assertEqual(len($found[1].comments), 1);
    testing.assertEqual(len(results(parse("H|\\^&\rP|1|A\rL|1|N\r")[0])), 0);
    try {
        results(parse("H|\\^&\rP|1|A\rR|1|^^^K|4.1\rL|1|N\r")[0]);
        missed("an R without an O");
    } catch (e) {
        testing.assertContains($e.message, "an R record before any O record");
    }
}

func testOrderMessagesGroupPatients() {
    def a as Order init order("S-1", ["GLU", "CREA"]);
    $a.patientId = "PAT-1";
    $a.patientName = "Doe";
    $a.birthDate = "19800214";
    $a.sex = "F";
    $a.priority = "S";
    def b as Order init $a;
    $b.sampleId = "S-2";
    $b.tests = ["K"];
    def c as Order init order("S-3", ["NA"]);
    def m as Message init orderMessage("LIS", [$a, $b, $c], "N");
    testing.assertEqual(
        encode($m),
        "H|\\^&|||LIS|||||||P\r" +
            "P|1|PAT-1|||Doe||19800214|F\r" +
            "O|1|S-1||^^^GLU\\^^^CREA|S||||||N||||||||||||||O\r" +
            "O|2|S-2||^^^K|S||||||N||||||||||||||O\r" +
            "P|2\r" +
            "O|1|S-3||^^^NA|R||||||N||||||||||||||O\r" +
            "L|1|N\r");
    def back as list of Order init orders(parse(encode($m))[0]);
    testing.assertEqual(len($back), 3);
    testing.assertEqual($back[0], $a);
    testing.assertEqual($back[1], $b);
    testing.assertEqual($back[2], $c);
}

func testOrderMessagesAreChecked() {
    for (def bad in [order("", ["GLU"]), order("S-1", []), order("S-1", ["GLU", ""])]) {
        try {
            orderMessage("LIS", [$bad], "N");
            missed("a bad order");
        } catch (e) {
            testing.assertContains($e.message, "an order needs a specimen ID and a test");
        }
    }
    try {
        orderMessage("LIS", [order("S-1", ["GLU"])], "Z");
        missed("termination Z");
    } catch (e) {
        testing.assertContains(
            $e.message,
            "the termination code must be one of N, T, R, E, Q, I, F");
    }
    testing.assertEqual(encode(orderMessage("", [], "I")), "H|\\^&||||||||||P\rL|1|I\r");
}

func testQueries() {
    def m as Message init queryMessage("LIS", ["S-1", "S-2"], ["ALL"], "O");
    testing.assertEqual(
        encode($m),
        "H|\\^&|||LIS|||||||P\rQ|1|^S-1\\^S-2||^^^ALL||||||||O\rL|1|N\r");
    def q as Query init queries($m)[0];
    testing.assertEqual($q.sampleIds, ["S-1", "S-2"]);
    testing.assertEqual($q.patientIds, ["", ""]);
    testing.assertEqual($q.tests, ["ALL"]);
    testing.assertEqual($q.status, "O");
    def ranged as Query init queries(
        parse("H|\\^&\rQ|1|PAT-1^S-9^^||^^^GLU||20260101000000|20260201000000|||||F\rL|1|N\r")[0])[0];
    testing.assertEqual($ranged.patientIds, ["PAT-1"]);
    testing.assertEqual($ranged.begin + "-" + $ranged.end, "20260101000000-20260201000000");
    testing.assertEqual($ranged.status, "F");
    testing.assertEqual(len(queries(parse(SAMPLE)[0])), 0);
    try {
        queryMessage("LIS", [], ["ALL"], "O");
        missed("no specimen");
    } catch (e) {
        testing.assertContains($e.message, "a query needs a specimen ID and a test");
    }
    try {
        queryMessage("LIS", ["S-1"], ["ALL"], "Z");
        missed("status Z");
    } catch (e) {
        testing.assertContains($e.message, "the query status must be one of");
    }
}
