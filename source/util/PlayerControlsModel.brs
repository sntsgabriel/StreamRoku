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
