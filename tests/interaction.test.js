// Exercise actual screen handlers with fake Roku nodes; no network or device needed.
const fs = require('fs');
const path = require('path');
const {spawnSync} = require('child_process');
const root = path.resolve(__dirname, '..');
function extract(file, name) {
  const src = fs.readFileSync(path.join(root, file), 'utf8');
  const re = new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`, 'mi');
  const found = src.match(re);
  if (!found) throw new Error(`Missing handler ${name}`);
  return found[0];
}
const handlers = [
  ...['onQueryChanged','onSearchDebounce','PumpSearchTasks','onSearchLoaded'].map(n=>extract('components/SearchScreen.brs',n)),
  ...['onTrackPanelChoice','SetCaptionMode','SelectSubtitleTrack'].map(n=>extract('components/PlayerScreen.brs',n)),
  extract('components/CaptionVideo.brs','onKeyEvent').replace(/onKeyEvent/i,'CaptionVideoKeyEvent')
].join('\n');
const mocks = `
sub CancelSearch()
  m.cancelled = m.cancelled + 1
  m.searchGeneration = m.searchGeneration + 1
  m.searchTasks = invalid
  m.searchQueue = []
end sub
sub ClearResults()
  m.cleared = m.cleared + 1
end sub
function Lang(section as string, key as string) as string
  return key
end function
sub RunSearch(query as string)
  m.ran.Push(query)
end sub
function AsyncTask_Launch(parent as object, name as string, callback as string, params as object, id as string) as object
  return params
end function
sub AsyncTask_Reap(task as object, parent as object, doStop as boolean)
  m.reaped = m.reaped + 1
end sub
sub RebuildRows()
  m.rebuilt = m.rebuilt + 1
end sub
sub UpdateSearchStatus()
end sub
`;
const scenarios = `
m.cancelled = 0 : m.cleared = 0 : m.searchGeneration = 0
m.debounce = { control: "stop" } : m.keyboard = { text: "a" }
m.status = { text: "" } : m.ran = []
m.top = {screenActive: true}
m.pendingQuery = "old query"
onQueryChanged()
Harness_Equal(m.debounce.control, "stop", "one character does not issue network searches")
Harness_Equal(m.pendingQuery, "", "editing invalidates pending source-resolution query")
Harness_Equal(m.rows.Count(), 0, "editing removes old-query results immediately")
m.keyboard.text = " ab "
onQueryChanged()
Harness_Equal(m.debounce.control, "start", "two characters schedule a debounced search")
m.keyboard.text = "a"
onQueryChanged()
Harness_Equal(m.debounce.control, "stop", "deleting below threshold cancels pending debounce")
onSearchDebounce()
Harness_Equal(m.ran.Count(), 0, "an obsolete timer cannot search a short prefix")
m.keyboard.text = " Alien "
m.top.screenActive = false
onSearchDebounce()
Harness_Equal(m.ran.Count(), 0, "hidden screen does not initiate searches")
m.top.screenActive = true
onSearchDebounce()
Harness_Equal(m.ran[0], "Alien", "timer uses latest trimmed text")
m.searchGeneration = 10 : m.searchTasks = {} : m.searchQueue = []
for i = 0 to 3
  m.searchQueue.Push({key: i.ToStr(), address: "example", cats: []})
end for
m.lastQuery = "Alien"
PumpSearchTasks()
Harness_Equal(m.searchQueue.Count(), 2, "only two providers launch together")
Harness_Equal(m.searchTasks["0"].generation, 10, "tasks carry the current query generation")
m.reaped = 0 : m.rebuilt = 0 : m.landed = {} : m.searchFailed = false
oldTask = { addonKey: "0", generation: 9, result: {sections: []} }
event = {task: oldTask, GetRoSGNode: function() : return m.task : end function}
onSearchLoaded(event)
Harness_Equal(m.reaped, 0, "late prior-query result cannot claim current provider slot")
Harness_Equal(m.searchTasks["0"].generation, 10, "current provider task survives old completion")
currentTask = m.searchTasks["0"]
currentTask.result = {sections: [{key: "movies", metas: [{id: "tt1"}]}]}
event.task = currentTask
onSearchLoaded(event)
Harness_Equal(m.landed.movies[0].id, "tt1", "current results enter the grid")
Harness_Equal(m.rebuilt, 1, "current completion renders once")
Harness_Equal(m.searchQueue.Count(), 1, "completion releases one slot for next provider")
m.video = {globalCaptionMode: "On", subtitleTrack: "original", content: {marker: "immutable"}, HasField: function(name) : return true : end function}
m.trackPanel = { choice: {action: "off", track: ""}, callFunc: function(name) : return invalid : end function }
onTrackPanelChoice()
Harness_Equal(m.video.globalCaptionMode, "Off", "off disables captions without stopping playback")
Harness_Equal(m.video.subtitleTrack, "original", "off preserves the selected track")
m.trackPanel.choice = {action: "track", track: "mkv/por1"}
onTrackPanelChoice()
Harness_Equal(m.video.subtitleTrack, "mkv/por1", "selection uses the player's actual track identifier")
Harness_Equal(m.video.globalCaptionMode, "On", "choosing a track enables captions")
Harness_Equal(m.video.content.marker, "immutable", "live caption choice leaves content metadata intact")
m.trackPanel.choice = invalid
onTrackPanelChoice()
Harness_Equal(m.video.subtitleTrack, "mkv/por1", "empty selection leaves the active track alone")
m.trackPanel.choice = {action: "audio", track: "audio/pt"}
onTrackPanelChoice()
Harness_Equal(m.video.audioTrack, "audio/pt", "audio selection uses the actual audio identifier")
Harness_Equal(m.audioTrackApplied, true, "manual audio is protected from later automatic preference updates")
Harness_Equal(m.video.subtitleTrack, "mkv/por1", "audio selection preserves subtitles")
m.video.globalCaptionMode = "Off"
m.trackPanel.choice = {action: "on", track: "mkv/por1"}
onTrackPanelChoice()
Harness_Equal(m.video.globalCaptionMode, "On", "enable restores captions")
m.top = {captionControlsRequested: false}
Harness_Equal(CaptionVideoKeyEvent("down", true), true, "down opens caption controls")
Harness_Equal(m.top.captionControlsRequested, true, "caption button request reaches player")
Harness_Equal(CaptionVideoKeyEvent("options", true), false, "native Roku options remain available")
Harness_Equal(CaptionVideoKeyEvent("back", true), false, "native back handling is preserved")
Harness_Equal(CaptionVideoKeyEvent("down", false), false, "key release does not reopen controls")
m.top={state:"playing",control:"unchanged",captionControlsRequested:false}
Harness_Equal(CaptionVideoKeyEvent("OK",true),true,"center OK is handled during playback")
Harness_Equal(m.top.control,"pause","center OK pauses the actual Video node")
m.top.control="unchanged"
Harness_Equal(CaptionVideoKeyEvent("OK",false),false,"OK release does not toggle a second time")
Harness_Equal(m.top.control,"unchanged","releasing center button preserves pause command")
m.top.state="paused"
Harness_Equal(CaptionVideoKeyEvent("OK",true),true,"center OK is handled when paused")
Harness_Equal(m.top.control,"resume","center OK resumes without restarting content")
for each state in ["buffering","error","finished","stopped"]
 m.top.state=state : m.top.control="unchanged"
 Harness_Equal(CaptionVideoKeyEvent("OK",true),false,"OK outside playing/paused falls through to native handling")
 Harness_Equal(m.top.control,"unchanged","OK does not issue pause/resume in a terminal or buffering state")
end for
m.top.state="playing" : m.top.control="unchanged"
Harness_Equal(CaptionVideoKeyEvent("play",true),false,"dedicated Play button retains native handling")
Harness_Equal(CaptionVideoKeyEvent("right",true),false,"native seek retains its key handling")
print "Assertions passed:"; m.passed; " failed:"; m.failed
if m.failed = 0 then print "INTERACTION PASS" else print "INTERACTION FAIL"
`;
const target = path.join(root,'work','interaction-run.brs');
fs.mkdirSync(path.dirname(target),{recursive:true});
fs.writeFileSync(target, fs.readFileSync(path.join(root,'tests','harness.brs'),'utf8')+'\n'+mocks+'\n'+handlers+'\n'+scenarios);
const result=spawnSync(path.join(root,'node_modules/.bin/brs'),['--root',path.join(root,'work'),target],{encoding:'utf8',cwd:root});
process.stdout.write(result.stdout || '');
process.stderr.write(result.stderr || '');
if(result.status!==0 || !(result.stdout||'').includes('INTERACTION PASS'))process.exit(1);
