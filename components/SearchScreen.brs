' SearchScreen — inline keyboard and live results from installed search providers.
' A 600ms debounce avoids a request per keystroke; each edit invalidates the
' previous generation. Two providers run at a time and results never steal
' keyboard focus. Source discovery still happens off the render thread.

sub init()
    m.status = m.top.FindNode("searchStatus")
    m.results = m.top.FindNode("searchResults")

    t = Theme()
    m.top.FindNode("searchTitle").color = t.accent
    m.top.FindNode("searchSub").color = t.textSecondary
    m.status.color = t.accent
    m.results.rowLabelOffset = [0,10]
    m.results.focusBitmapBlendColor = t.accent

    m.results.ObserveField("rowItemSelected", "onResultSelected")

    m.pendingQuery = ""
    m.lastQuery = ""
    m.sources = []
    m.sourcesSignature = ""
    m.sourcesTask = invalid
    m.searchOrder = []
    m.landed = {}
    m.searchFailed = false
    m.rows = []
    m.searchTasks = invalid
    m.searchQueue = []
    m.searchGeneration = 0
    m.keyboard = m.top.FindNode("liveKeyboard")
    m.resultsButton = m.top.FindNode("showResults")
    m.debounce = m.top.FindNode("searchDebounce")
    m.keyboard.ObserveField("text", "onQueryChanged")
    m.resultsButton.ObserveField("buttonSelected", "onShowResults")
    m.debounce.ObserveField("fire", "onSearchDebounce")
end sub

function OnEnter(params as object) as void
    ' The language first, then the title and the subtitle (the markup holds
    ' the English default; the table decides what is shown).
    RefreshTexts()
    m.top.FindNode("searchTitle").text = Lang("search", "title")
    m.top.FindNode("searchSub").text = Lang("search", "liveHint")
    m.resultsButton.text = Lang("search", "showResults")
    ' The add-on set can move while Search is off-screen (install/uninstall,
    ' session swap). Re-derive when it did, so the rows never describe a
    ' registry that no longer exists.
    if m.stores <> invalid and CatalogSignature() <> m.sourcesSignature then ResetSearch()

    ' A caller-supplied query (future rail-injected) runs as soon as sources are
    ' in hand; it is held in m.pendingQuery until they land.
    if params <> invalid and params.query <> invalid and params.query <> ""
        m.pendingQuery = params.query
        EnsureSources()
        return
    end if

    ' Re-entry after Details: results are still here, just take focus back.
    if m.rows.Count() > 0
        m.results.SetFocus(true)
        return
    end if

    EnsureSources()
    ShowSearchDialog()
end function

function OnExit() as void
    m.debounce.control = "stop"
    ' Any query held while sources were still resolving is dropped with the
    ' exit — a later re-entry shows a fresh prompt, it must not replay it.
    m.pendingQuery = ""
    CancelSearch()
    CancelSources()
end function

function OnBackPressed() as boolean
    if m.results.HasFocus() or m.resultsButton.HasFocus()
        m.keyboard.SetFocus(true)
        return true
    end if
    return false
end function

sub BlurFocus()
    m.debounce.control = "stop"
end sub

' --- sources (which add-ons serve which catalogs) ---------------------------

' The installed add-on set the current sources were derived from, as a
' comparable string. Mirrors Home/Discover: derive from live store state, sort
' so ordering cannot make two equal sets look different, join. No network — a
' set comparison, not a re-derivation.
function CatalogSignature() as string
    if m.stores = invalid then return ""
    addons = m.stores.addons.callFunc("AddonsGetAll")
    if addons = invalid then return ""
    parts = []
    for each addon in addons
        if addon.address <> invalid then parts.Push(addon.address)
    end for
    parts.Sort("i")
    return parts.Join(";")
end function

