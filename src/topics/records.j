# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# astm - records: the LIS02 (E1394) record syntax. Delimiters from the header,
# escape sequences, field / repeat / component access, building records, and
# messages from H to L. Spliced into astm.j via include.

/** The most fields, repeats and components `parse` reads in one call: 262144. */
export def const MAX_FIELDS as int init 262144;

/** The most records `parse` reads in one call: 16384, over ten thousand results. */
export def const MAX_RECORDS as int init 16384;

/**
 * The four delimiters of a message, read from its header record.
 *
 * @field field {string} between fields, usually `|`
 * @field repetition {string} between repeats of a field, usually `\`
 * @field component {string} between components, usually `^`
 * @field escape {string} opens and closes an escape sequence, usually `&`
 */
export def struct Delimiters {
    field as string,
    repetition as string,
    component as string,
    escape as string
};

/**
 * One record: its fields as they are on the wire, still escaped, and the
 * delimiters they use. `fields[0]` is field 1, the record type.
 *
 * @field fields {list of string} the fields, field n at index n - 1
 * @field delimiters {Delimiters} the delimiters of its message
 */
export def struct Record {
    fields as list of string,
    delimiters as Delimiters
};

/**
 * One message: a header record, the records under it and a terminator
 * record.
 *
 * @field delimiters {Delimiters} the delimiters its header declares
 * @field records {list of Record} every record, H first and L last
 */
export def struct Message {
    delimiters as Delimiters,
    records as list of Record
};

/**
 * The delimiters a definition declares: field, repeat, component and escape,
 * in that order, as in field 2 of a header (`|\^&`).
 *
 * @param definition {string} the four characters
 * @return {Delimiters} the delimiters
 * @throws {Error} kind "astm" unless they are four distinct printable ASCII characters that are not letters, digits or spaces
 * @example
 *   def d as astm.Delimiters init astm.delimiters("!~*%");
 */
export func delimiters(definition as string) {
    if (len($definition) != 4) {
        fail("a delimiter definition is 4 characters, got " + shown($definition));
    }
    def chars as list of string init strings.chars($definition);
    for (def c in $chars) {
        if (not regex.matches('^[!-/:-@\[-`{-~]$', $c)) {
            fail("a delimiter is printable ASCII and not a letter, digit or space: " +
                shown($definition));
        }
        if (strings.count($definition, $c) != 1) {
            fail("the delimiters must differ: " + shown($definition));
        }
    }
    return Delimiters{
        field: $chars[0],
        repetition: $chars[1],
        component: $chars[2],
        escape: $chars[3]
    };
}

/**
 * The definition of delimiters, as field 2 of a header writes it.
 *
 * @param d {Delimiters} the delimiters
 * @return {string} field, repeat, component and escape
 */
func definitionOf(d as Delimiters) {
    return $d.field + $d.repetition + $d.component + $d.escape;
}

/**
 * A new record of a type, with no fields after the type. A header (`H`) also
 * gets the delimiter definition as field 2.
 *
 * @param type {string} one upper-case letter: H, P, O, R, C, Q, M, S, L, ...
 * @param d {Delimiters} the delimiters of its message
 * @return {Record} the record
 * @throws {Error} kind "astm" when the type is not one upper-case letter
 * @example
 *   def r as astm.Record init astm.record("R", $d);
 */
export func record(type as string, d as Delimiters) {
    checkType($type);
    if ($type == "H") {
        return Record{fields: ["H", $d.repetition + $d.component + $d.escape], delimiters: $d};
    }
    return Record{fields: [$type], delimiters: $d};
}

/**
 * Refuse a record type that is not one upper-case letter.
 *
 * @param type {string} the type
 * @throws {Error} kind "astm" when it is not
 */
func checkType(type as string) {
    if (not regex.matches('^[A-Z]$', $type)) {
        fail("a record type is one upper-case letter, got " + shown($type));
    }
}

/**
 * The type of a record, its field 1.
 *
 * @param r {Record} the record
 * @return {string} such as `H`, `P`, `O`, `R`
 */
