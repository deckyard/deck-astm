# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# astm - core: the error helper and the control characters of LIS01. Spliced
# into astm.j via include.

/** The delimiter definition most instruments use: field `|`, repeat `\`, component `^`, escape `&`. */
export def const DEFAULT_DELIMITERS as string init '|\^&';

# the LIS01 control characters
def const STX as int init 2;
def const ETX as int init 3;
def const EOT as int init 4;
def const ENQ as int init 5;
def const ACK as int init 6;
def const LF as int init 10;
def const CR as int init 13;
def const NAK as int init 21;
def const ETB as int init 23;

# the record terminator of LIS02, as text
def const CR_TEXT as string init "\r";

# control characters, which no record holds
def const CONTROL as string init '[\x00-\x1f\x7f]';

# what an error message never shows: control characters and the bidi controls
# that reorder a terminal line
def const UNSHOWN as string init '[\x00-\x1f\x7f-\x9f\x{200e}\x{200f}\x{202a}-\x{202e}\x{2066}-\x{2069}]';

/**
 * Throw an astm error.
 *
 * @param message {string} what went wrong, without the `astm: ` prefix
 * @throws {Error} kind "astm", always
 */
func fail(message as string) {
    throw Error{kind: "astm", message: "astm: " + $message};
}

/**
 * Throw a reached cap: kind "limit", the message as `fail` writes it.
 *
 * @param message {string} what was over the cap, without the `astm: ` prefix
 * @throws {Error} kind "limit", always
 */
func failLimit(message as string) {
    throw Error{kind: "limit", message: "astm: " + $message};
}

/**
 * Throw a timer that ran out: kind "timeout", the message as `fail` writes
 * it.
 *
 * @param message {string} what did not come in time, without the `astm: ` prefix
 * @throws {Error} kind "timeout", always
 */
func failTimeout(message as string) {
    throw Error{kind: "timeout", message: "astm: " + $message};
}

/**
 * Throw a connection the other side closed: kind "closed", the message as
 * `fail` writes it.
 *
 * @param message {string} what closed, without the `astm: ` prefix
 * @throws {Error} kind "closed", always
 */
func failClosed(message as string) {
    throw Error{kind: "closed", message: "astm: " + $message};
}

/**
 * Whether a caught error has a kind every library shares, which a wrapper
 * passes on as it is: a reached cap, a deadline, a closed connection, a
 * cancelled task or a network failure (a `net.NetError`).
 *
 * @param kind {string} the error's kind
 * @return {bool} whether it passes on
 */
func generic(kind as string) {
    return lists.contains(["limit", "timeout", "closed", "cancelled", "net"], $kind);
}

/**
 * Text quoted for an error message: at most 80 characters, control and bidi
 * characters as `?`.
 *
 * @param s {string} the text
 * @return {string} the text in double quotes
 */
func shown(s as string) {
    def text as string init $s;
    if (len($text) > 80) {
        $text = $text[..80] + "...";
    }
    return "\"" + regex.replace(UNSHOWN, $text, "?") + "\"";
}

/**
 * Refuse an int outside a range.
 *
 * @param value {int} the value
 * @param low {int} the smallest allowed
 * @param high {int} the largest allowed
 * @param what {string} what the value is, for the message
 * @throws {Error} kind "astm" when the value is outside the range
 */
func checkRange(value as int, low as int, high as int, what as string) {
    if ($value < $low or $value > $high) {
        fail(io.sprintf("%s must be %d to %d, got %d", $what, $low, $high, $value));
    }
}

