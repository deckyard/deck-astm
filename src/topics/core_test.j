# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# astm - white-box tests for the core topic, and the helper the other
# overlays share. Spliced into astm_test.j via include.

/**
 * Fail a test that should have thrown: the error is not of kind `astm`, so
 * the catch that expects one fails.
 *
 * @param what {string} what should have thrown
 */
func missed(what as string) {
    throw Error{kind: "missed", message: "no error for " + $what};
}

func testShownCleansAndCuts() {
    testing.assertEqual(shown("a\rb"), "\"a?b\"");
    testing.assertEqual(len(shown(strings.replicate("x", 300))), 85);
}

func testRangesAreChecked() {
    checkRange(5, 1, 5, "five");
    try {
        checkRange(6, 1, 5, "the count");
        missed("6");
    } catch (e) {
        testing.assertEqual($e.message, "astm: the count must be 1 to 5, got 6");
    }
}
