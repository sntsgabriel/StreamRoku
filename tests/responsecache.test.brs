function CacheTestClock() as object
    return { now: 0, TotalSeconds: function() : return m.now : end function }
end function

function CacheTestNode(model as object) as object
    node = { model: model }
    node.callFunc = function(method as string, a = invalid as dynamic, b = invalid as dynamic, c = invalid as dynamic, d = invalid as dynamic) as dynamic
        if method = "Read" then return m.model.Read(a, b)
        if method = "Write" then return m.model.Write(a, b, c, d)
        if method = "GetGeneration" then return m.model.GetGeneration()
        if method = "Clear" then m.model.Clear()
        return invalid
    end function
    return node
end function

sub Test_ResponseCache_BoundsAndLifetime()
    Harness_Suite("Response cache is bounded, expiring, isolated and LRU")
    clock = CacheTestClock()
    cache = ResponseCacheStore(clock, 10000, 2, 2000)
    Harness_Ok(cache.Write("first", "one", 10, 0), "first item accepted")
    Harness_Ok(cache.Write("second", "two", 10, 0), "second item accepted")
    Harness_Equal(cache.Read("first", 0), "one", "read returns stored bytes")
    cache.Write("third", "three", 10, 0)
    Harness_Equal(cache.Read("second", 0), "", "least recently read item is evicted")
    Harness_Equal(cache.Read("first", 0), "one", "recently accessed entry survives eviction")
    Harness_Equal(cache.Stats().entries, 2, "entry count is capped")
    Harness_Equal(cache.Stats().evictions, 1, "eviction counted")
    clock.now = 9
    Harness_Equal(cache.Read("first", 0), "one", "fresh entry is available")
    clock.now = 10
    Harness_Equal(cache.Read("first", 0), "", "exact expiration boundary is a miss")
    Harness_Equal(cache.Stats().entries, 0, "expired payloads are released")
    Harness_Equal(cache.Stats().reservedBytes, 0, "expired payload budget is released")
    cache.Write("url/Case", "upper", 30, 0)
    cache.Write("url/case", "lower", 30, 0)
    Harness_Equal(cache.Read("url/Case", 0), "upper", "URL path case is preserved")
    Harness_Equal(cache.Read("url/case", 0), "lower", "distinct URL casing cannot collide")
    cache.Clear()
    Harness_Equal(cache.GetGeneration(), 1, "invalidation advances the request epoch")
    Harness_Equal(cache.Stats().entries, 0, "invalidation clears entries")
    Harness_Ok(not cache.Write("late", "old-account", 30, 0), "late old-generation write is rejected")
    Harness_Ok(cache.Write("late", "new-account", 30, 1), "current generation can write")
    Harness_Equal(cache.Read("late", 0), "", "old task cannot read new-account cache")
    Harness_Equal(cache.Read("late", 1), "new-account", "new task can read new-account cache")
    cache = ResponseCacheStore(clock, 600, 64, 600)
    cache.Write("one", String(60, "x"), 30, 0)
    cache.Write("two", String(60, "x"), 30, 0)
    Harness_Equal(cache.Stats().entries, 1, "byte budget evicts even below count limit")
    Harness_Ok(cache.Stats().reservedBytes <= 600, "serialized storage cannot exceed byte budget")
    Harness_Ok(not cache.Write("huge", String(200, "x"), 30, 0), "oversized entry is skipped")
    Harness_Ok(not cache.Write("bad", "payload", 0, 0), "nonpositive TTL is refused")
    cache.Write("two", "replacement", 30, 0)
    Harness_Equal(cache.Stats().entries, 1, "replacement does not duplicate entries")
    Harness_Equal(cache.Read("two", 0), "replacement", "replacement is readable")
end sub