export func recordType(r as Record) {
    if (len($r.fields) == 0) {
        fail("a record without fields");
    }
    return $r.fields[0];
}

/**
 * Refuse a record that would not encode as one valid record: no type, a
 * field holding the field delimiter, a control character or an invalid
 * escape sequence, or a header whose field 2 is not its delimiters.
 *
 * @param r {Record} the record
 * @throws {Error} kind "astm" when the record is not valid
 */
func checkRecord(r as Record) {
    checkType(recordType($r));
    def d as Delimiters init $r.delimiters;
    if ($r.fields[0] == "H" and
        (len($r.fields) < 2 or $r.fields[1] != $d.repetition + $d.component + $d.escape)) {
        fail("a header's field 2 is not its delimiters");
    }
    for (def i in 1..len($r.fields)) {
        def f as string init $r.fields[$i];
        if (strings.contains($f, $d.field) or regex.matches(CONTROL, $f)) {
            fail(io.sprintf(
                "field %d of the %s record holds the field delimiter or a control character",
                $i + 1,
                $r.fields[0]));
        }
        if ($i > 1 or $r.fields[0] != "H") {
            checkEscapes($f, $d);
        }
    }
}

/**
 * Parse one record without its CR.
 *
 * @param text {string} the record
 * @param d {Delimiters} the delimiters of its message
 * @return {Record} the record
 * @throws {Error} kind "astm" when it is empty, holds a control character, has no valid type, or a header's definition differs from `d`
 */
func parseRecord(text as string, d as Delimiters) {
    if ($text == "") {
        fail("an empty record");
    }
    if (regex.matches(CONTROL, $text)) {
        fail("a record holds a control character: " + shown($text));
    }
    def r as Record init Record{fields: strings.split($text, $d.field), delimiters: $d};
    checkType($r.fields[0]);
    if ($r.fields[0] == "H" and
        (len($r.fields) < 2 or $r.fields[1] != $d.repetition + $d.component + $d.escape)) {
        fail("a header does not start with H" + definitionOf($d) + ": " + shown($text));
    }
    def first as int init 1;
    if ($r.fields[0] == "H") {
        $first = 2;
    }
    for (def i in $first..len($r.fields)) {
        checkEscapes($r.fields[$i], $d);
    }
    return $r;
}

/**
 * Add a record's fields, repeats and components to a count, refusing more
 * than `MAX_FIELDS`.
 *
 * @param count {int} the fields so far
 * @param line {string} the record
 * @param d {Delimiters} its delimiters
 * @return {int} the new count
 * @throws {Error} kind "limit" past `MAX_FIELDS`
 */
func countFields(count as int, line as string, d as Delimiters) {
    def total as int init $count + strings.count($line, $d.field) +
        strings.count($line, $d.repetition) + strings.count($line, $d.component) + 1;
    if ($total > MAX_FIELDS) {
        failLimit(io.sprintf("more than %d fields, repeats and components", MAX_FIELDS));
    }
    return $total;
}

/**
 * Parse a transmission's text: one or more messages, each from an H record
 * to an L record, every record ended by a CR. The delimiters are read from
 * each header.
 *
 * @param text {string} the records
 * @return {list of Message} the messages in order
 * @throws {Error} kind "astm" when the text is empty, a record does not end with a CR, a record comes before an H or after its L, a message lacks its L, or a record does not parse; kind "limit" when the text holds more than `MAX_RECORDS` records or `MAX_FIELDS` fields, repeats and components
 * @example
 *   for (def m in astm.parse($text)) {
 *       io.printf("%d records\n", len($m.records));
 *   }
 */
