sub init()
    m.top.focusable = true
    m.holdKey = ""
    m.holdClock = CreateObject("roTimespan")
    m.seekHoldTimer = m.top.FindNode("seekHoldTimer")
    m.seekHoldTimer.ObserveField("fire", "onSeekHoldTick")
    m.focusZone = "timeline"
    m.seeking = false
    m.seekPending = false
    m.seekClock = CreateObject("roTimespan")
    m.seekSettleTimer = m.top.FindNode("seekSettleTimer")
    m.seekSettleTimer.ObserveField("fire", "UpdateProgress")
    m.chrome = m.top.FindNode("chrome")
    m.details = m.top.FindNode("details")
    m.idleTimer = m.top.FindNode("idleTimer")
    m.hideTimer = m.top.FindNode("hideTimer")
    m.buttons = [m.top.FindNode("backAction"), m.top.FindNode("captionsAction"), m.top.FindNode("restartAction"), m.top.FindNode("toggleAction"), m.top.FindNode("nextAction")]
    m.actionIds = ["back", "captions", "restart", "toggle", "next"]
    m.focusedIndex = 3
    m.idle = false
    m.presented = false
    m.presentedPaused = false
    m.pauseClock = CreateObject("roTimespan")
    t = Theme()
    m.top.FindNode("progressTrack").color = t.textSecondary
    m.top.FindNode("seekRange").color = t.accent
    m.top.FindNode("seekBubbleFace").color = t.mediaPanelBg
    m.top.FindNode("timelineLabel").color = t.textWhite
    m.top.FindNode("seekTime").color = t.textWhite
    m.top.FindNode("seekDelta").color = t.accent
    m.top.FindNode("remaining").color = t.mediaPanelMuted
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
    if m.top.words = invalid then return ""
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
        StopSeekHold()
        m.idle = false
        m.chrome.visible = true
        m.details.visible = false
        m.focusedIndex = 3
        m.focusZone = "timeline"
        m.seeking = false
        m.seekPending = false
        if m.seekSettleTimer <> invalid then m.seekSettleTimer.control = "stop"
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
    if m.buttons = invalid then return
    if m.top.nextAvailable <> true and m.focusedIndex = 4 then m.focusedIndex = 3
    toggle = "pause"
    icon = "pause"
    if m.top.paused
        toggle = "resume"
        icon = "play"
    end if
    names = ["back", "captions", "restart", toggle, "nextEpisode"]
    icons = ["back", "captions", "restart", icon, "next"]
    for i = 0 to m.buttons.Count() - 1
        m.buttons[i].caption = Word(names[i])
        m.buttons[i].icon = "pkg:/images/player-" + icons[i] + ".png"
        m.buttons[i].selected = m.focusZone = "actions" and i = m.focusedIndex
    end for
    m.buttons[3].translation = [0, 324]
    if m.buttons.Count() > 4
        m.buttons[4].visible = m.top.nextAvailable = true
        if m.top.nextAvailable = true then m.buttons[3].translation = [0, 432]
    end if
end sub

sub WakeControls()
    StopSeekHold()
    m.focusZone = "timeline"
    m.seeking = false
    UpdateButtons()
    UpdateProgress()
    m.idle = false
    m.details.visible = false
    m.chrome.visible = true
    ResetIdle()
end sub

sub ResetIdle()
    m.idleTimer.control = "stop"
    m.hideTimer.control = "stop"
    if m.seeking = true then return
    if m.top.paused
        m.pauseClock.Mark()
        m.idleTimer.control = "start"
    else
        m.hideTimer.control = "start"
    end if
end sub

sub onPauseTick()
    if not m.top.visible or not m.top.paused or m.idle or m.seeking = true then return
    ' Measure elapsed time rather than relying on a single delayed event.
    if m.pauseClock.TotalMilliseconds() >= 8000 then ShowIdleDetails()
end sub

sub ShowIdleDetails()
    if not m.top.visible or not m.top.paused or m.seeking = true then return
    m.idleTimer.control = "stop"
    m.idle = true
    m.chrome.visible = false
    m.details.visible = true
end sub

sub AutoHide()
    if m.top.visible and not m.top.paused and m.seeking <> true then m.top.action = "dismiss"
end sub

