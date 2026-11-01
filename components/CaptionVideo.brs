' Down opens the app's caption button; native play, seek, Back and * remain available.
function onKeyEvent(key as string, press as boolean) as boolean
    if press and key = "down"
        m.top.captionControlsRequested = true
        return true
    end if
    return false
end function
