# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# astm - link: the LIS01 (E1381) low-level protocol over TCP or a serial
# port. Establishment (ENQ / ACK / NAK / EOT), frames with numbers and
# checksums, retries, the timers and contention. Spliced into astm.j via
# include.

/** The most text bytes in one frame: 240, as LIS01 sets it. */
export def const DEFAULT_FRAME_SIZE as int init 240;

/** How long a sender waits for a reply, in milliseconds: 15 s, as LIS01 sets it. */
export def const DEFAULT_REPLY_TIMEOUT_MS as int init 15000;

/** How long a receiver waits for the next frame, in milliseconds: 30 s, as LIS01 sets it. */
export def const DEFAULT_FRAME_TIMEOUT_MS as int init 30000;

/** The largest transmission read or sent, in bytes: 128 KiB, over a thousand results. */
export def const DEFAULT_MAX_BYTES as int init 131072;

# how many bytes read from the connection may wait for the protocol: one
# chunk fits, so queueing a chunk never blocks
def const INPUT_CAPACITY as int init 65536;

# how many transmissions received during contention wait for `receive`
def const INBOX_CAPACITY as int init 4;

# how long the line must stay quiet before a refused frame is sent again, in ms
def const SETTLE_MS as int init 50;

# how many bytes one read of the connection takes
def const CHUNK as int init 4096;

/**
 * How one side of a link behaves. `profile()` gives the LIS01 values for
 * the computer system (the LIS), `instrumentProfile()` for an instrument;
 * set a field to match a device that differs.
 *
 * @field instrument {bool} this side is the instrument, which wins contention (both sides sending ENQ at once)
 * @field encoding {string} the character set of the text: `iso-8859-1` (default), `windows-1252`, `ascii`, `utf-8`, ...
 * @field frameSize {int} the most text bytes in a frame, both ways: 1 to 64000, 240 by default; a longer frame received is refused with NAK
 * @field retries {int} how often a frame refused with NAK is sent again, and how many busy NAKs to an ENQ are waited out: 0 to 100, 6 by default
 * @field replyTimeoutMs {int} how long a sender waits for a reply: 15000 by default
 * @field frameTimeoutMs {int} how long a receiver waits for the next frame: 30000 by default
 * @field busyWaitMs {int} how long a sender waits after a busy NAK before the next ENQ: 10000 by default
 * @field contentionWaitMs {int} how long a side that lost contention waits before its next ENQ: 20000 for the computer system, 1000 for an instrument
 * @field maxBytes {int} the largest transmission read or sent: 1024 to 67108864 bytes, 128 KiB by default
 */
export def struct Profile {
    instrument as bool,
    encoding as string,
    frameSize as int,
    retries as int,
    replyTimeoutMs as int,
    frameTimeoutMs as int,
    busyWaitMs as int,
    contentionWaitMs as int,
    maxBytes as int
};

/**
 * A connection to the other side: a TCP socket or a serial port, from
 * `connect`, `accept` or `openSerial`. `close` ends it.
 *
 * @field kind {string} `tcp` or `serial`
 * @field conn {net.Conn} the socket of a `tcp` link
 * @field port {serial.Port} the port of a `serial` link
 * @field input {channel of int} bytes read from the connection and not yet taken, one by one
 * @field output {channel of int} what a `pipe` link sends (the tests' in-memory link)
 * @field inbox {channel of string} transmissions received while sending, for `receive`
 * @field profile {Profile} how this side behaves
 */
export def struct Link {
    kind as string,
    conn as net.Conn,
    port as serial.Port,
    input as channel of int,
    output as channel of int,
    inbox as channel of string,
    profile as Profile
};

# a piece of a record for one frame
def struct Piece {
    text as bytes,
    final as bool
};

# a frame as received: its number, text and end, or why it is refused
def struct Frame {
    number as int,
    text as bytes,
    final as bool,
    problem as string,
    size as int,
    next as int
};

/**
 * The profile of the computer system (the LIS), with LIS01's values.
 *
 * @return {Profile} the profile
 * @example
 *   def p as astm.Profile init astm.profile();
 *   $p.encoding = "windows-1252";
 */
