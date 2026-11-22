# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# astm - white-box tests for the link topic. Spliced into astm_test.j via
# include.
#
# A peer is a script run in a spawned task against a `pipe` link: the deck
# writes to the link's output and reads its input, the peer the other way.
# Steps: `w <wire>` writes (control characters as <STX>, <ETX>, <ETB>,
# <EOT>, <ENQ>, <ACK>, <NAK>, <CR>, <LF>), `f <n> <text>` writes a good last
# frame with number n holding text and its CR, `e <n> <text>` a good ETB
# frame holding text as is, `r` reads one reply (a byte, or a frame to its
# LF) into the log, `s <ms>` sleeps. The log is the replies joined by `;`.

# the control characters by name, as the scripts write them
def const NAMES as map of string to int init {
    "STX": 2,
    "ETX": 3,
    "EOT": 4,
    "ENQ": 5,
    "ACK": 6,
    "LF": 10,
    "CR": 13,
    "NAK": 21,
    "ETB": 23
};

# how long a peer waits for the deck before it logs <none>
def const PEER_WAIT_MS as int init 2000;

/**
 * A link whose other side is the test, with short timers.
 *
 * @return {Link} the link
 */
func pipe() {
    def p as Profile init profile();
    $p.replyTimeoutMs = 400;
    $p.frameTimeoutMs = 400;
    $p.busyWaitMs = 10;
    $p.contentionWaitMs = 10;
    return Link{
        kind: "pipe",
        conn: net.Conn{},
        port: serial.Port{},
        input: channel.make(INPUT_CAPACITY),
        output: channel.make(INPUT_CAPACITY),
        inbox: channel.make(INBOX_CAPACITY),
        profile: $p
    };
}

/**
 * Wire text with control characters written by name, as bytes.
 *
 * @param s {string} the text
 * @return {bytes} the bytes
 */
func wire(s as string) {
    def text as string init $s;
    for (def name in maps.keys(NAMES)) {
        $text = strings.replace($text, "<" + $name + ">", convert.fromCodepoint(NAMES[$name]));
    }
    return encoding.encode("iso-8859-1", $text);
}

/**
 * Bytes as wire text, control characters by name.
 *
 * @param b {bytes} the bytes
 * @return {string} the text
 */
func named(b as bytes) {
    def out as list of string init [];
    for (def i in 0..len($b)) {
        def c as int init $b[$i];
        def name as string init "";
        for (def k in maps.keys(NAMES)) {
            if (NAMES[$k] == $c) {
                $name = "<" + $k + ">";
            }
        }
        if ($name == "") {
            $name = convert.fromCodepoint($c);
        }
        $out[] = $name;
    }
    return strings.join($out, "");
}

/**
 * Write bytes into the deck's input.
 *
 * @param l {Link} the link
 * @param b {bytes} the bytes
 */
func feed(l as Link, b as bytes) {
    for (def i in 0..len($b)) {
        channel.send($l.input, $b[$i]);
    }
}

/**
 * The next reply of the deck: a byte, or a frame from STX to LF.
 *
 * @param l {Link} the link
 * @return {string} the reply as wire text, `<none>` when nothing came
 */
func nextReply(l as Link) {
    def back as Link init $l;
    $back.input = $l.output;
    def b as int init readByte($back, PEER_WAIT_MS);
    if ($b == -1) {
        return "<none>";
    }
    def got as bytes init control($b);
    if ($b != STX) {
        return named($got);
    }
    while ($b != LF) {
        $b = readByte($back, PEER_WAIT_MS);
        if ($b == -1) {
            return named($got) + "<none>";
        }
        $got[] = $b;
    }
    return named($got);
}

/**
 * Run a peer script.
 *
 * @param l {Link} the link
 * @param steps {list of string} the steps
 * @return {string} the log
 */
func play(l as Link, steps as list of string) {
    def log as list of string init [];
    for (def step in $steps) {
        def verb as string init $step[..1];
        def rest as string init "";
        if (len($step) > 2) {
            $rest = $step[2..];
        }
        if ($verb == "w") {
            feed($l, wire($rest));
        } elseif ($verb == "f" or $verb == "e") {
            def number as int init convert.toInt($rest[..1]);
            def text as string init $rest[2..];
            if ($verb == "f") {
                $text = $text + CR_TEXT;
            }
            feed($l, frame($number, wire($text), $verb == "f"));
        } elseif ($verb == "r") {
            $log[] = nextReply($l);
        } else {
            pause(convert.toInt($rest));
        }
    }
    return strings.join($log, ";");
}

