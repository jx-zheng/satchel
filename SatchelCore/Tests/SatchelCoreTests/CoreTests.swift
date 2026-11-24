import XCTest
@testable import SatchelCore

final class CatalogTests: XCTestCase {
    func testExactly102ToolsInSiteOrder() {
        XCTAssertEqual(ToolRegistry.all.count, 102)
        XCTAssertEqual(Set(ToolRegistry.all.map(\.id)).count, 102)
        XCTAssertEqual(Set(ToolRegistry.all.map(\.name)).count, 102)
        XCTAssertEqual(ToolID.allCases.count, 102)
        let counts = ToolRegistry.counts()
        XCTAssertEqual(counts[.video], 15)
        XCTAssertEqual(counts[.audio], 5)
        XCTAssertEqual(counts[.images], 13)
        XCTAssertEqual(counts[.docs], 23)
        XCTAssertEqual(counts[.text], 9)
        XCTAssertEqual(counts[.files], 5)
        XCTAssertEqual(counts[.mac], 18)
        XCTAssertEqual(counts[.dev], 14)
    }

    func testNamesAreOriginalAndComplete() {
        for tool in ToolRegistry.all {
            XCTAssertFalse(tool.name.isEmpty)
            XCTAssertFalse(tool.summary.isEmpty)
            XCTAssertFalse(tool.symbol.isEmpty)
            XCTAssertFalse(tool.keywords.isEmpty)
            XCTAssertFalse(tool.name.localizedCaseInsensitiveContains("toolbox"))
            XCTAssertFalse(tool.summary.localizedCaseInsensitiveContains("toolbox"))
            XCTAssertGreaterThan(tool.summary.count, 20)
        }
    }

    func testCategoryOrderMatchesTheTabs() {
        let titles = ToolCategory.allCases.map(\.title)
        XCTAssertEqual(titles, ["Video", "Audio", "Images", "Docs", "Text & Speech", "Files", "Mac", "Dev"])
        XCTAssertEqual(ToolRegistry.tools(in: .video).first?.id, .downloadVideo)
        XCTAssertEqual(ToolRegistry.tools(in: .dev).last?.id, .csvJSON)
        XCTAssertEqual(ToolRegistry.tools(in: .mac).count, 18)
    }

    func testPlaceholderSet() {
        let placeholders = Set(ToolRegistry.all.filter { $0.status == .placeholder }.map(\.id))
        XCTAssertEqual(placeholders, [])
    }
}

final class SearchTests: XCTestCase {
    func testEmptyQueryPreservesOrder() {
        let results = ToolSearch.results(query: "   ", in: ToolRegistry.all)
        XCTAssertEqual(results.map(\.id), ToolRegistry.all.map(\.id))
    }

    func testExactNameBeatsALooserMatch() {
        let results = ToolSearch.results(query: "QR Code", in: ToolRegistry.all)
        XCTAssertEqual(results.first?.id, .qrCode)
    }

    func testPhraseRequiresEveryToken() {
        let results = ToolSearch.results(query: "compress pdf", in: ToolRegistry.all)
        XCTAssertEqual(results.first?.id, .compressPDF)
        XCTAssertFalse(results.contains { $0.id == .compressVideo })
    }

    func testFuzzyPrefixFindsCompressTools() {
        let results = ToolSearch.results(query: "compres", in: ToolRegistry.all)
        let ids = Set(results.prefix(3).map(\.id))
        XCTAssertEqual(ids, [.compressVideo, .compressImages, .compressPDF])
    }

    func testKeywordFindsExtractText() {
        let results = ToolSearch.results(query: "ocr", in: ToolRegistry.all)
        XCTAssertTrue(results.contains { $0.id == .extractText })
        XCTAssertTrue(results.contains { $0.id == .searchablePDF })
    }

    func testCategoryFilter() {
        let results = ToolSearch.results(query: "trim", in: ToolRegistry.all, category: .video)
        XCTAssertEqual(results.first?.id, .trimVideo)
        XCTAssertFalse(results.contains { $0.id == .trimAudio })
    }

    func testNoMatch() {
        XCTAssertTrue(ToolSearch.results(query: "zzzz-not-a-tool", in: ToolRegistry.all).isEmpty)
    }
}

