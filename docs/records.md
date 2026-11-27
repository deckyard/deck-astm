<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Records and messages

A LIS02 message is a list of records, each one line of text ended by a CR.
The first character of a record is its type; fields follow, separated by the
field delimiter:

```text
H|\^&|||Analyzer^A7^2.1|||||||P||20260312094500
P|1|PAT-1001|||Doe^Jane||19800214|F
O|1|S-2001||^^^GLU\^^^CREA|R||20260312080000||||X||||1||||||||||F
R|1|^^^GLU|5.4|mmol/l|3.9^6.1|N||F||auto||20260312094410|A7
C|1|I|21 Test limit high|I
L|1|N
```

| Type | Record | Level |
|---|---|---|
| `H` | header: the delimiters, the sender, the processing ID | 0 |
| `P` | patient | 1 |
| `O` | test order, with the specimen | 2 |
| `R` | result | 3 |
| `C` | comment on the record before it | any |
| `Q` | request for information (a host query) | 1 |
| `M` | manufacturer's own information | any |
| `S` | scientific | any |
| `L` | message terminator | 0 |

## Delimiters

The header declares the four delimiters right after its `H`: field,
repeat, component, escape. `|\^&` is usual, but the deck reads them from
every header and assumes nothing:

```jennifer
def m as astm.Message init astm.parse("H!~*%\rP!1!PAT-1\rL!1\r")[0];
io.printf("%s\n", astm.field($m.records[1], 3));   # PAT-1
```

## Reading fields

A `Record` keeps its fields as they are on the wire. Fields, repeats and
components are numbered from 1, as LIS02 numbers them, so field 1 is the
record type and the numbers match an interface manual's tables.

```jennifer
def o as astm.Record init $m.records[2];
astm.raw($o, 5);                # "^^^GLU\^^^CREA"
astm.repeats($o, 5);            # 2
astm.component($o, 5, 2, 4);    # "CREA"
astm.values($r, 9);             # ["F", "R"] from "F\R"
astm.field($r, 5);              # "mmol/l"
```

`field` reads a field that holds one value. A field with repeats or
components is an error there, so a structured field is never read as if it
were plain text; read it with `component`, `components` or `values`.

## Escapes

A delimiter inside a value is written as an escape sequence: `&F&` (field),
`&R&` (repeat), `&S&` (component), `&E&` (escape), and `&Xhh..&` for other
characters as hex pairs, each pair one character from 00 to FF (Latin-1,
whatever the link's encoding). The reading functions decode them, `setField`
and `setComponent` write them. The highlighting sequences `&H&` and `&N&`
read as nothing. A local `&Z..&` sequence has no meaning outside its system
and is an error when read; `raw` shows the field as sent. Any other
sequence is an error everywhere.

`message` and `encodeRecord` check every record: a field holding the field
delimiter, a CR or another control character, or an invalid escape
sequence is an error, so a record built by hand cannot turn into two on
the wire.

`parse` reads at most `MAX_RECORDS` (16384) records and `MAX_FIELDS` (262144)
fields, repeats and components in one call, which bounds the memory a
hostile sender can make it use to about 100 MB.

## Results, orders and queries

`results` walks the P / O / R / C hierarchy and gives one `Result` per R
record, with the patient and specimen above it and the comments after it.
Each keeps its records for the fields the struct does not name:

```jennifer
for (def r in astm.results($m)) {
    io.printf("%s %s = %s %s\n", $r.sampleId, $r.test, $r.value, $r.units);
    io.printf("range %s to %s\n", astm.component($r.record, 6, 1, 1),
        astm.component($r.record, 6, 1, 2));
}
```

`orders` and `queries` read O and Q records the same way. To answer a host
query, build the orders and wrap them with `orderMessage`; the termination
code says how the query went (`F` processed, `I` no information):

```jennifer
for (def q in astm.queries($m)) {
    def found as list of astm.Order init [];
    for (def id in $q.sampleIds) {
        def o as astm.Order init astm.order($id, ["GLU", "CREA"]);
        $o.reportType = "Q";
        $found[] = $o;
    }
    astm.send($link, [astm.orderMessage("LIS", $found, "F")]);
}
```

## Building records

`record`, `setField` and `setComponent` build any record; `message` checks
that the records make one message (H first, L last). The sequence numbers
in field 2 are the caller's.

```jennifer
def d as astm.Delimiters init astm.delimiters(astm.DEFAULT_DELIMITERS);
def r as astm.Record init astm.setField(astm.record("R", $d), 2, "1");
$r = astm.setComponent($r, 3, 1, 4, "GLU");
$r = astm.setField($r, 4, "5.4");
def l as astm.Record init astm.setField(astm.setField(astm.record("L", $d), 2, "1"), 3, "N");
```
