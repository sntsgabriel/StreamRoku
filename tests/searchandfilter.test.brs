' SearchHistoryStore and StreamFilter unit tests.

sub Test_SearchHistory_AddAndDeduplicate()
    Harness_Suite("SearchHistoryStore add, order, and deduplication")
    registry = MockRegistry()
    history = SearchHistoryStore(registry)

    history.Add("matrix")
    history.Add("avatar")
    allSearches = history.GetAll()
    Harness_Equal(allSearches.Count(), 2, "two searches stored")
    Harness_Equal(allSearches[0], "avatar", "latest search is first")
    Harness_Equal(allSearches[1], "matrix", "older search is second")

    ' Adding existing search moves it to the front
    history.Add("matrix")
    allSearches = history.GetAll()
    Harness_Equal(allSearches.Count(), 2, "no duplicates created")
    Harness_Equal(allSearches[0], "matrix", "re-added search moves to the front")
    Harness_Equal(allSearches[1], "avatar", "avatar shifted back")
end sub

sub Test_SearchHistory_CapsAtTen()
    Harness_Suite("SearchHistoryStore 10 item cap and persistence")
    registry = MockRegistry()
    history = SearchHistoryStore(registry)

    for i = 1 to 15
        history.Add("query_" + StrI(i).Trim())
    end for

    allSearches = history.GetAll()
    Harness_Equal(allSearches.Count(), 10, "capped at exactly 10 items")
    Harness_Equal(allSearches[0], "query_15", "newest item kept first")
    Harness_Equal(allSearches[9], "query_6", "tenth item kept")

    ' Verify persistence across reloads
    reloaded = SearchHistoryStore(registry)
    reloadedSearches = reloaded.GetAll()
    Harness_Equal(reloadedSearches.Count(), 10, "10 items persisted and reloaded")
    Harness_Equal(reloadedSearches[0], "query_15", "order preserved on reload")
end sub

sub Test_SearchHistory_RemoveAndClear()
    Harness_Suite("SearchHistoryStore remove and clear")
    registry = MockRegistry()
    history = SearchHistoryStore(registry)

    history.Add("one")
    history.Add("two")
    history.Add("three")

    history.Remove("two")
    allSearches = history.GetAll()
    Harness_Equal(allSearches.Count(), 2, "one item removed")
    Harness_Equal(allSearches[0], "three", "three is first")
    Harness_Equal(allSearches[1], "one", "one is second")

    Harness_Equal(registry.Read("history_item_2"), "", "removing a query removes stale persisted tail")
    history.Clear()
    Harness_Equal(history.GetAll().Count(), 0, "history cleared")

    reloaded = SearchHistoryStore(registry)
    Harness_Equal(reloaded.GetAll().Count(), 0, "cleared history persisted")
    Harness_Equal(registry.Read("history_item_0"), "", "clear deletes persisted queries")
end sub

sub Test_StreamFilter_ResolutionDetection()
    Harness_Suite("StreamFilter resolution detection")
    stream4k = { name: "Torrentio 4K", title: "Movie.2024.2160p.UHD.HDR" }
    stream1080 = { name: "Torrentio 1080p", title: "Movie.2024.FHD.1080p" }
    stream720 = { name: "Torrentio 720p", title: "Movie.2024.HD.720p" }
    stream480 = { name: "Torrentio SD", title: "Movie.2024.480p" }
    streamNone = { name: "Stream", title: "Unknown quality" }
    Harness_Equal(DetectStreamResolution({title: "Birthday SDR"}, "not_set"), "not_set", "film title fragments are not HD or SD quality tags")
    Harness_Equal(DetectStreamResolution({title: "file.1080p.HDR.mkv"}, "not_set"), "1080p", "punctuation separates real quality tags")

    Harness_Equal(DetectStreamResolution(stream4k, "not_set"), "4K", "detects 4K/2160p/UHD")
    Harness_Equal(DetectStreamResolution(stream1080, "not_set"), "1080p", "detects 1080p/FHD")
    Harness_Equal(DetectStreamResolution(stream720, "not_set"), "720p", "detects 720p/HD")
    Harness_Equal(DetectStreamResolution(stream480, "not_set"), "480p", "detects 480p/SD")
    Harness_Equal(DetectStreamResolution(streamNone, "not_set"), "not_set", "falls back to not_set")
    Harness_Equal(DetectStreamResolution(invalid, "not_set"), "not_set", "handles invalid stream safely")
