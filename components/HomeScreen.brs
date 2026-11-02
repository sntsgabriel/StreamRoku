' HomeScreen — the stack bottom: continue watching first, then catalog rows.
' Netflix-style immersive hero banner with dynamic selection tracking.
' Collapsible side rail with user profile and sections.
'
' The body is a single RowList: Roku owns the whole grid physics — vertical row
' scrolling/clipping (no row is ever stranded past the screen edge), horizontal
' per-row tile scrolling, row labels, focus reporting and non-focused-row
' dimming. Each row item is a PosterTile (see its interface fields). OK on a
' poster publishes one pushRequest; the Scene does the stack work.
'
' Rows are served by the addon stores: a HomeCatalogsTask walks the add-ons off
' the UI thread, fetching every advertisable catalog, and republishes the row
' set after each completion so the grid fills in one row at a time instead of
' blocking startup on the whole catalog set. On top sits a Continue Watching row
' built from the (local) LibraryStore whenever the user has entries — guests
' included, since that state is local. Rows that fail to load are skipped; on
' total failure the grid stays empty so a break in the fetch pipeline is
' unambiguous.
'
' The grid tree is built lazily on first OnEnter, not in init(): init runs during
' CreateScene, before screen.Show(), and nodes created pre-Show can be dropped by
' the renderer. Rows are inserted as they arrive and the grid is assembled
' exactly once; later visits either leave the tree alone (nothing changed) or
' refresh only the Continue Watching row in place (progress was made elsewhere).
' The RowList's own scroll + focus therefore survive every trip away and back.

sub init()
    m.homeLayout = HomeNormalizeLayout(invalid)
    m.homeMenu = m.top.FindNode("homeMenu")
    m.homeMenu.ObserveField("choice", "onHomeMenuChoice")
    m.heroProgress = m.top.FindNode("heroProgress")
    m.menuPage = ""
    m.menuError = ""
    m.catalog = m.top.FindNode("catalog")
    m.catalog.ObserveField("rowItemSelected", "onRowItemSelected")
    m.catalog.ObserveField("rowItemFocused", "UpdateSelectedTitle")
    m.catalogArea = m.top.FindNode("catalogArea")
    m.selectedTitle = m.top.FindNode("selectedTitle")
    m.emptyState = m.top.FindNode("emptyState")
    m.rail = m.top.FindNode("rail")
    m.rail.ObserveField("rowItemSelected", "onRailItemSelected")
    m.railBg = m.top.FindNode("railBg")
    m.railClip = m.top.FindNode("railClip")
    m.railAnimation = m.top.FindNode("railAnimation")
    m.railWidthInterpolator = m.top.FindNode("railWidthInterpolator")
    m.railBg.ObserveField("width", "ApplyRailWidth")
    m.railExpanded = false
    m.railMotionAllowed = true
    m.homeSub = m.top.FindNode("homeSub")
    m.homeHint = ""

    ' Hero banner nodes
    m.heroBg = m.top.FindNode("heroBg")
    m.heroBgNext = m.top.FindNode("heroBgNext")
    m.heroLogo = m.top.FindNode("heroLogo")
    m.heroTitle = m.top.FindNode("heroTitle")
    m.heroMeta = m.top.FindNode("heroMeta")
    m.heroDesc = m.top.FindNode("heroDesc")
    m.heroInfoGroup = m.top.FindNode("heroInfoGroup")
    m.heroDebounceTimer = m.top.FindNode("heroDebounceTimer")
    m.heroCrossfadeAnim = m.top.FindNode("heroCrossfadeAnim")

    ' Profile nodes
    m.profileName = m.top.FindNode("profileName")
    m.profileSub = m.top.FindNode("profileSub")
    m.avatarInitial = m.top.FindNode("avatarInitial")

    if m.heroDebounceTimer <> invalid then m.heroDebounceTimer.ObserveField("fire", "onHeroDebounce")
    if m.heroCrossfadeAnim <> invalid then m.heroCrossfadeAnim.ObserveField("state", "onHeroCrossfadeState")
    if m.heroBgNext <> invalid then m.heroBgNext.ObserveField("loadStatus", "onHeroBgLoaded")

    m.heroMetadata = {}
    m.heroMetaTask = invalid
    m.heroGeneration = 0

    t = Theme()
    homeBg = m.top.FindNode("homeBg")
    if homeBg <> invalid then homeBg.color = t.screenBg
    m.top.FindNode("homeTitle").color = t.accent
    m.homeSub.color = t.textSecondary
    if m.selectedTitle <> invalid then m.selectedTitle.color = t.textPrimary
    if m.heroTitle <> invalid then m.heroTitle.color = t.textPrimary
    if m.heroMeta <> invalid then m.heroMeta.color = &hCCCCCCFF
    if m.heroDesc <> invalid then m.heroDesc.color = &hEEEEEEFF
    if m.profileName <> invalid then m.profileName.color = t.textPrimary
    if m.profileSub <> invalid then m.profileSub.color = t.textSecondary
    m.emptyState.color = t.textSecondary
    m.heroProgress.color = t.accent
    m.top.FindNode("brand").color = t.accent
    m.top.FindNode("compactBrand").color = t.accent
    m.top.FindNode("railBg").color = t.railTint
    m.catalog.rowLabelOffset = [0, 10]
    m.catalog.focusBitmapBlendColor = t.accentFocus

    m.catalogRowsBuilt = false
    m.catalogRows = []
    m.gridRows = []
    m.gridBuilt = false
    m.gridLanguage = ""
    m.cwSignature = ""
    m.catalogSignature = ""
    m.railBuilt = false
    m.railLanguage = ""
    ApplyRailWidth()
end sub