export func parse(text as string) {
    if ($text == "") {
        fail("no records");
    }
    if (not strings.endsWith($text, CR_TEXT)) {
        fail("the last record does not end with a CR: " + shown($text));
    }
    if (strings.count($text, CR_TEXT) > MAX_RECORDS) {
        failLimit(io.sprintf("more than %d records", MAX_RECORDS));
    }
    def lines as list of string init strings.split($text[..len($text) - 1], CR_TEXT);
    def fields as int init 0;
    def messages as list of Message init [];
    def records as list of Record init [];
    def d as Delimiters init delimiters(DEFAULT_DELIMITERS);
    def open as bool init false;
    def n as int init 0;
    for (def line in $lines) {
        $n = $n + 1;
        if (strings.startsWith($line, "H")) {
            if ($open) {
                fail(io.sprintf("record %d: a header before the L of the message before it", $n));
            }
            if (len($line) < 5) {
                fail(io.sprintf("record %d: a header without its delimiters: %s", $n, shown($line)));
            }
            $d = delimiters($line[1..5]);
            $fields = countFields($fields, $line, $d);
            $records = [parseRecord($line, $d)];
            $open = true;
        } else {
            if (not $open) {
                fail(io.sprintf("record %d: no header before %s", $n, shown($line)));
            }
            $fields = countFields($fields, $line, $d);
            def r as Record init parseRecord($line, $d);
            $records[] = $r;
            if ($r.fields[0] == "L") {
                $messages[] = Message{delimiters: $d, records: $records};
                $records = [];
                $open = false;
            }
        }
    }
    if ($open) {
        fail("the last message has no L record");
    }
    return $messages;
}

/**
 * A message from its records, checked: an H first, an L last, no other H or
 * L, one set of delimiters, and every record valid (no field holding the
 * field delimiter, a control character or an invalid escape sequence).
 *
 * @param records {list of Record} the records
 * @return {Message} the message
 * @throws {Error} kind "astm" when the records do not make one message
 * @example
 *   def m as astm.Message init astm.message([$h, $p, $o, $l]);
 */
export func message(records as list of Record) {
    if (len($records) < 2) {
        fail("a message has at least an H and an L record");
    }
    def last as int init len($records) - 1;
    def d as Delimiters init $records[0].delimiters;
    for (def i in 0..len($records)) {
        checkRecord($records[$i]);
        def type as string init $records[$i].fields[0];
        if (($i == 0) != ($type == "H")) {
            fail(io.sprintf("record %d: a message has one H record, first", $i + 1));
        }
        if (($i == $last) != ($type == "L")) {
            fail(io.sprintf("record %d: a message has one L record, last", $i + 1));
        }
        if ($records[$i].delimiters != $d) {
            fail(io.sprintf("record %d: other delimiters than the header's", $i + 1));
        }
    }
    return Message{delimiters: $d, records: $records};
}

/**
 * A message as text: every record followed by a CR.
 *
 * @param m {Message} the message
 * @return {string} its records
 */
export func encode(m as Message) {
    def lines as list of string init [];
    for (def r in $m.records) {
        $lines[] = encodeRecord($r);
    }
    return strings.join($lines, CR_TEXT) + CR_TEXT;
}

/**
 * A record as text, without its CR.
 *
 * @param r {Record} the record
 * @return {string} its fields joined by the field delimiter
 * @throws {Error} kind "astm" when the record is not valid: see `message`
 */
export func encodeRecord(r as Record) {
    checkRecord($r);
    return strings.join($r.fields, $r.delimiters.field);
}

/**
 * Refuse a field number below 1.
 *
 * @param n {int} the field number
 */
func checkField(n as int) {
    if ($n < 1) {
        fail(io.sprintf("fields are numbered from 1, got %d", $n));
    }
}

/**
 * A field as it is on the wire, still escaped; `""` past the last field.
 *
 * @param r {Record} the record
 * @param n {int} the field number, from 1
 * @return {string} the field
 */
export func raw(r as Record, n as int) {
    checkField($n);
    if ($n > len($r.fields)) {
        return "";
    }
    return $r.fields[$n - 1];
}

/**
 * Refuse field 2 of a header for repeat and component access: it is the
 * delimiter definition.
 *
 * @param r {Record} the record
 * @param n {int} the field number
 */
func checkNotDefinition(r as Record, n as int) {
    if ($n == 2 and recordType($r) == "H") {
        fail("field 2 of a header is the delimiter definition: read it with raw");
    }
}

