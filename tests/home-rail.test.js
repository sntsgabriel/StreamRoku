const fs=require('fs');const path=require('path');const {spawnSync}=require('child_process');
const root=path.resolve(__dirname,'..');
function extract(file,name){const s=fs.readFileSync(path.join(root,file),'utf8');const found=s.match(new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`,'mi'));if(!found)throw Error(name);return found[0];}
const source=[...['SetHomeFocus','SetRailExpanded','ApplyRailWidth','OnBackPressed','ApplyCatalogRow'].map(n=>extract('components/HomeScreen.brs',n)),extract('components/HomeScreen.brs','onKeyEvent').replace('onKeyEvent(','HomeKeyEvent('),...['MenuExpanded','onMenuExpanded','UpdateLook'].map(n=>extract('components/RailTile.brs',n))].join('\n');
const mocks=`
function Theme() as object
 return {screenBg:"black",accent:"accent_green",accentFocus:"green",textSecondary:"gray",accentClear:"clear",textPrimary:"white"}
end function
function TilePosterShape(metas as object) as string
 return "poster"
end function
function MakeRowNode(descriptor as object, counts as dynamic) as object
 return descriptor
end function
sub ApplyCatalogSizes()
end sub
sub ResyncRowLabels()
end sub
sub UpdateCatalogFeedback()
end sub
sub RebuildRows()
end sub
`;
const cases=`
m.focus={current:"catalog"}
m.rail={content:invalid,context:m.focus,HasFocus:function() : return m.context.current="rail" : end function,SetFocus:function(value) : m.context.current="rail" : end function}
m.catalog={content:{marker:"same catalog"},rowItemFocused:[1,3],context:m.focus,drawFocusFeedback:true,opacity:1.0,HasFocus:function() : return m.context.current="catalog" : end function,SetFocus:function(value) : m.context.current="catalog" : end function}
item={menuExpanded:false}
row={item:item,GetChildCount:function() : return 1 : end function,GetChild:function(index) : return m.item : end function}
m.rail.content={rows:[row],GetChildCount:function() : return m.rows.Count() : end function,GetChild:function(index) : return m.rows[index] : end function}
m.railBg={width:96} : m.railClip={}
m.railAnimation={control:"stop"} : m.railWidthInterpolator={}
m.nodes={brand:{},compactBrand:{},catalogArea:{translation:[136,0]}}
m.top={nodes:m.nodes,FindNode:function(id) : return m.nodes[id] : end function}
m.catalogArea=m.nodes.catalogArea
m.gridRows=[{},{}] : m.railExpanded=false : m.railMotionAllowed=true
ApplyRailWidth()
Harness_Equal(m.railClip.clippingRect[2],96,"collapsed viewport contains just icons")
Harness_Equal(m.catalogArea.translation[0],136,"catalog starts at collapsed margin")
Harness_Equal(m.nodes.brand.opacity,0,"full brand hidden when collapsed")
Harness_Equal(m.nodes.compactBrand.opacity,1,"compact brand remains visible")
Harness_Equal(HomeKeyEvent("left",true),true,"Left from catalog opens navigation")
Harness_Equal(m.focus.current,"rail","rail receives focus")
Harness_Equal(m.catalog.drawFocusFeedback,false,"catalog suppresses focus feedback when menu has focus")
Harness_Equal(item.menuExpanded,true,"all rail labels enter expanded state")
Harness_Equal(m.railWidthInterpolator.keyValue[0],96,"opening starts from collapsed width")
Harness_Equal(m.railWidthInterpolator.keyValue[1],360,"expanded menu has space for full labels")
Harness_Equal(m.railAnimation.control,"start","opening animates")
m.railBg.width=228
ApplyRailWidth()
Harness_Equal(m.railClip.clippingRect[2],228,"clip follows intermediate animated width")
Harness_Equal(m.catalogArea.translation[0],258,"catalog smoothly shifts with intermediate menu width")
Harness_Equal(m.nodes.brand.opacity,0.5,"full brand fades in during transition")
Harness_Equal(m.nodes.compactBrand.opacity,0.5,"compact brand fades out during transition")
Harness_Equal(HomeKeyEvent("right",true),true,"Right returns to films")
Harness_Equal(m.focus.current,"catalog","catalog regains focus")
Harness_Equal(m.catalog.drawFocusFeedback,true,"catalog restores focus feedback when returning to films")
Harness_Equal(item.menuExpanded,false,"labels collapse when browsing films")
Harness_Equal(m.railWidthInterpolator.keyValue[0],228,"interrupted animation reverses from current width")
Harness_Equal(m.railWidthInterpolator.keyValue[1],96,"closing ends at icon-only width")
Harness_Equal(m.catalog.content.marker,"same catalog","toggle does not replace catalog content")
Harness_Equal(m.catalog.rowItemFocused[0],1,"toggle preserves catalog row")
Harness_Equal(m.catalog.rowItemFocused[1],3,"toggle preserves selected film")
HomeKeyEvent("options",true)
Harness_Equal(m.focus.current,"rail","Options shortcut opens menu")
Harness_Equal(OnBackPressed(),true,"Back closes menu before exiting Home")
Harness_Equal(m.focus.current,"catalog","Back restores catalog focus")
Harness_Equal(OnBackPressed(),false,"Back in catalog retains normal app exit flow")
m.gridRows=[]
SetHomeFocus(false)
Harness_Equal(m.focus.current,"rail","empty catalog keeps navigation reachable")
Harness_Equal(m.railExpanded,true,"empty catalog cannot collapse focused navigation")
m.railMotionAllowed=false : m.gridRows=[{}]
SetHomeFocus(false)
Harness_Equal(m.railBg.width,96,"light mode applies final width without animation")
Harness_Equal(m.catalogArea.translation[0],136,"light mode positions catalog without animation")
Harness_Equal(m.railAnimation.control,"stop","light mode stops rail animation")
m.railBg.width=360
ApplyRailWidth()
Harness_Equal(m.catalogArea.translation[0],380,"expanded catalog clears 360px menu overlay")
Harness_Equal(m.nodes.brand.opacity,1,"expanded state displays complete brand")
Harness_Equal(m.nodes.compactBrand.opacity,0,"expanded state hides compact brand")
Harness_Equal(HomeKeyEvent("left",false),false,"key release does not toggle navigation")
m.top={itemHasFocus:true,rowHasFocus:invalid,itemContent:{menuExpanded:false,active:false,HasField:function(key) : return key="menuExpanded" or key="active" : end function}}
m.label={opacity:0.8} : m.glyph={} : m.border={} : m.zoomAnim={} : m.activeIndicator={}
m.labelAnimation={control:"stop"} : m.labelOpacityInterpolator={}
onMenuExpanded()
Harness_Equal(m.labelOpacityInterpolator.keyValue[0],0.8,"label fade starts at current opacity")
Harness_Equal(m.labelOpacityInterpolator.keyValue[1],0,"collapsed menu fades labels out")
Harness_Equal(m.border.color,"clear","collapsed rail does not retain full-width focus fill")
m.top.itemContent.menuExpanded=true
onMenuExpanded()
Harness_Equal(m.labelOpacityInterpolator.keyValue[1],1,"expanded menu fades labels in")
Harness_Equal(m.border.color,"green","focused expanded row retains visible selection")
m.top.rowHasFocus=false
UpdateLook()
Harness_Equal(m.border.color,"clear","row lacking rowHasFocus cleanly drops focus fill even if itemHasFocus is true")
m.top.itemContent.active=true
UpdateLook()
Harness_Equal(m.activeIndicator.visible,true,"active navigation section shows distinct indicator when unfocused")
Harness_Equal(m.border.color,"clear","active navigation section never shows control focus fill when unfocused")
m.top.rowHasFocus=true
UpdateLook()
Harness_Equal(m.activeIndicator.visible,false,"active indicator hidden when row receives control focus")
Harness_Equal(m.border.color,"green","focused active row shows clear control focus fill")
m.gridRows=[] : m.catalogRows=[]
m.catalog={content:{rows:[],GetChildCount:function() : return m.rows.Count() : end function,AppendChild:sub(node) : m.rows.Push(node) : end sub}}
ApplyCatalogRow({index:0,title:"Popular",metaType:"movie",addonAddress:"example",metas:[]})
Harness_Equal(m.gridRows[0].title,"Popular","streamed catalog retains the task title")
Harness_Equal(m.catalog.content.rows[0].title,"Popular","catalog node receives a visible title")
print "Assertions passed:";m.passed;" failed:";m.failed
if m.failed=0 then print "HOME RAIL PASS" else print "HOME RAIL FAIL"
`;
const target=path.join(root,'work/home-rail-run.brs');fs.writeFileSync(target,fs.readFileSync(path.join(root,'tests/harness.brs'),'utf8')+'\n'+mocks+'\n'+source+'\n'+cases);
const result=spawnSync(path.join(root,'node_modules/.bin/brs'),['--root',path.join(root,'work'),target],{encoding:'utf8',cwd:root});process.stdout.write(result.stdout||'');process.stderr.write(result.stderr||'');if(result.status!==0||!(result.stdout||'').includes('HOME RAIL PASS'))process.exit(1);
