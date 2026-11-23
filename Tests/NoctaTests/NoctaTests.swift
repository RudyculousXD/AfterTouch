import XCTest
@testable import Nocta

// MARK: - Lock Screen safety

/// The most important tests in the project. If the controller can overlap the password field
/// or Touch ID prompt, the app is unsafe regardless of how well anything else works.
final class LockScreenLayoutTests: XCTestCase {

    /// A representative spread: the built-in display this was developed on, a 4K external,
    /// a small laptop, and a deliberately short screen that leaves no room to expand.
    private let screens: [CGRect] = [
        CGRect(x: 0, y: 0, width: 1512, height: 982),   // 14" MacBook Pro
        CGRect(x: 0, y: 0, width: 3840, height: 2160),  // 4K external
        CGRect(x: 0, y: 0, width: 1280, height: 800),   // small laptop
        CGRect(x: 0, y: 0, width: 1920, height: 600),   // ultra-short / letterboxed
    ]

    /// The panel is sized to the expanded card, so a panel clear of the reserved bands means
    /// the card is clear in *both* states. Each assertion below therefore covers expansion.
    private func panel(_ position: LockScreenPosition, _ screen: CGRect) -> CGRect {
        LockScreenLayout.frame(for: position, in: screen)
    }

    func testEveryPositionStaysClearOfReservedBands() {
        for screen in screens {
            for position in LockScreenPosition.allCases {
                let frame = panel(position, screen)
                XCTAssertTrue(
                    LockScreenLayout.isClearOfReservedBands(frame, in: screen),
                    "\(position.title) on \(screen.width)x\(screen.height) intruded into a reserved band: \(frame)"
                )
            }
        }
    }

    func testControllerNeverOverlapsTheAuthenticationRegion() {
        for screen in screens {
            let authTop = screen.minY + screen.height * LockScreenLayout.authReserve
            for position in LockScreenPosition.allCases {
                XCTAssertGreaterThanOrEqual(
                    panel(position, screen).minY, authTop,
                    "\(position.title) overlapped the password / Touch ID region"
                )
            }
        }
    }

    func testControllerNeverOverlapsTheClock() {
        for screen in screens {
            let clockBottom = screen.maxY - screen.height * LockScreenLayout.clockReserve
            for position in LockScreenPosition.allCases {
                XCTAssertLessThanOrEqual(panel(position, screen).maxY, clockBottom,
                                         "\(position.title) overlapped the lock screen clock")
            }
        }
    }

    /// The expanded player is only offered where it fits. On a screen too short for it the
    /// card stays collapsed rather than growing over the unlock UI.
    func testExpansionIsOfferedOnlyWhereItFits() {
        let roomy = LockScreenLayout.metrics(
            for: .bottom, in: CGRect(x: 0, y: 0, width: 3840, height: 2160)
        )
        XCTAssertTrue(roomy.allowsExpansion)
        XCTAssertEqual(roomy.expandedSize.height, LockScreenLayout.idealExpandedHeight)

        let short = LockScreenLayout.metrics(
            for: .bottom, in: CGRect(x: 0, y: 0, width: 1920, height: 600)
        )
        XCTAssertFalse(short.allowsExpansion)
        XCTAssertEqual(short.cardSize(expanded: true), short.collapsedSize,
                       "A card that can't expand must stay the collapsed size")
    }