/**
 * A field's value, unescaped. The field holds one value: a field with
 * repeats or components is read with `component`, `components` or `values`.
 * Field 2 of a header gives the delimiters after the field delimiter
 * (`\^&`).
 *
 * @param r {Record} the record
 * @param n {int} the field number, from 1
 * @return {string} the value, `""` when the field is empty or absent
 * @throws {Error} kind "astm" when the field has repeats or components, or an invalid escape sequence
 * @example
 *   def sample as string init astm.field($order, 3);
 */
export func field(r as Record, n as int) {
    def s as string init raw($r, $n);
    if ($n == 2 and recordType($r) == "H") {
        return $s;
    }
    if (strings.contains($s, $r.delimiters.repetition) or
        strings.contains($s, $r.delimiters.component)) {
        fail(io.sprintf(
            "field %d of the %s record has repeats or components: %s",
            $n,
            $r.fields[0],
            shown($s)));
    }
    return unescaped($s, $r.delimiters);
}

/**
 * How many repeats a field has: 0 when it is empty.
 *
 * @param r {Record} the record
 * @param n {int} the field number, from 1
 * @return {int} the number of repeats
 */
export func repeats(r as Record, n as int) {
    checkNotDefinition($r, $n);
    def s as string init raw($r, $n);
    if ($s == "") {
        return 0;
    }
    return len(strings.split($s, $r.delimiters.repetition));
}

/**
 * The components of one repeat of a field, unescaped.
 *
 * @param r {Record} the record
 * @param n {int} the field number, from 1
 * @param rep {int} the repeat, from 1
 * @return {list of string} its components, empty when the repeat is absent
 * @throws {Error} kind "astm" on an invalid escape sequence
 */
export func components(r as Record, n as int, rep as int) {
    checkNotDefinition($r, $n);
    if ($rep < 1) {
        fail(io.sprintf("repeats are numbered from 1, got %d", $rep));
    }
    def s as string init raw($r, $n);
    def out as list of string init [];
    if ($s == "") {
        return $out;
    }
    def reps as list of string init strings.split($s, $r.delimiters.repetition);
    if ($rep > len($reps)) {
        return $out;
    }
    for (def c in strings.split($reps[$rep - 1], $r.delimiters.component)) {
        $out[] = unescaped($c, $r.delimiters);
    }
    return $out;
}

/**
 * One component of one repeat of a field, unescaped.
 *
 * @param r {Record} the record
 * @param n {int} the field number, from 1
 * @param rep {int} the repeat, from 1
 * @param component {int} the component, from 1
 * @return {string} the component, `""` when absent
 * @throws {Error} kind "astm" on an invalid escape sequence
 * @example
 *   def test as string init astm.component($result, 3, 1, 4);   # ^^^GLU -> GLU
 */
export func component(r as Record, n as int, rep as int, component as int) {
    if ($component < 1) {
        fail(io.sprintf("components are numbered from 1, got %d", $component));
    }
    def parts as list of string init components($r, $n, $rep);
    if ($component > len($parts)) {
        return "";
    }
    return $parts[$component - 1];
}

/**
 * The first component of every repeat of a field, unescaped: the values of
 * a repeated code field such as a result status `F\R`.
 *
 * @param r {Record} the record
 * @param n {int} the field number, from 1
 * @return {list of string} one value per repeat
 * @throws {Error} kind "astm" on an invalid escape sequence
 */
export func values(r as Record, n as int) {
    return componentOfEach($r, $n, 1);
}

/**
 * One component of every repeat of a field, unescaped, splitting the field
 * once.
 *
 * @param r {Record} the record
 * @param n {int} the field number, from 1
 * @param component {int} the component, from 1
 * @return {list of string} one value per repeat, `""` where the repeat lacks the component
 */
func componentOfEach(r as Record, n as int, component as int) {
    checkNotDefinition($r, $n);
    def out as list of string init [];
    def s as string init raw($r, $n);
    if ($s == "") {
        return $out;
    }
    for (def rep in strings.split($s, $r.delimiters.repetition)) {
        def parts as list of string init strings.split($rep, $r.delimiters.component);
        if ($component > len($parts)) {
            $out[] = "";
        } else {
            $out[] = unescaped($parts[$component - 1], $r.delimiters);
        }
    }
    return $out;
}