sub Test_ResponseCache_StoresAndTransport()
    Harness_Suite("Validated catalog and detail cache avoids HTTP until TTL expires")
    clock = CacheTestClock()
    cache = ResponseCacheStore(clock)
    node = CacheTestNode(cache)
    log = []
    body = FormatJson({metas: [{id:"tt1",type:"movie",name:"Original"}], hasMore:true})
    http = Transport(ScriptedHttpClient([{method:"GET",ok:true,status:200,body:body,error:""}], log), node, 0)
    catalogs = CatalogStore(http)
    first = catalogs.Catalog("https://addon.invalid", "movie", "top")
    Harness_Ok(first.ok, "validated catalog succeeds")
    first.metas[0].name = "mutated by caller"
    second = catalogs.Catalog("https://addon.invalid", "movie", "top")
    Harness_Equal(log.Count(), 1, "repeated catalog request uses one HTTP fetch")
    Harness_Equal(second.metas[0].name, "Original", "cached data is isolated from caller mutations")
    Harness_Equal(second.hasMore, true, "pagination flag survives serialization")
    clock.now = 299
    catalogs.Catalog("https://addon.invalid", "movie", "top")
    Harness_Equal(log.Count(), 1, "catalog remains fresh before five minutes")
    clock.now = 300
    catalogs.Catalog("https://addon.invalid", "movie", "top")
    Harness_Equal(log.Count(), 2, "catalog refetches at five-minute expiration")
    catalogs.Catalog("https://addon.invalid", "movie", "top", "skip=100")
    catalogs.Catalog("https://addon.invalid", "series", "top")
    catalogs.Catalog("https://other.invalid", "movie", "top")
    catalogs.Catalog("https://addon.invalid?profile=one", "movie", "top")
    catalogs.Catalog("https://addon.invalid?profile=two", "movie", "top")
    Harness_Equal(log.Count(), 7, "page/type/provider/configuration have separate cache keys")
    catalogs.Catalog("https://addon.invalid", "movie", "top", "search=Matrix")
    clock.now = 359
    catalogs.Catalog("https://addon.invalid", "movie", "top", "search=Matrix")
    Harness_Equal(log.Count(), 8, "search results have a short reusable window")
    clock.now = 360
    catalogs.Catalog("https://addon.invalid", "movie", "top", "search=Matrix")
    Harness_Equal(log.Count(), 9, "search expires after one minute")
    detailLog = []
    metaBody = FormatJson({meta:{id:"tt1",type:"movie",name:"A movie",imdbRating:8.1}})
    detailHttp = Transport(ScriptedHttpClient([{method:"GET",ok:true,status:200,body:metaBody,error:""}], detailLog), node, 0)
    details = EpisodesStore(detailHttp)
    meta = details.GetMeta("https://addon.invalid", "movie", "tt1")
    Harness_Ok(meta.ok, "movie details validated")
    Harness_Equal(meta.meta.imdbRating, "8.1", "normalization still runs before caching")
    details.GetMeta("https://addon.invalid", "movie", "tt1")
    Harness_Equal(detailLog.Count(), 1, "repeated detail request avoids HTTP")
    clock.now = 2159
    details.GetMeta("https://addon.invalid", "movie", "tt1")
    Harness_Equal(detailLog.Count(), 1, "details are fresh before thirty minutes")
    clock.now = 2160
    details.GetMeta("https://addon.invalid", "movie", "tt1")
    Harness_Equal(detailLog.Count(), 2, "details refetch after thirty minutes")
    cache.Clear()
    details.GetMeta("https://addon.invalid", "movie", "tt1")
    Harness_Equal(cache.Stats().entries, 0, "old in-flight request cannot repopulate cache after invalidation")
    freshHttp = Transport(ScriptedHttpClient([{method:"GET",ok:true,status:200,body:metaBody,error:""}], detailLog), node, 1)
    EpisodesStore(freshHttp).GetMeta("https://addon.invalid", "movie", "tt1")
    Harness_Equal(cache.Stats().entries, 1, "new epoch can cache a fresh response")
end sub

sub Test_ResponseCache_FailuresNeverCached()
    Harness_Suite("Cache never persists failures or blocks normal network fallback")
    for each scenario in [
        {body:"broken JSON",status:200,ok:true},
        {body:FormatJson({metas:"bad"}),status:200,ok:true},
        {body:FormatJson({metas:[]}),status:500,ok:false},
        {body:FormatJson({metas:[{id:"tt1",name:"Gateway"}]}),status:504,ok:false}
    ]
        model = ResponseCacheStore(CacheTestClock())
        log = []
        http = Transport(ScriptedHttpClient([{method:"GET",ok:scenario.ok,status:scenario.status,body:scenario.body,error:"test error"}], log), CacheTestNode(model), 0)
        catalog = CatalogStore(http)
        catalog.Catalog("https://invalid.invalid", "movie", "top")
        catalog.Catalog("https://invalid.invalid", "movie", "top")
        Harness_Equal(log.Count(), 2, "failed/malformed/gateway response does not suppress retry")
        Harness_Equal(model.Stats().entries, 0, "failed/malformed/gateway response is not stored")
    end for
    model = ResponseCacheStore(CacheTestClock())
    log = []
    http = Transport(ScriptedHttpClient([{method:"GET",ok:true,status:200,body:FormatJson({meta:{id:"series",videos:[]}}),error:""}], log), CacheTestNode(model), 0)
    details = EpisodesStore(http)
    details.GetMeta("https://addon.invalid", "series", "series")
    details.GetMeta("https://addon.invalid", "series", "series")
    Harness_Equal(log.Count(), 2, "incomplete series details are not cached")
    Harness_Equal(model.Stats().entries, 0, "invalid meta cannot poison cache")
    log = []
    http = Transport(ScriptedHttpClient([{method:"GET",ok:true,status:200,body:FormatJson({metas:[]}),error:""}], log), {}, 0)
    result = CatalogStore(http).Catalog("https://addon.invalid", "movie", "top")
    Harness_Ok(result.ok, "unavailable cache falls back to network without losing result")
    Harness_Equal(log.Count(), 1, "unavailable cache performs normal request")
end sub