final class LayoutTests: XCTestCase {
    func testHomeCardsAndMacRow() {
        let plan = HomeLayout.make(recents: [], favorites: [])
        XCTAssertEqual(plan.categoryCards.map(\.category), [.docs, .video, .images, .audio, .text, .files])
        let docs = plan.categoryCards[0]
        XCTAssertEqual(docs.total, 23)
        XCTAssertEqual(docs.shownNames.count, 8)
        XCTAssertEqual(docs.moreCount, 15)
        XCTAssertEqual(docs.shownNames.first, "Scan Document")
        XCTAssertEqual(plan.featureIDs, [.compressVideo, .removeBackground, .batchRename])
        XCTAssertEqual(plan.macRow.count, 4)
        XCTAssertEqual(plan.macMore, 14)
        XCTAssertEqual(plan.macRow.first, .networkSpeed)
        XCTAssertFalse(plan.spotlight.isEmpty)
        XCTAssertEqual(plan.spotlight.first, .compressVideo)
    }

    func testSpotlightSkipsToolsAlreadyOpened() {
        let plan = HomeLayout.make(recents: [.compressVideo, .removeBackground], favorites: [])
        XCTAssertFalse(plan.spotlight.contains(.compressVideo))
        XCTAssertFalse(plan.spotlight.contains(.removeBackground))
        XCTAssertEqual(plan.spotlight.first, .signPDF)
        XCTAssertEqual(plan.recentIDs, [.compressVideo, .removeBackground])
    }

    func testRecentsDedupeAndCap() {
        var list: [ToolID] = []
        list = RecentList.push(.trimVideo, into: list)
        list = RecentList.push(.signPDF, into: list)
        list = RecentList.push(.trimVideo, into: list)
        XCTAssertEqual(list, [.trimVideo, .signPDF])
        for id in ToolID.allCases {
            list = RecentList.push(id, into: list)
        }
        XCTAssertEqual(list.count, RecentList.storeLimit)
        XCTAssertEqual(list.first, ToolID.allCases.last)
    }

    func testFavoritesToggle() {
        var list = FavoriteList.toggle(.qrCode, in: [])
        XCTAssertEqual(list, [.qrCode])
        list = FavoriteList.toggle(.mergePDFs, in: list)
        list = FavoriteList.toggle(.qrCode, in: list)
        XCTAssertEqual(list, [.mergePDFs])
    }

    func testWeekSavingsRollsOver() {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let first = ISO8601DateFormatter().date(from: "2024-12-30T12:00:00Z")!
        XCTAssertEqual(WeekSavings.key(for: first, calendar: calendar), "2025-W01")
        let later = ISO8601DateFormatter().date(from: "2025-01-08T12:00:00Z")!
        let saved = WeekSavings.empty
            .recording(saved: 1_000, fileCount: 2, on: first, calendar: calendar)
            .recording(saved: 500, fileCount: 1, on: first, calendar: calendar)
        XCTAssertEqual(saved.bytes, 1_500)
        XCTAssertEqual(saved.files, 3)
        let next = saved.recording(saved: 40, fileCount: 1, on: later, calendar: calendar)
        XCTAssertEqual(next.bytes, 40)
        XCTAssertEqual(next.files, 1)
        XCTAssertNotEqual(next.weekKey, saved.weekKey)
        let ignored = saved.recording(saved: -5, fileCount: 1, on: first, calendar: calendar)
        XCTAssertEqual(ignored.bytes, 1_500)
    }

    func testByteFormat() {
        XCTAssertEqual(ByteFormat.string(bytes: 0), "0 B")
        XCTAssertEqual(ByteFormat.string(bytes: 1024), "1.00 KB")
        XCTAssertEqual(ByteFormat.string(bytes: 1_460_000_000), "1.36 GB")
        let onePointFourSix = Int64(1.46 * 1024 * 1024 * 1024)
        XCTAssertEqual(ByteFormat.string(bytes: onePointFourSix), "1.46 GB")
    }
}

final class FileRuleTests: XCTestCase {
    func testOutputNames() {
        XCTAssertEqual(OutputNaming.fileName(original: "clip.mov", suffix: "-compressed", newExtension: "mp4"), "clip-compressed.mp4")
        XCTAssertEqual(OutputNaming.fileName(original: "clip.mov", suffix: "-muted"), "clip-muted.mov")
        XCTAssertEqual(OutputNaming.fileName(original: ".gitignore", suffix: "-copy"), ".gitignore-copy")
        XCTAssertEqual(
            OutputNaming.unique("clip-compressed.mp4", existing: ["clip-compressed.mp4", "clip-compressed-2.mp4"]),
            "clip-compressed-3.mp4"
        )
    }