export func profile() {
    return Profile{
        instrument: false,
        encoding: "iso-8859-1",
        frameSize: DEFAULT_FRAME_SIZE,
        retries: 6,
        replyTimeoutMs: DEFAULT_REPLY_TIMEOUT_MS,
        frameTimeoutMs: DEFAULT_FRAME_TIMEOUT_MS,
        busyWaitMs: 10000,
        contentionWaitMs: 20000,
        maxBytes: DEFAULT_MAX_BYTES
    };
}

/**
 * The profile of an instrument, with LIS01's values: it wins contention and
 * waits 1 s after losing it.
 *
 * @return {Profile} the profile
 */
export func instrumentProfile() {
    def p as Profile init profile();
    $p.instrument = true;
    $p.contentionWaitMs = 1000;
    return $p;
}

/**
 * Refuse a profile with a value out of range or an unknown encoding.
 *
 * @param p {Profile} the profile
 */
func checkProfile(p as Profile) {
    checkRange($p.frameSize, 1, 64000, "the frame size");
    checkRange($p.retries, 0, 100, "the retries");
    checkRange($p.replyTimeoutMs, 1, 86400000, "the reply timeout");
    checkRange($p.frameTimeoutMs, 1, 86400000, "the frame timeout");
    checkRange($p.busyWaitMs, 0, 86400000, "the busy wait");
    checkRange($p.contentionWaitMs, 0, 86400000, "the contention wait");
    checkRange($p.maxBytes, 1024, 67108864, "the largest transmission");
    if ($p.encoding != "utf-8") {
        try {
            encoding.encode($p.encoding, "A");
        } catch (e) {
            fail("an unknown encoding " + shown($p.encoding));
        }
    }
}

/**
 * Text as bytes in a profile's encoding.
 *
 * @param s {string} the text
 * @param name {string} the encoding
 * @return {bytes} the bytes
 * @throws {Error} kind "astm" when a character has no byte in the encoding
 */
func encodeText(s as string, name as string) {
    try {
        if ($name == "utf-8") {
            return encoding.encode("utf-8", $s);
        }
        return encoding.encode($name, $s);
    } catch (e) {
        fail("the text cannot be sent in " + $name + ": " + $e.message);
    }
}

/**
 * Bytes as text in a profile's encoding.
 *
 * @param b {bytes} the bytes
 * @param name {string} the encoding
 * @return {string} the text
 * @throws {Error} kind "astm" when the bytes are not valid in the encoding
 */
func decodeText(b as bytes, name as string) {
    try {
        if ($name == "utf-8") {
            return encoding.decode("utf-8", $b);
        }
        return encoding.decode($name, $b);
    } catch (e) {
        fail("the transmission is not valid " + $name + ": " + $e.message);
    }
}

/**
 * A link on a connection. Nothing reads until the protocol asks:
 * `readByte` reads a chunk under a deadline when the link's input is empty.
 *
 * @param kind {string} `tcp` or `serial`
 * @param conn {net.Conn} the socket of a `tcp` link
 * @param port {serial.Port} the port of a `serial` link
 * @param p {Profile} the profile
 * @return {Link} the link
 */
func startLink(kind as string, conn as net.Conn, port as serial.Port, p as Profile) {
    return Link{
        kind: $kind,
        conn: $conn,
        port: $port,
        input: channel.make(INPUT_CAPACITY),
        output: channel.make(1),
        inbox: channel.make(INBOX_CAPACITY),
        profile: $p
    };
}

/**
 * Connect to the other side over TCP, as a client.
 *
 * @param address {string} `host:port`
 * @param p {Profile} how this side behaves
 * @return {Link} the link
 * @throws {Error} kind "astm" when the profile is invalid; kind "timeout" when the address cannot be reached within the reply timeout; kind "net" (a `net.NetError`) when the connection is refused or fails
 * @example
 *   def link as astm.Link init astm.connect("10.0.0.20:4001", astm.profile());
 */
