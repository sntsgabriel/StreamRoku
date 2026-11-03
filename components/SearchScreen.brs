' SearchScreen — YouTube TV-style inline search interface with live results.
' Top wide search bar displays current query or placeholder.
' Left column provides search history and suggestions.
' Right column embeds compact DynamicKeyboard in a guarded viewport.
' Bottom area displays recommended content or live multi-catalog search results.
' Loading, connection error, and empty states are strictly separated.
' Connection failures provide a "Try again" action while preserving the query.

sub init()
    m.status = m.top.FindNode("searchStatus")
    m.results = m.top.FindNode("searchResults")
    m.resultsHeader = m.top.FindNode("resultsHeader")
    m.searchQueryDisplay = m.top.FindNode("searchQueryDisplay")
    m.retrySearchBtn = m.top.FindNode("retrySearchBtn")

    t = Theme()
    m.top.FindNode("searchTitle").color = t.accent
    m.top.FindNode("searchSub").color = t.textSecondary
    m.status.color = t.accent
    m.results.rowLabelOffset = [0, 10]
    m.results.focusBitmapBlendColor = t.accentFocus

    searchBarBg = m.top.FindNode("searchBarBg")
    if searchBarBg <> invalid then searchBarBg.color = t.railTint
    searchBarIcon = m.top.FindNode("searchBarIcon")
    if searchBarIcon <> invalid then searchBarIcon.color = t.accent
    if m.resultsHeader <> invalid then m.resultsHeader.color = t.textPrimary
    if m.searchQueryDisplay <> invalid then m.searchQueryDisplay.color = &h888888FF

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
    m.keyboardLayoutTimer = m.top.FindNode("keyboardLayoutTimer")
    m.keyboardLayoutAttempts = 0
    m.keyboardLayoutTimer.ObserveField("fire", "FitSearchKeyboard")
    m.keyboard.ObserveField("focusedChild", "ScheduleKeyboardLayout")
    m.keyboard.ObserveField("text", "onQueryChanged")
    m.resultsButton.ObserveField("buttonSelected", "onShowResults")
    m.debounce.ObserveField("fire", "onSearchDebounce")
    if m.retrySearchBtn <> invalid then m.retrySearchBtn.ObserveField("buttonSelected", "onRetrySearch")
    if m.resultsButton <> invalid then m.resultsButton.visible = false
    if m.resultsHeader <> invalid then m.resultsHeader.visible = false

    m.historyStore = SearchHistoryStore(CreateObject("roRegistrySection", "search_history"), 10)
    m.historyGroup = m.top.FindNode("historyGroup")
    m.historyTitle = m.top.FindNode("historyTitle")
    m.historyList = m.top.FindNode("historyList")
    m.clearHistoryBtn = m.top.FindNode("clearHistoryBtn")
    m.removeHistoryBtn = m.top.FindNode("removeHistoryBtn")
    if m.historyList <> invalid then m.historyList.ObserveField("itemSelected", "onHistorySelected")
    if m.clearHistoryBtn <> invalid then m.clearHistoryBtn.ObserveField("buttonSelected", "onClearHistory")
    if m.removeHistoryBtn <> invalid then m.removeHistoryBtn.ObserveField("buttonSelected", "onRemoveHistoryItem")
    if m.historyTitle <> invalid then m.historyTitle.color = t.accent
    if m.historyList <> invalid then
        m.historyList.color = t.textPrimary
        m.historyList.focusedColor = t.textWhite
        m.historyList.focusBitmapBlendColor = t.accentFocus
    end if
end sub

