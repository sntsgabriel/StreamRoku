sub init()
    m.languages = m.top.FindNode("languages")
    m.tracks = m.top.FindNode("tracks")
    m.subTab = m.top.FindNode("subTab")
    m.audioTab = m.top.FindNode("audioTab")
    m.close = m.top.FindNode("close")
    m.off = m.top.FindNode("off")
    m.on = m.top.FindNode("on")
    m.mode = "subtitle"
    m.groups = []
    m.entries = []
    t = Theme()
    m.top.FindNode("shade").color = t.scrim
    m.top.FindNode("card").color = t.mediaPanelBg
    for each id in ["title", "languageHeading", "trackHeading", "detailHeading", "empty"]
        m.top.FindNode(id).color = t.textPrimary
    end for
    m.top.FindNode("details").color = t.textSecondary
    m.top.FindNode("hint").color = t.textSecondary
    for each list in [m.languages, m.tracks]
        list.color = t.textPrimary
        list.focusedColor = t.textWhite
        list.focusBitmapBlendColor = t.mediaPanelAccent
    end for
    m.languages.ObserveField("itemFocused", "onLanguageFocused")
    m.languages.ObserveField("itemSelected", "FocusTracks")
    m.tracks.ObserveField("itemFocused", "UpdateDetails")
    m.tracks.ObserveField("itemSelected", "SelectTrack")
    m.subTab.ObserveField("buttonSelected", "ShowSubtitles")
    m.audioTab.ObserveField("buttonSelected", "ShowAudio")
    m.close.ObserveField("buttonSelected", "RequestClose")
    m.off.ObserveField("buttonSelected", "TurnOff")
    m.on.ObserveField("buttonSelected", "TurnOn")
end sub

function Word(key as string) as string
    return TrackField(m.top.words, key)
end function

sub Open()
    m.top.visible = true
    m.mode = "subtitle"
    m.subTab.text = Word("subtitles")
    m.audioTab.text = Word("audio")
    m.close.text = Word("close")
    m.top.FindNode("languageHeading").text = Word("languages")
    m.top.FindNode("trackHeading").text = Word("tracks")
    m.top.FindNode("detailHeading").text = Word("details")
    m.top.FindNode("hint").text = Word("hint")
    m.off.text = Word("off")
    m.on.text = Word("on")
    RebuildLanguages()
    FocusLanguages()
end sub

sub DismissPanel()
    m.top.visible = false
    m.groups = []
    m.entries = []
    m.languages.content = invalid
    m.tracks.content = invalid
end sub

sub RequestClose()
    m.top.closeRequested = true
end sub

sub ShowSubtitles()
    m.mode = "subtitle"
    RebuildLanguages()
    FocusLanguages()
end sub

sub ShowAudio()
    m.mode = "audio"
    RebuildLanguages()
    FocusLanguages()
end sub

sub RebuildLanguages()
    entries = m.top.subtitleEntries
    title = Word("subtitles")
    if m.mode = "audio"
        entries = m.top.audioEntries
        title = Word("audio")
    end if
    if entries = invalid then entries = []
    m.top.FindNode("title").text = title
    m.groups = TrackPanelGroups(entries)
    m.off.visible = m.mode = "subtitle"
    m.on.visible = m.mode = "subtitle" and entries.Count() > 0
    m.top.FindNode("empty").visible = entries.Count() = 0
    emptyWord = "noSubtitles"
    if m.mode = "audio" then emptyWord = "noAudio"
    m.top.FindNode("empty").text = Word(emptyWord)
    selected = m.top.currentSubtitle
    if m.mode = "audio" then selected = m.top.currentAudio
    initial = 0
    content = CreateObject("roSGNode", "ContentNode")
    for i = 0 to m.groups.Count() - 1
        group = m.groups[i]
        node = content.CreateChild("ContentNode")
        node.title = group.label
        for each entry in group.entries
            if entry.id = selected then initial = i
        end for
    end for
    m.languages.content = content
    m.languages.jumpToItem = initial
    ShowLanguage(initial)
end sub