sub Dismiss()
    StopSeekHold()
    m.seeking = false
    m.seekPending = false
    if m.seekSettleTimer <> invalid then m.seekSettleTimer.control = "stop"
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
    elapsed = m.top.FindNode("elapsed")
    if elapsed = invalid then return
    actual = m.top.position
    duration = m.top.duration
    position = actual
    focused = m.focusZone = "timeline"
    if m.seekPending = true
        if Abs(actual - m.seekPosition) <= 2 or m.seekClock.TotalMilliseconds() >= 4000
            m.seekPending = false
            m.seekSettleTimer.control = "stop"
        else
            position = m.seekPosition
        end if
    end if
    if m.seeking = true then position = m.seekPosition
    elapsed.text = PlayerClock(actual)
    total = "—:—"
    remaining = ""
    hint = Word("actionsHint")
    label = ""
    if duration > 0
        total = PlayerClock(duration)
        left = duration - position
        if left < 0 then left = 0
        remaining = Word("remainingTime").Replace("{time}", PlayerClock(left))
        if focused
            hint = Word("timelineHint")
            label = Word("timeline")
            if m.seeking = true then hint = Word("seekHint")
        end if
    else if focused
        hint = Word("liveHint")
        label = Word("live")
    end if
    m.top.FindNode("total").text = total
    m.top.FindNode("remaining").text = remaining
    m.top.FindNode("hint").text = hint
    m.top.FindNode("timelineLabel").text = label
    played = PlayerProgress(actual, duration, 1632)
    target = PlayerProgress(position, duration, 1632)
    m.top.FindNode("progressFill").width = played
    height = 6
    dotSize = 22
    if focused
        height = 10
        dotSize = 32
    end if
    for each id in ["progressTrack", "progressFill", "seekRange"]
        node = m.top.FindNode(id)
        node.height = height
        node.translation = [0, 67 - height / 2]
    end for
    range = m.top.FindNode("seekRange")
    range.visible = m.seeking = true
    start = played
    if target < played then start = target
    range.translation = [start, 67 - height / 2]
    range.width = Abs(target - played)
    dot = m.top.FindNode("progressDot")
    dot.visible = duration > 0
    dot.width = dotSize
    dot.height = dotSize
    dot.translation = [target - dotSize / 2, 67 - dotSize / 2]
    bubble = m.top.FindNode("seekBubble")
    bubble.visible = focused and duration > 0
    x = target - 100
    if x < 0 then x = 0
    if x > 1432 then x = 1432
    bubble.translation = [x, -28]
    m.top.FindNode("seekTime").text = PlayerClock(position)
    delta = position - actual
    sign = "+"
    if delta < 0 then sign = "−"
    deltaText = ""
    if m.seeking = true then deltaText = sign + PlayerClock(Abs(delta))
    m.top.FindNode("seekDelta").text = deltaText
end sub

sub PreviewSeek(offset as float)
    if m.top.duration <= 0 then return
    position = m.top.position
    if m.seeking = true or m.seekPending = true then position = m.seekPosition
    m.focusZone = "timeline"
    m.seekPending = false
    if m.seekSettleTimer <> invalid then m.seekSettleTimer.control = "stop"
    m.seekPosition = PlayerSeekTarget(position, m.top.duration, offset)
    m.seeking = true
    ResetIdle()
    UpdateButtons()
    UpdateProgress()
end sub

sub CancelSeek()
    StopSeekHold()
    m.seeking = false
    ResetIdle()
    UpdateProgress()
end sub

sub SeekConfirmed(position as float)
    m.seeking = false
    m.seekPosition = position
    m.seekPending = true
    m.seekClock.Mark()
    m.seekSettleTimer.control = "start"
    ResetIdle()
    UpdateProgress()
end sub

sub PlaybackChanged()
    m.presentedPaused = m.top.paused
    UpdateButtons()
    if m.seeking <> true then ResetIdle()
    UpdateProgress()
end sub

sub SelectAction()
    StopSeekHold()
    if m.focusZone = "timeline"
        if m.seeking = true
            m.top.seekRequest = { position: m.seekPosition }
        else
            m.top.action = "toggle"
        end if
        return
    end if
    if m.focusedIndex < 0 or m.focusedIndex >= m.actionIds.Count() then return
    m.top.action = m.actionIds[m.focusedIndex]
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press
        if m.holdKey <> invalid and m.holdKey <> "" and key = m.holdKey
            StopSeekHold()
            return true
        end if
        return false
    end if
    if key <> "left" and key <> "right" and key <> "rewind" and key <> "fastforward" and key <> "replay" then StopSeekHold()
    if m.idle
        if key = "OK" or key = "play"
            m.top.action = "toggle"
        else
            WakeControls()
        end if
        return true
    end if
    if key = "up" or key = "down"
        if m.seeking = true then CancelSeek()
        ResetIdle()
        if m.focusZone = "timeline"
            if key = "up"
                m.focusZone = "actions"
                m.focusedIndex = 3
            else
                m.top.action = "dismiss"
            end if
        else
            direction = 1
            if key = "up" then direction = -1
            m.focusedIndex = PlayerMoveAction(m.focusedIndex, direction, m.top.nextAvailable = true)
            if m.focusedIndex < 0
                m.focusedIndex = 3
                m.focusZone = "timeline"
            end if
        end if
        UpdateButtons()
        UpdateProgress()
        return true
    else if key = "OK"
        ResetIdle()
        SelectAction()
        return true
    else if key = "back"
        if m.seeking = true then CancelSeek() else m.top.action = "dismiss"
        return true
    else if key = "play"
        m.top.action = "toggle"
        return true
    else if key = "left" or key = "right"
        if m.focusZone <> "timeline"
            m.focusZone = "timeline"
            UpdateButtons()
            UpdateProgress()
            ResetIdle()
        else
            StartSeekHold(key)
        end if
        return true
    else if key = "fastforward" or key = "rewind" or key = "replay"
        StartSeekHold(key)
        return true
    else if key = "options"
        m.top.action = "captions"
        return true
    end if
    return false
end function

sub StopSeekHold()
    m.holdKey = ""
    if m.seekHoldTimer <> invalid then m.seekHoldTimer.control = "stop"
end sub

sub StartSeekHold(key as string)
    if m.top.duration <= 0 then return
    ' Native repeat presses are ignored: this timer owns repeat cadence.
    if m.holdKey = key then return
    StopSeekHold()
    m.holdKey = key
    m.holdClock.Mark()
    PreviewSeek(PlayerHoldSeekStep(key, 0))
    m.seekHoldTimer.control = "start"
end sub

sub onSeekHoldTick()
    if m.holdKey = "" then return
    if not m.top.visible or m.idle or m.focusZone <> "timeline"
        StopSeekHold()
        return
    end if
    elapsed = m.holdClock.TotalMilliseconds()
    if elapsed < 400 then return
    PreviewSeek(PlayerHoldSeekStep(m.holdKey, elapsed))
end sub
