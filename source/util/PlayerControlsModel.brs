function PlayerClock(seconds as dynamic) as string
    if seconds = invalid or seconds < 0 then seconds = 0
    total = Int(seconds)
    minutes = Int(total / 60)
    tail = (total mod 60).ToStr()
    if tail.Len() < 2 then tail = "0" + tail
    if minutes < 60 then return minutes.ToStr() + ":" + tail
    hours = Int(minutes / 60)
    middle = (minutes mod 60).ToStr()
    if middle.Len() < 2 then middle = "0" + middle
    return hours.ToStr() + ":" + middle + ":" + tail
end function

function PlayerProgress(position as float, duration as float, width as float) as float
    if duration <= 0 or position <= 0 then return 0
    if position >= duration then return width
    return width * position / duration
end function

function PlayerSeekTarget(position as float, duration as float, offset as float) as float
    if duration <= 0 then return position
    target = position + offset
    if target < 0 then target = 0
    if target > duration then target = duration
    return target
end function

function PlayerHoldSeekStep(key as string, heldMilliseconds as integer) as float
    stepSize = 10
    if key = "fastforward" or key = "rewind" then stepSize = 30
    factor = 1
    if heldMilliseconds >= 1000 then factor = 2
    if heldMilliseconds >= 2500 then factor = 4
    if heldMilliseconds >= 5000 then factor = 12
    stepSize = stepSize * factor
    if stepSize > 120 then stepSize = 120
    if key = "left" or key = "rewind" or key = "replay" then stepSize = -stepSize
    return stepSize
end function

function PlayerMoveAction(index as integer, direction as integer, nextAvailable as boolean) as integer
    order = [0, 1, 2, 3]
    if nextAvailable then order = [0, 1, 2, 4, 3]
    for i = 0 to order.Count() - 1
        if order[i] = index
            target = i + direction
            if target < 0 then return order[0]
            if target >= order.Count() then return -1
            return order[target]
        end if
    end for
    return 3
end function

function PlayerReachedEnd(hasPlayed as boolean, failed as boolean, position as float, duration as float) as boolean
    if not hasPlayed or failed or duration <= 0 or position < 0 then return false
    tolerance = duration * 0.01
    if tolerance > 3 then tolerance = 3
    if tolerance < 0.5 then tolerance = 0.5
    return position >= duration - tolerance
end function
