' Plain-data model shared by the Home UI and persisted settings.
function HomeNormalizeLayout(value as dynamic) as object
    result = { order: [], hidden: [], deduplicate: false }
    if Type(value) <> "roAssociativeArray" then return result
    for each field in ["order", "hidden"]
        entries = value[field]
        if Type(entries) = "roArray"
            seen = {}
            for each entry in entries
                if Type(entry) = "roString" or Type(entry) = "String"
                    if entry <> "" and entry.Len() <= 2048 and not seen.DoesExist(entry) and result[field].Count() < 200
                        result[field].Push(entry)
                        seen[entry] = true
                    end if
                end if
            end for
        end if
    end for
    if Type(value.deduplicate) = "Boolean" or Type(value.deduplicate) = "roBoolean"
        if value.deduplicate then result.deduplicate = true
    end if
    return result
end function

function HomeRowKey(row as object) as string
    if row.source = "library" then return "continue"
    if row.rowKey <> invalid then return row.rowKey
    return row.addonAddress + "|" + row.metaType + "|" + row.title
end function

function HomeHasKey(keys as object, key as string) as boolean
    for each candidate in keys
        if candidate = key then return true
    end for
    return false
end function

function HomeOrderedRows(rows as object, layout as object, includeHidden = false as boolean) as object
    result = []
    keys = []
    for each key in layout.order
        for i = 0 to rows.Count() - 1
            if HomeRowKey(rows[i]) = key and not HomeHasKey(keys, key)
                result.Push(rows[i])
                keys.Push(key)
            end if
        end for
    end for
    for i = 0 to rows.Count() - 1
        key = HomeRowKey(rows[i])
        if not HomeHasKey(keys, key)
            result.Push(rows[i])
            keys.Push(key)
        end if
    end for
    if includeHidden then return result
    visible = []
    signatures = {}
    for i = 0 to result.Count() - 1
        row = result[i]
        if HomeHasKey(layout.hidden, HomeRowKey(row)) then continue for
        if layout.deduplicate and row.source <> "library"
            ids = []
            for each meta in row.metas
                if meta.id <> invalid then ids.Push(meta.id)
            end for
            ids.Sort("i")
            signature = row.metaType + "|" + ids.Join("|")
            if ids.Count() > 0 and signatures.DoesExist(signature) then continue for
            signatures[signature] = true
        end if
        visible.Push(row)
    end for
    return visible
end function

function HomeResumeLabel(meta as object, remainingTemplate as string, episodeTemplate as string) as string
    parts = []
    if meta.type = "series" and meta.season <> invalid and meta.episode <> invalid
        if meta.season >= 0 and meta.episode > 0
            parts.Push(episodeTemplate.Replace("{season}", meta.season.ToStr()).Replace("{episode}", meta.episode.ToStr()))
        end if
    end if
    if meta.duration <> invalid and meta.position <> invalid
        if meta.duration > 0 and meta.position >= 0
            seconds = meta.duration - meta.position
            if meta.timeUnit = "milliseconds" then seconds = seconds / 1000
            if seconds < 0 then seconds = 0
            minutes = Int((seconds + 59) / 60)
            parts.Push(remainingTemplate.Replace("{minutes}", minutes.ToStr()))
        end if
    end if
    return parts.Join(" · ")
end function
