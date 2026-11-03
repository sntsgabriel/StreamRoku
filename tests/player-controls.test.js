// Exercise pause timers, sidebar actions and viewport ownership without a Roku.
const fs = require('fs');
const path = require('path');
const {spawnSync} = require('child_process');
const root = path.resolve(__dirname, '..');
function extract(file, name) {
    const src = fs.readFileSync(path.join(root, file), 'utf8');
    const found = src.match(new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`, 'mi'));
    if (!found) throw new Error(`Missing ${name}`);
    return found[0];
}
const source = [
    fs.readFileSync(path.join(root, 'source/util/PlayerControlsModel.brs'), 'utf8'),
    fs.readFileSync(path.join(root, 'source/util/TrackPanelModel.brs'), 'utf8'),
    ...['ShowPlayerControls','HidePlayerControls','UpdatePlayerProgress','SyncPlayerControlsState','onPlayerControlAction','onPlayerSeekRequest','RestartFromBeginning','ResolveOrdinal'].map(n => extract('components/PlayerScreen.brs', n)),
    extract('components/PlayerScreen.brs', 'ShowCaptionMenu').replace('ShowCaptionMenu(', 'ExerciseShowCaptionMenu('),
    extract('components/PlayerScreen.brs', 'CloseCaptionMenu'),
    extract('components/MainScene.brs', 'onPlayerAction'),
    ...['Open','onPauseTick','ResetIdle','ShowIdleDetails','AutoHide','Dismiss','WakeControls','SelectAction','UpdateButtons','Word','UpdateArtwork','UpdateProgress','PreviewSeek','CancelSeek','SeekConfirmed','PlaybackChanged','StopSeekHold','StartSeekHold','onSeekHoldTick'].map(n => extract('components/PlayerControls.brs', n)),
    extract('components/MediaChoiceRow.brs', 'UpdateLook').replace('UpdateLook(', 'MediaRowLook('),
    extract('components/PlayerControls.brs', 'onKeyEvent').replace('onKeyEvent(', 'ControlsKeyEvent(')
].join('\n');
const mocks = `
function ControlsTestNodes() as object
 nodes={}
 for each id in ["smallTitle","smallEpisode","mediaTitle","episode","stateLabel","idleState","hint","pausePrompt","mediaLogo","elapsed","total","remaining","progressTrack","progressFill","progressDot","seekRange","seekBubble","seekTime","seekDelta","timelineLabel"]
  nodes[id]={}
 end for
 return nodes
end function

function Lang(section as string, key as string) as string
 if key="episodeMarker" then return "T{season}:E{episode}"
 return key
end function
function Fill(text as string, values as object) as string
 for each key in values
  text=text.Replace("{"+key+"}",values[key])
 end for
 return text
end function
sub RefreshTrackPanel()
end sub
sub ShowCaptionMenu()
 m.captionOpened=true
end sub
sub DismissNextEpisode()
 m.nextDismissed=true
end sub
`;
const cases = `
Harness_Equal(PlayerClock(0),"0:00","zero timestamp")
Harness_Equal(PlayerClock(125),"2:05","minutes use padded seconds")
Harness_Equal(PlayerClock(3725),"1:02:05","long films include hours")
Harness_Equal(PlayerClock(-10),"0:00","negative time is clamped")
Harness_Equal(PlayerProgress(300,600,828),414,"half playback fills half the bar")
Harness_Equal(PlayerProgress(100,0,828),0,"unknown/live duration has no invented progress")
Harness_Equal(PlayerProgress(700,600,828),828,"progress cannot overflow")
m.top={screenActive:true}
m.playParams={name:"Example",episodeName:"Pilot",season:1,episode:2,logo:""}
m.video={state:"paused",position:180,duration:1200,enableUI:true,content:{marker:"same content"},subtitleTrack:"sub/pt",audioTrack:"audio/en",SetFocus:function(value) : m.focused=value : end function}
m.trackPanel={visible:false}
m.captionHintTimer={control:"start"} : m.captionHint={visible:true} : m.captionButton={visible:true}
m.playerControls={visible:false,opened:0,callFunc:function(name)
 if name="Open"
  m.visible=true
  m.opened=m.opened+1
 else
  m.visible=false
 end if
end function}
ShowPlayerControls()
Harness_Equal(m.playerControls.visible,true,"paused playback opens sidebar")
Harness_Equal(m.playerControls.paused,true,"overlay receives paused state")
Harness_Equal(m.playerControls.episodeText,"T1:E2 · Pilot","episode metadata reaches pause screen")
Harness_Equal(m.playerControls.position,180,"pause progress comes from actual playback")
firstOpen=m.playerControls.opened
for i=1 to 12
 SyncPlayerControlsState()
end for
Harness_Equal(m.playerControls.opened,firstOpen,"duplicate paused state notifications cannot restart overlay timer")
Harness_Equal(m.video.enableUI,false,"native chrome yields to overlay")
ShowPlayerControls()
HidePlayerControls()
Harness_Equal(m.video.enableUI,true,"repeated open restores original native UI")
m.video.enableUI=false
ShowPlayerControls()
HidePlayerControls()
Harness_Equal(m.video.enableUI,false,"original disabled UI is preserved")
m.video.enableUI=true
m.trackPanel.visible=true
before=m.playerControls.opened
ShowPlayerControls()
Harness_Equal(m.playerControls.opened,before,"pause must not steal focus from language selection")
m.trackPanel.visible=false
m.top.screenActive=false
ShowPlayerControls()
Harness_Equal(m.playerControls.opened,before,"covered or exited player cannot show controls")
m.top.screenActive=true
m.playerControls.action="restart"
onPlayerControlAction()
Harness_Equal(m.video.seek,0,"watch from beginning seeks to zero")
Harness_Equal(m.video.control,"resume","watch from beginning resumes a paused video")
Harness_Equal(m.video.content.marker,"same content","restart does not replace playing content")
Harness_Equal(m.video.subtitleTrack,"sub/pt","restart keeps subtitle choice")
Harness_Equal(m.video.audioTrack,"audio/en","restart keeps audio choice")
m.playerControls.action="left" : m.video.position=3
onPlayerControlAction()
Harness_Equal(m.video.seek,0,"rewind is clamped to the beginning")
m.playerControls.action="fastforward" : m.video.position=1190
onPlayerControlAction()
Harness_Equal(m.video.seek,1200,"fast forward is clamped to duration")
m.playerControls.action="captions"
onPlayerControlAction()
Harness_Equal(m.captionOpened,true,"sidebar opens audio/subtitle panel")
m.playerControls.action="back"
onPlayerControlAction()
Harness_Equal(m.top.pushRequest.screen,"back","sidebar Back uses the screen stack")
m.playerControls.action="toggle"
onPlayerControlAction()
Harness_Equal(m.video.control,"resume","Continue resumes")
m.video.state="playing"
onPlayerControlAction()
Harness_Equal(m.video.control,"pause","Pause pauses")
m.playerScreen={screenActive:true,pushRequest:{screen:"back"}}
m.stack={popped:0,pop:function() : m.popped=m.popped+1 : end function}
onPlayerAction()
Harness_Equal(m.stack.popped,1,"Back button pops the active player through the scene")
m.playerScreen.screenActive=false
onPlayerAction()
Harness_Equal(m.stack.popped,1,"stale Back request cannot pop a different screen")
m.playerScreen.screenActive=true
m.playerScreen.pushRequest={screen:"streamsScreen",params:{videoId:"series:1:2"}}
m.stack={popped:0,pushed:0,pop:function() : m.popped=m.popped+1 : end function,has:function(id) : return true : end function,popTo:sub(id) : m.target=id : end sub,push:sub(id,params) : m.pushed=m.pushed+1 : end sub}
m.streamsScreen={callFunc:sub(name,params) : m.params=params : end sub}
onPlayerAction()
Harness_Equal(m.stack.popped,1,"next episode removes the previous player")
Harness_Equal(m.stack.target,"streamsScreen","next episode reuses the existing streams screen")
Harness_Equal(m.stack.pushed,0,"next episode cannot duplicate the static streams node")
Harness_Equal(m.streamsScreen.params.videoId,"series:1:2","existing streams screen receives next episode")
m.playerScreen.screenActive=false
onPlayerAction()
Harness_Equal(m.stack.popped,1,"late next episode request cannot pop another screen")
m.video.translation=[0,0] : m.video.width=1920 : m.video.height=1080
m.trackPanel.callFunc=function(name)
 m.visible=name="Open"
end function
ShowPlayerControls()
ExerciseShowCaptionMenu()
Harness_Equal(m.playerControls.visible,false,"language panel replaces the sidebar")
Harness_Equal(m.trackViewport.enableUI,true,"language panel snapshots the original native UI")
CloseCaptionMenu()
Harness_Equal(m.video.enableUI,true,"closing language panel after sidebar restores native controls")
Harness_Equal(m.video.width,1920,"language panel after sidebar restores full-screen video")
m.video.state="error" : m.video.seek=42
RestartFromBeginning()
Harness_Equal(m.video.seek,42,"restart ignores errored or unstarted streams")
m.idleTimer={control:"stop"} : m.hideTimer={control:"stop"}
m.seekSettleTimer={control:"stop"}
m.seekHoldTimer={control:"stop"}
m.holdKey=""
m.holdClock={elapsed:0,Mark:function() : m.elapsed=0 : end function,TotalMilliseconds:function() : return m.elapsed : end function}
m.seekClock={elapsed:0,Mark:function() : m.elapsed=0 : end function,TotalMilliseconds:function() : return m.elapsed : end function}
m.seeking=false : m.seekPending=false : m.focusZone="actions"
m.pauseClock={elapsed:0,marks:0,Mark:function() : m.elapsed=0 : m.marks=m.marks+1 : end function,TotalMilliseconds:function() : return m.elapsed : end function}
m.details={visible:false}
m.chrome={visible:true}
m.buttons=[{},{},{},{}]
m.actionIds=["back","captions","restart","toggle"]
m.focusedIndex=3
m.nodes=ControlsTestNodes()
m.top={visible:true,paused:true,position:128,duration:600,globalNodes:m.nodes,FindNode:function(id) : return m.globalNodes[id] : end function,words:{back:"Back",captions:"Subtitles",restart:"Restart",resume:"Resume",pause:"Pause"}}
ResetIdle()
Harness_Equal(m.idleTimer.control,"start","pause arms delayed details")
Harness_Equal(m.hideTimer.control,"stop","paused controls do not auto hide")
m.idle=false
m.pauseClock.elapsed=7999
onPauseTick()
Harness_Equal(m.details.visible,false,"pause details wait for eight seconds of real elapsed time")
m.pauseClock.elapsed=8000
onPauseTick()
Harness_Equal(m.details.visible,true,"timer reveals pause artwork and metadata")
Harness_Equal(m.idleTimer.control,"stop","revealing details stops the repeated timer")
Harness_Equal(m.chrome.visible,false,"idle presentation hides buttons AND timeline together")
m.top.action=""
Harness_Equal(ControlsKeyEvent("right",true),true,"first arrow wakes idle screen")
Harness_Equal(m.top.action,"","waking idle screen cannot accidentally seek")
Harness_Equal(m.chrome.visible,true,"waking shows compact controls again")
ShowIdleDetails()
Harness_Equal(ControlsKeyEvent("OK",true),true,"OK resumes straight from idle screen")
Harness_Equal(m.top.action,"toggle","idle OK resumes instead of activating a hidden button")
WakeControls()
Harness_Equal(m.details.visible,false,"navigation returns to uncluttered controls")
m.top.paused=false
ShowIdleDetails()
Harness_Equal(m.details.visible,false,"late idle timer cannot show pause screen during playback")
ResetIdle()
Harness_Equal(m.hideTimer.control,"start","playing controls auto hide")
AutoHide()
Harness_Equal(m.top.action,"dismiss","auto hide requests native UI restoration")
m.top.paused=true : m.top.action=""
AutoHide()
Harness_Equal(m.top.action,"","stale hide timer cannot dismiss paused controls")
Harness_Equal(ControlsKeyEvent("play",true),true,"remote Play is handled while overlay has focus")
Harness_Equal(m.top.action,"toggle","remote Play toggles playback")
Harness_Equal(ControlsKeyEvent("back",true),true,"remote Back hides overlay before leaving player")
Harness_Equal(m.top.action,"dismiss","Back does not accidentally exit playback")
m.focusedIndex=3
Harness_Equal(m.focusZone,"timeline","waking controls selects timeline before pause")
Harness_Equal(ControlsKeyEvent("up",true),true,"up moves from timeline to pause")
Harness_Equal(m.focusedIndex,3,"first control above timeline is pause")
Harness_Equal(m.buttons[3].selected,true,"pause gains focus only after leaving timeline")
ControlsKeyEvent("up",true)
Harness_Equal(m.focusedIndex,2,"up reaches restart icon")
Harness_Equal(m.buttons[2].selected,true,"only focused icon gets selected label")
Harness_Equal(m.buttons[3].selected,false,"previous icon loses focus")
ControlsKeyEvent("OK",true)
Harness_Equal(m.top.action,"restart","OK activates the focused icon")
Dismiss()
Harness_Equal(m.idleTimer.control,"stop","dismiss cancels idle timer")
Harness_Equal(m.hideTimer.control,"stop","dismiss cancels auto hide timer")
Harness_Equal(m.top.visible,false,"dismiss hides overlay")
m.nodes={face:{},title:{},check:{},mediaLogo:{loadStatus:"ready"},mediaTitle:{}}
m.top={width:564,height:60,itemHasFocus:true,listHasFocus:true,itemContent:{title:"Português",trackChecked:true,HasField:function(key) : return key="trackChecked" : end function},FindNode:function(id) : return m.globalNodes[id] : end function}
m.top.globalNodes=m.nodes
MediaRowLook()
Harness_Equal(m.nodes.title.text,"Português","focused row retains its label")
Harness_Equal(m.nodes.title.color,"0x101010FF","focused label is dark on white")
Harness_Equal(m.nodes.face.visible,true,"focus plate is part of the same row")
Harness_Equal(m.nodes.title.height,m.nodes.face.height,"text and focus plate share exact row height")
Harness_Equal(m.nodes.check.visible,true,"active track check remains visible independently of focus")
m.top.listHasFocus=false
MediaRowLook()
Harness_Equal(m.nodes.face.visible,false,"inactive list has no stray focus plate")
Harness_Equal(m.nodes.title.color,"0xEEEEEEFF","inactive row stays readable")
m.top.logo="pkg:/example.png"
UpdateArtwork()
Harness_Equal(m.nodes.mediaTitle.visible,false,"loaded logo suppresses duplicated title")
Harness_Equal(m.nodes.mediaLogo.visible,true,"loaded logo is visible")
m.nodes.mediaLogo.loadStatus="failed"
UpdateArtwork()
Harness_Equal(m.nodes.mediaTitle.visible,true,"failed logo restores readable title fallback")
Harness_Equal(m.nodes.mediaLogo.visible,false,"failed artwork does not leave an empty image")
m.nodes={}
for each id in ["smallTitle","smallEpisode","mediaTitle","episode","stateLabel","idleState","hint","pausePrompt","mediaLogo","elapsed","total","remaining","progressTrack","progressFill","progressDot","seekRange","seekBubble","seekTime","seekDelta","timelineLabel"]
 m.nodes[id]={}
end for
m.nodes.mediaLogo.loadStatus="failed"
m.top={visible:false,paused:true,mediaTitle:"Film name",episodeText:"",logo:"",position:128,duration:600,words:{paused:"Paused"},SetFocus:function(value) : m.focused=value : end function,FindNode:function(id) : return m.globalNodes[id] : end function}
m.top.globalNodes=m.nodes
m.presented=false : m.presentedPaused=false
Open()
Harness_Equal(m.nodes.mediaTitle.text,"Film name","real Open populates pause title")
Harness_Equal(m.chrome.visible,true,"new pause starts with controls")
m.pauseClock.elapsed=7000
marks=m.pauseClock.marks
Open()
Harness_Equal(m.pauseClock.marks,marks,"reopening same pause cannot reset elapsed clock")
Harness_Equal(m.pauseClock.elapsed,7000,"seven elapsed seconds survive repeated Open")
m.pauseClock.elapsed=8100
onPauseTick()
Harness_Equal(m.details.visible,true,"title presentation appears after deadline through timer handler")
Harness_Equal(m.chrome.visible,false,"timer transition hides controls")
Open()
Harness_Equal(m.details.visible,true,"repeated Open cannot replace visible title with buttons")
Harness_Equal(m.chrome.visible,false,"repeated Open preserves clean pause screen")
WakeControls()
Harness_Equal(m.pauseClock.elapsed,0,"actual user navigation starts a fresh idle interval")
marks=m.pauseClock.marks
ControlsKeyEvent("unknown",true)
Harness_Equal(m.pauseClock.marks,marks,"unhandled keys cannot postpone the pause screen")
m.top.paused=false : m.pauseClock.elapsed=10000 : m.details.visible=false
onPauseTick()
Harness_Equal(m.details.visible,false,"stale tick after resume cannot show pause details")
print "Assertions passed:";m.passed;" failed:";m.failed
if m.failed=0 then print "PLAYER CONTROLS PASS" else print "PLAYER CONTROLS FAIL"
`;
const target = path.join(root, 'work/player-controls-run.brs');
fs.writeFileSync(target, fs.readFileSync(path.join(root, 'tests/harness.brs'), 'utf8') + '\n' + mocks + '\n' + source + '\n' + cases);
const result = spawnSync(path.join(root,'node_modules/.bin/brs'),['--root', path.join(root,'work'), target], {cwd:root, encoding:'utf8'});
process.stdout.write(result.stdout || '');
process.stderr.write(result.stderr || '');
if (result.status !== 0 || !(result.stdout || '').includes('PLAYER CONTROLS PASS')) process.exit(1);