export func connect(address as string, p as Profile) {
    checkProfile($p);
    def conn as net.Conn init net.Conn{};
    try {
        $conn = net.connectWith($address, net.ConnectOptions{timeoutMs: $p.replyTimeoutMs});
    } catch (e) {
        # the kinds every library shares pass on as they are
        if (generic($e.kind)) {
            throw $e;
        }
        fail("cannot reach " + shown($address) + ": " + $e.message);
    }
    return startLink("tcp", $conn, serial.Port{}, $p);
}

/**
 * Listen for the other side over TCP, as a server.
 *
 * @param address {string} `host:port`, `:4001` for every address
 * @return {net.Listener} the listener, for `accept`; `net.close` stops it
 * @throws {Error} kind "astm" when the address is malformed; kind "net" (a `net.NetError`) when it cannot be bound
 * @example
 *   def server as net.Listener init astm.listen(":4001");
 *   def link as astm.Link init astm.accept($server, astm.profile());
 */
export func listen(address as string) {
    try {
        return net.listen($address);
    } catch (e) {
        # the kinds every library shares pass on as they are
        if (generic($e.kind)) {
            throw $e;
        }
        fail("cannot listen on " + shown($address) + ": " + $e.message);
    }
}

/**
 * Wait for the other side to connect.
 *
 * @param listener {net.Listener} from `listen`
 * @param p {Profile} how this side behaves
 * @return {Link} the link
 * @throws {Error} kind "astm" when the profile is invalid; kind "closed" when the listener is closed; kind "net" (a `net.NetError`) when it fails
 */
export func accept(listener as net.Listener, p as Profile) {
    checkProfile($p);
    def conn as net.Conn init net.Conn{};
    try {
        $conn = net.accept($listener);
    } catch (e) {
        # the kinds every library shares pass on as they are
        if (generic($e.kind)) {
            throw $e;
        }
        fail("accept: " + $e.message);
    }
    return startLink("tcp", $conn, serial.Port{}, $p);
}

/**
 * Open a serial port (RS-232) to the other side. Needs Linux and the
 * default `jennifer` binary.
 *
 * @param path {string} the device, such as `/dev/ttyUSB0`
 * @param options {serial.Options} the line settings; LIS01's are 9600 baud, 8 data bits, no parity, 1 stop bit
 * @param p {Profile} how this side behaves
 * @return {Link} the link
 * @throws {Error} kind "astm" when the profile is invalid or the port cannot be opened
 * @example
 *   def link as astm.Link init astm.openSerial(
 *       "/dev/ttyUSB0", serial.Options{baud: 9600}, astm.profile());
 */
export func openSerial(path as string, options as serial.Options, p as Profile) {
    checkProfile($p);
    def port as serial.Port init serial.Port{};
    try {
        $port = serial.openWith($path, $options);
    } catch (e) {
        fail("cannot open " + shown($path) + ": " + $e.message);
    }
    return startLink("serial", net.Conn{}, $port, $p);
}

/**
 * Close a link. Closing one that is already closed does nothing.
 *
 * @param l {Link} the link
 */
export func close(l as Link) {
    try {
        if ($l.kind == "tcp") {
            net.close($l.conn);
        } elseif ($l.kind == "serial") {
            serial.close($l.port);
        }
    } catch (e) {
        return null;
    }
}

/**
 * Wait for a number of milliseconds.
 *
 * @param ms {int} how long
 */
func pause(ms as int) {
    if ($ms > 0) {
        time.sleep(time.fromMilliseconds($ms));
    }
}

/**
 * The milliseconds since a moment.
 *
 * @param start {time.Time} the moment
 * @return {int} the milliseconds
 */
func since(start as time.Time) {
    return time.milliseconds(time.sub(time.now(), $start));
}

/**
 * The next byte the other side sent, waiting at most a number of
 * milliseconds. Bytes already read come first; otherwise a chunk is read
 * from the connection under a read deadline and queued.
 *
 * @param l {Link} the link
 * @param ms {int} how long to wait, 0 to only look
 * @return {int} the byte, -1 when none came in time
 * @throws {Error} kind "closed" when the connection closed; kind "net" (a `net.NetError`) when it failed
 */