sub StartCatalogLoad()
    if m.catalogRowsBuilt or m.catalogTask <> invalid then return
    if m.stores = invalid then
        m.catalogRowsBuilt = true
        return
    end if
    addons = []
    for each addon in m.stores.addons.callFunc("AddonsGetAll")
        addons.Push({ address: addon.address, catalogs: addon.catalogs, name: addon.name })
    end for
    m.catalogSignature = CatalogSignature()
    if addons.Count() = 0 then
        m.catalogRowsBuilt = true
        return
    end if
    task = AsyncTask_Launch(m.top, "HomeCatalogsTask", "onCatalogState", { addons: addons }, invalid)
    m.catalogTask = task
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

sub EnsureCurrentRows()
    if m.stores = invalid or not m.gridBuilt then return
    if m.catalogSignature = CatalogSignature() then return
    RebuildRows()
end sub

sub onCatalogState(event as object)
    if m.catalogRowsBuilt then return
    state = event.GetData()
    if state = invalid then return
    ' >= rather than =: a lost or coalesced result message must not wedge the
    ' walk — with an exact match, one missed row would fail the check forever
    ' and silently truncate the grid. ApplyCatalogRow slots by row.index, so a
    ' gapped arrival still lands every later row in its deterministic slot.
    if state.row <> invalid and state.row.index >= m.catalogRows.Count() then ApplyCatalogRow(state.row)
    if state.done = true then FinishCatalogLoad()
end sub

' Insert one streamed catalog row at its deterministic slot. All rows arrive in
' ascending index order, so the grid stays in task order even though each
' snapshot is a full copy.
sub ApplyCatalogRow(row as object)
    cwOffset = 0
    if m.gridRows.Count() > 0 and m.gridRows[0].source = "library" then cwOffset = 1
    descriptor = {
        source: "catalog"
        title: row.title
        metaType: row.metaType
        addonAddress: row.addonAddress
        posterShape: TilePosterShape(row.metas)
        metas: row.metas
        addonName: row.addonName
    }
    descriptor.rowKey = row.addonAddress + "|" + row.metaType + "|" + StringOf(row.catalogId)
    if row.catalogId = invalid then descriptor.rowKey = row.addonAddress + "|" + row.metaType + "|" + row.title
    m.catalogRows.Push(descriptor)
    if m.homeLayout <> invalid and (m.homeLayout.order.Count() > 0 or m.homeLayout.hidden.Count() > 0 or m.homeLayout.deduplicate)
        ReflowHomeRows()
        return
    end if
    slot = cwOffset + row.index
    node = MakeRowNode(descriptor, invalid)
    if m.catalog.content <> invalid and m.catalog.content.getChildCount() > slot
        m.catalog.content.InsertChild(node, slot)
    else
        m.catalog.content.AppendChild(node)
    end if
    m.gridRows.Push(descriptor)
    m.catalog.numRows = m.gridRows.Count()
    ApplyCatalogSizes()
    ResyncRowLabels()
    UpdateCatalogFeedback()
end sub

function DuplicateCounts() as object
    counts = {}
    for each row in m.gridRows
        title = row.title
        if title = invalid then title = ""
        if counts[title] = invalid then counts[title] = 0
        counts[title] = counts[title] + 1
    end for
    return counts
end function

sub ResyncRowLabels()
    if m.catalog.content = invalid then return
    counts = DuplicateCounts()
    for r = 0 to m.gridRows.Count() - 1
        label = m.gridRows[r].title
        if label = invalid then label = ""
        if counts[label] > 1 then label = label + " · " + TypeLabel(m.gridRows[r].metaType)
        node = m.catalog.content.GetChild(r)
        if node <> invalid and node.title <> label then node.title = label
    end for
end sub

sub FinishCatalogLoad()
    m.catalogRowsBuilt = true
    UpdateCatalogFeedback()
    if m.catalogTask <> invalid
        task = m.catalogTask
        m.catalogTask = invalid
        AsyncTask_Reap(task, m.top, false)
    end if
end sub

sub BuildRows()
    m.gridRows = []
    cw = LibraryRow()
    if cw <> invalid then m.gridRows.Push(cw)
    for each row in m.catalogRows
        m.gridRows.Push(row)
    end for

    m.gridRows = HomeOrderedRows(m.gridRows, m.homeLayout)
    counts = DuplicateCounts()

    content = CreateObject("roSGNode", "ContentNode")
    for r = 0 to m.gridRows.Count() - 1
        content.AppendChild(MakeRowNode(m.gridRows[r], counts))
    end for
    m.catalog.content = content
    m.catalog.numRows = m.gridRows.Count()
    ApplyCatalogSizes()
    UpdateCatalogFeedback()
end sub

function RebuildRows() as void
    if m.catalogTask <> invalid
        task = m.catalogTask
        m.catalogTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
    m.catalogRowsBuilt = false
    m.catalogRows = []
    m.gridBuilt = false
    m.catalogSignature = ""
    BuildRows()
    m.gridBuilt = true
    m.gridLanguage = TextsLanguage()
    StartCatalogLoad()
end function

function MakeRowNode(row as object, counts as dynamic) as object
    node = CreateObject("roSGNode", "ContentNode")
    label = row.title
    if label = invalid then label = ""
    if counts <> invalid and counts[label] <> invalid and counts[label] > 1
        label = label + " · " + TypeLabel(row.metaType)
    end if
    node.title = label
    for each meta in row.metas
        glyph = meta.watchedGlyph
        if glyph = invalid and m.stores <> invalid then glyph = m.stores.library.callFunc("LibraryWatchedGlyph", meta.id, meta.type)
        PaintTileFields(node.CreateChild("TileContent"), meta, glyph)
    end for
    return node
end function

function RowCellSize(row as object) as object
    mt = invalid
    ps = ""
    if row <> invalid then
        mt = row.metaType
        if row.posterShape <> invalid then ps = row.posterShape
    end if
    return TileCellSize(mt, ps)
