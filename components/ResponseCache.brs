' No network, parsing, disk I/O or raw-URL logging on this shared node.
' Task callFunc operations are rendezvoused onto its owner (the render thread).
sub init()
    m.cache = ResponseCacheStore()
    timer = m.top.FindNode("pruneTimer")
    timer.ObserveField("fire", "Prune")
    timer.control = "start"
end sub

function GetGeneration() as integer
    return m.cache.GetGeneration()
end function

function Read(key as string, generation as integer) as string
    return m.cache.Read(key, generation)
end function

function Write(key as string, cacheText as string, ttl as integer, generation as integer) as boolean
    return m.cache.Write(key, cacheText, ttl, generation)
end function

sub Clear()
    m.cache.Clear()
end sub

sub Prune()
    m.cache.Prune()
end sub

function Stats() as object
    return m.cache.Stats()
end function