func readByte(l as Link, ms as int) {
    if (channel.len($l.input) > 0) {
        return channel.recv($l.input);
    }
    if ($l.kind == "pipe") {
        return waitPipe($l, $ms);
    }
    def chunk as bytes;
    try {
        $chunk = readChunk($l, $ms);
    } catch (e) {
        # A cancel is kind "cancelled" (jennifer after 0.25); the message
        # match is for older interpreters and goes with the next floor raise.
        if ($e.kind == "cancelled" or $e.message == "task cancelled") {
            throw $e;
        }
        if ($e.kind == "timeout") {
            return -1;
        }
        if ($e.kind == "closed") {
            failClosed("the connection closed");
        }
        # the kinds every library shares pass on as they are
        if (generic($e.kind)) {
            throw $e;
        }
        fail("the connection failed: " + $e.message);
    }
    if (len($chunk) == 0) {
        failClosed("the connection closed");
    }
    for (def i in 1..len($chunk)) {
        channel.send($l.input, $chunk[$i]);
    }
    return $chunk[0];
}

/**
 * Read what the connection has within a deadline.
 *
 * @param l {Link} a `tcp` or `serial` link
 * @param ms {int} the deadline, 0 for 1 ms (only look)
 * @return {bytes} the bytes, empty once the peer closed
 */
func readChunk(l as Link, ms as int) {
    def wait as int init $ms;
    if ($wait < 1) {
        $wait = 1;
    }
    if ($l.kind == "tcp") {
        net.setReadDeadline($l.conn, $wait);
        return net.readBytes($l.conn, CHUNK);
    }
    serial.setReadDeadline($l.port, $wait);
    return serial.read($l.port, CHUNK);
}

/**
 * The next byte a `pipe` link's input gets, waiting at most a number of
 * milliseconds: the tests' in-memory link, where the peer task feeds the
 * input channel directly.
 *
 * @param l {Link} the link
 * @param ms {int} how long to wait
 * @return {int} the byte, -1 when none came in time
 */
func waitPipe(l as Link, ms as int) {
    def input as channel of int init $l.input;
    try {
        def waiter as task of int init spawn {
            return channel.recv($input);
        };
        try {
            return task.waitTimeout($waiter, $ms);
        } catch (e) {
            if ($e.kind != "timeout") {
                throw $e;
            }
        }
        task.cancel($waiter);
        try {
            return task.wait($waiter);
        } catch (e) {
            # A cancel is kind "cancelled" (jennifer after 0.25); the message
            # match is for older interpreters and goes with the next floor raise.
            if (not ($e.kind == "cancelled" or $e.message == "task cancelled")) {
                throw $e;
            }
        }
    } catch (e) {
        # A cancel is kind "cancelled" (jennifer after 0.25); the message
        # match is for older interpreters and goes with the next floor raise.
        if ($e.kind == "cancelled" or $e.message == "task cancelled") {
            throw $e;
        }
        failClosed("the connection closed");
    }
    return -1;
}

/**
 * Send bytes to the other side.
 *
 * @param l {Link} the link
 * @param data {bytes} the bytes
 * @throws {Error} kind "timeout" when a write takes longer than the reply timeout; kind "closed" when the connection is closed; kind "net" (a `net.NetError`) when it fails
 */
func transmit(l as Link, data as bytes) {
    try {
        if ($l.kind == "tcp") {
            net.setWriteDeadline($l.conn, $l.profile.replyTimeoutMs);
            net.writeBytes($l.conn, $data);
        } elseif ($l.kind == "serial") {
            serial.setWriteDeadline($l.port, $l.profile.replyTimeoutMs);
            serial.write($l.port, $data);
        } else {
            for (def i in 0..len($data)) {
                channel.send($l.output, $data[$i]);
            }
        }
    } catch (e) {
        # the kinds every library shares pass on as they are
        if (generic($e.kind)) {
            throw $e;
        }
        fail("cannot send: " + $e.message);
    }
}

/**
 * One control character as bytes.
 *
 * @param c {int} the character
 * @return {bytes} it
 */