    /// The card grows away from whichever reserved band it sits next to.
    func testCardGrowsAwayFromTheReservedBands() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        XCTAssertEqual(LockScreenLayout.metrics(for: .bottom, in: screen).anchor, .bottom)
        XCTAssertEqual(LockScreenLayout.metrics(for: .top, in: screen).anchor, .top)
        XCTAssertEqual(LockScreenLayout.metrics(for: .upperMiddle, in: screen).anchor, .center)
    }

    /// The collapsed bar must sit inside the panel it shares with the expanded player,
    /// otherwise the panel's hit-testing would let clicks fall through the card itself.
    func testCollapsedCardSitsInsideThePanel() {
        for screen in screens {
            for position in LockScreenPosition.allCases {
                let metrics = LockScreenLayout.metrics(for: position, in: screen)
                let bounds = CGRect(origin: .zero, size: metrics.panelSize)
                for expanded in [false, true] {
                    XCTAssertTrue(
                        bounds.contains(metrics.cardRect(expanded: expanded)),
                        "card rect escaped the panel on \(screen.width)x\(screen.height)"
                    )
                }
            }
        }
    }

    func testCardIsHorizontallyCentred() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        XCTAssertEqual(panel(.bottom, screen).midX, screen.midX, accuracy: 0.5)
    }

    /// Displays are not always at the origin; a second monitor has a non-zero offset.
    func testHandlesDisplaysWithNonZeroOrigin() {
        let screen = CGRect(x: 1512, y: 240, width: 1920, height: 1080)
        for position in LockScreenPosition.allCases {
            let frame = panel(position, screen)
            XCTAssertTrue(LockScreenLayout.isClearOfReservedBands(frame, in: screen))
            XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.5)
        }
    }
}

// MARK: - Provider quirks

final class SpotifyDurationTests: XCTestCase {

    /// Verified against Spotify's shipping build on 2026-08-20: its dictionary documents
    /// `duration` in seconds, but the app actually returned 201946 for a 3m21s track.
    func testMillisecondDurationsAreNormalised() {
        XCTAssertEqual(SpotifyProvider.normalisedDuration(201_946), 201.946, accuracy: 0.001)
    }

    func testSecondDurationsArePassedThrough() {
        XCTAssertEqual(SpotifyProvider.normalisedDuration(202), 202, accuracy: 0.001)
    }

    /// The boundary must not misread a genuinely long track. 10,000 s is 2h46m — longer than
    /// any song, but far shorter than the millisecond value of even a 15-second clip.
    func testBoundaryBehaviour() {
        XCTAssertEqual(SpotifyProvider.normalisedDuration(10_000), 10_000, accuracy: 0.001)
        XCTAssertEqual(SpotifyProvider.normalisedDuration(10_001), 10.001, accuracy: 0.001)
    }

    func testZeroIsSafe() {
        XCTAssertEqual(SpotifyProvider.normalisedDuration(0), 0, accuracy: 0.001)
    }
}

// MARK: - Collapsed card insets

/// The collapsed artwork is drawn *over* the card, not inside its stack, so its inset and the
/// stack's must agree. When they diverged, the artwork hung 10pt below the header row that
/// reserves its place and covered the lyric line underneath.
final class CollapsedInsetTests: XCTestCase {
    func testTheHeaderRowLeavesRoomForTheArtworkBeneathIt() {
        let top = LockScreenLayout.collapsedPaddingVertical
        let headerBottom = top + LockScreenLayout.collapsedArtwork
        let contentHeight = LockScreenLayout.collapsedSize.height
            - LockScreenLayout.collapsedPaddingVertical * 2

        XCTAssertLessThan(
            headerBottom, contentHeight,
            "the artwork must finish inside the card's content box"
        )
    }

    /// The side inset is deliberately larger than the top and bottom one; a bar this wide reads
    /// as a block when all four are equal.
    func testSideInsetExceedsTheVerticalOne() {
        XCTAssertGreaterThan(
            LockScreenLayout.collapsedPadding, LockScreenLayout.collapsedPaddingVertical
        )
    }
}

// MARK: - Lyrics layout

/// The lyric line sits in the expanded column, so it necessarily costs the artwork some height.
/// These pin how much: the card's footprint must not change at all, and the price must stay a
/// single line. A five-line sheet took 84pt from a 245pt cover and read as a different card.
final class LyricsLayoutTests: XCTestCase {
    private let screens: [CGRect] = [
        CGRect(x: 0, y: 0, width: 1512, height: 982),
        CGRect(x: 0, y: 0, width: 3840, height: 2160),
        CGRect(x: 0, y: 0, width: 1280, height: 800),
    ]

    func testEnablingLyricsNeverChangesTheCardFootprint() {
        for screen in screens {
            for position in LockScreenPosition.allCases {
                let without = LockScreenLayout.metrics(for: position, in: screen, lyricsEnabled: false)
                let with = LockScreenLayout.metrics(for: position, in: screen, lyricsEnabled: true)
                XCTAssertEqual(without.panelSize, with.panelSize)
                XCTAssertEqual(without.expandedSize, with.expandedSize)
                XCTAssertEqual(without.collapsedSize, with.collapsedSize)
            }
        }
    }