end function

function RowSizes() as object
    sizes = []
    for each row in m.gridRows
        sizes.Push(RowCellSize(row))
    end for
    return sizes
end function

sub ApplyCatalogSizes()
    sizes = RowSizes()
    m.catalog.rowItemSize = sizes
    m.catalog.rowHeights = TileRowHeights(sizes)
end sub

sub PaintTileFields(item as object, meta as object, fallbackGlyph as dynamic)
    name = meta.name
    if name = invalid then name = ""
    item.title = name
    item.shortDescriptionLine2 = ""
    if meta.type <> invalid then item.shortDescriptionLine2 = TypeLabel(meta.type)
    poster = meta.poster
    if poster = invalid then poster = ""
    item.hdPosterUrl = poster
    item.progress = 0
    if meta.progress <> invalid and meta.progress > 0 then item.progress = meta.progress
    glyph = meta.watchedGlyph
    if glyph = invalid then glyph = fallbackGlyph
    if glyph = invalid then glyph = ""
    item.watchedGlyph = glyph

    bg = meta.background
    if bg = invalid then bg = ""
    item.background = bg

    logo = meta.logo
    if logo = invalid then logo = ""
    item.logo = logo

    desc = meta.description
    if desc = invalid then desc = ""
    item.description = desc

    rel = meta.releaseInfo
    if rel = invalid then rel = ""
    item.releaseInfo = rel

    rating = meta.imdbRating
    if rating = invalid then rating = ""
    item.imdbRating = rating

    rt = meta.runtime
    if rt = invalid then rt = ""
    item.runtime = rt

    mid = meta.id
    if mid = invalid then mid = ""
    item.metaId = mid

    mtype = meta.type
    if mtype = invalid then mtype = ""
    item.metaType = mtype
    item.resumeInfo = HomeResumeLabel(meta, Lang("home", "remainingMinutes"), Lang("home", "episodeProgress"))
end sub

function LibraryRow() as dynamic
    if m.stores = invalid then return invalid
    entries = m.stores.library.callFunc("LibraryContinueWatching")
    if entries = invalid then return invalid
    if entries.Count() = 0 then return invalid
    metas = []
    for each entry in entries
        metas.Push({
            id: entry.metaId
            type: entry.metaType
            name: entry.name
            poster: entry.poster
            posterShape: entry.posterShape
            background: entry.background
            logo: entry.logo
            description: entry.description
            releaseInfo: entry.releaseInfo
            imdbRating: entry.imdbRating
            videoId: entry.videoId
            season: entry.season
            episode: entry.episode
            timeUnit: entry.timeUnit
            duration: entry.duration
            position: entry.position
            progress: m.stores.library.callFunc("LibraryProgressFraction", entry.metaId)
            watchedGlyph: m.stores.library.callFunc("LibraryWatchedGlyph", entry.metaId, entry.metaType)
        })
    end for
    return { source: "library", title: Lang("home", "continueWatching"), metaType: "", posterShape: TilePosterShape(metas), metas: metas }
end function

function ContinueWatchingSignature() as string
    if m.stores = invalid then return ""
    entries = m.stores.library.callFunc("LibraryContinueWatching")
    if entries = invalid or entries.Count() = 0 then return ""
    parts = []
    for each entry in entries
        position = entry.position
        if position = invalid then position = 0
        duration = entry.duration
        if duration = invalid then duration = 0
        glyph = m.stores.library.callFunc("LibraryWatchedGlyph", entry.metaId, entry.metaType)
        parts.Push(entry.metaId + "|" + entry.videoId + "|" + entry.season.toStr() + "|" + entry.episode.toStr() + "|" + position.toStr() + "|" + duration.toStr() + "|" + glyph)
    end for
    parts.Sort("i")
    return parts.Join(";")
end function

sub RefreshContinueWatching()
    ReflowHomeRows()
end sub

sub SyncContinueWatchingRow(node as object, metas as object)
    existing = node.getChildCount()
    for c = 0 to metas.Count() - 1
        item = invalid
        if c < existing
            item = node.GetChild(c)
        else
            item = node.CreateChild("TileContent")
        end if
        PaintTileFields(item, metas[c], metas[c].watchedGlyph)
    end for
    while node.getChildCount() > metas.Count()
        node.RemoveChildIndex(node.getChildCount() - 1)
    end while
end sub

function MetaAddress() as string
    if m.stores = invalid then return ""
    addon = m.stores.addons.callFunc("AddonsGet", "com.linvo.cinemeta")
    if addon = invalid then return ""
    return addon.address
end function

function TypeLabel(metaType as string) as string
    if metaType = "movie" then return Lang("common", "movies")
    if metaType = "series" then return Lang("common", "series")
    if metaType = "channel" or metaType = "tv" then return Lang("common", "channels")
    return metaType
end function

function OnEnter(params as object) as void
    RefreshTexts()
    if m.stores <> invalid and m.stores.settings <> invalid
        m.railMotionAllowed = not m.stores.settings.callFunc("SettingsGetLightMode")
    end if
    if m.stores <> invalid then m.homeLayout = HomeNormalizeLayout(m.stores.settings.callFunc("SettingsGetHomeLayout"))
    m.homeSub.text = Lang("home", "optionsHint")
    m.top.FindNode("homeTitle").text = Lang("home", "title")
    if not m.railBuilt or m.railLanguage <> TextsLanguage() then BuildRail()
    UpdateProfileDisplay()
    StartCatalogLoad()
    sig = ContinueWatchingSignature()
    if not m.gridBuilt or m.gridLanguage <> TextsLanguage()
        BuildRows()
        m.gridBuilt = true
        m.gridLanguage = TextsLanguage()
    else if sig <> m.cwSignature
        RefreshContinueWatching()
    end if
    m.cwSignature = sig
    EnsureCurrentRows()
    UpdateCatalogFeedback()
    if m.railWasFocus = true or m.gridRows.Count() = 0
        SetHomeFocus(true)
    else
        SetHomeFocus(false)
    end if
