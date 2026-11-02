' Up/Down opens app controls. OK explicitly toggles playback rather than
' relying on the native Video UI to interpret the center button.
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "OK"
        if m.top.state = "playing"
            m.top.control = "pause"
            return true
        else if m.top.state = "paused"
            m.top.control = "resume"
            return true
        end if
    else if key = "down" or key = "up"
        m.top.captionControlsRequested = true
        return true
    end if
    return false
end function