    /// The allowance is one line. If it grows past this the artwork is being spent, and that
    /// is the trade this project already rejected once.
    func testTheAllowanceIsASingleLine() {
        XCTAssertLessThanOrEqual(LockScreenLayout.expandedLyricsAllowance, 24)
    }

    func testTheLineCostsTheArtworkExactlyTheAllowance() {
        let screen = screens[0]
        let without = LockScreenLayout.metrics(for: .bottom, in: screen, lyricsEnabled: false)
        let with = LockScreenLayout.metrics(for: .bottom, in: screen, lyricsEnabled: true)

        XCTAssertEqual(
            with.expandedPlayerHeight - without.expandedPlayerHeight,
            LockScreenLayout.expandedLyricsAllowance
        )
        XCTAssertEqual(
            without.expandedArtwork - with.expandedArtwork,
            LockScreenLayout.expandedLyricsAllowance,
            "the artwork gives up exactly the line's height, no more"
        )
        XCTAssertGreaterThanOrEqual(
            with.expandedArtwork, LockScreenLayout.expandedArtworkRange.lowerBound
        )
    }

    /// The safety property, re-asserted with lyrics on rather than assumed to carry over.
    func testEveryPositionStaysClearOfReservedBandsWithLyricsOn() {
        for screen in screens {
            for position in LockScreenPosition.allCases {
                let metrics = LockScreenLayout.metrics(for: position, in: screen, lyricsEnabled: true)
                let frame = LockScreenLayout.frame(for: position, in: screen, metrics: metrics)
                XCTAssertTrue(
                    LockScreenLayout.isClearOfReservedBands(frame, in: screen),
                    "\(position) on \(screen.size) intrudes into a reserved band with lyrics on"
                )
            }
        }
    }
}

// MARK: - Lyrics

/// The LRC parser and its lookup. This is where a lyrics feature actually goes wrong: a line
/// off by one is worse than no lyrics at all, because the card confidently shows the wrong words.
final class SyncedLyricsTests: XCTestCase {
    private let sample = """
    [ar:BoyWithUke]
    [ti:Paper Planes]
    [00:13.46] Okay, I can get a little violent
    [00:16.96] My ego out in outer space
    [00:20.21] I listen for the birds in silence
    [00:23.14] But I can only hear warplanes
    """

    func testParsesTimestampsAndDiscardsMetadataTags() throws {
        let lyrics = try XCTUnwrap(SyncedLyrics(lrc: sample))
        XCTAssertEqual(lyrics.lines.count, 4, "[ar:] and [ti:] are not timed lines")
        XCTAssertEqual(lyrics.lines[0].time, 13.46, accuracy: 0.001)
        XCTAssertEqual(lyrics.lines[0].text, "Okay, I can get a little violent")
        XCTAssertEqual(lyrics.lines[3].time, 23.14, accuracy: 0.001)
    }

    func testNothingIsShownBeforeTheFirstLine() throws {
        let lyrics = try XCTUnwrap(SyncedLyrics(lrc: sample))
        XCTAssertNil(lyrics.index(at: 0))
        XCTAssertNil(lyrics.index(at: 13.45))
    }

    /// A line holds until the next one starts — the property that makes the card readable
    /// rather than flickering between lines.
    func testALineHoldsUntilTheNextBegins() throws {
        let lyrics = try XCTUnwrap(SyncedLyrics(lrc: sample))
        XCTAssertEqual(lyrics.index(at: 13.46), 0)
        XCTAssertEqual(lyrics.index(at: 16.95), 0)
        XCTAssertEqual(lyrics.index(at: 16.96), 1)
        XCTAssertEqual(lyrics.line(at: 20.5)?.text, "I listen for the birds in silence")
    }

    func testTheLastLinePersistsToTheEndOfTheTrack() throws {
        let lyrics = try XCTUnwrap(SyncedLyrics(lrc: sample))
        XCTAssertEqual(lyrics.index(at: 600), 3)
    }