end function

function OnExit() as void
    CancelHeroMeta()
    m.railAnimation.control = "stop"
    if m.heroDebounceTimer <> invalid then m.heroDebounceTimer.control = "stop"
end function

function OnBackPressed() as boolean
    if m.homeMenu <> invalid and m.homeMenu.visible
        HandleHomeMenuBack()
        return true
    end if
    if m.rail.HasFocus() and m.gridRows.Count() > 0
        SetHomeFocus(false)
        return true
    end if
    return false
end function

sub BlurFocus()
    CancelHeroMeta()
    if m.heroDebounceTimer <> invalid then m.heroDebounceTimer.control = "stop"
    m.railWasFocus = m.rail.HasFocus()
    CancelOpen()
end sub

sub UpdateProfileDisplay()
    user = invalid
    if m.stores <> invalid and m.stores.auth <> invalid
        user = m.stores.auth.callFunc("AuthGetUser")
    end if
    name = Lang("home", "guest")
    initial = "U"
    if user <> invalid
        if user.email <> invalid and user.email <> ""
            name = user.email
            initial = UCase(user.email.Left(1))
        else if user.fullname <> invalid and user.fullname <> ""
            name = user.fullname
            initial = UCase(user.fullname.Left(1))
        end if
    end if
    if m.profileName <> invalid then m.profileName.text = name
    if m.profileSub <> invalid then m.profileSub.text = ""
    if m.avatarInitial <> invalid then m.avatarInitial.text = initial
end sub

sub BuildRail()
    entries = [
        { label: Lang("home", "navSearch"), glyph: "pkg:/images/search.png", screen: "searchScreen" }
        { label: Lang("home", "navHome"), glyph: "pkg:/images/nav-home.png", screen: "homeScreen", active: true }
        { label: Lang("home", "navSeries"), glyph: "pkg:/images/nav-series.png", screen: "discoverScreen", params: { type: "series" } }
        { label: Lang("home", "navMovies"), glyph: "pkg:/images/nav-movies.png", screen: "discoverScreen", params: { type: "movie" } }
        { label: Lang("home", "navLibrary"), glyph: "pkg:/images/library.png", screen: "libraryScreen" }
        { label: Lang("home", "navAddons"), glyph: "pkg:/images/puzzle.png", screen: "addonsScreen" }
        { label: Lang("home", "navSettings"), glyph: "pkg:/images/settings.png", screen: "settingsScreen" }
        { label: Lang("home", "navCustomize"), glyph: "pkg:/images/settings.png", screen: "customizeHome" }
        { label: Lang("home", "navSupport"), glyph: "pkg:/images/support.png", screen: "supportDialog", dialog: true }
    ]
    m.railEntries = entries
    content = CreateObject("roSGNode", "ContentNode")
    for each entry in entries
        row = content.CreateChild("ContentNode")
        item = row.CreateChild("ContentNode")
        item.title = entry.glyph
        item.shortDescriptionLine1 = entry.label
        active = false
        if entry.active = true then active = true
        item.AddFields({menuExpanded: m.railExpanded, active: active})
    end for
    m.rail.content = content
    m.rail.numRows = 8
    m.railBuilt = true
    m.railLanguage = TextsLanguage()
end sub

sub onRailItemSelected()
    data = m.rail.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    row = data[0]
    if row < 0 or m.railEntries = invalid or row >= m.railEntries.Count() then return
    target = m.railEntries[row]
    if target.screen = "customizeHome"
        m.homeMenuOrigin = "rail"
        ShowHomeCustomization()
        return
    end if
    if target.screen = "homeScreen"
        SetHomeFocus(false)
        return
    end if
    request = {
        screen: target.screen
        params: {}
    }
    if target.params <> invalid then request.params = target.params
    if target.dialog = true then request.dialog = true
    m.top.pushRequest = request
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "right" and m.rail.HasFocus()
        SetHomeFocus(false)
        return true
    else if key = "left" and m.catalog.HasFocus()
        SetHomeFocus(true)
        return true
    else if key = "replay"
        if m.catalogTask = invalid
            InvalidateHomeCache()
            RebuildRows()
        end if
        return true
    else if key = "options"
        if m.catalog.HasFocus()
            OpenHomeActions()
            return true
        else if m.rail.HasFocus()
            m.homeMenuOrigin = "rail"
            ShowHomeCustomization()
            return true
        end if
    end if
    return false
end function

sub onRowItemSelected(event as object)
    data = event.GetData()
    if data = invalid or data.Count() < 2 then return
    row = data[0]
    index = data[1]
    if row < 0 or index < 0 or m.stores = invalid then return
    if row >= m.gridRows.Count() then return
    metas = m.gridRows[row].metas
    if index >= metas.Count() then return

    item = metas[index]
    if m.gridRows[row].source = "library"
        OpenContinueWatching(item)
    else
        m.top.pushRequest = {
            screen: "detailsScreen"
            params: {
                addonAddress: m.gridRows[row].addonAddress
                meta: item
            }
        }
    end if
end sub

sub OpenContinueWatching(item as object)
    address = MetaAddress()
    CancelOpen()
    m.pendingOpen = {
        address: address
        meta: {
            id: item.id
            type: item.type
            name: item.name
            poster: item.poster
        }
        resume: {
            videoId: item.videoId
            season: item.season
            episode: item.episode
            position: item.position
        }
    }
    ShowHomeBusy(true)

    task = AsyncTask_Launch(m.top, "MetaLoaderTask", "onContinueWatchingLoaded", {
        addonAddress: address
        metaType: item.type
        metaId: item.id
    }, "continueWatchingLoader")
    m.openTask = task
