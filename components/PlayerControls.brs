sub init()
    m.chrome = m.top.FindNode("chrome")
    m.details = m.top.FindNode("details")
    m.idleTimer = m.top.FindNode("idleTimer")
    m.hideTimer = m.top.FindNode("hideTimer")
    m.buttons = [m.top.FindNode("backAction"), m.top.FindNode("captionsAction"), m.top.FindNode("restartAction"), m.top.FindNode("toggleAction")]
    m.actionIds = ["back", "captions", "restart", "toggle"]
    m.focusedIndex = 3
    m.idle = false
    m.presented = false
    m.presentedPaused = false
    m.pauseClock = CreateObject("roTimespan")
    t = Theme()
    m.top.FindNode("progressTrack").color = "0xFFFFFF55"
    m.top.FindNode("progressFill").color = t.textWhite
    for each id in ["smallTitle", "mediaTitle", "episode", "elapsed", "total"]
        m.top.FindNode(id).color = t.textWhite
    end for
    for each id in ["smallEpisode", "stateLabel", "idleState", "hint", "pausePrompt"]
        m.top.FindNode(id).color = t.mediaPanelMuted
    end for
    m.top.FindNode("mediaLogo").ObserveField("loadStatus", "UpdateArtwork")
    m.idleTimer.ObserveField("fire", "onPauseTick")
    m.hideTimer.ObserveField("fire", "AutoHide")
end sub

function Word(key as string) as string
    value = m.top.words[key]
    if value = invalid then return ""
    return value
end function

sub Open()
    ' Opening the same paused session again must preserve its idle deadline and
    ' details screen. Native state notifications can arrive more than once.
    samePause = m.presented and m.top.visible and m.top.paused and m.presentedPaused
    m.top.visible = true
    if not samePause
        m.idle = false
        m.chrome.visible = true
        m.details.visible = false
        m.focusedIndex = 3
    end if
    m.presented = true
    m.presentedPaused = m.top.paused
    m.top.FindNode("smallTitle").text = m.top.mediaTitle
    m.top.FindNode("smallEpisode").text = m.top.episodeText
    m.top.FindNode("mediaTitle").text = m.top.mediaTitle
    m.top.FindNode("episode").text = m.top.episodeText
    m.top.FindNode("stateLabel").text = ""
    if m.top.paused then m.top.FindNode("stateLabel").text = Word("paused")
    m.top.FindNode("idleState").text = UCase(Word("paused"))
    m.top.FindNode("hint").text = Word("controlsHint")
    m.top.FindNode("pausePrompt").text = Word("pausePrompt")
    m.top.FindNode("mediaLogo").uri = m.top.logo
    UpdateArtwork()
    UpdateButtons()
    UpdateProgress()
    if not samePause
        m.top.SetFocus(true)
        ResetIdle()
    end if
end sub

sub UpdateArtwork()
    logo = m.top.FindNode("mediaLogo")
    ready = m.top.logo <> "" and logo.loadStatus = "ready"
    logo.visible = ready
    ' Artwork and fallback title are alternatives, never duplicate headings.
    m.top.FindNode("mediaTitle").visible = not ready
end sub

sub UpdateButtons()
    toggle = "pause"
    icon = "pause"
    if m.top.paused
        toggle = "resume"
        icon = "play"
    end if
    names = ["back", "captions", "restart", toggle]
    icons = ["back", "captions", "restart", icon]
    for i = 0 to m.buttons.Count() - 1
        m.buttons[i].caption = Word(names[i])
        m.buttons[i].icon = "pkg:/images/player-" + icons[i] + ".png"
        m.buttons[i].selected = i = m.focusedIndex
    end for
end sub

sub WakeControls()
    m.idle = false
    m.details.visible = false
    m.chrome.visible = true
    ResetIdle()
end sub

sub ResetIdle()
    m.idleTimer.control = "stop"
    m.hideTimer.control = "stop"
    if m.top.paused
        m.pauseClock.Mark()
        m.idleTimer.control = "start"
    else
        m.hideTimer.control = "start"
    end if
end sub

sub onPauseTick()
    if not m.top.visible or not m.top.paused or m.idle then return
    ' Measure elapsed time rather than relying on a single delayed event.
    if m.pauseClock.TotalMilliseconds() >= 8000 then ShowIdleDetails()
end sub

sub ShowIdleDetails()
    if not m.top.visible or not m.top.paused then return
    m.idleTimer.control = "stop"
    m.idle = true
    m.chrome.visible = false
    m.details.visible = true
end sub

sub AutoHide()
    if m.top.visible and not m.top.paused then m.top.action = "dismiss"
end sub

sub Dismiss()
    m.idleTimer.control = "stop"
    m.hideTimer.control = "stop"
    m.idle = false
    m.presented = false
    m.presentedPaused = false
    m.chrome.visible = false
    m.details.visible = false
    m.top.visible = false
end sub

sub UpdateProgress()
    m.top.FindNode("elapsed").text = PlayerClock(m.top.position)
    total = "—:—"
    if m.top.duration > 0 then total = PlayerClock(m.top.duration)
    m.top.FindNode("total").text = total
    width = PlayerProgress(m.top.position, m.top.duration, 1296)
    m.top.FindNode("progressFill").width = width
    m.top.FindNode("progressDot").translation = [136 + width, 39]
end sub

sub SelectAction()
    if m.focusedIndex < 0 or m.focusedIndex >= m.actionIds.Count() then return
    m.top.action = m.actionIds[m.focusedIndex]
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.idle
        if key = "OK" or key = "play"
            m.top.action = "toggle"
        else
            ' First interaction wakes the controls, without accidental seek/exit.
            WakeControls()
        end if
        return true
    end if
    if key = "up" or key = "down"
        ResetIdle()
        if key = "up" then m.focusedIndex = m.focusedIndex - 1 else m.focusedIndex = m.focusedIndex + 1
        if m.focusedIndex < 0 then m.focusedIndex = 0
        if m.focusedIndex > 3 then m.focusedIndex = 3
        UpdateButtons()
        return true
    else if key = "OK"
        SelectAction()
        return true
    else if key = "back"
        m.top.action = "dismiss"
        return true
    else if key = "play"
        m.top.action = "toggle"
        return true
    else if key = "left" or key = "right" or key = "fastforward" or key = "rewind" or key = "replay"
        m.top.action = key
        return true
    else if key = "options"
        m.top.action = "captions"
        return true
    end if
    return false
end function
