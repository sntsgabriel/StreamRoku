// Regressions from the photographed search overflow and audit of related controls.
const fs=require('fs'); const path=require('path'); const {spawnSync}=require('child_process');
const root=path.resolve(__dirname,'..');
function extract(file,name){
 const src=fs.readFileSync(path.join(root,file),'utf8');
 const match=src.match(new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`,'mi'));
 if(!match)throw new Error(`Missing ${name}`); return match[0];
}
const source=[
 fs.readFileSync(path.join(root,'source/util/UiLayout.brs'),'utf8'),
 fs.readFileSync(path.join(root,'source/util/TrackPanelModel.brs'),'utf8'),
 ...['FitSearchKeyboard','ScheduleKeyboardLayout','onQueryChanged','onShowResults','RememberCompletedSearch','ShowHistory','HideHistory','onRemoveHistoryItem','onSearchDebounce'].map(n=>extract('components/SearchScreen.brs',n)),
 extract('components/SearchScreen.brs','RunSearch').replace('sub RunSearch(', 'sub ExerciseRunSearch('),
 ...['SelectSubtitle','SelectAudio','RequestClose','FocusSection'].map(n=>extract('components/MediaTrackPanel.brs',n)),
 extract('components/MediaTrackPanel.brs','onKeyEvent').replace('onKeyEvent(', 'TrackPanelKeyEvent('),
 ...['ApplyPreferredAudioTrack','ShowCaptionMenu','CloseCaptionMenu'].map(n=>extract('components/PlayerScreen.brs',n))
].join('\n');
const mocks=`
function Theme() as object
 return {textWhite:"white",mediaPanelInk:"black"}
end function
function Lang(section as string,key as string) as string
 return key
end function
sub ApplySectionLook()
end sub
sub HidePlayerControls()
end sub
sub RefreshTrackPanel()
end sub
sub RunSearch(query as string)
 m.runCalls = m.runCalls + 1
end sub
sub CancelSearch()
 if m.cancelled = invalid then m.cancelled = 0
 m.cancelled = m.cancelled + 1
 m.searchTasks = invalid
end sub
sub ClearResults()
end sub
function SearchCandidates() as object
 return []
end function
sub LaunchSearchTasks()
end sub
`;
const cases=`
Harness_Equal(FitWidgetRect({width:0,height:500},760,580),invalid,"unsettled native layout is deferred")
fit = FitWidgetRect({x:0,y:0,width:1600,height:600},760,580)
Harness_Ok(fit.scale[0]*1600 <= 760.01,"full native keyboard including side controls fits reserved width")
fit = FitWidgetRect({x:-20,y:10,width:1000,height:2000},760,580)
Harness_Ok(fit.scale[1]*2000 <= 580.01,"tall keyboard respects height above results button")
Harness_Ok(Abs(fit.translation[0]+(-20)*fit.scale[0]) < 0.01,"negative native origin is compensated")
m.top = {screenActive:true}
m.keyboardLayoutTimer = {control:"stop"}
m.keyboardLayoutAttempts = 0
m.keyboard = {rect:{x:0,y:0,width:1600,height:600}, localBoundingRect:function() : return m.rect : end function, SetFocus:function(value) : m.focused=value : end function}
FitSearchKeyboard()
firstScale=m.keyboard.scale[0]
Harness_Ok(firstScale*1600 <= 760.01,"screen handler applies measured fit instead of fixed 0.7")
m.keyboard.rect.width=2200
FitSearchKeyboard()
Harness_Ok(m.keyboard.scale[0]<firstScale,"layout adapts to a wider firmware or keyboard mode")
m.historyGroup={visible:true}
m.historyList={itemFocused:1,itemSelected:0,content:{},SetFocus:function(value) : m.focused=value : end function}
m.historyStore={items:["Alien","Matrix"],saved:[],GetAll:function() : return m.items : end function,Add:function(query) : m.saved.Push(query) : end function,Remove:function(query) : m.removed=query : m.items=[] : end function}
m.results={visible:false,SetFocus:function(value) : m.focused=value : end function}
onShowResults()
Harness_Equal(m.historyList.focused,true,"View results reaches recent searches when history is shown")
onRemoveHistoryItem()
Harness_Equal(m.historyStore.removed,"Matrix","remove targets focused history row rather than last OK selection")
Harness_Equal(m.historyGroup.visible,false,"removing last stored entry hides history")
Harness_Equal(m.results.visible,true,"empty history restores result visibility")
m.historyGroup.visible=false
m.sources=[{}] : m.sourcesTask=invalid : m.status={text:""}
ExerciseRunSearch("ab")
ExerciseRunSearch("abi")
Harness_Equal(m.historyStore.saved.Count(),0,"live prefixes do not fill persisted recent searches")
m.lastQuery="Abigail" : m.rows=[{}]
onShowResults()
Harness_Equal(m.historyStore.saved[0],"Abigail","explicitly entering results records the complete query")
m.debounce={control:"stop"}
m.runCalls=0 : m.searchTasks={} : m.lastQuery="Matrix" : m.keyboard.text="Matrix"
onSearchDebounce()
Harness_Equal(m.runCalls,0,"history selection's pending debounce does not duplicate its active search")
m.cancelled=0
onQueryChanged()
Harness_Equal(m.cancelled,0,"deferred text observer does not cancel the history search already running")
m.top={choice:invalid}
m.audioSection=false
m.subtitleRows=[{id:"",code:"",action:"off"},{id:"new/pt",code:"pt-BR",action:"track"},{id:"new/fr",code:"fr",action:"track"}]
m.audioRows=[{id:"audio/pt",code:"pt"}]
m.subtitles={itemSelected:2,itemFocused:1,focused:true,HasFocus:function() : return m.focused : end function,SetFocus:function(value) : m.focused=value : end function}
m.audio={itemSelected:0,itemFocused:0,focused:false,HasFocus:function() : return m.focused : end function,SetFocus:function(value) : m.focused=value : end function}
SelectSubtitle()
Harness_Equal(m.top.choice.track,"new/fr","direct subtitle selection preserves exact selector")
Harness_Equal(m.top.choice.code,"fr","selection saves the selected language")
m.subtitles.itemSelected=0
SelectSubtitle()
Harness_Equal(m.top.choice.action,"off","Off is an ordinary subtitle row")
m.top.choice=invalid : m.subtitles.itemSelected=99
SelectSubtitle()
Harness_Equal(m.top.choice,invalid,"stale selection cannot select another track")
SelectAudio()
Harness_Equal(m.top.choice.track,"audio/pt","audio is independently selectable")
Harness_Equal(TrackPanelKeyEvent("down",true),false,"down within subtitle choices stays with native list scrolling")
Harness_Equal(TrackPanelKeyEvent("right",true),true,"right reaches audio section")
Harness_Equal(m.audio.focused,true,"audio receives focus")
m.subtitles.focused=false
Harness_Equal(TrackPanelKeyEvent("left",true),true,"left returns from audio to subtitle tab")
Harness_Equal(m.subtitles.focused,true,"subtitles receive focus again")
m.audioRows=[]
m.top.SetFocus=function(value) : m.focused=value : end function
FocusSection(true)
Harness_Equal(m.top.focused,true,"empty audio tab keeps focus on the panel")
Harness_Equal(TrackPanelKeyEvent("left",true),true,"empty audio tab can return to subtitles")
Harness_Equal(TrackPanelKeyEvent("back",false),false,"key release does not close panel")
Harness_Equal(TrackPanelKeyEvent("back",true),true,"Back closes options")
Harness_Equal(m.top.closeRequested,true,"close is delivered to player for viewport restoration")
m.video={audioTrack:"audio/pt",availableAudioTracks:[{Track:"audio/pt",Language:"por"},{Track:"audio/en",Language:"eng"}],HasField:function(field) : return true : end function}
m.audioTrackApplied=false : m.preferredAudioLanguage="pt"
ApplyPreferredAudioTrack()
Harness_Equal(m.audioTrackApplied,true,"matching native audio preference is latched without repeated application")
m.video={translation:[0,0],width:1920,height:1080,enableUI:true}
m.trackPanel={visible:false,callFunc:function(name)
 if name="Open"
  m.visible=true
 else
  m.visible=false
 end if
end function}
m.captionHintTimer={control:"start"} : m.captionButton={visible:true} : m.captionHint={visible:true}
ShowCaptionMenu()
Harness_Equal(m.video.width,1128,"open presents the live video beside the options")
Harness_Equal(m.video.enableUI,false,"native transport controls cannot cover the smaller preview")
ShowCaptionMenu()
CloseCaptionMenu()
Harness_Equal(m.video.width,1920,"repeated open still restores original full width")
Harness_Equal(m.video.height,1080,"close restores full height")
Harness_Equal(m.video.translation[0],0,"close restores original video position")
Harness_Equal(m.video.enableUI,true,"close restores native playback controls")
Harness_Equal(m.trackViewport,invalid,"saved viewport is cleared after closing")
print "Assertions passed:";m.passed;" failed:";m.failed
if m.failed=0 then print "BUGFIX PASS" else print "BUGFIX FAIL"
`;
const work=path.join(root,'work');fs.mkdirSync(work,{recursive:true});const target=path.join(work,'bugfix-run.brs');
fs.writeFileSync(target,fs.readFileSync(path.join(root,'tests/harness.brs'),'utf8')+'\n'+mocks+'\n'+source+'\n'+cases);
const result=spawnSync(path.join(root,'node_modules/.bin/brs'),['--root',work,target],{encoding:'utf8',cwd:root});
process.stdout.write(result.stdout||'');process.stderr.write(result.stderr||'');
if(result.status!==0 || !(result.stdout||'').includes('BUGFIX PASS'))process.exit(1);
// The two render viewports have a real gutter and cannot draw into each other.
const xml=fs.readFileSync(path.join(root,'components/SearchScreen.xml'),'utf8');
if(!/id="keyboardViewport"[^>]*clippingRect="\[0, 0, 760, 580\]"/.test(xml))throw new Error('Keyboard viewport guard missing');
if(!/id="searchResults"[^>]*clippingRect=/.test(xml))throw new Error('Result viewport guard missing');
