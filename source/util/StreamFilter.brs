' StreamFilter.brs — pure stream categorization and filtering over available stream metadata.

function DetectStreamResolution(stream as object, notSetWord as string) as string
    if stream = invalid then return notSetWord
    text = LCase(StringOf(stream.name) + " " + StringOf(stream.title) + " " + StringOf(stream.description))
    if stream.behaviorHints <> invalid and stream.behaviorHints.filename <> invalid
        text = text + " " + LCase(StringOf(stream.behaviorHints.filename))
    end if

    if HasStreamMetadataToken(text, "2160p|4k|uhd") then return "4K"
    if HasStreamMetadataToken(text, "1080p|fhd") then return "1080p"
    if HasStreamMetadataToken(text, "720p|hd") then return "720p"
    if HasStreamMetadataToken(text, "480p|sd|576p") then return "480p"
    return notSetWord
end function

function DetectStreamFormat(stream as object, notSetWord as string) as string
    if stream = invalid then return notSetWord
    text = ""
    if stream.behaviorHints <> invalid and stream.behaviorHints.filename <> invalid
        text = LCase(StringOf(stream.behaviorHints.filename))
    end if
    if text = "" then text = LCase(StringOf(stream.url))
    if text = "" then text = LCase(StringOf(stream.title) + " " + StringOf(stream.description))

    for each ext in ["mkv", "mp4", "m3u8", "avi", "ts", "webm"]
        if text.InStr("." + ext) >= 0 or text.InStr(" " + ext) >= 0
            if ext = "m3u8" then return "HLS"
            return UCase(ext)
        end if
    end for
    return notSetWord
end function

function DetectStreamLanguage(stream as object, notSetWord as string) as string
    if stream = invalid then return notSetWord
    text = LCase(StringOf(stream.name) + " " + StringOf(stream.title) + " " + StringOf(stream.description))
    if stream.behaviorHints <> invalid and stream.behaviorHints.filename <> invalid
        text = text + " " + LCase(StringOf(stream.behaviorHints.filename))
    end if

    if text.InStr("dual") >= 0 or text.InStr("multi") >= 0 then return "Dual / Multi"
    if text.InStr("dublado") >= 0 or text.InStr("pt-br") >= 0 or text.InStr("pob") >= 0 or text.InStr("brazilian") >= 0
        return "Português (BR)"
    end if
    if text.InStr("legendado") >= 0 then return "Legendado"
    if text.InStr("portuguese") >= 0 or text.InStr("português") >= 0 or text.InStr(" pt ") >= 0 or text.InStr("[pt]") >= 0
        return "Português"
    end if
    if text.InStr("english") >= 0 or text.InStr(" en ") >= 0 or text.InStr("[en]") >= 0 or HasStreamMetadataToken(text, "eng")
        return "English"
    end if
    if text.InStr("spanish") >= 0 or text.InStr("español") >= 0 or text.InStr("latino") >= 0 or text.InStr(" es ") >= 0
        return "Español"
    end if
    return notSetWord
end function

function FilterStreamList(streams as object, filterRes as string, filterLang as string, filterFmt as string, notSetWord as string) as object
    if streams = invalid or Type(streams) <> "roArray" then return []
    if (filterRes = "" or filterRes = "all") and (filterLang = "" or filterLang = "all") and (filterFmt = "" or filterFmt = "all")
        return streams
    end if

    filtered = []
    for each stream in streams
        if filterRes <> "" and filterRes <> "all"
            res = DetectStreamResolution(stream, notSetWord)
            if res <> filterRes then continue for
        end if
        if filterLang <> "" and filterLang <> "all"
            detectedLang = DetectStreamLanguage(stream, notSetWord)
            if detectedLang <> filterLang then continue for
        end if
        if filterFmt <> "" and filterFmt <> "all"
            fmt = DetectStreamFormat(stream, notSetWord)
            if fmt <> filterFmt then continue for
        end if
        filtered.Push(stream)
    end for
    return filtered
end function

' Match complete metadata tokens, not fragments of film titles (Birthday, Avengers).
function HasStreamMetadataToken(text as string, tokens as string) as boolean
    if m._streamTokenMatchers = invalid then m._streamTokenMatchers = {}
    if not m._streamTokenMatchers.DoesExist(tokens)
        m._streamTokenMatchers[tokens] = CreateObject("roRegex", "(^|[^a-z0-9])(" + tokens + ")([^a-z0-9]|$)", "i")
    end if
    return m._streamTokenMatchers[tokens].IsMatch(text)
end function