    /// Some LRC files share one line of text across several timestamps for a repeated chorus.
    func testRepeatedTimestampsOnOneLineBecomeSeparateEntries() throws {
        let lyrics = try XCTUnwrap(SyncedLyrics(lrc: "[00:10.00][01:20.50] Chorus line"))
        XCTAssertEqual(lyrics.lines.count, 2)
        XCTAssertEqual(lyrics.lines.map(\.text), ["Chorus line", "Chorus line"])
        XCTAssertEqual(lyrics.lines[1].time, 80.5, accuracy: 0.001)
    }

    func testTimestampsWithoutFractionsParse() throws {
        let lyrics = try XCTUnwrap(SyncedLyrics(lrc: "[01:05] A line"))
        XCTAssertEqual(lyrics.lines[0].time, 65, accuracy: 0.001)
    }

    /// Plain lyrics have no timestamps at all; the parser must refuse them so the caller can
    /// fall back rather than render an empty sheet.
    func testUntimedTextIsRejected() {
        XCTAssertNil(SyncedLyrics(lrc: "Just some words\nAnd more words"))
        XCTAssertNil(SyncedLyrics(lrc: ""))
        XCTAssertNil(SyncedLyrics(lrc: "[ar:Only metadata]"))
    }

    /// A malformed stamp must not be read as a valid time.
    func testMalformedTimestampsAreIgnored() {
        XCTAssertNil(SyncedLyrics(lrc: "[99:99.99] impossible seconds"))
        XCTAssertNil(SyncedLyrics(lrc: "[abc:de] not numbers"))
    }

    func testOutOfOrderLinesAreSorted() throws {
        let lyrics = try XCTUnwrap(SyncedLyrics(lrc: "[00:30.00] second\n[00:10.00] first"))
        XCTAssertEqual(lyrics.lines.map(\.text), ["first", "second"])
    }
}

// MARK: - Repeat cycling

/// The repeat control must only offer states the provider actually has. Spotify's `repeating`
/// is a boolean, so a three-position cycle there sets `.one`, reads back `.all` on the next
/// poll, and leaves the button apparently ignoring every other press.
final class RepeatCycleTests: XCTestCase {
    func testThreeStateCycleWhenRepeatOneIsSupported() {
        XCTAssertEqual(RepeatMode.next(after: .off, hasRepeatOne: true), .all)
        XCTAssertEqual(RepeatMode.next(after: .all, hasRepeatOne: true), .one)
        XCTAssertEqual(RepeatMode.next(after: .one, hasRepeatOne: true), .off)
    }

    func testTwoStateCycleWhenRepeatOneIsNotSupported() {
        XCTAssertEqual(RepeatMode.next(after: .off, hasRepeatOne: false), .all)
        XCTAssertEqual(RepeatMode.next(after: .all, hasRepeatOne: false), .off)
    }

    /// Defensive: a provider could report `.one` from state set outside Nocta. Pressing the
    /// control must still move somewhere valid rather than sticking.
    func testAStaleRepeatOneStillCyclesToOff() {
        XCTAssertEqual(RepeatMode.next(after: .one, hasRepeatOne: false), .off)
    }

    /// Signed out, Spotify has only the Apple Events boolean, so the third position must not
    /// be offered. Signed in it gains it, because the Web API can express all three states.
    func testSignedOutSpotifyDoesNotDeclareRepeatOne() {
        XCTAssertTrue(SpotifyProvider().capabilities.contains(.repeatMode))
        XCTAssertFalse(SpotifyProvider().capabilities.contains(.repeatOne))
        XCTAssertTrue(AppleMusicProvider().capabilities.contains(.repeatOne))
    }

    func testRepeatModeMapsToSpotifyAPIValues() {
        XCTAssertEqual(SpotifyWebClient.apiValue(for: .off), "off")
        XCTAssertEqual(SpotifyWebClient.apiValue(for: .all), "context")
        XCTAssertEqual(SpotifyWebClient.apiValue(for: .one), "track")
    }