    func testRenamePreview() {
        let items = [
            RenameItem(name: "Report Final.PDF"),
            RenameItem(name: "notes.txt")
        ]
        let rows = RenameEngine.preview(
            items: items,
            operations: [
                .findReplace(find: "Final", replace: "v2", useRegex: false, caseInsensitive: false),
                .changeCase(.snake),
                .number(start: 1, padding: 2, position: .suffix),
                .newExtension("pdf")
            ]
        )
        XCTAssertEqual(rows[0].proposed, "report_v2-01.pdf")
        XCTAssertNil(rows[0].issue)
        XCTAssertEqual(rows[1].proposed, "notes-02.pdf")
    }

    func testRenameCollisionAndRegex() {
        let rows = RenameEngine.preview(
            items: [RenameItem(name: "a.txt"), RenameItem(name: "b.txt")],
            operations: [.number(start: 1, padding: 1, position: .replace)]
        )
        XCTAssertEqual(rows[0].proposed, "1.txt")
        XCTAssertEqual(rows[1].proposed, "2.txt")
        XCTAssertNil(rows[0].issue)

        let collision = RenameEngine.preview(
            items: [RenameItem(name: "a.txt"), RenameItem(name: "b.txt")],
            operations: [.findReplace(find: "[ab]", replace: "same", useRegex: true, caseInsensitive: false)]
        )
        XCTAssertNotNil(collision[0].issue)
        XCTAssertNotNil(collision[1].issue)

        let regex = RenameEngine.preview(
            items: [RenameItem(name: "IMG_1234.JPG")],
            operations: [.findReplace(find: "IMG_(\\d+)", replace: "photo-$1", useRegex: true, caseInsensitive: true)]
        )
        XCTAssertEqual(regex[0].proposed, "photo-1234.JPG")

        let bad = RenameEngine.preview(
            items: [RenameItem(name: "a.txt")],
            operations: [.findReplace(find: "(", replace: "", useRegex: true, caseInsensitive: false)]
        )
        XCTAssertEqual(bad[0].issue, "Invalid pattern")
    }

    func testDateStampUsesFileDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: 2024, month: 5, day: 9))!
        let rows = RenameEngine.preview(
            items: [RenameItem(name: "shot.png", modified: date)],
            operations: [.dateStamp(format: "yyyyMMdd", useFileDate: true)],
            now: Date(timeIntervalSince1970: 0),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        XCTAssertEqual(rows[0].proposed, "shot20240509.png")
    }

    func testDuplicateGrouping() {
        let files = [
            DuplicateFile(path: "/a/one", size: 10, hash: "aa"),
            DuplicateFile(path: "/b/two", size: 10, hash: "aa"),
            DuplicateFile(path: "/c/three", size: 10, hash: "bb"),
            DuplicateFile(path: "/d/unique", size: 4, hash: "cc"),
            DuplicateFile(path: "/e/empty", size: 0, hash: "dd"),
            DuplicateFile(path: "/f/empty2", size: 0, hash: "dd")
        ]
        let sizes = DuplicateGrouper.sizeCandidates(files)
        XCTAssertEqual(sizes.count, 1)
        XCTAssertEqual(sizes[0].map(\.path).sorted(), ["/a/one", "/b/two", "/c/three"])
        let hashes = DuplicateGrouper.hashGroups(files)
        XCTAssertEqual(hashes.count, 2)
        XCTAssertEqual(hashes[0].map(\.path), ["/a/one", "/b/two"])
        XCTAssertEqual(hashes[1].map(\.hash), ["dd", "dd"])
    }

    func testOrganizeDownloads() {
        let plan = DownloadOrganizer.plan([
            DownloadEntry(name: "photo.JPG", isDirectory: false),
            DownloadEntry(name: "Talk.mp4", isDirectory: false),
            DownloadEntry(name: "notes.pdf", isDirectory: false),
            DownloadEntry(name: "App.dmg", isDirectory: false),
            DownloadEntry(name: "bundle.zip", isDirectory: false),
            DownloadEntry(name: "readme", isDirectory: false),
            DownloadEntry(name: ".DS_Store", isDirectory: false),
            DownloadEntry(name: "Images", isDirectory: true),
            DownloadEntry(name: "Project", isDirectory: true)
        ])
        XCTAssertEqual(plan, [
            PlannedMove(name: "photo.JPG", folder: "Images"),
            PlannedMove(name: "Talk.mp4", folder: "Videos"),
            PlannedMove(name: "notes.pdf", folder: "Documents"),
            PlannedMove(name: "App.dmg", folder: "Installers"),
            PlannedMove(name: "bundle.zip", folder: "Archives"),
            PlannedMove(name: "readme", folder: "Other")
        ])
    }

    func testPageLists() throws {
        XCTAssertEqual(try PageList.parse("1-3, 5", count: 6), [1, 2, 3, 5])
        XCTAssertEqual(try PageList.parse("4-2", count: 5), [4, 3, 2])
        XCTAssertEqual(try PageList.parse("all", count: 3), [1, 2, 3])
        XCTAssertThrowsError(try PageList.parse("9", count: 3))
        XCTAssertThrowsError(try PageList.parse("", count: 3))
        XCTAssertEqual(try PageList.permutation([3, 1, 2], count: 3), [3, 1, 2])
        XCTAssertThrowsError(try PageList.permutation([1, 1, 2], count: 3))
    }
}

