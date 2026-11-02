sub init()
    m.subtitles = m.top.FindNode("subtitles")
    m.audio = m.top.FindNode("audio")
    m.subtitleRows = []
    m.audioRows = []
    m.audioSection = false
    t = Theme()
    m.top.FindNode("card").color = t.mediaPanelBg
    for each id in ["panelHeading", "subtitleHeading", "audioHeading"]
        m.top.FindNode(id).color = t.textWhite
    end for
    for each id in ["subtitleEmpty", "audioEmpty", "hint", "subtitleCount", "audioCount", "tabHint"]
        m.top.FindNode(id).color = t.mediaPanelMuted
    end for
    m.subtitles.ObserveField("itemSelected", "SelectSubtitle")
    m.audio.ObserveField("itemSelected", "SelectAudio")
    m.subtitles.ObserveField("itemFocused", "UpdateCounts")
    m.audio.ObserveField("itemFocused", "UpdateCounts")
end sub

function Word(key as string) as string
    return TrackField(m.top.words, key)
end function

sub Open()
    m.top.visible = true
    m.top.FindNode("panelHeading").text = Word("panelTitle")
    m.top.FindNode("subtitleHeading").text = Word("subtitles")
    m.top.FindNode("audioHeading").text = Word("audio")
    m.top.FindNode("hint").text = Word("hint")
    m.top.FindNode("tabHint").text = Word("tabHint")
    m.subtitleRows = TrackPanelRows(m.top.subtitleEntries, true, m.top.words)
    m.audioRows = TrackPanelRows(m.top.audioEntries, false, m.top.words)
    RenderLists(true)
    FocusSection(false)
end sub

sub DismissPanel()
    m.top.visible = false
    m.subtitleRows = []
    m.audioRows = []
    m.subtitles.content = invalid
    m.audio.content = invalid
end sub

sub RequestClose()
    m.top.closeRequested = true
end sub

' A selection check is independent of keyboard focus. Rebuilding content must
' preserve the browsing position, including when late native tracks arrive.
sub RenderLists(initial as boolean)
    RenderList(m.subtitles, m.subtitleRows, m.top.currentSubtitle, m.top.captionsEnabled, initial)
    RenderList(m.audio, m.audioRows, m.top.currentAudio, true, initial)
    m.top.FindNode("subtitleEmpty").text = ""
    if m.subtitleRows.Count() = 1 then m.top.FindNode("subtitleEmpty").text = Word("noSubtitles")
    m.top.FindNode("audioEmpty").text = ""
    if m.audioRows.Count() = 0 then m.top.FindNode("audioEmpty").text = Word("noAudio")
    UpdateCounts()
end sub

sub RenderList(list as object, rows as object, selected as string, enabled as boolean, initial as boolean)
    previous = list.itemFocused
    content = CreateObject("roSGNode", "ContentNode")
    active = 0
    for i = 0 to rows.Count() - 1
        row = rows[i]
        checked = enabled and row.id = selected and row.action <> "off"
        if row.action = "off" then checked = not enabled
        if checked then active = i
        node = content.CreateChild("ContentNode")
        node.title = row.label
        node.AddFields({trackChecked: checked})
    end for
    list.content = content
    if initial then previous = active
    if previous < 0 then previous = 0
    if previous >= rows.Count() then previous = rows.Count() - 1
    if previous >= 0 then list.jumpToItem = previous
end sub

sub FocusSection(audio as boolean)
    target = m.subtitles
    if audio then target = m.audio
    m.audioSection = audio
    ApplySectionLook()
    if audio and m.audioRows.Count() = 0
        m.top.SetFocus(true)
    else
        target.SetFocus(true)
    end if
end sub

sub RefreshSelection()
    RenderLists(false)
end sub

sub RefreshEntries()
    subtitles = TrackPanelRows(m.top.subtitleEntries, true, m.top.words)
    audio = TrackPanelRows(m.top.audioEntries, false, m.top.words)
    subIndex = TrackPanelRestoreIndex(m.subtitleRows, subtitles, m.subtitles.itemFocused)
    audioIndex = TrackPanelRestoreIndex(m.audioRows, audio, m.audio.itemFocused)
    m.subtitleRows = subtitles
    m.audioRows = audio
    RenderLists(false)
    if subIndex >= 0 then m.subtitles.jumpToItem = subIndex
    if audioIndex >= 0 then m.audio.jumpToItem = audioIndex
end sub

sub SelectSubtitle()
    index = m.subtitles.itemSelected
    if index < 0 or index >= m.subtitleRows.Count() then return
    row = m.subtitleRows[index]
    m.top.choice = { action: row.action, track: row.id, code: row.code }
end sub

sub SelectAudio()
    index = m.audio.itemSelected
    if index < 0 or index >= m.audioRows.Count() then return
    row = m.audioRows[index]
    m.top.choice = { action: "audio", track: row.id, code: row.code }
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "back"
        RequestClose()
        return true
    else if key = "right"
        FocusSection(true)
        return true
    else if key = "left"
        FocusSection(false)
        return true
    else if (key = "up" or key = "down") and m.audioSection and m.audioRows.Count() = 0
        return true
    end if
    return false
end function

sub UpdateCounts()
    subtitleCount = ""
    audioCount = ""
    if m.subtitleRows.Count() > 10 then subtitleCount = (m.subtitles.itemFocused + 1).ToStr() + " / " + m.subtitleRows.Count().ToStr()
    if m.audioRows.Count() > 10 then audioCount = (m.audio.itemFocused + 1).ToStr() + " / " + m.audioRows.Count().ToStr()
    m.top.FindNode("subtitleCount").text = subtitleCount
    m.top.FindNode("audioCount").text = audioCount
end sub

sub ApplySectionLook()
    t = Theme()
    m.subtitles.visible = not m.audioSection
    m.audio.visible = m.audioSection
    m.top.FindNode("subtitleEmpty").visible = not m.audioSection
    m.top.FindNode("audioEmpty").visible = m.audioSection
    m.top.FindNode("subtitleCount").visible = not m.audioSection
    m.top.FindNode("audioCount").visible = m.audioSection
    m.top.FindNode("subtitleUnderline").visible = not m.audioSection
    m.top.FindNode("audioUnderline").visible = m.audioSection
    m.top.FindNode("subtitleHeading").color = t.textWhite
    m.top.FindNode("audioHeading").color = t.mediaPanelMuted
    if m.audioSection
        m.top.FindNode("subtitleHeading").color = t.mediaPanelMuted
        m.top.FindNode("audioHeading").color = t.textWhite
    end if
end sub