    /// `context` means "repeat the album or playlist" — the state this app calls `.all`.
    /// Getting this pair backwards would silently swap two buttons.
    func testSpotifyAPIValuesMapBackToRepeatMode() {
        XCTAssertEqual(SpotifyWebClient.repeatMode(fromAPI: "off"), .off)
        XCTAssertEqual(SpotifyWebClient.repeatMode(fromAPI: "context"), .all)
        XCTAssertEqual(SpotifyWebClient.repeatMode(fromAPI: "track"), .one)
        XCTAssertNil(SpotifyWebClient.repeatMode(fromAPI: "something-new"))
    }

    func testEveryModeSurvivesARoundTrip() {
        for mode in RepeatMode.allCases {
            XCTAssertEqual(
                SpotifyWebClient.repeatMode(fromAPI: SpotifyWebClient.apiValue(for: mode)), mode
            )
        }
    }
}

/// The poll loop reads repeat state once a second; the cache is what keeps that off the network.
final class RepeatStateCacheTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 2_000_000)

    func testStoredValueIsReturnedWhileFresh() {
        let cache = RepeatStateCache()
        cache.store(.one, now: t0)
        XCTAssertEqual(cache.fresh(within: 15, now: t0.addingTimeInterval(14))?.value, .one)
    }

    func testValueExpiresAfterTheInterval() {
        let cache = RepeatStateCache()
        cache.store(.one, now: t0)
        XCTAssertNil(cache.fresh(within: 15, now: t0.addingTimeInterval(16)))
    }

    /// A failed read is remembered as "unknown" rather than retried every poll.
    func testFailedReadIsCachedAsUnknown() {
        let cache = RepeatStateCache()
        cache.store(nil, now: t0)
        let entry = cache.fresh(within: 15, now: t0.addingTimeInterval(1))
        XCTAssertNotNil(entry)
        XCTAssertNil(entry?.value)
    }

    /// Falling back to Apple Events invalidates, so the next poll re-reads rather than
    /// reporting a state the fallback could not actually set.
    func testInvalidateForcesARead() {
        let cache = RepeatStateCache()
        cache.store(.all, now: t0)
        cache.invalidate()
        XCTAssertNil(cache.fresh(within: 15, now: t0))
    }
}

// MARK: - Lookup coalescing

/// Pins the single-flight behaviour. Without it, several refreshes landing together on a cache
/// miss each issue their own request — four identical lookups in one millisecond were observed.
final class LikedLookupCoalescerTests: XCTestCase {
    private actor CallCounter {
        private(set) var count = 0
        func increment() { count += 1 }
    }

    private let uri = "spotify:track:2RkZ5LkEzeHGRsmDqKwmaJ"
    private let other = "spotify:track:4uLU6hMCjMI75M1A2tKUQC"

    func testConcurrentLookupsOfOneTrackShareASingleFetch() async {
        let coalescer = LikedLookupCoalescer()
        let counter = CallCounter()

        await withTaskGroup(of: Bool?.self) { group in
            for _ in 0..<4 {
                group.addTask { [uri] in
                    await coalescer.value(for: uri) {
                        await counter.increment()
                        // Hold the flight open long enough for the followers to arrive.
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        return true
                    }
                }
            }
            for await value in group {
                XCTAssertEqual(value, true, "every caller must receive the shared result")
            }
        }

        let calls = await counter.count
        XCTAssertEqual(calls, 1, "concurrent lookups of one track must collapse to one request")
    }

    func testDifferentTracksAreNotCollapsedTogether() async {
        let coalescer = LikedLookupCoalescer()
        let counter = CallCounter()

        await withTaskGroup(of: Bool?.self) { group in
            for uri in [uri, other] {
                group.addTask {
                    await coalescer.value(for: uri) {
                        await counter.increment()
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        return true
                    }
                }
            }
            for await _ in group {}
        }

        let calls = await counter.count
        XCTAssertEqual(calls, 2, "distinct tracks must each be fetched")
    }

    /// The entry is released when the flight ends, so a later miss fetches again rather than
    /// being answered forever from a task that has already finished.
    func testALaterLookupFetchesAgain() async {
        let coalescer = LikedLookupCoalescer()
        let counter = CallCounter()

        for _ in 0..<2 {
            _ = await coalescer.value(for: uri) {
                await counter.increment()
                return true
            }
        }

        let calls = await counter.count
        XCTAssertEqual(calls, 2)
    }
}

// MARK: - Spotify library URIs

