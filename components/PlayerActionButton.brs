sub init()
    UpdateLook()
end sub

sub UpdateLook()
    m.top.FindNode("caption").color = "0xFFFFFFFF"
    m.top.FindNode("caption").text = m.top.caption
    m.top.FindNode("caption").visible = m.top.selected
    m.top.FindNode("icon").uri = m.top.icon
    m.top.FindNode("icon").blendColor = "0xFFFFFFFF"
    m.top.FindNode("plate").blendColor = "0x181818BB"
    if m.top.selected
        m.top.FindNode("plate").blendColor = "0xFFFFFFFF"
        m.top.FindNode("icon").blendColor = "0x101010FF"
    end if
end sub