/**
 * Start a peer script in a task.
 *
 * @param l {Link} the link
 * @param steps {list of string} the steps
 * @return {task of string} the task, whose value is the log
 */
func peer(l as Link, steps as list of string) {
    return spawn {
        return play($l, $steps);
    };
}

# a small message and its frames as the deck sends them
def const SMALL as string init "H|\\^&\rL|1|N\r";
def const SMALL_H as string init "<STX>1H|\\^&<CR><ETX>E5<CR><LF>";
def const SMALL_L as string init "<STX>2L|1|N<CR><ETX>05<CR><LF>";

func testChecksumsAndFrames() {
    testing.assertEqual(named(frame(1, wire("H|\\^&<CR>"), true)), SMALL_H);
    testing.assertEqual(named(frame(2, wire("L|1|N<CR>"), true)), SMALL_L);
    testing.assertEqual(
        named(frame(1, wire("P|1|PAT-1"), false)),
        "<STX>1P|1|PAT-1<ETB>04<CR><LF>");
    testing.assertEqual(frameOf(frame(7, wire("x"), true)[1..]).number, 7);
}

func testSendFramesEveryRecord() {
    def l as Link init pipe();
    def p as task of string init peer($l, ["r", "w <ACK>", "r", "w <ACK>", "r", "w <ACK>", "r"]);
    send($l, parse(SMALL));
    testing.assertEqual(task.wait($p), "<ENQ>;" + SMALL_H + ";" + SMALL_L + ";<EOT>");
}

func testSendSplitsLongRecordsAndWrapsFrameNumbers() {
    def l as Link init pipe();
    $l.profile.frameSize = 4;
    def steps as list of string init [];
    for (def i in 0..11) {
        $steps[] = "r";
        $steps[] = "w <ACK>";
    }
    $steps[] = "r";
    def p as task of string init peer($l, $steps);
    send($l, parse("H|\\^&\rP|1|ABCDEFGHIJKLMNOPQRS\rL|1|N\r"));
    def frames as list of string init strings.split(task.wait($p), ";");
    def starts as list of string init [
        "<ENQ>",
        "<STX>1H|\\^<ETB>",
        "<STX>2&<CR><ETX>",
        "<STX>3P|1|<ETB>",
        "<STX>4ABCD<ETB>",
        "<STX>5EFGH<ETB>",
        "<STX>6IJKL<ETB>",
        "<STX>7MNOP<ETB>",
        "<STX>0QRS<CR><ETX>",
        "<STX>1L|1|<ETB>",
        "<STX>2N<CR><ETX>",
        "<EOT>"
    ];
    testing.assertEqual(len($frames), len($starts));
    for (def i in 0..len($starts)) {
        testing.assertTrue(strings.startsWith($frames[$i], $starts[$i]));
    }
}

func testSendRepeatsARefusedFrame() {
    def l as Link init pipe();
    def p as task of string init peer(
        $l,
        ["r", "w <ACK>", "r", "w <NAK>", "r", "w X", "r", "w <ACK>", "r", "w <EOT>", "r"]);
    send($l, parse(SMALL));
    testing.assertEqual(
        task.wait($p),
        "<ENQ>;" + SMALL_H + ";" + SMALL_H + ";" + SMALL_H + ";" + SMALL_L + ";<EOT>");
}

func testSendGivesUpAfterTheRetries() {
    def l as Link init pipe();
    $l.profile.retries = 1;
    def p as task of string init peer($l, ["r", "w <ACK>", "r", "w <NAK>", "r", "w <NAK>", "r"]);
    try {
        send($l, parse(SMALL));
        missed("two NAKs");
    } catch (e) {
        testing.assertEqual($e.message, "astm: frame 1 was refused 2 times");
    }
    testing.assertEqual(task.wait($p), "<ENQ>;" + SMALL_H + ";" + SMALL_H + ";<EOT>");
}