function OnEnter(params as object) as void
    RefreshTexts()
    ScheduleKeyboardLayout()
    m.top.FindNode("searchTitle").text = Lang("search", "title")
    m.top.FindNode("searchSub").text = Lang("search", "liveHint")
    m.resultsButton.text = Lang("search", "showResults")
    m.resultsButton.visible = (m.rows.Count() > 0)
    if m.retrySearchBtn <> invalid then
        m.retrySearchBtn.text = Lang("search", "retry")
        m.retrySearchBtn.visible = false
    end if
    if m.resultsHeader <> invalid then
        if m.keyboard <> invalid and m.keyboard.text.Trim().Len() >= 2
            m.resultsHeader.text = Lang("search", "searchResults")
        else
            m.resultsHeader.text = Lang("search", "recommended")
        end if
        m.resultsHeader.visible = (m.rows.Count() > 0)
    end if

    UpdateQueryDisplay()

    if m.stores <> invalid and CatalogSignature() <> m.sourcesSignature then ResetSearch()

    if params <> invalid and params.query <> invalid and params.query <> ""
        m.pendingQuery = params.query
        EnsureSources()
        return
    end if

    if m.rows.Count() > 0
        m.results.SetFocus(true)
        return
    end if

    if m.historyTitle <> invalid then m.historyTitle.text = Lang("search", "recentSearches")
    if m.clearHistoryBtn <> invalid then m.clearHistoryBtn.text = Lang("search", "clearHistory")
    if m.removeHistoryBtn <> invalid then m.removeHistoryBtn.text = Lang("search", "removeSelected")
    EnsureSources()
    ShowSearchDialog()
    if m.keyboard <> invalid and m.keyboard.text.Trim().Len() < 2 then ShowHistory()
end function

function OnExit() as void
    m.keyboardLayoutTimer.control = "stop"
    m.debounce.control = "stop"
    m.pendingQuery = ""
    CancelSearch()
    CancelSources()
end function

function OnBackPressed() as boolean
    if m.results.HasFocus() or m.resultsButton.HasFocus() or (m.retrySearchBtn <> invalid and m.retrySearchBtn.HasFocus()) or (m.historyGroup <> invalid and (m.historyList.HasFocus() or m.clearHistoryBtn.HasFocus() or m.removeHistoryBtn.HasFocus()))
        m.keyboard.SetFocus(true)
        return true
    end if
    return false
end function

sub BlurFocus()
    m.keyboardLayoutTimer.control = "stop"
    m.debounce.control = "stop"
end sub

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

sub FlushPendingQuery()
    if m.pendingQuery <> invalid and m.pendingQuery <> "" then
        query = m.pendingQuery
        m.pendingQuery = ""
        RunSearch(query)
    end if
end sub

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
    if m.resultsButton <> invalid then m.resultsButton.visible = false
    if m.resultsHeader <> invalid then m.resultsHeader.visible = false
end sub

sub ShowSearchDialog()
    ApplySearchKeyboard(m.keyboard)
    m.keyboard.SetFocus(true)
    if m.keyboard.text.Trim().Len() < 2
        m.status.text = Lang("search", "minChars")
    else if m.searchTasks = invalid
        m.debounce.control = "start"
    end if
end sub

sub onQueryChanged()
    if m.keyboardLayoutTimer <> invalid then ScheduleKeyboardLayout()
    m.debounce.control = "stop"
    query = m.keyboard.text.Trim()
    if m.searchQueryDisplay <> invalid
        if query <> ""
            m.searchQueryDisplay.text = query
            m.searchQueryDisplay.color = &hFFFFFFFF
        else
            m.searchQueryDisplay.text = Lang("search", "placeholder")
            m.searchQueryDisplay.color = &h888888FF
        end if
    end if
    if query = m.lastQuery and m.searchTasks <> invalid then return
    CancelSearch()
    m.pendingQuery = ""
    m.rows = []
    ClearResults()
    if query.Len() < 2
        m.status.text = Lang("search", "minChars")
        if m.retrySearchBtn <> invalid then m.retrySearchBtn.visible = false
        if m.resultsButton <> invalid then m.resultsButton.visible = false
        if m.resultsHeader <> invalid
            m.resultsHeader.text = Lang("search", "recommended")
            m.resultsHeader.visible = false
        end if
        if m.historyGroup <> invalid then ShowHistory()
        return
    end if
    if m.historyGroup <> invalid then HideHistory()
    if m.resultsHeader <> invalid
        m.resultsHeader.text = Lang("search", "searchResults")
        m.resultsHeader.visible = false
    end if
    if m.resultsButton <> invalid then m.resultsButton.visible = false
    if m.retrySearchBtn <> invalid then m.retrySearchBtn.visible = false
    m.status.text = Lang("search", "searching")
    m.debounce.control = "start"
