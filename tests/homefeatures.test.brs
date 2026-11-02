sub Test_HomeFeatures_LayoutAndProgress()
    Harness_Suite("Home row order, visibility, deduplication and timing")
    cw = { source: "library", metas: [] }
    movies = { source: "catalog", rowKey: "movies", metaType: "movie", metas: [{id:"a"},{id:"b"}] }
    duplicate = { source: "catalog", rowKey: "duplicate", metaType: "movie", metas: [{id:"b"},{id:"a"}] }
    series = { source: "catalog", rowKey: "series", metaType: "series", metas: [{id:"a"},{id:"b"}] }
    rows = [cw, movies, duplicate, series]
    layout = HomeNormalizeLayout({ order: ["series", "continue", "series"], hidden: ["movies"], deduplicate: true })
    visible = HomeOrderedRows(rows, layout)
    Harness_Equal(visible.Count(), 3, "hidden catalog does not suppress its visible duplicate")
    Harness_Equal(HomeRowKey(visible[0]), "series", "explicit order wins")
    Harness_Equal(HomeRowKey(visible[1]), "continue", "continue watching can move independently")
    layout.hidden = []
    visible = HomeOrderedRows(rows, layout)
    Harness_Equal(visible.Count(), 3, "identical movie catalogs collapse despite poster order")
    Harness_Equal(HomeRowKey(visible[2]), "movies", "stable first visible provider is retained")
    Harness_Equal(HomeOrderedRows(rows, layout, true).Count(), 4, "editor includes auto-hidden duplicates")
    layout.hidden = ["continue", "series", "movies", "duplicate"]
    Harness_Equal(HomeOrderedRows(rows, layout).Count(), 0, "all rows can be hidden without losing preferences")
    Harness_Equal(HomeNormalizeLayout({order:["a", 2, "a"], hidden:"bad"}).order.Count(), 1, "malformed or duplicate keys rejected")
    Harness_Equal(HomeNormalizeLayout(invalid).hidden.Count(), 0, "reset restores all rows")
    seconds = { type:"series", season:2, episode:5, position:120, duration:1500 }
    Harness_Equal(HomeResumeLabel(seconds, "{minutes} min", "T{season} E{episode}"), "T2 E5 · 23 min", "local Roku seconds produce correct minutes")
    millis = { type:"series", season:2, episode:5, position:120000, duration:1500000, timeUnit:"milliseconds" }
    Harness_Equal(HomeResumeLabel(millis, "{minutes} min", "T{season} E{episode}"), "T2 E5 · 23 min", "account milliseconds produce the same minutes")
    Harness_Equal(HomeResumeLabel({type:"movie",position:1,duration:0}, "{minutes}", "T{season}"), "", "unknown duration never invents a remaining time")
    Harness_Equal(HomeResumeLabel({type:"movie",position:70,duration:60}, "{minutes}", ""), "0", "completed media cannot show negative time")
end sub

sub Test_HomeFeatures_SettingsAndAccount()
    Harness_Suite("Home layout persists and account actions preserve unrelated fields")
    registry = MockRegistry()
    settings = SettingsStore(registry)
    Harness_Ok(settings.SetHomeLayout({order:["series","continue"],hidden:["movies"],deduplicate:true}), "preferences save")
    reopened = SettingsStore(registry)
    Harness_Equal(reopened.GetHomeLayout().order[0], "series", "order survives reopening settings")
    Harness_Equal(reopened.GetHomeLayout().hidden[0], "movies", "visibility survives reopening settings")
    Harness_Equal(reopened.GetHomeLayout().deduplicate, true, "deduplication survives reopening settings")
    copy = reopened.GetHomeLayout()
    copy.hidden.Push("extra")
    Harness_Equal(reopened.GetHomeLayout().hidden.Count(), 1, "callers cannot mutate persisted layout through returned arrays")
    registry.failWrites = true
    Harness_Equal(reopened.SetHomeLayout(invalid), false, "registry failure is reported")
    Harness_Equal(reopened.GetHomeLayout().order[0], "series", "failed save retains previous in-memory layout")
    codec = StremioLibraryCodec()
    original = LibraryItemFixture("tt1", "movie", "Movie", "old", {timeOffset:120000,duration:600000})
    original.state.watched = "bitfield"
    original.state.custom = "preserve"
    packet = {action:"removeContinue",metaId:"tt1",metaType:"movie",name:"Movie",poster:"",posterShape:""}
    changed = codec.BuildHomeActionItem("stremio", [original], "now", packet)
    Harness_Equal(changed.state.timeOffset, 0, "remove continue clears resume offset")
    Harness_Equal(changed.removed, original.removed, "remove continue preserves library membership")
    Harness_Equal(changed.state.duration, 600000, "duration preserved")
    Harness_Equal(changed.state.custom, "preserve", "unknown account fields preserved")
    Harness_Equal(original.state.timeOffset, 120000, "codec never mutates the original server record")
    packet.action = "markWatched"
    watched = codec.BuildHomeActionItem("stremio", [original], "now", packet)
    Harness_Equal(watched.state.flaggedWatched, 1, "whole title is explicitly marked watched")
    Harness_Equal(watched.state.watched, "bitfield", "existing per-episode bitfield preserved")
    Harness_Equal(codec.BuildHomeActionItem("guest", [original], "now", packet), invalid, "guest never creates an account write")
end sub
