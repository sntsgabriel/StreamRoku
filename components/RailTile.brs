' RailTile — icon and translated label for the Home left rail. Same field plumbing as
' every tile: RowList feeds seed the ContentNode through itemContent and drive
' focus through itemHasFocus / rowHasFocus. The glyph is read from
' itemContent.title.

sub init()
    m.border = m.top.FindNode("railBorder")
    m.glyph = m.top.FindNode("railGlyph")
    m.label = m.top.FindNode("railLabel")
    m.zoomAnim = m.top.FindNode("zoomAnim")
    m.labelAnimation = m.top.FindNode("labelAnimation")
    m.labelOpacityInterpolator = m.top.FindNode("labelOpacityInterpolator")
    m.activeIndicator = m.top.FindNode("activeIndicator")
    m.labelContent = invalid

    m.border.color = Theme().accentClear

    m.top.ObserveField("itemContent", "onItemContentChanged")
    m.top.ObserveField("itemHasFocus", "onItemHasFocusChanged")
    m.top.ObserveField("rowHasFocus", "onRowHasFocusChanged")
end sub

' Every inbound field change re-applies the whole look from the tile's current
' field values. Rebuilt on itemContent changes too so recycled tiles never carry
' stale focus or dimming.
sub UpdateLook()
    t = Theme()
    hasFocus = false
    if MenuExpanded() and m.top.itemHasFocus = true
        ' In a real RowList, rowHasFocus is false on rows that do not have focus.
        if m.top.rowHasFocus <> false then hasFocus = true
    end if

    content = m.top.itemContent
    isActive = false
    if content <> invalid and content.HasField("active") and content.active = true
        isActive = true
    end if

    if m.activeIndicator <> invalid
        m.activeIndicator.color = t.accent
        ' Show active indicator when item represents active section and does not have control focus
        m.activeIndicator.visible = (isActive and not hasFocus)
    end if

    if hasFocus
        m.zoomAnim.control = "start"
        m.glyph.blendColor = t.screenBg
        m.border.color = t.accentFocus
        m.label.color = t.screenBg
        m.top.opacity = 1.0
    else
        m.zoomAnim.control = "stop"
        m.glyph.scale = [1.0, 1.0]
        if isActive
            m.glyph.blendColor = t.accent
            m.label.color = t.textPrimary
        else
            m.glyph.blendColor = t.textSecondary
            m.label.color = t.textPrimary
        end if
        m.border.color = t.accentClear
        m.top.opacity = 1.0
    end if
end sub

sub onItemContentChanged()
    if m.top.itemContent = invalid then return
    ' Unconditional for the same reason as PosterTile: re-assigning the uri is
    ' what makes Roku re-request an evicted texture, so guarding it strands the
    ' icon blank on a recycled tile.
    if m.labelContent <> invalid then m.labelContent.UnobserveField("menuExpanded")
    m.labelContent = m.top.itemContent
    m.labelContent.ObserveField("menuExpanded", "onMenuExpanded")
    m.glyph.uri = m.top.itemContent.title
    m.label.text = m.top.itemContent.shortDescriptionLine1
    m.labelAnimation.control = "stop"
    m.label.opacity = 0
    if MenuExpanded() then m.label.opacity = 1
    UpdateLook()
end sub

sub onItemHasFocusChanged()
    UpdateLook()
end sub

sub onRowHasFocusChanged()
    UpdateLook()
end sub

function MenuExpanded() as boolean
    content = m.top.itemContent
    if content = invalid then return false
    if not content.HasField("menuExpanded") then return false
    return content.menuExpanded
end function

sub onMenuExpanded()
    target = 0
    if MenuExpanded() then target = 1
    m.labelAnimation.control = "stop"
    m.labelOpacityInterpolator.keyValue = [m.label.opacity, target]
    m.labelAnimation.control = "start"
    UpdateLook()
end sub