end sub

sub onSearchDebounce()
    if not m.top.screenActive then return
    query = m.keyboard.text.Trim()
    if query.Len() >= 2
        if query = m.lastQuery and m.searchTasks <> invalid then return
        RunSearch(query)
    end if
end sub

sub onShowResults()
    if m.historyGroup <> invalid and m.historyGroup.visible
        items = m.historyStore.GetAll()
        if items.Count() > 0 then m.historyList.SetFocus(true)
    else if m.rows.Count() > 0
        RememberCompletedSearch()
        m.results.SetFocus(true)
    end if
end sub

sub RememberCompletedSearch()
    if m.historyStore <> invalid and m.lastQuery <> "" then m.historyStore.Add(m.lastQuery)
end sub

sub ApplySearchKeyboard(dialog as object) as void
    if dialog = invalid then return
    editor = dialog.textEditBox
    if editor = invalid then return

    editor.voiceEntryType = "generic"
    editor.cursorPosition = Len(dialog.text)
end sub

sub RunSearch(query as string)
    if m.historyGroup <> invalid then HideHistory()
    if query = "" then
        m.status.text = Lang("search", "typeNothing")
        return
    end if

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
    if m.retrySearchBtn <> invalid then m.retrySearchBtn.visible = false
    ClearResults()

    LaunchSearchTasks()
end sub

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

function TypeSearchLabel(raw as dynamic) as string
    if raw = invalid then return ""
    if raw = "movie" then return Lang("common", "movies")
    if raw = "series" then return Lang("common", "series")
    if raw = "channel" or raw = "tv" then return Lang("search", "tvChannel")
    if raw = "" then return ""
    return UCase(raw.Left(1)) + raw.Mid(1)
end function

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

sub PumpSearchTasks()
    if m.searchTasks = invalid then return
    active = 0
    for each key in m.searchTasks
        if m.searchTasks[key] <> invalid then active = active + 1
    end for
    maxActive = 2
    if m.stores <> invalid and m.stores.settings <> invalid and m.stores.settings.callFunc("SettingsGetLightMode")
        maxActive = 1
    end if
    while active < maxActive and m.searchQueue.Count() > 0
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

sub ShowHistory()
    if m.historyGroup = invalid or m.historyStore = invalid then return
    items = m.historyStore.GetAll()
    if items.Count() = 0
        m.historyList.content = invalid
        HideHistory()
        return
    end if
    content = CreateObject("roSGNode", "ContentNode")
    for each item in items
        node = content.CreateChild("ContentNode")
        node.title = item
    end for
    m.historyList.content = content
    m.historyGroup.visible = true
    if m.results <> invalid then m.results.visible = false
end sub

sub HideHistory()
    if m.historyGroup <> invalid then m.historyGroup.visible = false
    if m.results <> invalid then m.results.visible = true
end sub

sub onHistorySelected()
    if m.historyStore = invalid or m.historyList = invalid then return
    items = m.historyStore.GetAll()
    idx = m.historyList.itemSelected
    if idx < 0 or idx >= items.Count() then return
    selectedQuery = items[idx]
    m.keyboard.text = selectedQuery
    UpdateQueryDisplay()
    m.debounce.control = "stop"
    HideHistory()
    RunSearch(selectedQuery)
end sub