end sub

sub CancelOpen()
    if m.openTask <> invalid
        task = m.openTask
        m.openTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
    m.pendingOpen = invalid
    ShowHomeBusy(false)
end sub

sub onContinueWatchingLoaded()
    if m.openTask = invalid then return
    task = m.openTask
    m.openTask = invalid
    result = task.result
    AsyncTask_Reap(task, m.top, false)

    pending = m.pendingOpen
    m.pendingOpen = invalid
    ShowHomeBusy(false)
    if pending = invalid then return

    meta = pending.meta
    if result <> invalid and result.ok and result.meta <> invalid then meta = result.meta
    m.top.pushRequest = {
        screen: "detailsScreen"
        params: {
            addonAddress: pending.address
            meta: meta
            resume: pending.resume
        }
    }
end sub

sub ShowHomeBusy(show as boolean)
    if m.homeSub = invalid then return
    if show
        if m.homeSub.text <> Lang("home", "loading")
            m.homeHint = m.homeSub.text
            m.homeSub.text = Lang("home", "loading")
        end if
    else
        if m.homeHint <> invalid and m.homeHint <> "" then m.homeSub.text = m.homeHint
        m.homeHint = ""
    end if
end sub

sub UpdateCatalogFeedback()
    if m.emptyState = invalid then return
    empty = m.gridRows.Count() = 0
    m.emptyState.visible = empty
    if empty
        if m.selectedTitle <> invalid then m.selectedTitle.text = ""
        if m.heroTitle <> invalid then m.heroTitle.text = ""
        if m.heroDesc <> invalid then m.heroDesc.text = ""
        if m.heroMeta <> invalid then m.heroMeta.text = ""
        if m.heroProgress <> invalid then m.heroProgress.visible = false
        if m.catalogRowsBuilt
            m.emptyState.text = Lang("home", "empty")
            if m.catalogRows.Count() > 0 then m.emptyState.text = Lang("home", "emptyHome")
        else
            m.emptyState.text = Lang("home", "loading")
        end if
    else
        UpdateSelectedTitle()
    end if
end sub

sub UpdateSelectedTitle()
    if m.catalog = invalid or m.catalog.content = invalid then return
    focusedItem = m.catalog.rowItemFocused
    if focusedItem = invalid or focusedItem.Count() < 2 then return
    if focusedItem[0] < 0 or focusedItem[1] < 0 then return
    row = m.catalog.content.GetChild(focusedItem[0])
    if row = invalid then return
    item = row.GetChild(focusedItem[1])
    if item = invalid then return

    if m.selectedTitle <> invalid
        m.selectedTitle.text = item.title
        if item.shortDescriptionLine2 <> invalid and item.shortDescriptionLine2 <> "" then m.selectedTitle.text = item.title + " · " + item.shortDescriptionLine2
    end if

    CancelHeroMeta()
    m.heroGeneration = m.heroGeneration + 1
    if m.heroDebounceTimer <> invalid
        m.heroDebounceTimer.control = "stop"
        m.heroDebounceTimer.control = "start"
    end if
end sub

sub UpdateHeroProgressLayout()
    ' Keep the hero and catalog anchored while RowList animates between rows.
    ' Changing translation on focus (or after delayed metadata) adds a second
    ' jump on top of the native scroll, especially when reversing direction.
    if m.heroProgress <> invalid
        m.heroProgress.visible = m.heroProgress.text <> ""
    end if
end sub

function SelectedHeroItem() as dynamic
    if m.catalog = invalid or m.catalog.content = invalid then return invalid
    focusedItem = m.catalog.rowItemFocused
    if focusedItem = invalid or focusedItem.Count() < 2 then return invalid
    if focusedItem[0] < 0 or focusedItem[1] < 0 then return invalid
    row = m.catalog.content.GetChild(focusedItem[0])
    if row = invalid then return invalid
    item = row.GetChild(focusedItem[1])
    if item = invalid then return invalid
    return item
end function

sub onHeroDebounce()
    if not m.top.screenActive then return
    if m.homeMenu <> invalid and m.homeMenu.visible then return
    item = SelectedHeroItem()
    if item = invalid then return
    key = item.metaType + ":" + item.metaId
    if m.heroMetadata.DoesExist(key) then MergeHeroMetadata(item, m.heroMetadata[key])
    ' Reuse already loaded catalog artwork before doing any network work.
    if item.background = ""
        for each row in m.catalogRows
            for each meta in row.metas
                if meta.id = item.metaId and meta.type = item.metaType then MergeHeroMetadata(item, meta)
                if item.background <> "" then exit for
            end for
            if item.background <> "" then exit for
        end for
    end if
    RenderHomeHero(item)
    if item.background <> "" then return
    focused = m.catalog.rowItemFocused
    if focused[0] >= m.gridRows.Count() then return
    if m.gridRows[focused[0]].source <> "library" then return
    if m.heroMetadata.DoesExist(key) then return
    if item.metaId = "" or item.metaType = "" then return
    address = MetaAddress()
    if address = "" then return
    CancelHeroMeta()
    m.heroMetaTask = AsyncTask_Launch(m.top, "MetaLoaderTask", "onHeroMetadataLoaded", {
        addonAddress: address
        metaType: item.metaType
        metaId: item.metaId
        requestGeneration: m.heroGeneration
    }, "homeHeroMetadata")
end sub

sub MergeHeroMetadata(item as object, meta as object)
    for each field in ["background", "logo", "description", "releaseInfo", "imdbRating", "runtime"]
        if item[field] = invalid or item[field] = ""
            if meta[field] <> invalid then item[field] = StringOf(meta[field])
        end if
    end for