func testSendWaitsOutABusyReceiver() {
    def l as Link init pipe();
    def p as task of string init peer(
        $l,
        ["r", "w <NAK>", "r", "w <ACK>", "r", "w <ACK>", "r", "w <ACK>", "r"]);
    send($l, parse(SMALL));
    testing.assertEqual(task.wait($p), "<ENQ>;<ENQ>;" + SMALL_H + ";" + SMALL_L + ";<EOT>");
    $l.profile.retries = 0;
    def q as task of string init peer($l, ["r", "w <NAK>"]);
    try {
        send($l, parse(SMALL));
        missed("busy");
    } catch (e) {
        testing.assertEqual($e.message, "astm: the receiver answered ENQ with NAK (busy) 1 times");
    }
    task.wait($q);
}

func testSendTimesOutAndEndsTheTransmission() {
    def l as Link init pipe();
    def p as task of string init peer($l, ["r", "r"]);
    try {
        send($l, parse(SMALL));
        missed("silence");
    } catch (e) {
        testing.assertEqual($e.kind, "timeout");
        testing.assertEqual($e.message, "astm: no reply to ENQ within 400 ms");
    }
    testing.assertEqual(task.wait($p), "<ENQ>;<EOT>");
    def q as task of string init peer($l, ["r", "w <ACK>", "r", "r"]);
    try {
        send($l, parse(SMALL));
        missed("silence after a frame");
    } catch (e) {
        testing.assertEqual($e.kind, "timeout");
        testing.assertEqual($e.message, "astm: no reply to frame 1 within 400 ms");
    }
    testing.assertEqual(task.wait($q), "<ENQ>;" + SMALL_H + ";<EOT>");
    def odd as task of string init peer($l, ["r", "w X", "r"]);
    try {
        send($l, parse(SMALL));
        missed("X");
    } catch (e) {
        testing.assertEqual($e.message, "astm: the receiver answered ENQ with 0x58");
    }
    task.wait($odd);
}

func testSendRefusesWhatItCannotSend() {
    def l as Link init pipe();
    for (def bad in [[], parse("H|\\^&\rC|1|I|µ\rL|1\r")]) {
        $l.profile.encoding = "ascii";
        try {
            send($l, $bad);
            missed("nothing or µ in ascii");
        } catch (e) {
            testing.assertEqual($e.kind, "astm");
        }
    }
    def m as Message init parse(SMALL)[0];
    $m.records[1].fields[1] = "1\r";
    try {
        send(pipe(), [$m]);
        missed("a CR in a field");
    } catch (e) {
        testing.assertContains($e.message, "holds the field delimiter or a control character");
    }
    def big as Link init pipe();
    $big.profile.maxBytes = 1024;
    try {
        send($big, parse("H|\\^&\rC|1|I|" + strings.replicate("x", 1100) + "\rL|1\r"));
        missed("too big");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "astm: the messages exceed the largest transmission, 1024 bytes");
    }
}

func testContentionTheComputerReceivesFirst() {
    def l as Link init pipe();
    def p as task of string init peer(
        $l,
        [
            "r",
            "w <ENQ>",
            "s 20",
            "w <ENQ>",
            "r",
            "f 1 H|\\^&",
            "r",
            "f 2 Q|1|^S-7||^^^ALL||||||||O",
            "r",
            "f 3 L|1|N",
            "r",
            "w <EOT>",
            "r",
            "w <ACK>",
            "r",
            "w <ACK>",
            "r",
            "w <ACK>",
            "r"
        ]);
    send($l, parse(SMALL));
    testing.assertEqual(
        task.wait($p),
        "<ENQ>;<ACK>;<ACK>;<ACK>;<ACK>;<ENQ>;" + SMALL_H + ";" + SMALL_L + ";<EOT>");
    def got as list of Message init receive($l, 0);
    testing.assertEqual(queries($got[0])[0].sampleIds, ["S-7"]);
    testing.assertEqual(len(receive($l, 0)), 0);
}

func testContentionTheInstrumentTriesAgain() {
    def l as Link init pipe();
    $l.profile = instrumentProfile();
    $l.profile.contentionWaitMs = 10;
    def p as task of string init peer(
        $l,
        ["r", "w <ENQ>", "r", "w <ACK>", "r", "w <ACK>", "r", "w <ACK>", "r"]);
    send($l, parse(SMALL));
    testing.assertEqual(task.wait($p), "<ENQ>;<ENQ>;" + SMALL_H + ";" + SMALL_L + ";<EOT>");
}