/// The unified `/me/library` endpoints take whole Spotify URIs, not the bare ids the
/// deprecated `/me/tracks` family wanted. Pinning the shape stops a silent regression to the
/// old form, which fails as an unexplained 403.
final class SpotifyLibraryURITests: XCTestCase {
    func testTrackURIPassesThroughWhole() {
        XCTAssertEqual(
            SpotifyWebClient.trackURI(validating: "spotify:track:2RkZ5LkEzeHGRsmDqKwmaJ"),
            "spotify:track:2RkZ5LkEzeHGRsmDqKwmaJ"
        )
    }

    func testNonTrackURIsAreRejected() {
        XCTAssertNil(SpotifyWebClient.trackURI(validating: "spotify:episode:512ojhOuo1ktJprKbVcKyQ"))
        XCTAssertNil(SpotifyWebClient.trackURI(validating: "spotify:local:::Some+File:214"))
        XCTAssertNil(SpotifyWebClient.trackURI(validating: "not-a-uri"))
        XCTAssertNil(SpotifyWebClient.trackURI(validating: ""))
    }
}

// MARK: - Liked-state caching

/// Pins the behaviour that stops the heart button turning itself off: liked state must be
/// answered from cache rather than re-read from the Web API on every one-second poll, and a
/// failed read must be remembered rather than retried immediately.
final class LikedTrackCacheTests: XCTestCase {
    private let uri = "spotify:track:2RkZ5LkEzeHGRsmDqKwmaJ"
    private let other = "spotify:track:4uLU6hMCjMI75M1A2tKUQC"
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testStoredValueIsReturnedWhileFresh() {
        let cache = LikedTrackCache()
        cache.store(true, for: uri, now: t0)
        XCTAssertEqual(cache.fresh(for: uri, within: 60, now: t0.addingTimeInterval(59))?.value, true)
    }

    func testValueExpiresAfterTheInterval() {
        let cache = LikedTrackCache()
        cache.store(true, for: uri, now: t0)
        XCTAssertNil(cache.fresh(for: uri, within: 60, now: t0.addingTimeInterval(61)))
    }

    func testAnotherTrackIsNeverAnsweredFromCache() {
        let cache = LikedTrackCache()
        cache.store(true, for: uri, now: t0)
        XCTAssertNil(cache.fresh(for: other, within: 60, now: t0))
    }

    /// A failed lookup is cached as "unknown". Without this a rate-limited session re-requests
    /// once a second and stays rate limited.
    func testFailedLookupIsRememberedAsUnknown() {
        let cache = LikedTrackCache()
        cache.store(nil, for: uri, now: t0)
        let entry = cache.fresh(for: uri, within: 60, now: t0.addingTimeInterval(5))
        XCTAssertNotNil(entry, "a failed lookup must still count as fresh, or it retries at 1 Hz")
        XCTAssertNil(entry?.value)
    }

    /// The write-through that removes the race with Spotify's eventually-consistent
    /// saved-tracks index: after a successful save the answer is known locally.
    func testWriteThroughOverwritesAnEarlierAnswer() {
        let cache = LikedTrackCache()
        cache.store(false, for: uri, now: t0)
        cache.store(true, for: uri, now: t0.addingTimeInterval(1))
        XCTAssertEqual(cache.fresh(for: uri, within: 60, now: t0.addingTimeInterval(2))?.value, true)
    }
}

final class ProviderCapabilityTests: XCTestCase {

    /// Spotify has no mute property and its `starred` is broken, so the UI must not offer
    /// either. This asserts the difference is declared rather than discovered at runtime.
    func testSpotifyDeclaresNoNativeMuteOrFavourite() {
        let spotify = SpotifyProvider()
        XCTAssertFalse(spotify.capabilities.contains(.nativeMute))
        XCTAssertFalse(spotify.capabilities.contains(.favorite))
        XCTAssertTrue(spotify.capabilities.contains(.seek))
        XCTAssertTrue(spotify.capabilities.contains(.volume))
    }

    func testAppleMusicDeclaresNativeMuteAndFavourite() {
        let music = AppleMusicProvider()
        XCTAssertTrue(music.capabilities.contains(.nativeMute))
        XCTAssertTrue(music.capabilities.contains(.favorite))
    }