end sub

sub CancelHeroMeta()
    if m.heroMetaTask = invalid then return
    task = m.heroMetaTask
    m.heroMetaTask = invalid
    AsyncTask_Reap(task, m.top, true)
end sub

sub onHeroMetadataLoaded(event as object)
    task = event.GetRoSGNode()
    if m.heroMetaTask = invalid then return
    if task.requestGeneration <> m.heroMetaTask.requestGeneration then return
    m.heroMetaTask = invalid
    AsyncTask_Reap(task, m.top, false)
    if not m.top.screenActive or task.requestGeneration <> m.heroGeneration then return
    item = SelectedHeroItem()
    if item = invalid then return
    if item.metaId <> task.metaId or item.metaType <> task.metaType then return
    result = task.result
    if result = invalid or not result.ok or result.meta = invalid then return
    if result.meta.id <> invalid and result.meta.id <> task.metaId then return
    if result.meta.type <> invalid and result.meta.type <> task.metaType then return
    MergeHeroMetadata(item, result.meta)
    ' Cache only display fields, not a series' potentially huge episode list.
    m.heroMetadata[item.metaType + ":" + item.metaId] = {
        background: item.background
        logo: item.logo
        description: item.description
        releaseInfo: item.releaseInfo
        imdbRating: item.imdbRating
        runtime: item.runtime
    }
    RenderHomeHero(item)
end sub

sub RenderHomeHero(item as object)
    if m.heroProgress <> invalid
        info = item.resumeInfo
        if info = invalid then info = ""
        m.heroProgress.text = info
        UpdateHeroProgressLayout()
    end if
    if m.heroTitle <> invalid then m.heroTitle.text = item.title
    if m.heroDesc <> invalid
        desc = item.description
        if desc = invalid then desc = ""
        m.heroDesc.text = desc
    end if

    if m.heroMeta <> invalid
        parts = []
        if item.releaseInfo <> invalid and item.releaseInfo <> "" then parts.Push(item.releaseInfo)
        if item.imdbRating <> invalid and item.imdbRating <> "" then parts.Push("★ " + item.imdbRating)
        if item.runtime <> invalid and item.runtime <> "" then parts.Push(FormatHeroRuntime(item.runtime))
        if item.metaType <> invalid and item.metaType <> "" then parts.Push(TypeLabel(item.metaType))
        m.heroMeta.text = parts.Join("  ·  ")
    end if


    if item.logo <> invalid and item.logo <> "" and m.heroLogo <> invalid
        m.heroLogo.uri = item.logo
        m.heroLogo.visible = true
        if m.heroTitle <> invalid then m.heroTitle.visible = false
    else
        if m.heroLogo <> invalid then m.heroLogo.visible = false
        if m.heroTitle <> invalid then m.heroTitle.visible = true
    end if

    m.heroFallbackPoster = item.hdPosterUrl
    bg = item.background
    if bg = invalid or bg = "" then bg = m.heroFallbackPoster
    if bg <> invalid and bg <> ""
        if m.heroBgNext <> invalid
            m.heroBgNext.opacity = 0.0
            m.heroBgNext.uri = bg
        end if
    else
        if m.heroBg <> invalid then m.heroBg.uri = ""
        if m.heroBgNext <> invalid
            m.heroBgNext.uri = ""
            m.heroBgNext.opacity = 0.0
        end if
    end if
end sub

sub onHeroBgLoaded()
    if m.heroBgNext = invalid then return
    status = m.heroBgNext.loadStatus
    if status = "ready"
        if m.heroCrossfadeAnim <> invalid
            m.heroCrossfadeAnim.control = "stop"
            m.heroCrossfadeAnim.control = "start"
        else
            m.heroBg.uri = m.heroBgNext.uri
            m.heroBg.opacity = 1.0
            m.heroBgNext.opacity = 0.0
        end if
    else if status = "failed"
        if m.heroFallbackPoster <> invalid and m.heroFallbackPoster <> "" and m.heroBgNext.uri <> m.heroFallbackPoster
            m.heroBgNext.uri = m.heroFallbackPoster
        else
            m.heroBgNext.uri = ""
            m.heroBg.uri = ""
        end if
    end if
end sub

sub onHeroCrossfadeState()
    if m.heroCrossfadeAnim = invalid or m.heroBg = invalid or m.heroBgNext = invalid then return
    if m.heroCrossfadeAnim.state = "stopped"
        m.heroBg.uri = m.heroBgNext.uri
        m.heroBg.opacity = 1.0
        m.heroBgNext.opacity = 0.0
    end if
end sub

function FormatHeroRuntime(rt as dynamic) as string
    if rt = invalid then return ""
    mins = 0
    if Type(rt) = "roInt" or Type(rt) = "Integer"
        mins = rt
    else if Type(rt) = "roString" or Type(rt) = "String"
        mins = Val(rt)
    end if
    if mins <= 0 then return rt.toStr()
    h = Int(mins / 60)
    m = mins mod 60
    if h > 0 and m > 0
        return h.toStr() + "h " + m.toStr() + "min"
    else if h > 0
        return h.toStr() + "h"
    else
        return m.toStr() + "min"
    end if
end function



sub SetHomeFocus(menu as boolean)
    if not menu and m.gridRows.Count() = 0 then menu = true
    if menu
        m.rail.SetFocus(true)
        m.catalog.drawFocusFeedback = false
        m.catalog.opacity = 0.55
    else
        m.catalog.SetFocus(true)
        m.catalog.drawFocusFeedback = true
        m.catalog.opacity = 1.0
    end if
    SetRailExpanded(menu)
end sub