func control(c as int) {
    def b as bytes;
    $b[] = $c;
    return $b;
}

/**
 * The LIS01 checksum: the bytes added modulo 256.
 *
 * @param data {bytes} the frame number, text and ETX or ETB
 * @return {int} 0 to 255
 */
func checksum(data as bytes) {
    def sum as int init 0;
    for (def i in 0..len($data)) {
        $sum = ($sum + $data[$i]) % 256;
    }
    return $sum;
}

/**
 * The ASCII code of an upper-case hex digit.
 *
 * @param n {int} 0 to 15
 * @return {int} the code of `0`-`9` or `A`-`F`
 */
func hexCode(n as int) {
    if ($n < 10) {
        return 48 + $n;
    }
    return 55 + $n;
}

/**
 * A frame: STX, the frame number, the text, ETB or ETX, the checksum in two
 * upper-case hex digits, CR, LF.
 *
 * @param number {int} the frame number, 0 to 7
 * @param text {bytes} the text
 * @param final {bool} the last frame of a record (ETX), else ETB
 * @return {bytes} the frame
 */
func frame(number as int, text as bytes, final as bool) {
    def body as bytes;
    $body[] = 48 + $number;
    $body = binary.concat($body, $text);
    if ($final) {
        $body[] = ETX;
    } else {
        $body[] = ETB;
    }
    def sum as int init checksum($body);
    def out as bytes init binary.concat(control(STX), $body);
    $out[] = hexCode($sum // 16);
    $out[] = hexCode($sum % 16);
    $out[] = CR;
    $out[] = LF;
    return $out;
}

/**
 * The frame texts of messages: each record with its CR, split into pieces
 * of at most the frame size.
 *
 * @param messages {list of Message} the messages
 * @param p {Profile} the profile
 * @return {list of Piece} the pieces in order
 * @throws {Error} kind "astm" when a record holds a control character or the messages exceed the largest transmission
 */
func piecesOf(messages as list of Message, p as Profile) {
    def out as list of Piece init [];
    def total as int init 0;
    for (def m in $messages) {
        for (def r in $m.records) {
            def line as string init encodeRecord($r);
            if (regex.matches(CONTROL, $line)) {
                fail("a record holds a control character: " + shown($line));
            }
            def text as bytes init encodeText($line + CR_TEXT, $p.encoding);
            $total = $total + len($text);
            if ($total > $p.maxBytes) {
                fail(io.sprintf(
                    "the messages exceed the largest transmission, %d bytes",
                    $p.maxBytes));
            }
            def at as int init 0;
            while ($at < len($text)) {
                def end as int init $at + $p.frameSize;
                if ($end > len($text)) {
                    $end = len($text);
                }
                $out[] = Piece{text: $text[$at..$end], final: $end == len($text)};
                $at = $end;
            }
        }
    }
    return $out;
}

/**
 * Send messages to the other side in one transmission: ENQ, a frame per
 * record (or several for a record longer than the frame size), EOT. A busy
 * receiver (NAK to the ENQ) is waited out; a frame refused with NAK is sent
 * again. When both sides send ENQ at once, the instrument goes first: a
 * computer-system profile receives the instrument's transmission (kept for
 * the next `receive`) and then sends. An EOT in reply to a frame (the
 * receiver asking to stop) is taken as its ACK.
 *
 * @param l {Link} the link
 * @param messages {list of Message} the messages
 * @throws {Error} kind "astm" when nothing is to be sent, a record cannot be encoded, a frame is refused more often than the retries allow, or the receiver stays busy; kind "timeout" when no reply comes within the reply timeout; kind "closed" or "net" (a `net.NetError`) when the connection closes or fails; a transmission begun is ended with EOT
 * @example
 *   astm.send($link, [astm.orderMessage("LIS", $orders, "N")]);
 */
export func send(l as Link, messages as list of Message) {
    if (len($messages) == 0) {
        fail("no messages to send");
    }
    def pieces as list of Piece init piecesOf($messages, $l.profile);
    establish($l);
    def number as int init 1;
    for (def piece in $pieces) {
        sendFrame($l, frame($number, $piece.text, $piece.final), $number);
        $number = ($number + 1) % 8;
    }
    transmit($l, control(EOT));
}

/**
 * The establishment phase: ENQ until the receiver answers ACK.
 *
 * @param l {Link} the link
 * @throws {Error} kind "timeout" when no reply comes; kind "astm" when the receiver stays busy, contention repeats more often than the retries allow, or the receiver answers something else
 */
func establish(l as Link) {
    def p as Profile init $l.profile;
    def busy as int init 0;
    def contended as int init 0;
    drain($l);
    while (true) {
        transmit($l, control(ENQ));
        def reply as int init readByte($l, $p.replyTimeoutMs);
        if ($reply == ACK) {
            return null;
        }
        if ($reply == -1) {
            transmit($l, control(EOT));
            failTimeout(io.sprintf("no reply to ENQ within %d ms", $p.replyTimeoutMs));
        }
        if ($reply == NAK) {
            $busy = $busy + 1;
            if ($busy > $p.retries) {
                fail(io.sprintf("the receiver answered ENQ with NAK (busy) %d times", $busy));
            }
            pause($p.busyWaitMs);
        } elseif ($reply == ENQ) {
            $contended = $contended + 1;
            if ($contended > $p.retries) {
                transmit($l, control(EOT));
                fail(io.sprintf(
                    "the other side answered ENQ with its own ENQ %d times",
                    $contended));
            }
            if ($p.instrument) {
                pause($p.contentionWaitMs);
            } else {
                def start as time.Time init time.now();
                def text as string init receiveTransmission($l, $p.replyTimeoutMs);
                if ($text != "") {
                    if (channel.len($l.inbox) >= INBOX_CAPACITY) {
                        fail(io.sprintf(
                            "%d transmissions received while sending are not read",
                            INBOX_CAPACITY));
                    }
                    channel.send($l.inbox, $text);
                }
                pause($p.contentionWaitMs - since($start));
            }
        } else {
            transmit($l, control(EOT));
            fail("the receiver answered ENQ with 0x" +
                strings.upper(io.sprintf("%d|base=16|pad=2|fill=0", $reply)));
        }
    }
}

/**
 * Send one frame until the receiver accepts it.
 *
 * @param l {Link} the link
 * @param f {bytes} the frame
 * @param number {int} its number, for messages
 * @throws {Error} kind "timeout" when no reply comes; kind "astm" when it is refused more often than the retries allow
 */
func sendFrame(l as Link, f as bytes, number as int) {
    def refused as int init 0;
    while (true) {
        transmit($l, $f);
        def reply as int init readByte($l, $l.profile.replyTimeoutMs);
        if ($reply == ACK or $reply == EOT) {
            return null;
        }
        if ($reply == -1) {
            transmit($l, control(EOT));
            failTimeout(io.sprintf(
                "no reply to frame %d within %d ms",
                $number,
                $l.profile.replyTimeoutMs));
        }
        $refused = $refused + 1;
        if ($refused > $l.profile.retries) {
            transmit($l, control(EOT));
            fail(io.sprintf("frame %d was refused %d times", $number, $refused));
        }
        settle($l);
    }
}

/**
 * Drop the bytes already read and not yet taken, and what the connection
 * has right now, bounded by the largest transmission.
 *
 * @param l {Link} the link
 */
func drain(l as Link) {
    def dropped as int init 0;
    while ($dropped <= $l.profile.maxBytes and readByte($l, 0) != -1) {
        $dropped = $dropped + 1;
    }
}

/**
 * Drop bytes until the line has been quiet for `SETTLE_MS`, so a late reply
 * to a refused frame is not taken as the reply to its next copy.
 *
 * @param l {Link} the link
 * @throws {Error} kind "limit" when more than the largest transmission arrives without a pause
 */
func settle(l as Link) {
    def dropped as int init 0;
    while (readByte($l, SETTLE_MS) != -1) {
        $dropped = $dropped + 1;
        if ($dropped > $l.profile.maxBytes) {
            failLimit("the line does not go quiet after a refused frame");
        }
    }
}

/**
 * Receive the next transmission: wait for the other side's ENQ, answer ACK,
 * take its frames, answer each with ACK (or NAK when it is damaged, so the
 * sender sends it again), until its EOT. A transmission received while
 * `send` lost contention comes first. Bytes other than ENQ while waiting are
 * line noise and skipped, as are bytes between frames, within limits: the
 * wait ends on time whatever arrives, a transmission may put at most twice
 * `maxBytes` on the line, and at most `retries + 1` frames in a row may be
 * refused or repeated.
 *
 * @param l {Link} the link
 * @param waitMs {int} how long to wait for an ENQ: 0 to 86400000 ms, 0 to only look
 * @return {list of Message} the messages, empty when no transmission began in time or it held no frame
 * @throws {Error} kind "limit" when the transmission exceeds the largest one or the limits above; kind "timeout" when a frame does not follow or end within the frame timeout; kind "astm" when its text is not valid in the encoding or its records do not parse; kind "closed" when the connection closed; kind "net" (a `net.NetError`) when it fails
 * @example
 *   for (def m in astm.receive($link, 1000)) {
 *       for (def r in astm.results($m)) {
 *           io.printf("%s %s = %s\n", $r.sampleId, $r.test, $r.value);
 *       }
 *   }
 */
export func receive(l as Link, waitMs as int) {
    checkRange($waitMs, 0, 86400000, "the wait");
    def text as string init "";
    if (channel.len($l.inbox) > 0) {
        $text = channel.recv($l.inbox);
    } else {
        $text = receiveTransmission($l, $waitMs);
    }
    if ($text == "") {
        def none as list of Message init [];
        return $none;
    }
    return parse($text);
}

/**
 * Wait for an ENQ and receive the transmission it begins.
 *
 * @param l {Link} the link
 * @param waitMs {int} how long to wait for the ENQ
 * @return {string} the transmission's text, `""` when none began in time
 */
func receiveTransmission(l as Link, waitMs as int) {
    def start as time.Time init time.now();
    def looked as bool init false;
    while (true) {
        def left as int init $waitMs - since($start);
        if ($left <= 0 and $looked) {
            return "";
        }
        if ($left < 0) {
            $left = 0;
        }
        $looked = true;
        def b as int init readByte($l, $left);
        if ($b == -1) {
            return "";
        }
        if ($b == ENQ) {
            break;
        }
    }
    transmit($l, control(ACK));
    return transferIn($l);
}

/**
 * The transfer phase of a receiver: frames until EOT.
 *
 * @param l {Link} the link
 * @return {string} the text of the frames received, in order
 */
func transferIn(l as Link) {
    def p as Profile init $l.profile;
    def expected as int init 1;
    def received as int init 0;
    def ended as bool init true;
    def total as int init 0;
    def wire as int init 0;
    def stalled as int init 0;
    def pending as int init -1;
    def parts as list of bytes init [];
    while (true) {
        def b as int init $pending;
        $pending = -1;
        if ($b == -1) {
            $b = readByte($l, $p.frameTimeoutMs);
        }
        if ($b == -1) {
            failTimeout(io.sprintf(
                "no frame within %d ms; the transmission is dropped",
                $p.frameTimeoutMs));
        }
        $wire = $wire + 1;
        if ($b == EOT) {
            break;
        }
        if ($b == STX) {
            def f as Frame init readFrame($l);
            $wire = $wire + $f.size;
            $pending = $f.next;
            if ($f.problem != "") {
                if ($f.next != EOT) {
                    transmit($l, control(NAK));
                }
                $stalled = $stalled + 1;
            } elseif ($f.number == $expected) {
                $total = $total + len($f.text);
                if ($total > $p.maxBytes) {
                    failLimit(io.sprintf("the transmission exceeds %d bytes", $p.maxBytes));
                }
                $parts[] = $f.text;
                $ended = $f.final;
                $received = $received + 1;
                $expected = ($expected + 1) % 8;
                $stalled = 0;
                transmit($l, control(ACK));
            } elseif ($received > 0 and $f.number == ($expected + 7) % 8) {
                $stalled = $stalled + 1;
                transmit($l, control(ACK));
            } else {
                $stalled = $stalled + 1;
                transmit($l, control(NAK));
            }
        }
        checkProgress($wire, $stalled, $p);
    }
    if (not $ended) {
        fail("the transmission ended inside a record: its last frame ended with ETB");
    }
    return decodeText(binary.join($parts), $p.encoding);
}

/**
 * Refuse a transmission that does not move on: more line bytes than twice
 * the largest transmission (noise, refused frames), or more frames in a row
 * refused or repeated than a sender may send.
 *
 * @param wire {int} the bytes read in this transmission
 * @param stalled {int} the frames in a row refused or repeated
 * @param p {Profile} the profile
 * @throws {Error} kind "limit" when the line carries too many bytes; kind "astm" when too many frames in a row were refused
 */
func checkProgress(wire as int, stalled as int, p as Profile) {
    if ($wire > 2 * $p.maxBytes) {
        failLimit(io.sprintf("more than %d bytes on the line in one transmission", 2 * $p.maxBytes));
    }
    if ($stalled > $p.retries + 1) {
        fail(io.sprintf("%d frames in a row were refused or repeated", $stalled));
    }
}

/**
 * Read a frame after its STX, up to its LF, and check it.
 *
 * @param l {Link} the link
 * @return {Frame} the frame, with `problem` set when it is refused
 */
func readFrame(l as Link) {
    def p as Profile init $l.profile;
    def raw as bytes;
    def limit as int init $p.frameSize + 6;
    def count as int init 0;
    while (true) {
        def b as int init readByte($l, $p.frameTimeoutMs);
        if ($b == -1) {
            failTimeout(io.sprintf(
                "a frame did not end within %d ms; the transmission is dropped",
                $p.frameTimeoutMs));
        }
        if ($b == STX or $b == EOT or $b == ENQ) {
            return Frame{
                number: 0,
                text: control(LF),
                final: false,
                problem: "cut off",
                size: $count,
                next: $b
            };
        }
        $count = $count + 1;
        if ($count > $p.maxBytes) {
            failLimit(io.sprintf("a frame exceeds %d bytes", $p.maxBytes));
        }
        if ($count <= $limit) {
            $raw[] = $b;
        }
        if ($b == LF) {
            break;
        }
    }
    if ($count > $limit) {
        return Frame{
            number: 0,
            text: control(LF),
            final: false,
            problem: "too long",
            size: $count,
            next: -1
        };
    }
    def f as Frame init frameOf($raw);
    $f.size = $count;
    return $f;
}

/**
 * Check a frame read from its number to its LF.
 *
 * @param raw {bytes} the frame without its STX
 * @return {Frame} the frame, with `problem` set when it is refused
 */
func frameOf(raw as bytes) {
    def n as int init len($raw);
    def bad as Frame init Frame{
        number: 0,
        text: control(LF),
        final: false,
        problem: "",
        size: 0,
        next: -1
    };
    if ($n < 6 or $raw[$n - 2] != CR) {
        $bad.problem = "no CR LF end";
        return $bad;
    }
    if ($raw[0] < 48 or $raw[0] > 55) {
        $bad.problem = "no frame number";
        return $bad;
    }
    def end as int init $raw[$n - 5];
    if ($end != ETX and $end != ETB) {
        $bad.problem = "no ETX or ETB";
        return $bad;
    }
    def sum as int init checksum($raw[..$n - 4]);
    if ($raw[$n - 4] != hexCode($sum // 16) or $raw[$n - 3] != hexCode($sum % 16)) {
        $bad.problem = "a wrong checksum";
        return $bad;
    }
    def text as bytes init $raw[1..$n - 5];
    for (def i in 0..len($text)) {
        def b as int init $text[$i];
        if (($b < 32 and $b != CR) or $b == 127) {
            $bad.problem = "a control character in the text";
            return $bad;
        }
    }
    return Frame{
        number: $raw[0] - 48,
        text: $text,
        final: $end == ETX,
        problem: "",
        size: 0,
        next: -1
    };
}