func testReceiveAcknowledgesEachFrame() {
    def l as Link init pipe();
    def p as task of string init peer(
        $l,
        [
            "w x<ACK>",
            "w <ENQ>",
            "r",
            "e 1 H|\\^&<CR>P|1|PA",
            "r",
            "f 2 T-1",
            "r",
            "w junk",
            "f 3 L|1|N",
            "r",
            "w <EOT>"
        ]);
    def got as list of Message init receive($l, 1000);
    testing.assertEqual(task.wait($p), "<ACK>;<ACK>;<ACK>;<ACK>");
    testing.assertEqual(field($got[0].records[1], 3), "PAT-1");
}

func testReceiveRefusesDamagedFrames() {
    def l as Link init pipe();
    def p as task of string init peer(
        $l,
        [
            "w <ENQ>",
            "r",
            "w <STX>1H|\\^&<CR><ETX>E6<CR><LF>",
            "r",
            "w <STX>1H|\\^&<CR><ETX>e5<CR><LF>",
            "r",
            "w <STX>1H|\\^&<CR><ETX>E5<LF>",
            "r",
            "w <STX>8H|\\^&<CR><ETX>E5<CR><LF>",
            "r",
            "w <STX>1H|\\^&<CR>E5<CR><LF>",
            "r",
            "f 2 L|1|N",
            "r",
            "f 1 H|\\^&",
            "r",
            "f 1 H|\\^&",
            "r",
            "f 2 L|1|<NAK>",
            "r",
            "w <STX>2" + strings.replicate("x", 250) + "<CR><ETX>00<CR><LF>",
            "r",
            "f 2 L|1|N",
            "r",
            "w <EOT>"
        ]);
    def got as list of Message init receive($l, 1000);
    testing.assertEqual(
        task.wait($p),
        "<ACK>;<NAK>;<NAK>;<NAK>;<NAK>;<NAK>;<NAK>;<ACK>;<ACK>;<NAK>;<NAK>;<ACK>");
    testing.assertEqual(encode($got[0]), SMALL);
}

func testReceiveReturnsNothingWhenIdle() {
    def l as Link init pipe();
    testing.assertEqual(len(receive($l, 0)), 0);
    testing.assertEqual(len(receive($l, 50)), 0);
    def p as task of string init peer($l, ["w <ENQ>", "r", "w <EOT>"]);
    testing.assertEqual(len(receive($l, 1000)), 0);
    task.wait($p);
    try {
        receive($l, -1);
        missed("-1");
    } catch (e) {
        testing.assertContains($e.message, "the wait must be 0 to 86400000");
    }
}

func testReceiveFailsWhenTheSenderStops() {
    def l as Link init pipe();
    def p as task of string init peer($l, ["w <ENQ>", "r", "f 1 H|\\^&", "r"]);
    try {
        receive($l, 1000);
        missed("silence");
    } catch (e) {
        testing.assertEqual($e.kind, "timeout");
        testing.assertEqual(
            $e.message,
            "astm: no frame within 400 ms; the transmission is dropped");
    }
    task.wait($p);
    def q as task of string init peer($l, ["w <ENQ>", "r", "w <STX>1H|"]);
    try {
        receive($l, 1000);
        missed("a frame cut off");
    } catch (e) {
        testing.assertEqual($e.kind, "timeout");
        testing.assertEqual(
            $e.message,
            "astm: a frame did not end within 400 ms; the transmission is dropped");
    }
    task.wait($q);
    def r as task of string init peer($l, ["w <ENQ>", "r", "e 1 H|\\^&", "r", "w <EOT>"]);
    try {
        receive($l, 1000);
        missed("an ETB frame last");
    } catch (e) {
        testing.assertContains($e.message, "the transmission ended inside a record");
    }
    task.wait($r);
}

func testReceiveDecodesAndChecksTheText() {
    def l as Link init pipe();
    $l.profile.encoding = "windows-1252";
    def p as task of string init peer(
        $l,
        [
            "w <ENQ>",
            "r",
            "f 1 H|\\^&",
            "r",
            "f 2 R|1|^^^ALB|3|µg/l",
            "r",
            "f 3 L|1|N",
            "r",
            "w <EOT>"
        ]);
    testing.assertEqual(
        results(parse("H|\\^&\rO|1|S\rR|1|^^^ALB|3|µg/l\rL|1|N\r")[0])[0].units,
        "µg/l");
    def got as list of Message init receive($l, 1000);
    task.wait($p);
    testing.assertEqual(field($got[0].records[1], 5), "µg/l");
    $l.profile.encoding = "utf-8";
    def q as task of string init peer($l, ["w <ENQ>", "r", "f 1 H|\\^&µ", "r", "w <EOT>"]);
    try {
        receive($l, 1000);
        missed("latin-1 as utf-8");
    } catch (e) {
        testing.assertContains($e.message, "the transmission is not valid utf-8");
    }
    task.wait($q);
    def r as task of string init peer($l, ["w <ENQ>", "r", "f 1 P|1", "r", "w <EOT>"]);
    try {
        receive($l, 1000);
        missed("no header");
    } catch (e) {
        testing.assertContains($e.message, "record 1: no header");
    }
    task.wait($r);
}