sub onClearHistory()
    if m.historyStore = invalid then return
    m.historyStore.Clear()
    ShowHistory()
    m.keyboard.SetFocus(true)
end sub

sub onRemoveHistoryItem()
    if m.historyStore = invalid or m.historyList = invalid then return
    items = m.historyStore.GetAll()
    idx = m.historyList.itemFocused
    if idx < 0 or idx >= items.Count() then return
    m.historyStore.Remove(items[idx])
    ShowHistory()
    m.keyboard.SetFocus(true)
end sub

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
    if m.resultsButton <> invalid then m.resultsButton.visible = (m.rows.Count() > 0)
    if m.resultsHeader <> invalid then m.resultsHeader.visible = (m.rows.Count() > 0)
end sub

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
        sizes.Push(TileCellSize(row.rawType, TilePosterShape(row.metas)))
    end for
    m.results.content = content
    m.results.rowItemSize = sizes
    m.results.rowHeights = TileRowHeights(sizes)
    m.results.numRows = m.rows.Count()
end sub

sub UpdateSearchStatus()
    if m.searchTasks = invalid then return
    pending = m.searchQueue.Count()
    for each key in m.searchTasks
        if m.searchTasks[key] <> invalid then pending = pending + 1
    end for
    if pending > 0
        m.status.text = Lang("search", "searching")
        if m.retrySearchBtn <> invalid then m.retrySearchBtn.visible = false
        if m.resultsButton <> invalid then m.resultsButton.visible = (m.rows.Count() > 0)
        if m.resultsHeader <> invalid then m.resultsHeader.visible = (m.rows.Count() > 0)
    else if m.rows.Count() > 0
        m.status.text = ""
        if m.retrySearchBtn <> invalid then m.retrySearchBtn.visible = false
        if m.resultsButton <> invalid then m.resultsButton.visible = true
        if m.resultsHeader <> invalid then m.resultsHeader.visible = true
    else if m.searchFailed
        m.status.text = Lang("search", "searchFailed")
        if m.retrySearchBtn <> invalid then
            m.retrySearchBtn.text = Lang("search", "retry")
            m.retrySearchBtn.visible = true
        end if
        if m.resultsButton <> invalid then m.resultsButton.visible = false
        if m.resultsHeader <> invalid then m.resultsHeader.visible = false
    else
        m.status.text = Fill(Lang("search", "noResults"), { query: m.lastQuery })
        if m.retrySearchBtn <> invalid then m.retrySearchBtn.visible = false
        if m.resultsButton <> invalid then m.resultsButton.visible = false
        if m.resultsHeader <> invalid then m.resultsHeader.visible = false
    end if
end sub

sub onRetrySearch()
    if m.lastQuery <> invalid and m.lastQuery <> ""
        RunSearch(m.lastQuery)
    end if
end sub

