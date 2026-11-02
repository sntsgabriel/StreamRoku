sub init()
    m.list = m.top.FindNode("choices")
    m.list.ObserveField("rowItemSelected", "onChoice")
    t = Theme()
    m.top.FindNode("scrim").color = t.scrim
    m.top.FindNode("panel").color = t.screenBg
    m.top.FindNode("title").color = t.textPrimary
    m.top.FindNode("subtitle").color = t.textSecondary
    m.top.FindNode("footer").color = t.textSecondary
    m.top.visible = false
end sub

sub Open(title as string, subtitle as string, entries as object, footer as string)
    m.entries = entries
    m.top.FindNode("title").text = title
    m.top.FindNode("subtitle").text = subtitle
    m.top.FindNode("footer").text = footer
    root = CreateObject("roSGNode", "ContentNode")
    for each entry in entries
        row = root.CreateChild("ContentNode")
        row.CreateChild("ContentNode").title = entry.label
    end for
    m.list.content = root
    m.list.jumpToRowItem = [0, 0]
    m.top.visible = true
    m.list.SetFocus(true)
end sub

sub DismissMenu()
    m.top.visible = false
end sub

sub onChoice()
    selected = m.list.rowItemSelected
    if selected = invalid or selected.Count() < 2 then return
    if selected[0] < 0 or selected[0] >= m.entries.Count() then return
    m.top.choice = m.entries[selected[0]]
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "back" or key = "options" then m.top.choice = { action: "back" }
    return true
end function