func testReceiveCapsTheTransmission() {
    def l as Link init pipe();
    $l.profile.maxBytes = 1024;
    def steps as list of string init ["w <ENQ>", "r"];
    for (def i in 0..6) {
        $steps[] = "f " + convert.toString(($i + 1) % 8) + " C|1|" + strings.replicate("x", 200);
        $steps[] = "r";
    }
    def p as task of string init peer($l, $steps);
    try {
        receive($l, 1000);
        missed("too big");
    } catch (e) {
        testing.assertEqual($e.kind, "limit");
        testing.assertEqual($e.message, "astm: the transmission exceeds 1024 bytes");
    }
    task.discard($p);
}

func testProfilesAreChecked() {
    def bad as list of Profile init [];
    def p as Profile init profile();
    $p.frameSize = 0;
    $bad[] = $p;
    $p = profile();
    $p.retries = 101;
    $bad[] = $p;
    $p = profile();
    $p.replyTimeoutMs = 0;
    $bad[] = $p;
    $p = profile();
    $p.maxBytes = 100;
    $bad[] = $p;
    $p = profile();
    $p.encoding = "klingon";
    $bad[] = $p;
    for (def b in $bad) {
        try {
            connect("127.0.0.1:1", $b);
            missed("a bad profile");
        } catch (e) {
            testing.assertEqual($e.kind, "astm");
        }
    }
    testing.assertTrue(instrumentProfile().instrument);
    testing.assertEqual(instrumentProfile().contentionWaitMs, 1000);
    try {
        openSerial("/dev/astm-test-missing", serial.Options{baud: 9600}, profile());
        missed("a missing port");
    } catch (e) {
        testing.assertContains($e.message, "astm: cannot open \"/dev/astm-test-missing\"");
    }
}

func testOverTcp() {
    def server as net.Listener init listen("127.0.0.1:0");
    def address as string init net.address($server);
    def lis as task of string init spawn {
        def link as Link init accept($server, profile());
        def got as list of Message init receive($link, 3000);
        close($link);
        return encode($got[0]);
    };
    def p as Profile init instrumentProfile();
    def link as Link init connect($address, $p);
    send($link, parse(SAMPLE));
    testing.assertEqual(task.wait($lis), SAMPLE);
    try {
        receive($link, 3000);
        missed("a closed connection");
    } catch (e) {
        # the other side closing is the generic kind "closed"
        testing.assertEqual($e.kind, "closed");
        testing.assertEqual($e.message, "astm: the connection closed");
    }
    close($link);
    close($link);
    net.close($server);
    try {
        accept($server, profile());
        missed("a closed listener");
    } catch (e) {
        # net's own error for a closed listener, passed on as it is
        testing.assertEqual($e.kind, "closed");
    }
    try {
        connect($address, $p);
        missed("nobody listening");
    } catch (e) {
        testing.assertEqual($e.kind, "net");
    }
    try {
        listen("127.0.0.1:99999");
        missed("port 99999");
    } catch (e) {
        testing.assertContains($e.message, "astm: cannot listen on");
    }
}

func testNetErrorsPassOnWithTheirFields() {
    def server as net.Listener init listen("127.0.0.1:0");
    def address as string init net.address($server);
    net.close($server);
    try {
        connect($address, profile());
        missed("nobody listening");
    } catch (e) {
        testing.assertEqual($e.kind, "net");
        def ne as net.NetError init $e;
        testing.assertEqual($ne.op, "connect");
        testing.assertEqual($ne.reason, "refused");
    }
    $server = listen("127.0.0.1:0");
    $address = net.address($server);
    def peer as task of bool init spawn {
        def conn as net.Conn init net.accept($server);
        time.sleep(time.fromMilliseconds(100));
        net.abort($conn);
        return true;
    };
    def link as Link init connect($address, profile());
    task.wait($peer);
    try {
        receive($link, 3000);
        missed("a reset connection");
    } catch (e) {
        testing.assertEqual($e.kind, "net");
        def ne as net.NetError init $e;
        testing.assertEqual($ne.reason, "reset");
    }
    close($link);
    net.close($server);
}

