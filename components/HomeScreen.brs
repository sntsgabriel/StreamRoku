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
    m.heroButtonsGroup = m.top.FindNode("heroButtonsGroup")
    m.btnPlay = m.top.FindNode("btnPlay")
    m.btnDetails = m.top.FindNode("btnDetails")
    m.heroDebounceTimer = m.top.FindNode("heroDebounceTimer")
    m.heroCrossfadeAnim = m.top.FindNode("heroCrossfadeAnim")

    ' Profile nodes
    m.profileName = m.top.FindNode("profileName")
    m.profileSub = m.top.FindNode("profileSub")
    m.avatarInitial = m.top.FindNode("avatarInitial")

    if m.heroDebounceTimer <> invalid then m.heroDebounceTimer.ObserveField("fire", "onHeroDebounce")
    if m.heroCrossfadeAnim <> invalid then m.heroCrossfadeAnim.ObserveField("state", "onHeroCrossfadeState")
    if m.heroBgNext <> invalid then m.heroBgNext.ObserveField("loadStatus", "onHeroBgLoaded")
    if m.btnPlay <> invalid then m.btnPlay.ObserveField("buttonSelected", "onHeroPlay")
    if m.btnDetails <> invalid then m.btnDetails.ObserveField("buttonSelected", "onHeroDetails")

    m.heroGeneration = 0
    m.currentHeroMeta = invalid
    m.currentHeroRow = 0
    m.heroCollapsed = false

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
    }
    slot = cwOffset + row.index
    node = MakeRowNode(descriptor, invalid)
    if m.catalog.content <> invalid and m.catalog.content.getChildCount() > slot
        m.catalog.content.InsertChild(node, slot)
    else
        m.catalog.content.AppendChild(node)
    end if
    m.catalogRows.Push(descriptor)
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

    counts = DuplicateCounts()

    content = CreateObject("roSGNode", "ContentNode")
    for r = 0 to m.gridRows.Count() - 1
        content.AppendChild(MakeRowNode(m.gridRows[r], counts))
    end for
    m.catalog.content = content
    if m.gridRows.Count() > 0 then m.catalog.numRows = m.gridRows.Count()
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
    if m.catalog.content = invalid then return
    content = m.catalog.content
    haveCw = m.gridRows.Count() > 0 and m.gridRows[0].source = "library"
    live = LibraryRow()
    if live <> invalid
        if haveCw
            SyncContinueWatchingRow(content.GetChild(0), live.metas)
            m.gridRows[0] = live
        else
            content.InsertChild(MakeRowNode(live, invalid), 0)
            m.gridRows.Unshift(live)
            m.catalog.numRows = m.gridRows.Count()
            ApplyCatalogSizes()
        end if
    else if haveCw
        content.RemoveChildIndex(0)
        m.gridRows.Delete(0)
        m.catalog.numRows = m.gridRows.Count()
        ApplyCatalogSizes()
    end if
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
    m.homeSub.text = ""
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
    m.railAnimation.control = "stop"
    if m.heroDebounceTimer <> invalid then m.heroDebounceTimer.control = "stop"
end function

function OnBackPressed() as boolean
    if m.btnPlay <> invalid and (m.btnPlay.HasFocus() or (m.btnDetails <> invalid and m.btnDetails.HasFocus()))
        m.catalog.SetFocus(true)
        m.catalog.drawFocusFeedback = true
        return true
    end if
    if m.rail.HasFocus() and m.gridRows.Count() > 0
        SetHomeFocus(false)
        return true
    end if
    return false
end function

sub BlurFocus()
    m.railWasFocus = m.rail.HasFocus()
    CancelOpen()
end sub

sub UpdateProfileDisplay()
    user = invalid
    if m.stores <> invalid and m.stores.auth <> invalid
        user = m.stores.auth.callFunc("AuthGetUser")
    end if
    name = Lang("home", "guest")
    subtext = "Rokumio"
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
    if m.profileSub <> invalid then m.profileSub.text = subtext
    if m.avatarInitial <> invalid then m.avatarInitial.text = initial
end sub