    /// Providers must never launch their app just to answer a question.
    func testProvidersReportNotRunningWithoutLaunching() async throws {
        let music = AppleMusicProvider()
        guard !music.isRunning() else {
            throw XCTSkip("Music.app is running; this test needs it closed.")
        }
        do {
            _ = try await music.snapshot()
            XCTFail("Expected notRunning rather than a snapshot")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .notRunning(appName: "Music"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertFalse(music.isRunning(), "Reading state must not have launched Music.app")
    }
}

// MARK: - Snapshot maths

final class PlayerSnapshotTests: XCTestCase {

    private func snapshot(
        status: PlaybackStatus, position: TimeInterval, duration: TimeInterval, age: TimeInterval
    ) -> PlayerSnapshot {
        PlayerSnapshot(
            track: Track(id: "t", title: "t", artist: "a", album: "b", duration: duration),
            status: status,
            position: position,
            volume: 50,
            isMuted: false,
            isShuffling: false,
            repeatMode: .off,
            capturedAt: Date().addingTimeInterval(-age)
        )
    }

    func testPositionAdvancesWhilePlaying() {
        let snap = snapshot(status: .playing, position: 10, duration: 200, age: 5)
        XCTAssertEqual(snap.interpolatedPosition(), 15, accuracy: 0.1)
    }

    func testPositionIsFrozenWhilePaused() {
        let snap = snapshot(status: .paused, position: 10, duration: 200, age: 5)
        XCTAssertEqual(snap.interpolatedPosition(), 10, accuracy: 0.001)
    }

    /// Without clamping, a paused-then-resumed track could report a position past its end and
    /// drive the scrubber off the rail.
    func testPositionIsClampedToDuration() {
        let snap = snapshot(status: .playing, position: 195, duration: 200, age: 60)
        XCTAssertEqual(snap.interpolatedPosition(), 200, accuracy: 0.001)
    }

    func testIdleSnapshotHasNoTrack() {
        XCTAssertNil(PlayerSnapshot.idle.track)
        XCTAssertEqual(PlayerSnapshot.idle.status, .stopped)
    }
}

// MARK: - Mock provider behaviour

final class MockProviderTests: XCTestCase {

    private func makeProvider() -> MockProvider {
        MockProvider(advancesWithWallClock: false)
    }

    func testPlayPauseToggles() async throws {
        let provider = makeProvider()
        let before = try await provider.snapshot().status
        try await provider.playPause()
        let after = try await provider.snapshot().status
        XCTAssertNotEqual(after, before)
    }

    func testNextAdvancesAndWrapsAround() async throws {
        let provider = makeProvider()
        let first = try await provider.snapshot().track?.id
        try await provider.nextTrack()
        let second = try await provider.snapshot().track?.id
        XCTAssertNotEqual(second, first)

        // Wrap back around to the beginning.
        try await provider.nextTrack()
        try await provider.nextTrack()
        let wrapped = try await provider.snapshot().track?.id
        XCTAssertEqual(wrapped, first)
    }

    /// Matches the convention both real players use: restart if we're past the opening
    /// seconds, otherwise step back a track.
    func testPreviousRestartsTrackWhenPastTheOpening() async throws {
        let provider = makeProvider()
        try await provider.nextTrack()
        let current = try await provider.snapshot().track?.id
        try await provider.seek(to: 30)
        try await provider.previousTrack()

        let after = try await provider.snapshot()
        XCTAssertEqual(after.track?.id, current, "Should have restarted, not changed track")
        XCTAssertEqual(after.position, 0, accuracy: 0.001)
    }

    func testPreviousStepsBackNearTheStart() async throws {
        let provider = makeProvider()
        try await provider.nextTrack()
        let current = try await provider.snapshot().track?.id
        try await provider.seek(to: 1)
        try await provider.previousTrack()
        let after = try await provider.snapshot().track?.id
        XCTAssertNotEqual(after, current)
    }

    func testSeekIsClampedToTheTrack() async throws {
        let provider = makeProvider()
        let duration = try await provider.snapshot().track?.duration ?? 0
        try await provider.seek(to: duration + 500)
        let past = try await provider.snapshot().position
        XCTAssertEqual(past, duration, accuracy: 0.001)

        try await provider.seek(to: -50)
        let negative = try await provider.snapshot().position
        XCTAssertEqual(negative, 0, accuracy: 0.001)
    }

    func testVolumeIsClamped() async throws {
        let provider = makeProvider()
        try await provider.setVolume(500)
        let high = try await provider.snapshot().volume
        XCTAssertEqual(high, 100)

        try await provider.setVolume(-20)
        let low = try await provider.snapshot().volume
        XCTAssertEqual(low, 0)
    }

    func testMuteReportsZeroVolumeButRemembersTheLevel() async throws {
        let provider = makeProvider()
        try await provider.setVolume(70)
        try await provider.setMuted(true)

        let muted = try await provider.snapshot()
        XCTAssertTrue(muted.isMuted)
        XCTAssertEqual(muted.volume, 0)

        try await provider.setMuted(false)
        let restored = try await provider.snapshot().volume
        XCTAssertEqual(restored, 70)
    }

    func testFavouriteRoundTrips() async throws {
        let provider = makeProvider()
        let initial = try await provider.snapshot().track?.isFavorite
        XCTAssertEqual(initial, false)

        try await provider.setFavorite(true)
        let liked = try await provider.snapshot().track?.isFavorite
        XCTAssertEqual(liked, true)

        try await provider.setFavorite(false)
        let unliked = try await provider.snapshot().track?.isFavorite
        XCTAssertEqual(unliked, false)
    }

    /// The demo set deliberately includes edge cases the UI has to survive.
    func testDemoTracksCoverTheAwkwardUIStates() {
        let tracks = MockProvider.demoTracks
        XCTAssertTrue(tracks.contains { $0.artwork == nil }, "need a missing-artwork case")
        XCTAssertTrue(tracks.contains { $0.title.count > 40 }, "need a long-title case")
        XCTAssertTrue(tracks.contains { $0.artist.count > 25 }, "need a long-artist case")
    }
}

// MARK: - Optional-requirement defaults

final class UnsupportedOperationTests: XCTestCase {

    /// A provider that implements only the mandatory members. Optional operations should
    /// surface a clear error rather than silently doing nothing.
    private final class MinimalProvider: MediaProvider {
        let id = ProviderID(rawValue: "minimal")
        let displayName = "Minimal"
        let capabilities: ProviderCapabilities = []
        func isRunning() -> Bool { true }
        func snapshot() async throws -> PlayerSnapshot { .idle }
        func play() async throws {}
        func pause() async throws {}
        func playPause() async throws {}
        func nextTrack() async throws {}
        func previousTrack() async throws {}
    }

    func testOptionalOperationsThrowRatherThanNoOp() async {
        let provider = MinimalProvider()
        await assertUnsupported { try await provider.seek(to: 5) }
        await assertUnsupported { try await provider.setVolume(50) }
        await assertUnsupported { try await provider.setMuted(true) }
        await assertUnsupported { try await provider.setShuffle(true) }
        await assertUnsupported { try await provider.setRepeat(.all) }
        await assertUnsupported { try await provider.setFavorite(true) }
    }

    private func assertUnsupported(
        _ operation: () async throws -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected an unsupported error", file: file, line: line)
        } catch let error as ProviderError {
            guard case .unsupported = error else {
                return XCTFail("Expected .unsupported, got \(error)", file: file, line: line)
            }
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

// MARK: - Formatting

final class TimeFormattingTests: XCTestCase {
    func testFormatsMinutesAndSeconds() {
        XCTAssertEqual(formatTime(0), "0:00")
        XCTAssertEqual(formatTime(9), "0:09")
        XCTAssertEqual(formatTime(201.946), "3:22")
    }

    func testFormatsHoursForLongContent() {
        XCTAssertEqual(formatTime(3661), "1:01:01")
    }

    /// A provider that can't report duration hands us 0 or NaN; neither should render as junk.
    func testInvalidValuesRenderAsPlaceholder() {
        XCTAssertEqual(formatTime(-1), "--:--")
        XCTAssertEqual(formatTime(.nan), "--:--")
        XCTAssertEqual(formatTime(.infinity), "--:--")
    }
}
