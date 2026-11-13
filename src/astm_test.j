# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * White-box tests: jennifer test src/astm_test.j
 *
 * No test needs an instrument. The link tests run the deck against a peer
 * scripted in a spawned task, over a `pipe` link (two channels) or a TCP
 * socket on 127.0.0.1; the checksums in them were computed apart from the
 * deck. The topic overlays are fragments spliced in here, not standalone
 * suites.
 */
use maps;
use time;
use testing;

include "topics/core_test.j";
include "topics/records_test.j";
include "topics/messages_test.j";
include "topics/link_test.j";