sub BuildRail()
    entries = [
        { label: Lang("home", "navSearch"), glyph: "pkg:/images/search.png", screen: "searchScreen" }
        { label: Lang("home", "navHome"), glyph: "pkg:/images/discover.png", screen: "homeScreen", active: true }
        { label: Lang("home", "navSeries"), glyph: "pkg:/images/discover.png", screen: "discoverScreen", params: { type: "series" } }
        { label: Lang("home", "navMovies"), glyph: "pkg:/images/discover.png", screen: "discoverScreen", params: { type: "movie" } }
        { label: Lang("home", "navLibrary"), glyph: "pkg:/images/library.png", screen: "libraryScreen" }
        { label: Lang("home", "navAddons"), glyph: "pkg:/images/puzzle.png", screen: "addonsScreen" }
        { label: Lang("home", "navSettings"), glyph: "pkg:/images/settings.png", screen: "settingsScreen" }
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
    m.rail.numRows = entries.Count()
    m.railBuilt = true
    m.railLanguage = TextsLanguage()
end sub

sub onRailItemSelected()
    data = m.rail.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    row = data[0]
    if row < 0 or m.railEntries = invalid or row >= m.railEntries.Count() then return
    target = m.railEntries[row]
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
    else if key = "up" and m.catalog.HasFocus()
        if m.catalog.rowItemFocused <> invalid and m.catalog.rowItemFocused[0] = 0
            if m.btnPlay <> invalid and m.btnPlay.visible
                m.btnPlay.SetFocus(true)
                m.catalog.drawFocusFeedback = false
                return true
            end if
        end if
    else if key = "down" and (m.btnPlay <> invalid and m.btnPlay.HasFocus())
        m.catalog.SetFocus(true)
        m.catalog.drawFocusFeedback = true
        return true
    else if key = "down" and (m.btnDetails <> invalid and m.btnDetails.HasFocus())
        m.catalog.SetFocus(true)
        m.catalog.drawFocusFeedback = true
        return true
    else if key = "right" and (m.btnPlay <> invalid and m.btnPlay.HasFocus())
        if m.btnDetails <> invalid
            m.btnDetails.SetFocus(true)
            return true
        end if
    else if key = "left" and (m.btnDetails <> invalid and m.btnDetails.HasFocus())
        if m.btnPlay <> invalid
            m.btnPlay.SetFocus(true)
            return true
        end if
    else if key = "left" and (m.btnPlay <> invalid and m.btnPlay.HasFocus())
        SetHomeFocus(true)
        return true
    else if key = "replay"
        if m.catalogTask = invalid
            InvalidateHomeCache()
            RebuildRows()
        end if
        return true
    else if key = "options"
        if m.catalog.HasFocus() or (m.btnPlay <> invalid and m.btnPlay.HasFocus()) or (m.btnDetails <> invalid and m.btnDetails.HasFocus())
            SetHomeFocus(true)
            return true
        else if m.rail.HasFocus()
            SetHomeFocus(false)
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
        if m.heroButtonsGroup <> invalid then m.heroButtonsGroup.visible = false
        if m.catalogRowsBuilt
            m.emptyState.text = Lang("home", "empty")
        else
            m.emptyState.text = Lang("home", "loading")
        end if
    else
        if m.heroButtonsGroup <> invalid then m.heroButtonsGroup.visible = true
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

    if focusedItem[0] > 0
        SetHeroCollapsed(true)
    else
        SetHeroCollapsed(false)
    end if

    m.heroGeneration = m.heroGeneration + 1
    if m.heroDebounceTimer <> invalid
        m.heroDebounceTimer.control = "stop"
        m.heroDebounceTimer.control = "start"
    end if
end sub

sub SetHeroCollapsed(collapsed as boolean)
    if m.heroCollapsed = collapsed then return
    m.heroCollapsed = collapsed
    if m.catalog = invalid then return

    if collapsed
        m.catalog.translation = [0, 140]
        if m.heroButtonsGroup <> invalid then m.heroButtonsGroup.visible = false
        if m.heroDesc <> invalid then m.heroDesc.visible = false
    else
        m.catalog.translation = [0, 360]
        if m.heroButtonsGroup <> invalid then m.heroButtonsGroup.visible = true
        if m.heroDesc <> invalid then m.heroDesc.visible = true
    end if
end sub

sub onHeroDebounce()
    if m.catalog = invalid or m.catalog.content = invalid then return
    focusedItem = m.catalog.rowItemFocused
    if focusedItem = invalid or focusedItem.Count() < 2 then return
    if focusedItem[0] < 0 or focusedItem[1] < 0 then return
    row = m.catalog.content.GetChild(focusedItem[0])
    if row = invalid then return
    item = row.GetChild(focusedItem[1])
    if item = invalid then return

    m.currentHeroMeta = item
    m.currentHeroRow = focusedItem[0]

    if m.heroTitle <> invalid then m.heroTitle.text = item.title
    if m.heroDesc <> invalid
        desc = item.description
        if desc = invalid or desc = "" then desc = Lang("common", "noSynopsis")
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

    if m.btnPlay <> invalid
        if item.progress <> invalid and item.progress > 0
            m.btnPlay.text = Lang("home", "resume")
        else
            m.btnPlay.text = Lang("home", "watch")
        end if
    end if
    if m.btnDetails <> invalid then m.btnDetails.text = Lang("home", "moreInfo")

    if item.logo <> invalid and item.logo <> "" and m.heroLogo <> invalid
        m.heroLogo.uri = item.logo
        m.heroLogo.visible = true
        if m.heroTitle <> invalid then m.heroTitle.visible = false
    else
        if m.heroLogo <> invalid then m.heroLogo.visible = false
        if m.heroTitle <> invalid then m.heroTitle.visible = true
    end if

    bg = item.background
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
        m.heroBgNext.uri = ""
        m.heroBg.uri = ""
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

sub onHeroPlay()
    if m.currentHeroMeta = invalid or m.gridRows = invalid then return
    rowIdx = 0
    if m.currentHeroRow <> invalid and m.currentHeroRow < m.gridRows.Count() then rowIdx = m.currentHeroRow
    row = m.gridRows[rowIdx]
    if row = invalid then return

    if row.source = "library"
        OpenContinueWatching(m.currentHeroMeta)
    else
        m.top.pushRequest = {
            screen: "detailsScreen"
            params: {
                addonAddress: row.addonAddress
                meta: m.currentHeroMeta
            }
        }
    end if
end sub

sub onHeroDetails()
    if m.currentHeroMeta = invalid or m.gridRows = invalid then return
    rowIdx = 0
    if m.currentHeroRow <> invalid and m.currentHeroRow < m.gridRows.Count() then rowIdx = m.currentHeroRow
    row = m.gridRows[rowIdx]
    if row = invalid then return

    m.top.pushRequest = {
        screen: "detailsScreen"
        params: {
            addonAddress: row.addonAddress
            meta: m.currentHeroMeta
        }
    }
end sub

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