final class TextAndDevTests: XCTestCase {
    func testWordCount() {
        let count = TextTransforms.count("Hello world.\n\nSecond line stays.")
        XCTAssertEqual(count.words, 5)
        XCTAssertEqual(count.sentences, 2)
        XCTAssertEqual(count.paragraphs, 2)
        XCTAssertEqual(count.lines, 3)
        XCTAssertEqual(count.readingMinutes, 1)
        XCTAssertEqual(TextTransforms.count("").words, 0)
        XCTAssertEqual(TextTransforms.count("").lines, 0)
    }

    func testCaseConverter() {
        XCTAssertEqual(TextTransforms.apply("hello world", .title), "Hello World")
        XCTAssertEqual(TextTransforms.apply("Hello World", .camel), "helloWorld")
        XCTAssertEqual(TextTransforms.apply("hello world", .pascal), "HelloWorld")
        XCTAssertEqual(TextTransforms.apply("Hello World", .snake), "hello_world")
        XCTAssertEqual(TextTransforms.apply("Hello World", .kebab), "hello-world")
        XCTAssertEqual(TextTransforms.apply("parseURLValue", .snake), "parse_url_value")
        XCTAssertEqual(TextTransforms.apply("already_snake", .camel), "alreadySnake")
    }

    func testHashes() {
        XCTAssertEqual(
            Digests.sha256Hex("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        XCTAssertEqual(
            Digests.sha256Hex(""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        XCTAssertEqual(Digests.sha1Hex("abc"), "a9993e364706816aba3e25717850c26c9cd0d89d")
    }

    func testBase64RoundTrip() throws {
        XCTAssertEqual(Base64Codec.encode("hi", urlSafe: false), "aGk=")
        XCTAssertEqual(try Base64Codec.decode("aGk=", urlSafe: false), "hi")
        let url = Base64Codec.encode(Data([0xfb, 0xff, 0xef]), urlSafe: true)
        XCTAssertFalse(url.contains("+"))
        XCTAssertFalse(url.contains("/"))
        XCTAssertFalse(url.contains("="))
        XCTAssertEqual(try Base64Codec.decodeData(url, urlSafe: true), Data([0xfb, 0xff, 0xef]))
        XCTAssertThrowsError(try Base64Codec.decode("!!!!", urlSafe: false))
    }

    func testJWT() throws {
        let header = Base64Codec.encode("{\"alg\":\"none\"}", urlSafe: true)
        let payload = Base64Codec.encode("{\"sub\":\"satchel\",\"n\":1}", urlSafe: true)
        let parts = try JWTDecoder.decode("\(header).\(payload).sig")
        XCTAssertTrue(parts.headerJSON.contains("none"))
        XCTAssertTrue(parts.payloadJSON.contains("satchel"))
        XCTAssertThrowsError(try JWTDecoder.decode("not-a-token"))
    }

    func testJSONAndCSV() throws {
        let pretty = try JSONFormat.pretty("{\"b\":1,\"a\":2}")
        XCTAssertTrue(pretty.contains("\"a\" : 2") || pretty.contains("\"a\": 2"))
        let mini = try JSONFormat.minify(" { \"b\" : 1 } ")
        XCTAssertEqual(mini, "{\"b\":1}")
        XCTAssertThrowsError(try JSONFormat.pretty("{"))
        let json = try TabularConvert.csvToJSON("name,qty\n\"a,b\",2\n")
        XCTAssertTrue(json.contains("a,b"))
        let csv = try TabularConvert.jsonToCSV("[{\"name\":\"a\",\"ok\":true},{\"name\":\"b\",\"extra\":1}]")
        let header = csv.split(separator: "\n").first.map(String.init) ?? ""
        XCTAssertEqual(Set(header.split(separator: ",").map(String.init)), ["extra", "name", "ok"])
        XCTAssertTrue(csv.contains("true") || csv.contains("1"))
    }

    func testTimestamp() {
        let date = TimestampCodec.date(unix: 1_700_000_000, unit: .seconds)
        XCTAssertEqual(TimestampCodec.unix(from: date, unit: .seconds), 1_700_000_000)
        XCTAssertEqual(TimestampCodec.unix(from: date, unit: .milliseconds), 1_700_000_000_000)
        let iso = TimestampCodec.iso8601(date, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(TimestampCodec.parseISO(iso), date)
    }

    func testUUIDAndPassword() throws {
        var rng = SplitMix64(seed: 42)
        let uuid = UUIDFactory.make(using: &rng)
        XCTAssertTrue(UUIDFactory.isVersion4(uuid))
        var again = SplitMix64(seed: 42)
        XCTAssertEqual(UUIDFactory.make(using: &again), uuid)
        var passwordRNG = SplitMix64(seed: 7)
        let password = try PasswordGenerator.generate(.default, using: &passwordRNG)
        XCTAssertEqual(password.count, 20)
        XCTAssertTrue(password.contains { $0.isLetter && $0.isUppercase })
        XCTAssertTrue(password.contains { $0.isLetter && $0.isLowercase })
        XCTAssertTrue(password.contains { $0.isNumber })
        XCTAssertFalse(password.contains("0"))
        XCTAssertFalse(password.contains("O"))
        XCTAssertThrowsError(try PasswordGenerator.generate(
            PasswordOptions(length: 2, upper: true, lower: true, digits: true, symbols: false, avoidAmbiguous: false),
            using: &passwordRNG
        ))
    }

    func testDiffRegexLinksUnicodeLoremGeohash() throws {
        let rows = LineDiff.diff("a\nb\nc", "a\nx\nc")
        XCTAssertEqual(rows, [.same("a"), .removed("b"), .added("x"), .same("c")])
        let hits = try RegexTester.matches(pattern: #"id=(\d+)"#, text: "id=4 id=12", caseInsensitive: false, multiline: false)
        XCTAssertEqual(hits.map(\.full), ["id=4", "id=12"])
        XCTAssertEqual(hits.map { $0.groups.first ?? "" }, ["4", "12"])
        XCTAssertThrowsError(try RegexTester.matches(pattern: "(", text: "a", caseInsensitive: false, multiline: false))
        XCTAssertEqual(
            LinkCleaner.clean("https://example.com/a?utm_source=x&id=3&fbclid=abc#top"),
            "https://example.com/a?id=3#top"
        )
        let info = UnicodeInspector.inspect("A")
        XCTAssertEqual(info.first?.hex, "U+0041")
        XCTAssertEqual(info.first?.name, "LATIN CAPITAL LETTER A")
        XCTAssertEqual(info.first?.utf8Hex, "41")
        let lorem = LoremIpsum.generate(paragraphs: 2, sentences: 2, wordsPerSentence: 4)
        XCTAssertEqual(lorem.components(separatedBy: "\n\n").count, 2)
        XCTAssertEqual(LoremIpsum.wordList(count: 3), "lorem ipsum dolor")
        XCTAssertEqual(Geohash.encode(latitude: 57.64911, longitude: 10.40744, precision: 11), "u4pruydqqvj")
        let decoded = Geohash.decode("u4pruydqqvj")
        XCTAssertEqual(decoded.latitude, 57.64911, accuracy: 0.0001)
        XCTAssertEqual(decoded.longitude, 10.40744, accuracy: 0.0001)
        let formats = try Coordinates.parse("37.5, -122.25")
        XCTAssertEqual(formats.latitude, 37.5, accuracy: 0.0001)
        let rendered = Coordinates.formats(latitude: 37.5, longitude: -122.25)
        XCTAssertTrue(rendered.dms.contains("N"))
        XCTAssertTrue(rendered.dms.contains("W"))
        XCTAssertFalse(rendered.geohash.isEmpty)
    }
}
