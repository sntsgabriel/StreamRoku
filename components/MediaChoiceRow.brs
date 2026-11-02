sub init()
    UpdateLook()
end sub

sub UpdateLook()
    focused = m.top.itemHasFocus and m.top.listHasFocus
    m.top.FindNode("face").visible = focused
    m.top.FindNode("face").color = "0xFFFFFFFF"
    if m.top.width > 84 and m.top.height > 0
        m.top.FindNode("face").width = m.top.width
        m.top.FindNode("face").height = m.top.height
        m.top.FindNode("title").width = m.top.width - 84
        m.top.FindNode("title").height = m.top.height
    end if
    color = "0xEEEEEEFF"
    if focused then color = "0x101010FF"
    m.top.FindNode("title").color = color
    m.top.FindNode("check").blendColor = color
    content = m.top.itemContent
    if content = invalid then return
    m.top.FindNode("title").text = content.title
    m.top.FindNode("check").visible = content.HasField("trackChecked") and content.trackChecked
end sub