# A line that does not go quiet after a refused frame is a reached cap.
func testANoisyLineAfterARefusalIsALimit() {
    def l as Link init pipe();
    $l.profile.maxBytes = 1024;
    def p as task of string init peer(
        $l,
        ["r", "w <ACK>", "r", "w <NAK>" + strings.replicate("x", 3000)]);
    try {
        send($l, parse(SMALL));
        missed("a noisy line");
    } catch (e) {
        testing.assertEqual($e.kind, "limit");
        testing.assertEqual($e.message, "astm: the line does not go quiet after a refused frame");
    }
    task.wait($p);
}

func testALateReplyDoesNotShiftTheReplies() {
    def l as Link init pipe();
    def p as task of string init peer(
        $l,
        ["r", "w <ACK>", "r", "w X<ACK>", "r", "w <ACK>", "r", "w <NAK>", "r", "w <ACK>", "r"]);
    send($l, parse(SMALL));
    testing.assertEqual(
        task.wait($p),
        "<ENQ>;" + SMALL_H + ";" + SMALL_H + ";" + SMALL_L + ";" + SMALL_L + ";<EOT>");
}

func testReceiveWaitsNoLongerThanAskedDuringNoise() {
    def l as Link init pipe();
    def steps as list of string init [];
    for (def i in 0..8) {
        $steps[] = "w " + strings.replicate("x", 60000);
    }
    def p as task of string init peer($l, $steps);
    def started as time.Time init time.now();
    testing.assertEqual(len(receive($l, 100)), 0);
    testing.assertTrue(time.milliseconds(time.sub(time.now(), $started)) < 400);
    task.cancel($p);
    task.discard($p);
}

func testReceiveStopsANoisyOrStuckSender() {
    def l as Link init pipe();
    $l.profile.maxBytes = 1024;
    def p as task of string init peer($l, ["w <ENQ>", "r", "w " + strings.replicate("x", 3000)]);
    try {
        receive($l, 1000);
        missed("noise");
    } catch (e) {
        testing.assertEqual($e.kind, "limit");
        testing.assertEqual(
            $e.message,
            "astm: more than 2048 bytes on the line in one transmission");
    }
    task.wait($p);
    def m as Link init pipe();
    $m.profile.retries = 1;
    def bad as string init "w <STX>1H|\\^&<CR><ETX>00<CR><LF>";
    def q as task of string init peer($m, ["w <ENQ>", "r", $bad, "r", $bad, "r", $bad]);
    try {
        receive($m, 1000);
        missed("endless bad frames");
    } catch (e) {
        testing.assertEqual($e.message, "astm: 3 frames in a row were refused or repeated");
    }
    testing.assertEqual(task.wait($q), "<ACK>;<NAK>;<NAK>");
}

func testContentionIsBounded() {
    def l as Link init pipe();
    $l.profile = instrumentProfile();
    $l.profile.contentionWaitMs = 10;
    $l.profile.replyTimeoutMs = 400;
    $l.profile.retries = 1;
    def p as task of string init peer($l, ["r", "w <ENQ>", "r", "w <ENQ>", "r"]);
    try {
        send($l, parse(SMALL));
        missed("an echo");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "astm: the other side answered ENQ with its own ENQ 2 times");
    }
    testing.assertEqual(task.wait($p), "<ENQ>;<ENQ>;<EOT>");
}

func testAFrameCutOffByEotEndsTheTransmission() {
    def l as Link init pipe();
    def p as task of string init peer($l, ["w <ENQ>", "r", "w <STX>1H|\\^&", "w <EOT>"]);
    testing.assertEqual(len(receive($l, 1000)), 0);
    testing.assertEqual(task.wait($p), "<ACK>");
}

func testCloseEndsTheLink() {
    def server as net.Listener init listen("127.0.0.1:0");
    def peer as task of null init spawn {
        net.accept($server);
        return null;
    };
    def l as Link init connect(net.address($server), profile());
    task.wait($peer);
    close($l);
    close($l);
    try {
        receive($l, 100);
        missed("a closed link");
    } catch (e) {
        testing.assertEqual($e.message, "astm: the connection closed");
    }
    net.close($server);
}