sub FocusLanguages()
    if m.groups.Count() > 0
        m.languages.SetFocus(true)
    else if m.off.visible
        m.off.SetFocus(true)
    else
        m.close.SetFocus(true)
    end if
end sub

sub onLanguageFocused()
    ShowLanguage(m.languages.itemFocused)
end sub

sub ShowLanguage(index as integer)
    m.entries = []
    if index >= 0 and index < m.groups.Count() then m.entries = m.groups[index].entries
    RefreshSelection()
end sub

sub RefreshSelection()
    selected = m.top.currentSubtitle
    enabled = m.top.captionsEnabled
    if m.mode = "audio"
        selected = m.top.currentAudio
        enabled = true
    end if
    content = CreateObject("roSGNode", "ContentNode")
    for i = 0 to m.entries.Count() - 1
        entry = m.entries[i]
        node = content.CreateChild("ContentNode")
        prefix = ""
        if enabled and entry.id = selected then prefix = "✓ "
        node.title = prefix + entry.title + "  ·  " + entry.format + "  ·  " + (i + 1).ToStr()
    end for
    previous = m.tracks.itemFocused
    m.tracks.content = content
    if previous >= 0 and previous < m.entries.Count() then m.tracks.jumpToItem = previous
    UpdateDetails()
end sub

sub FocusTracks()
    if m.entries.Count() > 0 then m.tracks.SetFocus(true)
end sub

sub UpdateDetails()
    label = m.top.FindNode("details")
    label.text = ""
    index = m.tracks.itemFocused
    if index < 0 or index >= m.entries.Count() then return
    entry = m.entries[index]
    label.text = entry.language + chr(10) + chr(10) + entry.provider + chr(10) + chr(10) + entry.format
end sub

sub SelectTrack()
    index = m.tracks.itemSelected
    if index < 0 or index >= m.entries.Count() then return
    action = "track"
    if m.mode = "audio" then action = "audio"
    m.top.choice = { action: action, track: m.entries[index].id }
end sub

sub TurnOff()
    m.top.choice = { action: "off", track: "" }
end sub

sub TurnOn()
    track = m.top.currentSubtitle
    if track = "" and m.entries.Count() > 0 then track = m.entries[0].id
    if track <> "" then m.top.choice = { action: "on", track: track }
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "back"
        RequestClose()
        return true
    else if key = "right"
        if m.languages.HasFocus()
            FocusTracks()
        else if m.subTab.HasFocus()
            m.audioTab.SetFocus(true)
        else if m.audioTab.HasFocus()
            m.close.SetFocus(true)
        else if m.off.HasFocus() and m.on.visible
            m.on.SetFocus(true)
        else
            return false
        end if
        return true
    else if key = "left"
        if m.tracks.HasFocus()
            m.languages.SetFocus(true)
        else if m.audioTab.HasFocus()
            m.subTab.SetFocus(true)
        else if m.close.HasFocus()
            m.audioTab.SetFocus(true)
        else if m.on.HasFocus()
            m.off.SetFocus(true)
        else
            return false
        end if
        return true
    else if key = "down"
        if m.subTab.HasFocus() or m.audioTab.HasFocus() or m.close.HasFocus()
            FocusLanguages()
        else if m.mode = "subtitle" and (m.languages.HasFocus() or m.tracks.HasFocus())
            m.off.SetFocus(true)
        else
            return false
        end if
        return true
    else if key = "up"
        if m.off.HasFocus() or m.on.HasFocus()
            if m.groups.Count() > 0 then FocusLanguages() else m.subTab.SetFocus(true)
        else if m.languages.HasFocus() or m.tracks.HasFocus()
            m.subTab.SetFocus(true)
        else
            return false
        end if
        return true
    end if
    return false
end function

sub RefreshEntries()
    code = ""
    index = m.languages.itemFocused
    if index >= 0 and index < m.groups.Count() then code = m.groups[index].code
    RebuildLanguages()
    for i = 0 to m.groups.Count() - 1
        if m.groups[i].code = code
            m.languages.jumpToItem = i
            ShowLanguage(i)
            return
        end if
    end for
end sub
