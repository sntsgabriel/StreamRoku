const fs=require('fs');const path=require('path');const {spawnSync}=require('child_process');
const root=path.resolve(__dirname,'..');
function extract(file,name){const s=fs.readFileSync(path.join(root,file),'utf8');const found=s.match(new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`,'mi'));if(!found)throw Error(name);return found[0];}
const source=[fs.readFileSync(path.join(root,'source/util/PlayerControlsModel.brs'),'utf8'),...['UpdateProgress','PreviewSeek','CancelSeek','SeekConfirmed','PlaybackChanged','ResetIdle','SelectAction','UpdateButtons','Word','AutoHide','onPauseTick','ShowIdleDetails','WakeControls','StopSeekHold','StartSeekHold','onSeekHoldTick'].map(n=>extract('components/PlayerControls.brs',n)),extract('components/PlayerControls.brs','onKeyEvent').replace('onKeyEvent(','TimelineKeys('),extract('components/PlayerScreen.brs','onPlayerSeekRequest'),extract('components/PlayerScreen.brs','SyncPlayerControlsState'),extract('components/CaptionVideo.brs','onKeyEvent').replace('onKeyEvent(','VideoKeys(')].join('\n');
const mocks=`
sub ShowPlayerControls()
 m.opened=true
end sub
sub HidePlayerControls()
 m.playerControls.visible=false
end sub
`;
const cases=`
m.nodes={}
for each id in ["elapsed","total","remaining","hint","timelineLabel","progressFill","progressTrack","seekRange","progressDot","seekBubble","seekTime","seekDelta"]
 m.nodes[id]={}
end for
m.top={visible:true,paused:true,position:120,duration:600,words:{timeline:"Timeline",timelineHint:"timelineHint",seekHint:"seekHint",actionsHint:"actionsHint",remainingTime:"{time} remaining",live:"Live",liveHint:"Live controls"},nodes:m.nodes,FindNode:function(id) : return m.nodes[id] : end function}
m.buttons=[{},{},{},{}] : m.actionIds=["back","captions","restart","toggle"]
m.idle=false : m.seeking=false : m.seekPending=false : m.focusZone="timeline" : m.focusedIndex=3
m.chrome={visible:true} : m.details={visible:false}
m.idleTimer={} : m.hideTimer={} : m.seekSettleTimer={}
m.seekHoldTimer={} : m.holdKey=""
m.holdClock={elapsed:0,Mark:function() : m.elapsed=0 : end function,TotalMilliseconds:function() : return m.elapsed : end function}
m.pauseClock={Mark:function() : end function,TotalMilliseconds:function() : return 9000 : end function}
m.seekClock={elapsed:0,Mark:function() : m.elapsed=0 : end function,TotalMilliseconds:function() : return m.elapsed : end function}
UpdateButtons() : UpdateProgress()
Harness_Equal(m.buttons[3].selected,false,"timeline focus never highlights pause")
Harness_Equal(m.nodes.progressDot.width,32,"focused timeline has an obvious handle")
Harness_Equal(m.nodes.remaining.text,"8:00 remaining","remaining time is computed from actual duration")
TimelineKeys("right",true)
Harness_Equal(m.seekPosition,130,"right previews ten seconds forward")
Harness_Equal(m.top.seekRequest,invalid,"preview alone cannot seek the player")
Harness_Equal(m.top.position,120,"preview does not overwrite actual progress")
TimelineKeys("right",false)
TimelineKeys("right",true)
Harness_Equal(m.seekPosition,140,"repeated input accumulates from preview target")
m.top.position=125 : UpdateProgress()
Harness_Equal(m.seekPosition,140,"position updates cannot overwrite active preview")
Harness_Equal(m.nodes.seekTime.text,"2:20","preview timestamp stays stable during playback")
TimelineKeys("right",false)
Harness_Equal(m.seekPosition,140,"key release never duplicates seek steps")
TimelineKeys("fastforward",true)
Harness_Equal(m.seekPosition,170,"fast forward previews thirty seconds")
TimelineKeys("rewind",true)
Harness_Equal(m.seekPosition,140,"rewind previews thirty seconds back")
TimelineKeys("OK",true)
Harness_Equal(m.top.seekRequest.position,140,"OK publishes the preview target")
Harness_Equal(m.top.action,invalid,"confirming seek cannot trigger pause or resume")
SeekConfirmed(140)
Harness_Equal(m.seekPending,true,"confirmed target is held while native seek settles")
Harness_Equal(m.nodes.seekTime.text,"2:20","stale native position does not bounce handle back")
m.top.position=140 : UpdateProgress()
Harness_Equal(m.seekPending,false,"actual arrival releases optimistic target")
Harness_Equal(m.seekSettleTimer.control,"stop","settled seek stops its timer")
TimelineKeys("left",true)
m.top.seekRequest=invalid : m.top.action=""
TimelineKeys("back",true)
Harness_Equal(m.seeking,false,"first Back cancels preview")
Harness_Equal(m.top.action,"","canceling preview keeps controls visible")
Harness_Equal(m.top.seekRequest,invalid,"cancellation cannot send a seek")
TimelineKeys("up",true)
Harness_Equal(m.focusZone,"actions","Up reaches actions only after timeline")
Harness_Equal(m.focusedIndex,3,"pause is the action immediately above timeline")
TimelineKeys("down",true)
Harness_Equal(m.focusZone,"timeline","Down from pause returns to timeline")
Harness_Equal(m.buttons[3].selected,false,"pause drops highlight when returning to timeline")
PreviewSeek(-1000)
Harness_Equal(m.seekPosition,0,"seek preview clamps to beginning")
PreviewSeek(10000)
Harness_Equal(m.seekPosition,600,"seek preview clamps to duration")
Harness_Equal(m.nodes.seekBubble.translation[0],1432,"preview bubble stays inside right safe margin")
m.top.paused=false : m.top.action=""
ResetIdle() : AutoHide()
Harness_Equal(m.top.action,"","active preview cannot auto-hide")
Harness_Equal(m.hideTimer.control,"stop","preview suspends playing auto-hide timer")
m.top.paused=true : m.details.visible=false
onPauseTick()
Harness_Equal(m.details.visible,false,"active preview cannot be replaced by idle pause art")
CancelSeek()
Harness_Equal(m.idleTimer.control,"start","cancel restores paused idle timer")
SeekConfirmed(500) : m.seekClock.elapsed=4000
UpdateProgress()
Harness_Equal(m.seekPending,false,"failed native seek cannot freeze handle indefinitely")
m.top.duration=0 : m.seeking=false
PreviewSeek(10) : UpdateProgress()
Harness_Equal(m.seeking,false,"unknown duration disables scrubbing")
Harness_Equal(m.nodes.progressDot.visible,false,"unknown duration has no invented seek handle")
Harness_Equal(m.nodes.seekBubble.visible,false,"live stream has no invented preview timestamp")
overlayTop=m.top
' Exercise the actual parent callback independently of the overlay.
m.top={screenActive:true}
m.trackPanel={visible:false}
m.playerControls={visible:true,paused:true,seekRequest:{position:450},callFunc:sub(name,target=invalid) : m.confirmed=target : end sub}
m.video={state:"paused",duration:600,position:120,control:"pause",seek:-1,content:{marker:"same content"},audioTrack:"audio/pt",subtitleTrack:"sub/pt"}
onPlayerSeekRequest()
Harness_Equal(m.video.seek,450,"parent seeks the real Video node on confirmation")
Harness_Equal(m.video.control,"pause","seeking a paused video never requests resume")
Harness_Equal(m.playerControls.visible,true,"confirmation keeps timeline visible")
Harness_Equal(m.playerControls.confirmed,450,"parent acknowledges native seek target")
Harness_Equal(m.video.content.marker,"same content","seek never replaces media content")
Harness_Equal(m.video.audioTrack,"audio/pt","seek preserves audio selection")
Harness_Equal(m.video.subtitleTrack,"sub/pt","seek preserves subtitle selection")
m.video.state="playing" : m.playerControls.paused=false
SyncPlayerControlsState()
Harness_Equal(m.playerControls.visible,true,"playing notification after seek cannot hide timeline")
m.video.state="buffering"
SyncPlayerControlsState()
Harness_Equal(m.playerControls.visible,true,"seek buffering keeps timeline visible")
m.video.state="paused" : m.video.duration=0 : m.video.seek=42
onPlayerSeekRequest()
Harness_Equal(m.video.seek,42,"parent rejects seek when duration is unavailable")
m.top={state:"playing",captionControlsRequested:false}
Harness_Equal(VideoKeys("up",true),true,"Up on video opens the overlay")
Harness_Equal(m.top.captionControlsRequested,true,"Up goes through existing player control event")
m.top=overlayTop : m.top.position=120 : m.top.duration=600 : m.top.visible=true
m.idle=false : m.focusZone="timeline" : m.seeking=false : m.seekPending=false : m.holdKey=""
TimelineKeys("right",true)
Harness_Equal(m.seekPosition,130,"held seek starts with a single ten-second step")
m.holdClock.elapsed=200 : onSeekHoldTick()
Harness_Equal(m.seekPosition,130,"hold has an initial repeat delay")
m.holdClock.elapsed=400 : onSeekHoldTick()
Harness_Equal(m.seekPosition,140,"timer advances preview without relying on native repeat")
m.holdClock.elapsed=1000 : onSeekHoldTick()
Harness_Equal(m.seekPosition,160,"one-second hold accelerates to twenty-second steps")
m.holdClock.elapsed=2500 : onSeekHoldTick()
Harness_Equal(m.seekPosition,200,"longer hold accelerates further")
m.holdClock.elapsed=5000 : onSeekHoldTick()
Harness_Equal(m.seekPosition,320,"long hold reaches bounded two-minute steps")
TimelineKeys("right",false)
Harness_Equal(m.seekHoldTimer.control,"stop","release stops hold immediately")
onSeekHoldTick()
Harness_Equal(m.seekPosition,320,"a queued hold tick cannot advance after release")
Harness_Equal(PlayerHoldSeekStep("rewind",5000),-120,"rewind acceleration is capped and signed")
Harness_Equal(PlayerMoveAction(3,-1,true),4,"Next episode sits immediately above pause for series")
Harness_Equal(PlayerMoveAction(4,1,true),3,"Down from Next reaches pause")
Harness_Equal(PlayerMoveAction(3,-1,false),2,"movies skip unavailable Next action")
m.top={words:invalid}
Harness_Equal(Word("timeline"),"","early progress notifications tolerate unbound translations")
print "Assertions passed:";m.passed;" failed:";m.failed
if m.failed=0 then print "TIMELINE PASS" else print "TIMELINE FAIL"
`;
const target=path.join(root,'work/timeline-run.brs');fs.writeFileSync(target,fs.readFileSync(path.join(root,'tests/harness.brs'),'utf8')+'\n'+mocks+'\n'+source+'\n'+cases);
const result=spawnSync(path.join(root,'node_modules/.bin/brs'),['--root',path.join(root,'work'),target],{encoding:'utf8',cwd:root});process.stdout.write(result.stdout||'');process.stderr.write(result.stderr||'');if(result.status!==0||!(result.stdout||'').includes('TIMELINE PASS'))process.exit(1);