' Resolve the catalog sources, reusing the cache when the installed set is
' unchanged. When every add-on already carries its catalog descriptors the
' sources are built inline; otherwise a CatalogSourcesTask fetches the missing
' manifests off the UI thread (the built-in seeds are the only packets that
' need it).
sub EnsureSources()
    if m.stores = invalid
        m.status.text = Lang("search", "loadFailedAddons")
        return
    end if

    signature = CatalogSignature()
    if signature = m.sourcesSignature and m.sources.Count() > 0 then
        FlushPendingQuery()
        return
    end if

    addons = m.stores.addons.callFunc("AddonsGetAll")
    if addons = invalid then addons = []

    packets = []
    allKnown = true
    for each addon in addons
        address = addon.address
        if address = invalid or address = "" then continue for
        resources = addon.resources
        hasCatalog = false
        if resources <> invalid and Type(resources) = "roArray"
            hasCatalog = m.stores.addons.callFunc("AddonsHasResource", resources, "catalog")
        end if
        if not hasCatalog then continue for
        if addon.catalogs = invalid or Type(addon.catalogs) <> "roArray" then allKnown = false
        name = addon.name
        if name = invalid then name = ""
        packets.Push({ address: address, name: name, resources: resources, catalogs: addon.catalogs })
    end for

    m.sourcesSignature = signature
    if packets.Count() = 0
        m.sources = []
        FlushPendingQuery()
        return
    end if

    if allKnown
        m.sources = packets
        FlushPendingQuery()
        return
    end if

    CancelSources()
    task = AsyncTask_Launch(m.top, "CatalogSourcesTask", "onSourcesLoaded", { addons: packets }, "searchSources")
    m.sourcesTask = task
end sub

' A CatalogSourcesTask result landed. Dropped when it arrived after a cancel
' (m.sourcesTask was cleared) so a late manifest can never repaint a screen the
' user already left.
sub onSourcesLoaded()
    if m.sourcesTask = invalid then return
    task = m.sourcesTask
    m.sourcesTask = invalid
    AsyncTask_Reap(task, m.top, false)

    result = task.result
    if result = invalid or result.sources = invalid or Type(result.sources) <> "roArray"
        m.status.text = Lang("search", "loadFailedAddons")
        return
    end if

    m.sources = result.sources
    FlushPendingQuery()
end sub

sub CancelSources()
    if m.sourcesTask <> invalid
        task = m.sourcesTask
        m.sourcesTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
end sub

' A query that arrived before sources landed: run it now that they have. Nothing
' to do for a plain entry (no pending query).
sub FlushPendingQuery()
    if m.pendingQuery <> invalid and m.pendingQuery <> "" then
        query = m.pendingQuery
        m.pendingQuery = ""
        RunSearch(query)
    end if
end sub

' Drop the sources/rows/results for a changed add-on set so the next entry
' re-resolves from scratch.
sub ResetSearch()
    CancelSearch()
    CancelSources()
    m.sources = []
    m.sourcesSignature = ""
    m.pendingQuery = ""
    m.lastQuery = ""
    m.searchOrder = []
    m.landed = {}
    m.searchFailed = false
    m.rows = []
    ClearResults()
end sub

sub ClearResults()
    if m.results <> invalid
        m.results.content = CreateObject("roSGNode", "ContentNode")
        m.results.numRows = 0
    end if
end sub

' The query prompt. Starts empty, so each search is a fresh prompt rather than an
' edit of the last one.
sub ShowSearchDialog()
    ApplySearchKeyboard(m.keyboard)
    m.keyboard.SetFocus(true)
    if m.keyboard.text.Trim().Len() < 2 then m.status.text = Lang("search", "minChars")
end sub

' Invalidate the previous batch immediately, not when the next timer fires.
' This prevents a slow provider from painting results for a previous prefix.
sub onQueryChanged()
    m.debounce.control = "stop"
    CancelSearch()
    m.pendingQuery = ""
    m.rows = []
    ClearResults()
    query = m.keyboard.text.Trim()
    if query.Len() < 2
        m.status.text = Lang("search", "minChars")
        return
    end if
    m.status.text = Lang("search", "searching")
    m.debounce.control = "start"
end sub

sub onSearchDebounce()
    if not m.top.screenActive then return
    query = m.keyboard.text.Trim()
    if query.Len() >= 2 then RunSearch(query)
end sub

sub onShowResults()
    if m.rows.Count() > 0 then m.results.SetFocus(true)
end sub