/**
 * Put a field's wire text, adding empty fields before it as needed.
 *
 * @param r {Record} the record
 * @param n {int} the field number, 2 or more; not 2 of a header
 * @param text {string} the escaped text
 * @return {Record} the record with the field set
 */
func put(r as Record, n as int, text as string) {
    if ($n < 2) {
        fail(io.sprintf("field 1 is the record type; fields to set start at 2, got %d", $n));
    }
    if ($n == 2 and $r.fields[0] == "H") {
        fail("field 2 of a header is the delimiter definition");
    }
    if ($text == "" and $n > len($r.fields)) {
        return $r;
    }
    while (len($r.fields) < $n) {
        $r.fields[] = "";
    }
    $r.fields[$n - 1] = $text;
    return $r;
}

/**
 * Set a field to one value, escaping every delimiter in it.
 *
 * @param r {Record} the record
 * @param n {int} the field number, from 2
 * @param value {string} the value
 * @return {Record} the record with the field set
 * @example
 *   $p = astm.setField($p, 3, "PAT-1001");
 */
export func setField(r as Record, n as int, value as string) {
    def text as string init escaped($value, $r.delimiters);
    $r = put($r, $n, $text);
    return $r;
}

/**
 * Set one component of one repeat of a field, escaping every delimiter in
 * the value and adding empty repeats and components before it as needed.
 *
 * @param r {Record} the record
 * @param n {int} the field number, from 2
 * @param rep {int} the repeat, from 1
 * @param component {int} the component, from 1
 * @param value {string} the value
 * @return {Record} the record with the component set
 * @example
 *   $o = astm.setComponent($o, 5, 1, 4, "GLU");   # ^^^GLU
 */
export func setComponent(r as Record, n as int, rep as int, component as int, value as string) {
    checkNotDefinition($r, $n);
    if ($rep < 1 or $component < 1) {
        fail(io.sprintf(
            "repeats and components are numbered from 1, got %d and %d",
            $rep,
            $component));
    }
    def d as Delimiters init $r.delimiters;
    def s as string init raw($r, $n);
    if ($value == "" and $s == "") {
        return $r;
    }
    def reps as list of string init [];
    if ($s != "") {
        $reps = strings.split($s, $d.repetition);
    }
    while (len($reps) < $rep) {
        $reps[] = "";
    }
    def parts as list of string init strings.split($reps[$rep - 1], $d.component);
    while (len($parts) < $component) {
        $parts[] = "";
    }
    $parts[$component - 1] = escaped($value, $d);
    $reps[$rep - 1] = strings.join($parts, $d.component);
    def text as string init strings.join($reps, $d.repetition);
    $r = put($r, $n, $text);
    return $r;
}

/**
 * Set a field's wire text as given: repeats, components and escape
 * sequences already written with the record's delimiters.
 *
 * @param r {Record} the record
 * @param n {int} the field number, from 2
 * @param text {string} the text
 * @return {Record} the record with the field set
 * @throws {Error} kind "astm" when the text holds the field delimiter, a control character or an invalid escape sequence
 * @example
 *   $q = astm.setRaw($q, 5, "^^^ALL");
 */
export func setRaw(r as Record, n as int, text as string) {
    if (strings.contains($text, $r.delimiters.field) or regex.matches(CONTROL, $text)) {
        fail("raw field text holds the field delimiter or a control character: " + shown($text));
    }
    checkEscapes($text, $r.delimiters);
    $r = put($r, $n, $text);
    return $r;
}

/**
 * A value with its delimiters and control characters escaped: `&F&`,
 * `&R&`, `&S&`, `&E&` and `&Xhh&` with the message's escape character.
 *
 * @param value {string} the value
 * @param d {Delimiters} the delimiters
 * @return {string} the escaped text
 */