sub SetRailExpanded(expanded as boolean)
    m.railExpanded = expanded
    content = m.rail.content
    if content <> invalid
        for i = 0 to content.GetChildCount() - 1
            row = content.GetChild(i)
            if row.GetChildCount() > 0 then row.GetChild(0).menuExpanded = expanded
        end for
    end if
    target = 96
    if expanded then target = 360
    m.railAnimation.control = "stop"
    if m.railMotionAllowed and m.railBg.width <> target
        m.railWidthInterpolator.keyValue = [m.railBg.width, target]
        m.railAnimation.control = "start"
    else
        m.railBg.width = target
        ApplyRailWidth()
    end if
end sub

sub ApplyRailWidth()
    width = m.railBg.width
    m.railClip.clippingRect = [0, 0, width, 1080]
    progress = (width - 96) / 264
    if progress < 0 then progress = 0
    if progress > 1 then progress = 1
    m.top.FindNode("brand").opacity = progress
    m.top.FindNode("compactBrand").opacity = 1 - progress

    if m.profileName <> invalid then m.profileName.opacity = progress
    if m.profileSub <> invalid then m.profileSub.opacity = progress

    if m.catalogArea <> invalid
        catalogX = 136 + progress * (380 - 136)
        m.catalogArea.translation = [catalogX, 0]
    end if
end sub

sub InvalidateHomeCache()
    scene = m.top.GetScene()
    if scene = invalid then return
    cacheNode = scene.FindNode("responseCache")
    if cacheNode <> invalid then cacheNode.callFunc("Clear")
end sub

' Home context menus and layout edits. No network work runs on this thread.
function FocusedHomeContext() as dynamic
    at = m.catalog.rowItemFocused
    if at = invalid or at.Count() < 2 then return invalid
    if at[0] < 0 or at[0] >= m.gridRows.Count() then return invalid
    row = m.gridRows[at[0]]
    if at[1] < 0 or at[1] >= row.metas.Count() then return invalid
    return { rowKey: HomeRowKey(row), item: row.metas[at[1]], source: row.source, row: at[0], col: at[1] }
end function

function AllHomeRows() as object
    rows = []
    cw = LibraryRow()
    if cw <> invalid then rows.Push(cw)
    for each row in m.catalogRows
        rows.Push(row)
    end for
    return rows
end function

sub ReflowHomeRows()
    context = FocusedHomeContext()
    BuildRows()
    if m.gridRows.Count() = 0 then return
    target = [0, 0]
    if context <> invalid
        target[0] = context.row
        if target[0] >= m.gridRows.Count() then target[0] = m.gridRows.Count() - 1
        for r = 0 to m.gridRows.Count() - 1
            if HomeRowKey(m.gridRows[r]) = context.rowKey
                target[0] = r
                for c = 0 to m.gridRows[r].metas.Count() - 1
                    if m.gridRows[r].metas[c].id = context.item.id then target[1] = c
                end for
                exit for
            end if
        end for
    end if
    m.catalog.jumpToRowItem = target
end sub

sub PresentHomeMenu(title as string, subtitle as string, entries as object)
    CancelHeroMeta()
    if m.heroDebounceTimer <> invalid then m.heroDebounceTimer.control = "stop"
    footer = Lang("home", "menuHelp")
    if m.menuError <> "" then footer = m.menuError
    m.catalog.drawFocusFeedback = false
    m.homeMenu.callFunc("Open", title, subtitle, entries, footer)
end sub

sub OpenHomeActions()
    m.homeMenuOrigin = "catalog"
    m.actionContext = FocusedHomeContext()
    if m.actionContext = invalid
        ShowHomeCustomization()
        return
    end if
    m.menuPage = "actions"
    m.menuError = ""
    meta = m.actionContext.item
    entries = []
    saveLabel = Lang("home", "saveTitle")
    if m.stores.library.callFunc("LibraryIsSaved", meta.id) then saveLabel = Lang("home", "unsaveTitle")
    entries.Push({ action: "save", label: saveLabel })
    if meta.type = "movie" or meta.type = "series"
        watchedLabel = Lang("home", "markWatched")
        if meta.type = "series" then watchedLabel = Lang("home", "markSeriesWatched")
        entries.Push({ action: "markWatched", label: watchedLabel })
    end if
    if m.actionContext.source = "library" then entries.Push({ action: "removeContinue", label: Lang("home", "removeContinue") })
    entries.Push({ action: "customize", label: Lang("home", "customize") })
    entries.Push({ action: "back", label: Lang("common", "cancel") })
    PresentHomeMenu(StringOf(meta.name), Lang("home", "actions"), entries)
end sub

sub ShowHomeCustomization()
    m.menuPage = "home"
    duplicateLabel = Lang("home", "deduplicateOff")
    if m.homeLayout.deduplicate then duplicateLabel = Lang("home", "deduplicateOn")
    entries = [
        { action: "rows", label: Lang("home", "manageRows") }
        { action: "deduplicate", label: duplicateLabel }
        { action: "reset", label: Lang("home", "resetLayout") }
        { action: "back", label: Lang("common", "cancel") }
    ]
    PresentHomeMenu(Lang("home", "customize"), "", entries)
end sub

function HomeRowLabel(row as object) as string
    label = row.title
    if row.source <> "library"
        label = label + " · " + TypeLabel(row.metaType)
        if row.addonName <> invalid and row.addonName <> "" then label = label + " · " + row.addonName
    end if
    return label
end function