' Configures the dialog's internal VoiceTextEditBox, which StandardKeyboardDialog
' builds for itself and which is therefore reached through the dialog rather than
' owned here. The box exists as soon as the node is created — confirmed on
' device, where it is already a roSGNode:VoiceTextEditBox before the dialog is
' ever displayed — so this is called inline and needs nothing to wait for.
'
' No try, deliberately. A throw here prints the offending field and line to the
' device console, and the console is where this is read. The previous version
' swallowed the error, which is how a caret fix that never took became
' indistinguishable from one that did.
sub ApplySearchKeyboard(dialog as object) as void
    if dialog = invalid then return
    editor = dialog.textEditBox
    if editor = invalid then return

    ' Full word input, and the reason voice stopped being letter-by-letter:
    ' DynamicKeyboard builds its internal edit box with voiceEntryType
    ' "alphanumeric", meant for street addresses, and that beats the node class
    ' default of "generic". The dialog's own keyboardDomain defaults to
    ' "generic" too but does not reach this field. VERIFIED WORKING on device.
    editor.voiceEntryType = "generic"
    ' Caret after the text rather than at 0. A caret parked at 0 makes backspace
    ' and the left arrow no-ops by definition while typing still appends, which
    ' from the outside is indistinguishable from a dead keyboard.
    editor.cursorPosition = Len(dialog.text)
end sub

' Kick the query off the render thread against every search-capable catalog
' across the resolved sources. One SearchLoaderTask per add-on runs in parallel,
' each carrying that add-on's catalogs. No rows are premised: the grid stays
' empty until a catalog answers with results, and each row is then inserted in
' the catalog's discovery order.
sub RunSearch(query as string)
    if query = "" then
        m.status.text = Lang("search", "typeNothing")
        return
    end if

    ' Sources still resolving (a task is in flight): hold the query until they
    ' land, then run against whatever arrived.
    if m.sources = invalid or m.sources.Count() = 0
        if m.sourcesTask <> invalid
            m.pendingQuery = query
            m.status.text = Lang("search", "searching")
            return
        end if
        m.status.text = Lang("search", "noSearchAddons")
        return
    end if

    candidates = SearchCandidates()

    CancelSearch()
    m.pendingQuery = ""
    m.lastQuery = query

    if candidates.Count() = 0 then
        m.searchOrder = []
        m.landed = {}
        m.searchFailed = false
        m.rows = []
        ClearResults()
        m.status.text = Lang("search", "noSearchAddons")
        return
    end if

    m.searchOrder = candidates
    m.landed = {}
    m.searchFailed = false
    m.rows = []
    m.searchTasks = {}
    m.status.text = Lang("search", "searching")
    ClearResults()

    LaunchSearchTasks()
end sub

' The ordered list of searchable catalogs across all sources: one entry per
' search-capable catalog, in addon/manifest order. Title is always
' "{Catalog} - {mediaType}"; when two entries would still carry the same title
' (same catalog name, same media type, different add-ons) the add-on's name is
' prefixed so the rows stay distinguishable.
function SearchCandidates() as object
    candidates = []
    if m.stores = invalid then return candidates

    for each source in m.sources
        if source = invalid then continue for
        if source.catalogs = invalid then continue for
        address = source.address
        if address = invalid or address = "" then continue for
        addonName = source.name
        if addonName = invalid then addonName = ""
        for each descriptor in source.catalogs
            if descriptor = invalid then continue for
            if descriptor.type = invalid or descriptor.type = "" then continue for
            if descriptor.id = invalid or descriptor.id = "" then continue for
            caps = m.stores.addons.callFunc("AddonsCatalogCapabilities", descriptor)
            if caps = invalid or not caps.search then continue for
            base = m.stores.addons.callFunc("AddonsCatalogTitle", descriptor, source.name)
            candidates.Push({
                key: address + "|" + descriptor.type + "|" + descriptor.id
                addonKey: address
                addonName: addonName
                addonAddress: address
                rawType: descriptor.type
                catalogId: descriptor.id
                title: base + " - " + TypeSearchLabel(descriptor.type)
            })
        end for
    end for

    titleCounts = {}
    for each c in candidates
        if titleCounts[c.title] = invalid then titleCounts[c.title] = 0
        titleCounts[c.title] = titleCounts[c.title] + 1
    end for
    for each c in candidates
        if titleCounts[c.title] > 1 then c.title = c.addonName + " - " + c.title
    end for

    return candidates
