sub init()
    UpdateLook()
end sub

sub UpdateLook()
    face = m.top.FindNode("face")
    label = m.top.FindNode("label")
    if face = invalid or label = invalid then return
    if m.top.itemContent <> invalid then label.text = m.top.itemContent.title
    t = Theme()
    face.color = t.tileFace
    label.color = t.textPrimary
    if m.top.itemHasFocus and m.top.rowHasFocus
        face.color = t.textPrimary
        label.color = t.screenBg
    end if
end sub