sub ShowHomeRows()
    m.menuPage = "rows"
    entries = []
    visibleKeys = []
    for each visibleRow in HomeOrderedRows(AllHomeRows(), m.homeLayout)
        visibleKeys.Push(HomeRowKey(visibleRow))
    end for
    rows = HomeOrderedRows(AllHomeRows(), m.homeLayout, true)
    for r = 0 to rows.Count() - 1
        row = rows[r]
        key = HomeRowKey(row)
        state = Lang("home", "rowVisible")
        if not HomeHasKey(visibleKeys, key) then state = Lang("home", "rowDuplicate")
        if HomeHasKey(m.homeLayout.hidden, key) then state = Lang("home", "rowHidden")
        entries.Push({ action: "row", rowKey: key, label: HomeRowLabel(row) + " · " + state })
    end for
    entries.Push({ action: "back", label: Lang("common", "cancel") })
    PresentHomeMenu(Lang("home", "rowsTitle"), Lang("home", "manageRows"), entries)
end sub

sub ShowHomeRowEdit(key as string)
    m.menuPage = "row"
    m.editRowKey = key
    rows = HomeOrderedRows(AllHomeRows(), m.homeLayout, true)
    index = -1
    for i = 0 to rows.Count() - 1
        if HomeRowKey(rows[i]) = key then index = i
    end for
    if index < 0
        ShowHomeRows()
        return
    end if
    visibilityLabel = Lang("home", "hideRow")
    if HomeHasKey(m.homeLayout.hidden, key) then visibilityLabel = Lang("home", "showRow")
    entries = [{ action: "visibility", label: visibilityLabel }]
    if index > 0 then entries.Push({ action: "moveUp", label: Lang("home", "moveUp") })
    if index < rows.Count() - 1 then entries.Push({ action: "moveDown", label: Lang("home", "moveDown") })
    entries.Push({ action: "back", label: Lang("common", "cancel") })
    PresentHomeMenu(HomeRowLabel(rows[index]), Lang("home", "customize"), entries)
end sub

function SaveHomeLayout(value as object) as boolean
    candidate = HomeNormalizeLayout(value)
    if not m.stores.settings.callFunc("SettingsSetHomeLayout", candidate)
        m.menuError = Lang("home", "layoutSaveFailed")
        return false
    end if
    m.homeLayout = candidate
    m.menuError = ""
    ReflowHomeRows()
    return true
end function

sub CloseHomeMenu()
    m.homeMenu.callFunc("DismissMenu")
    m.menuPage = ""
    m.menuError = ""
    SetHomeFocus(m.homeMenuOrigin = "rail")
    if m.gridRows.Count() > 0 then UpdateSelectedTitle()
end sub

sub HandleHomeMenuBack()
    if m.menuPage = "row"
        ShowHomeRows()
    else if m.menuPage = "rows"
        ShowHomeCustomization()
    else
        CloseHomeMenu()
    end if
end sub

sub onHomeMenuChoice()
    choice = m.homeMenu.choice
    if choice = invalid then return
    action = choice.action
    if action = "back"
        HandleHomeMenuBack()
    else if action = "customize"
        ShowHomeCustomization()
    else if action = "rows"
        ShowHomeRows()
    else if action = "row"
        ShowHomeRowEdit(choice.rowKey)
    else if action = "deduplicate"
        layout = HomeNormalizeLayout(m.homeLayout)
        layout.deduplicate = not layout.deduplicate
        SaveHomeLayout(layout)
        ShowHomeCustomization()
    else if action = "reset"
        SaveHomeLayout(HomeNormalizeLayout(invalid))
        ShowHomeCustomization()
    else if action = "visibility"
        layout = HomeNormalizeLayout(m.homeLayout)
        found = false
        for i = layout.hidden.Count() - 1 to 0 step -1
            if layout.hidden[i] = m.editRowKey
                layout.hidden.Delete(i)
                found = true
            end if
        end for
        if not found then layout.hidden.Push(m.editRowKey)
        SaveHomeLayout(layout)
        ShowHomeRowEdit(m.editRowKey)
    else if action = "moveUp" or action = "moveDown"
        layout = HomeNormalizeLayout(m.homeLayout)
        rows = HomeOrderedRows(AllHomeRows(), layout, true)
        keys = []
        index = -1
        for i = 0 to rows.Count() - 1
            keys.Push(HomeRowKey(rows[i]))
            if keys[i] = m.editRowKey then index = i
        end for
        target = index - 1
        if action = "moveDown" then target = index + 1
        if index >= 0 and target >= 0 and target < keys.Count()
            swap = keys[target]
            keys[target] = keys[index]
            keys[index] = swap
            layout.order = keys
            SaveHomeLayout(layout)
        end if
        ShowHomeRowEdit(m.editRowKey)
    else if action = "save" or action = "markWatched" or action = "removeContinue"
        ApplyHomeTitleAction(action)
    end if
end sub

sub ApplyHomeTitleAction(action as string)
    if m.actionContext = invalid or m.stores = invalid then return
    meta = m.actionContext.item
    packet = {
        action: action
        metaId: StringOf(meta.id)
        metaType: StringOf(meta.type)
        name: StringOf(meta.name)
        poster: StringOf(meta.poster)
        posterShape: StringOf(meta.posterShape)
    }
    if action = "save"
        added = not m.stores.library.callFunc("LibraryIsSaved", packet.metaId)
        if added
            m.stores.library.callFunc("LibraryAddSaved", packet.metaId, packet.metaType, packet.name, packet.poster, packet.posterShape)
        else
            m.stores.library.callFunc("LibraryRemoveSaved", packet.metaId)
        end if
        packet.added = added
        m.top.libraryChange = packet
    else
        if action = "markWatched" then m.stores.library.callFunc("LibraryMarkTitleWatched", packet.metaId)
        resume = m.stores.library.callFunc("LibraryResumeFor", packet.metaId)
        if resume <> invalid then m.stores.library.callFunc("LibraryRemovePosition", resume.videoId)
        m.top.homeEdit = packet
    end if
    m.cwSignature = ContinueWatchingSignature()
    ReflowHomeRows()
    CloseHomeMenu()
end sub