end function

' The media type half of a search row title ("Popular - Movies"). movie/series
' read as "Movies"/"Series"; channel and tv are one family spelled "Tv channel";
' anything else keeps its declared name capitalized.
function TypeSearchLabel(raw as dynamic) as string
    if raw = invalid then return ""
    if raw = "movie" then return Lang("common", "movies")
    if raw = "series" then return Lang("common", "series")
    if raw = "channel" or raw = "tv" then return Lang("search", "tvChannel")
    if raw = "" then return ""
    ' UCase is a global function, not an roString method; the chained form threw
    ' &hf4 the first time an add-on declared a custom catalog type.
    return UCase(raw.Left(1)) + raw.Mid(1)
end function

' One SearchLoaderTask per add-on, passing the catalogs that add-on serves.
' Tasks are independent, so their completion order does not matter.
sub LaunchSearchTasks()
    byAddon = {}
    order = []
    for each candidate in m.searchOrder
        addonKey = candidate.addonKey
        if byAddon.DoesExist(addonKey) = false
            byAddon[addonKey] = { address: candidate.addonAddress, cats: [] }
            order.Push(addonKey)
        end if
        byAddon[addonKey].cats.Push({
            key: candidate.key
            type: candidate.rawType
            id: candidate.catalogId
        })
    end for

    m.searchQueue = []
    for each addonKey in order
        m.searchQueue.Push({ key: addonKey, address: byAddon[addonKey].address, cats: byAddon[addonKey].cats })
    end for
    PumpSearchTasks()
end sub

' At most two providers per generation; stale generations never enter the grid.
sub PumpSearchTasks()
    if m.searchTasks = invalid then return
    active = 0
    for each key in m.searchTasks
        if m.searchTasks[key] <> invalid then active = active + 1
    end for
    while active < 2 and m.searchQueue.Count() > 0
        entry = m.searchQueue.Shift()
        addonKey = entry.key
        task = AsyncTask_Launch(m.top, "SearchLoaderTask", "onSearchLoaded", {
            addonAddress: entry.address
            addonKey: addonKey
            catalogs: entry.cats
            query: m.lastQuery
            generation: m.searchGeneration
        }, "searchLoader" + addonKey)
        m.searchTasks[addonKey] = task
        active = active + 1
    end while
end sub

' One add-on's search landed (or failed). The task reports its sections keyed by
' catalog key; a stale result that landed after CancelSearch is dropped by the
' slot guard — the whole map is invalid (cancel), or the slot was cleared
' (already applied). A section's metas are parked in m.landed by key, then the
' row list is rebuilt from scratch so only catalogs that actually returned
' results appear, in discovery order.
sub onSearchLoaded(event as object)
    if m.searchTasks = invalid then return
    task = event.GetRoSGNode()
    if task = invalid then return
    if task.generation <> m.searchGeneration then return
    addonKey = task.addonKey
    if addonKey = invalid or addonKey = "" then return
    slot = m.searchTasks[addonKey]
    if slot = invalid then return
    m.searchTasks[addonKey] = invalid

    result = task.result
    AsyncTask_Reap(task, m.top, false)

    if result = invalid or result.sections = invalid or Type(result.sections) <> "roArray"
        m.searchFailed = true
    else
        for each section in result.sections
            if section = invalid or section.key = invalid then continue for
            if section.metas <> invalid and section.metas.Count() > 0
                m.landed[section.key] = section.metas
            else if section.error <> invalid and section.error <> ""
                m.searchFailed = true
            end if
        end for
    end if

    RebuildRows()
    PumpSearchTasks()
    UpdateSearchStatus()
end sub