func escaped(value as string, d as Delimiters) {
    def specials as string init $d.field + $d.repetition + $d.component + $d.escape;
    def needed as bool init regex.matches(CONTROL, $value);
    for (def c in strings.chars($specials)) {
        if (strings.contains($value, $c)) {
            $needed = true;
        }
    }
    if (not $needed) {
        return $value;
    }
    def e as string init $d.escape;
    def out as list of string init [];
    for (def c in strings.chars($value)) {
        if ($c == $d.field) {
            $out[] = $e + "F" + $e;
        } elseif ($c == $d.repetition) {
            $out[] = $e + "R" + $e;
        } elseif ($c == $d.component) {
            $out[] = $e + "S" + $e;
        } elseif ($c == $e) {
            $out[] = $e + "E" + $e;
        } elseif (regex.matches(CONTROL, $c)) {
            $out[] = $e + "X" +
                strings.upper(io.sprintf("%d|base=16|pad=2|fill=0", convert.toCodepoint($c))) + $e;
        } else {
            $out[] = $c;
        }
    }
    return strings.join($out, "");
}

/**
 * Refuse text with an unclosed or unknown escape sequence. LIS02 defines
 * `F`, `R`, `S`, `E`, `H`, `N`, `X` with hex pairs, and `Z` for local use.
 *
 * @param s {string} the escaped text
 * @param d {Delimiters} the delimiters
 * @throws {Error} kind "astm" on an unclosed or unknown sequence
 */
func checkEscapes(s as string, d as Delimiters) {
    if (not strings.contains($s, $d.escape)) {
        return null;
    }
    def parts as list of string init strings.split($s, $d.escape);
    if (len($parts) % 2 == 0) {
        fail("an escape sequence is not closed: " + shown($s));
    }
    for (def i in 0..len($parts) // 2) {
        def sequence as string init $parts[2 * $i + 1];
        if (not regex.matches('^([FRSEHN]|X([0-9A-Fa-f]{2})+|Z.*)$', $sequence) or
            strings.contains($sequence, $d.field) or strings.contains($sequence, $d.repetition) or
            strings.contains($sequence, $d.component)) {
            fail("an unknown escape sequence " + shown($d.escape + $sequence + $d.escape) + " in " +
                shown($s));
        }
    }
}

/**
 * A component's text with its escape sequences decoded: `F`, `R`, `S`, `E`
 * to the delimiters, `H` and `N` (highlighting on and off) to nothing, and
 * `X` followed by hex pairs, each pair one character from 00 to FF (Latin-1,
 * whatever the link's encoding).
 *
 * @param s {string} the escaped text
 * @param d {Delimiters} the delimiters
 * @return {string} the value
 * @throws {Error} kind "astm" on an unclosed or unknown escape sequence, bad hex, or a local `Z` sequence, which has no meaning outside its system (read such a field with `raw`)
 */
func unescaped(s as string, d as Delimiters) {
    if (not strings.contains($s, $d.escape)) {
        return $s;
    }
    checkEscapes($s, $d);
    def parts as list of string init strings.split($s, $d.escape);
    def out as list of string init [];
    for (def i in 0..len($parts)) {
        if ($i % 2 == 0) {
            $out[] = $parts[$i];
        } else {
            $out[] = decodeEscape($parts[$i], $d);
        }
    }
    return strings.join($out, "");
}

/**
 * The text one valid escape sequence stands for.
 *
 * @param sequence {string} the sequence without its escape characters
 * @param d {Delimiters} the delimiters
 * @return {string} the text
 */
func decodeEscape(sequence as string, d as Delimiters) {
    if ($sequence == "F") {
        return $d.field;
    }
    if ($sequence == "R") {
        return $d.repetition;
    }
    if ($sequence == "S") {
        return $d.component;
    }
    if ($sequence == "E") {
        return $d.escape;
    }
    if ($sequence == "H" or $sequence == "N") {
        return "";
    }
    if (strings.startsWith($sequence, "Z")) {
        fail("a local escape sequence " + shown($d.escape + $sequence + $d.escape) +
            " has no meaning outside its system: read the field with raw");
    }
    def out as list of string init [];
    def i as int init 1;
    while ($i < len($sequence)) {
        $out[] = convert.fromCodepoint(convert.toInt($sequence[$i..$i + 2], 16));
        $i = $i + 2;
    }
    return strings.join($out, "");
}