sub UpdateQueryDisplay()
    if m.searchQueryDisplay = invalid or m.keyboard = invalid then return
    q = m.keyboard.text
    if q <> invalid and q.Trim() <> ""
        m.searchQueryDisplay.text = q
        m.searchQueryDisplay.color = &hFFFFFFFF
    else
        m.searchQueryDisplay.text = Lang("search", "placeholder")
        m.searchQueryDisplay.color = &h888888FF
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
    RememberCompletedSearch()
    m.top.pushRequest = {
        screen: "detailsScreen"
        params: {
            addonAddress: target.addonAddress
            meta: metas[index]
        }
    }
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if m.historyGroup <> invalid and m.historyGroup.visible
        if key = "right" and m.historyList.HasFocus()
            m.keyboard.SetFocus(true)
            return true
        else if key = "left" and m.historyList.HasFocus()
            m.keyboard.SetFocus(true)
            return true
        else if key = "down" and m.historyList.HasFocus()
            m.clearHistoryBtn.SetFocus(true)
            return true
        else if key = "up" and (m.clearHistoryBtn.HasFocus() or m.removeHistoryBtn.HasFocus())
            m.historyList.SetFocus(true)
            return true
        else if key = "right" and m.clearHistoryBtn.HasFocus()
            m.removeHistoryBtn.SetFocus(true)
            return true
        else if key = "left" and m.removeHistoryBtn.HasFocus()
            m.clearHistoryBtn.SetFocus(true)
            return true
        else if key = "right" and (m.clearHistoryBtn.HasFocus() or m.removeHistoryBtn.HasFocus())
            m.keyboard.SetFocus(true)
            return true
        end if
    end if

    if key = "down" and m.keyboard.IsInFocusChain()
        if m.resultsButton <> invalid and m.resultsButton.visible
            m.resultsButton.SetFocus(true)
            return true
        else if m.retrySearchBtn <> invalid and m.retrySearchBtn.visible
            m.retrySearchBtn.SetFocus(true)
            return true
        else if m.historyGroup <> invalid and m.historyGroup.visible and m.historyList <> invalid and m.historyList.content <> invalid and m.historyList.content.getChildCount() > 0
            m.historyList.SetFocus(true)
            return true
        end if
    else if key = "left" and m.keyboard.IsInFocusChain()
        if m.historyGroup <> invalid and m.historyGroup.visible and m.historyList <> invalid and m.historyList.content <> invalid and m.historyList.content.getChildCount() > 0
            m.historyList.SetFocus(true)
            return true
        end if
    else if key = "up" and m.resultsButton.HasFocus()
        m.keyboard.SetFocus(true)
        return true
    else if key = "right" and m.resultsButton.HasFocus()
        if m.retrySearchBtn <> invalid and m.retrySearchBtn.visible
            m.retrySearchBtn.SetFocus(true)
            return true
        else
            onShowResults()
            return true
        end if
    else if key = "left" and m.resultsButton.HasFocus()
        if m.historyGroup <> invalid and m.historyGroup.visible and m.historyList <> invalid
            m.historyList.SetFocus(true)
            return true
        end if
    else if key = "down" and m.resultsButton.HasFocus()
        if m.rows.Count() > 0
            RememberCompletedSearch()
            m.results.SetFocus(true)
            return true
        end if
    else if key = "left" and m.retrySearchBtn <> invalid and m.retrySearchBtn.HasFocus()
        m.resultsButton.SetFocus(true)
        return true
    else if key = "up" and m.retrySearchBtn <> invalid and m.retrySearchBtn.HasFocus()
        m.keyboard.SetFocus(true)
        return true
    else if key = "up" and m.results.HasFocus()
        if m.resultsButton <> invalid and m.resultsButton.visible
            m.resultsButton.SetFocus(true)
        else
            m.keyboard.SetFocus(true)
        end if
        return true
    else if key = "left" and m.results.HasFocus()
        if m.results.rowItemSelected <> invalid and m.results.rowItemSelected.Count() > 1 and m.results.rowItemSelected[1] = 0
            m.keyboard.SetFocus(true)
            return true
        end if
    else if key = "options" and not m.keyboard.IsInFocusChain()
        ShowSearchDialog()
        return true
    end if
    return false
end function

sub ScheduleKeyboardLayout()
    m.keyboardLayoutAttempts = 0
    m.keyboardLayoutTimer.control = "stop"
    m.keyboardLayoutTimer.control = "start"
end sub

sub FitSearchKeyboard()
    if not m.top.screenActive then return
    m.keyboardLayoutAttempts = m.keyboardLayoutAttempts + 1
    fit = FitWidgetRect(m.keyboard.localBoundingRect(), 760, 580, 0.7)
    attempts = 6
    if fit <> invalid
        m.keyboard.scale = fit.scale
        m.keyboard.translation = fit.translation
        attempts = 3
    end if
    if m.keyboardLayoutAttempts < attempts then m.keyboardLayoutTimer.control = "start"
end sub
