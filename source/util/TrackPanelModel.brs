' Pure track presentation model. Identifiers remain opaque and are never shown as URLs.
function TrackText(value as dynamic) as string
    if Type(value) = "String" or Type(value) = "roString" then return value.Trim()
    return ""
end function

function TrackField(value as dynamic, key as string) as string
    if Type(value) <> "roAssociativeArray" then return ""
    return TrackText(value[key])
end function

function TrackLanguageCode(raw as dynamic) as string
    code = LCase(TrackText(raw)).Replace("_", "-")
    aliases = { por: "pt", pob: "pt-BR", pb: "pt-BR", "pt-br": "pt-BR", eng: "en", spa: "es", fre: "fr", fra: "fr", ger: "de", deu: "de", ita: "it", jpn: "ja", kor: "ko", chi: "zh", zho: "zh", rus: "ru", ara: "ar", hin: "hi", hrv: "hr", dut: "nl", nld: "nl", rum: "ro", ron: "ro", slv: "sl" }
    if aliases.DoesExist(code) then return aliases[code]
    if code = "" then return "und"
    return code
end function

function TrackLanguageLabel(code as string, words as object) as string
    label = TrackField(words, code)
    if label <> "" then return label
    return code
end function

function TrackFileFormat(track as dynamic, id as string, words as object) as string
    format = TrackField(track, "format")
    if format <> "" then return UCase(format)
    clean = LCase(id.Split("?")[0].Split("#")[0])
    for each extension in ["srt", "vtt", "ttml", "dfxp", "ass", "ssa"]
        if clean.Right(extension.Len() + 1) = "." + extension then return UCase(extension)
    end for
    return TrackField(words, "unknownFormat")
end function

function TrackPanelEntries(nativeTracks as dynamic, externalTracks as dynamic, mode as string, words as object) as object
    entries = []
    byUrl = {}
    if Type(externalTracks) = "roArray"
        for each raw in externalTracks
            url = TrackField(raw, "url")
            if url = "" then url = TrackField(raw, "downloadUrl")
            if url <> "" then byUrl[url] = raw
        end for
    end if
    if Type(nativeTracks) <> "roArray" then return entries
    for each track in nativeTracks
        if Type(track) <> "roAssociativeArray" then continue for
        id = TrackField(track, "TrackName")
        if mode = "audio" then id = TrackField(track, "Track")
        if id = "" then continue for
        code = TrackField(track, "Language")
        provider = TrackField(words, "embedded")
        format = TrackFileFormat(track, id, words)
        title = TrackField(track, "Description")
        if mode = "audio" then title = TrackField(track, "Name")
        raw = byUrl[id]
        if mode <> "audio" and raw <> invalid
            rawCode = TrackField(raw, "lang")
            if rawCode <> "" then code = rawCode
            provider = TrackField(raw, "providerName")
            if provider = "" then provider = TrackField(words, "addon")
            format = TrackFileFormat(raw, id, words)
            title = provider
        end if
        code = TrackLanguageCode(code)
        language = TrackLanguageLabel(code, words)
        if title = "" then title = language
        entries.Push({ id: id, code: code, language: language, title: title, provider: provider, format: format })
    end for
    return entries
end function

function TrackLanguageRank(code as string) as integer
    if code = "pt-BR" then return 0
    if code = "pt" then return 1
    if code = "en" then return 2
    if code = "es" then return 3
    return 4
end function

function TrackPanelGroups(entries as object) as object
    groups = []
    index = {}
    for each entry in entries
        if not index.DoesExist(entry.code)
            index[entry.code] = groups.Count()
            groups.Push({ code: entry.code, label: entry.language, entries: [] })
        end if
        groups[index[entry.code]].entries.Push(entry)
    end for
    for i = 1 to groups.Count() - 1
        group = groups[i]
        j = i - 1
        while j >= 0
            previous = groups[j]
            rank = TrackLanguageRank(group.code)
            before = rank < TrackLanguageRank(previous.code)
            if rank = TrackLanguageRank(previous.code) then before = LCase(group.label) < LCase(previous.label)
            if not before then exit while
            groups[j + 1] = groups[j]
            j = j - 1
        end while
        groups[j + 1] = group
    end for
    return groups
end function

' Flatten language groups into direct choices without exposing native track
' names, selectors or missing-format diagnostics. Keep every provider selectable.
function TrackPanelRows(entries as dynamic, subtitles as boolean, words as object) as object
    rows = []
    if subtitles then rows.Push({ id: "", code: "", action: "off", label: TrackField(words, "off") })
    if Type(entries) <> "roArray" then return rows
    for each group in TrackPanelGroups(entries)
        labels = {}
        for each entry in group.entries
            label = entry.language
            description = LCase(entry.title)
            if Instr(1, description, "cc") > 0 or Instr(1, description, "sdh") > 0
                label = label + " (CC)"
            else if Instr(1, description, "forced") > 0 or Instr(1, description, "forçad") > 0
                label = label + " (" + TrackField(words, "forced") + ")"
            end if
            if group.entries.Count() > 1
                provider = TrackField(entry, "provider")
                format = TrackField(entry, "format")
                if provider <> "" and provider <> TrackField(words, "embedded")
                    label = label + " · " + provider
                else if not subtitles and format <> "" and format <> TrackField(words, "unknownFormat")
                    label = label + " · " + format
                end if
            end if
            base = label
            count = 1
            if labels.DoesExist(base) then count = labels[base] + 1
            labels[base] = count
            if count > 1 then label = label + " (" + count.ToStr() + ")"
            action = "audio"
            if subtitles then action = "track"
            rows.Push({ id: entry.id, code: entry.code, action: action, label: label })
        end for
    end for
    return rows
end function

' Retain the browsed track when newly discovered languages reorder the list.
function TrackPanelRestoreIndex(previous as object, rows as object, index as integer) as integer
    if index >= 0 and index < previous.Count()
        id = previous[index].id
        for i = 0 to rows.Count() - 1
            if rows[i].id = id then return i
        end for
    end if
    if rows.Count() = 0 then return -1
    if index < 0 then return 0
    if index >= rows.Count() then return rows.Count() - 1
    return index
end function