end sub

sub Test_StreamFilter_FormatDetection()
    Harness_Suite("StreamFilter format detection")
    streamMkv = { title: "Movie.mkv", url: "http://example.com/stream.mkv" }
    streamMp4 = { title: "Movie.mp4", url: "http://example.com/stream.mp4" }
    streamHls = { title: "Live", url: "http://example.com/playlist.m3u8" }
    streamNone = { title: "Raw Video", url: "" }

    Harness_Equal(DetectStreamFormat(streamMkv, "not_set"), "MKV", "detects MKV")
    Harness_Equal(DetectStreamFormat(streamMp4, "not_set"), "MP4", "detects MP4")
    Harness_Equal(DetectStreamFormat(streamHls, "not_set"), "HLS", "detects HLS from m3u8")
    Harness_Equal(DetectStreamFormat(streamNone, "not_set"), "not_set", "falls back to not_set")
    Harness_Equal(DetectStreamFormat(invalid, "not_set"), "not_set", "handles invalid stream safely")
end sub

sub Test_StreamFilter_LanguageDetection()
    Harness_Suite("StreamFilter language detection")
    streamPtBr = { name: "Torrentio", title: "Filme 2024 Dublado PT-BR 1080p" }
    streamPt = { name: "Torrentio", title: "Filme 2024 Português [pt]" }
    streamEn = { name: "Torrentio", title: "Movie 2024 English Audio" }
    streamEs = { name: "Torrentio", title: "Pelicula 2024 Español Latino" }
    streamDual = { name: "Torrentio", title: "Filme 2024 Dual Audio" }
    streamNone = { name: "Torrentio", title: "Movie 2024" }
    Harness_Equal(DetectStreamLanguage({title: "Avengers"}, "not_set"), "not_set", "title fragment eng is not an English audio tag")
    Harness_Equal(DetectStreamLanguage({title: "Movie.[ENG].mkv"}, "not_set"), "English", "explicit English metadata token remains recognized")

    Harness_Equal(DetectStreamLanguage(streamPtBr, "not_set"), "Português (BR)", "detects Dublado / PT-BR")
    Harness_Equal(DetectStreamLanguage(streamPt, "not_set"), "Português", "detects generic Português")
    Harness_Equal(DetectStreamLanguage(streamEn, "not_set"), "English", "detects English")
    Harness_Equal(DetectStreamLanguage(streamEs, "not_set"), "Español", "detects Español")
    Harness_Equal(DetectStreamLanguage(streamDual, "not_set"), "Dual / Multi", "detects Dual / Multi")
    Harness_Equal(DetectStreamLanguage(streamNone, "not_set"), "not_set", "falls back to not_set")
end sub

sub Test_StreamFilter_ListFiltering()
    Harness_Suite("StreamFilter FilterStreamList")
    s1 = { name: "S1 4K", title: "Movie 4K Dublado PT-BR.mkv", url: "http://test.mkv" }
    s2 = { name: "S2 1080p", title: "Movie 1080p English.mp4", url: "http://test.mp4" }
    s3 = { name: "S3 720p", title: "Movie 720p Español.mkv", url: "http://test.mkv" }
    streams = [s1, s2, s3]

    allPass = FilterStreamList(streams, "all", "all", "all", "unknown")
    Harness_Equal(allPass.Count(), 3, "all filter keeps all streams")

    only4k = FilterStreamList(streams, "4K", "all", "all", "unknown")
    Harness_Equal(only4k.Count(), 1, "4K filter returns 1 stream")
    Harness_Equal(only4k[0].name, "S1 4K", "returns matching stream")

    onlyMp4 = FilterStreamList(streams, "all", "all", "MP4", "unknown")
    Harness_Equal(onlyMp4.Count(), 1, "MP4 filter returns 1 stream")
    Harness_Equal(onlyMp4[0].name, "S2 1080p", "returns matching stream")

    noneMatch = FilterStreamList(streams, "480p", "all", "all", "unknown")
    Harness_Equal(noneMatch.Count(), 0, "filter with no match returns empty array")

    Harness_Equal(FilterStreamList(invalid, "4K", "all", "all", "unknown").Count(), 0, "handles invalid stream list safely")
end sub