' m.rows = every catalog that landed metas, in the discovery order of
' m.searchOrder. Rows appear only with results, so a catalog with no matches (or
' an add-on that got no usable answer) never occupies a row.
sub RebuildRows()
    prevCount = m.rows.Count()
    rows = []
    for each candidate in m.searchOrder
        metas = m.landed[candidate.key]
        if metas <> invalid and metas.Count() > 0
            rows.Push({
                key: candidate.key
                addonAddress: candidate.addonAddress
                title: candidate.title
                rawType: candidate.rawType
                metas: metas
            })
        end if
    end for
    m.rows = rows
    RenderRows()
    if prevCount = 0 and m.rows.Count() > 0 then m.results.jumpToRowItem = [0, 0]
end sub

' Rebuild the whole grid from m.rows. Every row carries only landed metas, so
' there is nothing to render while a catalog is still resolving — the status
' line says what is happening.
sub RenderRows()
    content = CreateObject("roSGNode", "ContentNode")
    sizes = []
    for each row in m.rows
        rowNode = content.CreateChild("ContentNode")
        rowNode.title = row.title
        for each meta in row.metas
            entry = rowNode.CreateChild("TileContent")
            name = meta.name
            if name = invalid then name = ""
            entry.title = name
            poster = meta.poster
            if poster <> invalid and poster <> "" then entry.hdPosterUrl = poster
            glyph = ""
            if m.stores <> invalid then glyph = m.stores.library.callFunc("LibraryWatchedGlyph", meta.id, meta.type)
            entry.watchedGlyph = glyph
        end for
        ' Each result catalog sizes its own row to its posterShape (folded from
        ' the metas), so a landscape catalog lands wide rows even among 2:3 ones;
        ' falls back to the content type when no shape ships.
        sizes.Push(TileCellSize(row.rawType, TilePosterShape(row.metas)))
    end for
    m.results.content = content
    m.results.rowItemSize = sizes
    ' Per-row slot heights so a landscape/square catalog row sits tight instead of
    ' inheriting the 2:3 itemSize height and leaving a phantom gap (see
    ' TileRowHeights).
    m.results.rowHeights = TileRowHeights(sizes)
    m.results.numRows = m.rows.Count()
end sub

' The status line: "Searching…" while any add-on is still resolving; once all
' settle, clears when results exist, names the failure when every catalog failed,
' or says there were no matches.
sub UpdateSearchStatus()
    if m.searchTasks = invalid then return
    pending = m.searchQueue.Count()
    for each key in m.searchTasks
        if m.searchTasks[key] <> invalid then pending = pending + 1
    end for
    if pending > 0
        m.status.text = Lang("search", "searching")
    else if m.rows.Count() > 0
        m.status.text = ""
    else if m.searchFailed
        m.status.text = Lang("search", "searchFailed")
    else
        m.status.text = Fill(Lang("search", "noResults"), { query: m.lastQuery })
    end if
end sub

sub CancelSearch()
    m.searchGeneration = m.searchGeneration + 1
    m.searchQueue = []
    if m.searchTasks <> invalid
        for each key in m.searchTasks
            task = m.searchTasks[key]
            if task <> invalid then AsyncTask_Reap(task, m.top, true)
        end for
    end if
    m.searchTasks = invalid
end sub

' A result opens DetailsScreen through the same one-action channel Home uses for
' a catalog tile: full meta + the source add-on's address (from the row).
sub onResultSelected()
    data = m.results.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    row = data[0]
    index = data[1]
    if row < 0 or index < 0 then return
    if row >= m.rows.Count() then return
    target = m.rows[row]
    metas = target.metas
    if index >= metas.Count() then return
    m.top.pushRequest = {
        screen: "detailsScreen"
        params: {
            addonAddress: target.addonAddress
            meta: metas[index]
        }
    }
end sub

' The * (options) button reopens the query prompt, prefilled. Everything else
' falls through to the stack (Back pops, arrows move inside the results list).
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "down" and m.keyboard.IsInFocusChain()
        m.resultsButton.SetFocus(true)
        return true
    else if key = "up" and m.resultsButton.HasFocus()
        m.keyboard.SetFocus(true)
        return true
    else if key = "right" and m.resultsButton.HasFocus()
        onShowResults()
        return true
    else if key = "left" and m.results.HasFocus()
        m.keyboard.SetFocus(true)
        return true
    else if key = "options" and not m.keyboard.IsInFocusChain()
        ShowSearchDialog()
        return true
    end if
    return false
end function