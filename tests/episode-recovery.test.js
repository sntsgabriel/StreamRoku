const fs=require('fs');const path=require('path');const {spawnSync}=require('child_process');
const root=path.resolve(__dirname,'..');
function extract(file,name){const s=fs.readFileSync(path.join(root,file),'utf8');const found=s.match(new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`,'mi'));if(!found)throw Error(name);return found[0];}
const source=[extract('components/PlayerScreen.brs','SavePosition').replace('SavePosition()', 'ExerciseSavePosition()'),extract('components/PlayerScreen.brs','PublishWatchState').replace('PublishWatchState()', 'ExercisePublishWatchState()'),fs.readFileSync(path.join(root,'source/util/PlayerControlsModel.brs'),'utf8'),...['onVideoFinished','onVideoStateChanged','ShowPlaybackFailure','RetryCurrentEpisode','ChooseCurrentSource','RestoreFailureUI','EnsureNextEpisodeData','FindNextEpisode','CancelNextMetaLoad','onNextMetaLoaded','PlayNextEpisode','onNextEpisodeTimerFire','onPlayerControlAction','ResolveOrdinal'].map(n=>extract('components/PlayerScreen.brs',n)),...['UpdateButtons','Word'].map(n=>extract('components/PlayerControls.brs',n))].join('\n');
const mocks=`
function Lang(section as string,key as string) as string
 if key="episodeMarker" then return "T{season}:E{episode}"
 return key
end function
function Fill(value as string,fields as object) as string
 for each key in fields
  value=value.Replace("{"+key+"}",fields[key])
 end for
 return value
end function
function StringOf(value as dynamic) as string
 if value=invalid then return ""
 return value.ToStr()
end function
sub PublishWatchState()
end sub
sub SavePosition()
 m.savedCalls=m.savedCalls+1
end sub
sub ShowNextEpisodePrompt()
 m.prompts=m.prompts+1
 m.nextEpisodeGroup.visible=true
end sub
sub UpdateNextEpisodeCountdown()
end sub
sub ShowSeriesEndNotice()
 m.seriesEnded=true
end sub
sub CancelResolve()
end sub
sub CancelSubtitles()
end sub
sub StopPreVideoPulse()
end sub
sub HideBuffering()
end sub
sub HidePlayerControls()
 m.playerControls.visible=false
end sub
sub DismissNextEpisode()
 m.nextEpisodeGroup.visible=false
 m.nextEpisodeTimer.control="stop"
end sub
sub SyncPlayerControlsState()
end sub
function NotPlayableOnDevice() as boolean
 return false
end function
sub LogVideoError()
end sub
sub OnExit()
 m.exited=true
end sub
sub OnEnter(params as object)
 m.retried=params
end sub
sub ShowPlayerControls()
 m.playerControls.visible=true
end sub
sub ShowCaptionMenu()
end sub
sub RestartFromBeginning()
end sub
function AsyncTask_Launch(parent as object,name as string,callback as string,params as object,id as string) as object
 m.metadataRequests=m.metadataRequests+1
 return params
end function
sub AsyncTask_Reap(task as object,parent as object,stopTask as boolean)
 m.taskStopped=stopTask
end sub
`;
const cases=`
Harness_Equal(PlayerReachedEnd(false,false,600,600),false,"terminal state before first frame is not completion")
Harness_Equal(PlayerReachedEnd(true,true,600,600),false,"error always blocks automatic advancement")
Harness_Equal(PlayerReachedEnd(true,false,30,600),false,"early termination is a failed episode")
Harness_Equal(PlayerReachedEnd(true,false,599.5,600),true,"near-end final sample permits real completion")
Harness_Equal(PlayerReachedEnd(true,false,600,0),false,"unknown duration never guesses that playback completed")
m.top={screenActive:true,nodes:{failureTitle:{},failureEpisode:{},failureMessage:{}},FindNode:function(id) : return m.nodes[id] : end function}
m.playParams={metaType:"series",metaId:"tt1",videoId:"tt1:2:5",season:2,episode:5,name:"Series",addonAddress:"provider",position:0,stream:{marker:"chosen source"},meta:{id:"tt1",type:"series",videos:[{id:"tt1:2:5"},{id:"tt1:2:6"}]}}
m.stores={episodes:{callFunc:function(name,a=invalid,b=invalid,c=invalid)
 if name="EpisodesMergeMeta" then return b
 m.season=b : m.episode=c
 return {found:true,videoId:"tt1:2:6",season:2,episode:6,name:"Next"}
end function}}
m.video={state:"finished",enableUI:true,HasField:function(key) : return false : end function}
m.failureGroup={visible:false} : m.status={text:"sourceUnavailable"}
m.retryEpisodeButton={focuses:0,SetFocus:sub(value) : m.focuses=m.focuses+1 : end sub}
m.otherSourceButton={}
m.playerControls={visible:false} : m.nextEpisodeGroup={visible:true} : m.nextEpisodeTimer={control:"start"}
m.playTimer={} : m.prompts=0 : m.savedCalls=0 : m.exiting=false : m.hasPlayed=false : m.playStarted=true : m.playbackFailed=false : m.completionHandled=false
m.lastPlaybackPosition=0 : m.lastPlaybackDuration=0
onVideoFinished()
Harness_Equal(m.failureGroup.visible,true,"failed first-frame playback opens recovery for current episode")
Harness_Equal(m.nextEpisodeGroup.visible,false,"failure closes any stale next-episode screen")
Harness_Equal(m.nextEpisodeTimer.control,"stop","failure cancels autoplay countdown")
Harness_Equal(m.prompts,0,"false finished event cannot offer next episode")
Harness_Equal(m.top.nodes.failureEpisode.text,"Series · T2:E5","recovery identifies the current episode")
Harness_Equal(m.retryEpisodeButton.text,"retryCurrent","recovery offers retry rather than next")
m.nextEpisodeData={found:true,videoId:"tt1:2:6",season:2,episode:6,name:"Next"}
m.nextEpisodeCountdown=1 : m.top.pushRequest=invalid
onNextEpisodeTimerFire()
Harness_Equal(m.top.pushRequest,invalid,"queued autoplay tick after failure cannot skip current episode")
PlayNextEpisode()
Harness_Equal(m.top.pushRequest,invalid,"late Next activation is rejected after playback failure")
focuses=m.retryEpisodeButton.focuses
onVideoFinished()
Harness_Equal(m.retryEpisodeButton.focuses,focuses,"duplicate terminal events cannot steal recovery focus")
ChooseCurrentSource()
Harness_Equal(m.top.pushRequest.screen,"back","other-source action returns to current stream list")
Harness_Equal(m.playParams.videoId,"tt1:2:5","source action never increments episode")
m.hasPlayed=true : m.lastPlaybackPosition=85
RetryCurrentEpisode()
Harness_Equal(m.retried.videoId,"tt1:2:5","retry uses the same video id")
Harness_Equal(m.retried.stream.marker,"chosen source","retry retains the selected source")
Harness_Equal(m.retried.position,85,"retry keeps last valid playback progress")
RestoreFailureUI()
Harness_Equal(m.video.enableUI,true,"leaving failure restores native UI configuration")
' Native error followed by finished must stay on recovery even near the end.
m.failureGroup.visible=false : m.playbackFailed=false : m.hasPlayed=true : m.completionHandled=false
m.lastPlaybackPosition=599 : m.lastPlaybackDuration=600 : m.video.state="error"
onVideoStateChanged()
m.video.state="finished" : onVideoStateChanged()
Harness_Equal(m.prompts,0,"error then finished cannot trigger next episode")
' A real completion still has the old next-episode behavior, once only.
m.failureGroup.visible=false : m.playbackFailed=false : m.hasPlayed=true : m.completionHandled=false : m.video.state="finished"
onVideoFinished()
Harness_Equal(m.prompts,1,"real completion still offers next episode")
onVideoFinished()
Harness_Equal(m.prompts,1,"duplicate completion cannot start a second countdown")
' Manual next is separate from natural completion.
m.playerControls.action="next" : m.nextEpisodeData={found:true,videoId:"tt1:2:6",season:2,episode:6,name:"Next"}
onPlayerControlAction()
Harness_Equal(m.top.pushRequest.params.videoId,"tt1:2:6","player Next button opens the next episode")
Harness_Equal(m.top.pushRequest.params.metaId,"tt1","manual Next preserves series identity")
Harness_Equal(m.top.pushRequest.params.position,0,"manual Next starts new episode at zero")
' Missing full metadata is hydrated before showing the Next button.
m.nextMetaGeneration=7 : m.metadataRequests=0 : m.playParams.meta={id:"tt1",type:"series"}
EnsureNextEpisodeData()
Harness_Equal(m.metadataRequests,1,"sparse episode params fetch missing episode sequence")
Harness_Equal(m.playerControls.nextAvailable,false,"unknown next episode is not falsely enabled")
task=m.nextMetaTask
task.result={ok:true,meta:{id:"tt1",type:"series",videos:[{id:"tt1:2:5"},{id:"tt1:2:6"}]}}
event={task:task,GetRoSGNode:function() : return m.task : end function}
onNextMetaLoaded(event)
Harness_Equal(m.playerControls.nextAvailable,true,"metadata result enables player Next button")
Harness_Equal(m.stores.episodes.episode,5,"next lookup uses current episode ordinal")
' Render and navigation order match when the fifth action is present.
m.top={nextAvailable:true,paused:false,words:{nextEpisode:"Next episode"}}
m.buttons=[{},{},{},{},{}] : m.focusZone="actions" : m.focusedIndex=4
UpdateButtons()
Harness_Equal(m.buttons[4].visible,true,"series shows the actual fifth player button")
Harness_Equal(m.buttons[4].selected,true,"Next button has a visible selected state")
Harness_Equal(m.buttons[3].translation[1],432,"pause moves below Next when available")
m.top.nextAvailable=false : UpdateButtons()
Harness_Equal(m.buttons[4].visible,false,"movies and series ends hide unavailable Next")
Harness_Equal(m.focusedIndex,3,"disappearing Next returns focus to pause")
m.stores={library:{callFunc:function(name,a=invalid,b=invalid,c=invalid,d=invalid,e=invalid,f=invalid,g=invalid,h=invalid,i=invalid,j=invalid)
 if name="LibraryIsChannelType" then return false
 if name="LibrarySetPosition" then m.position=h : m.duration=i
 if name="LibraryMarkWatchedIfFinished" then m.watchedPosition=c
 return invalid
end function},watch:{callFunc:sub(name,packet) : m.packet=packet : end sub}}
m.top={} : m.video={position:0,duration:0}
m.hasPlayed=true : m.playbackFailed=true : m.completionHandled=false : m.saved=false
m.lastPlaybackPosition=85 : m.lastPlaybackDuration=600
ExerciseSavePosition()
Harness_Equal(m.stores.library.position,85,"failure stores last valid position instead of terminal zero")
ExercisePublishWatchState()
Harness_Equal(m.stores.watch.packet.position,85,"failure sync also retains current episode progress")
m.playbackFailed=false : m.completionHandled=true : m.saved=false : m.lastPlaybackPosition=599.5
ExerciseSavePosition()
Harness_Equal(m.stores.library.watchedPosition,599,"completed video uses last end sample when native position resets")
print "Assertions passed:";m.passed;" failed:";m.failed
if m.failed=0 then print "EPISODE RECOVERY PASS" else print "EPISODE RECOVERY FAIL"
`;
const target=path.join(root,'work/episode-recovery-run.brs');fs.writeFileSync(target,fs.readFileSync(path.join(root,'tests/harness.brs'),'utf8')+'\n'+mocks+'\n'+source+'\n'+cases);
const result=spawnSync(path.join(root,'node_modules/.bin/brs'),['--root',path.join(root,'work'),target],{encoding:'utf8',cwd:root});process.stdout.write(result.stdout||'');process.stderr.write(result.stderr||'');if(result.status!==0||!(result.stdout||'').includes('EPISODE RECOVERY PASS'))process.exit(1);
