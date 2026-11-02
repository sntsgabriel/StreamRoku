const fs = require('fs');
const path = require('path');
const {spawnSync} = require('child_process');
const root = path.resolve(__dirname, '..');
const cases = `
words = {"pt-BR":"Português (Brasil)", pt:"Português", en:"Inglês", es:"Espanhol", fr:"Francês", und:"Não informado", embedded:"No vídeo", addon:"Complemento", unknownFormat:"Desconhecido"}
native = [
 {TrackName:"mkv/en", Language:"eng", Description:"English CC"},
 {TrackName:"https://example.invalid/br.srt?token=private", Language:"por", Description:"por 1"},
 {TrackName:"mkv/pt", Language:"por", Description:"Português"},
 {TrackName:"https://example.invalid/en.vtt", Language:"eng"},
 {TrackName:""}, invalid
]
external = [
 {url:"https://example.invalid/br.srt?token=private", lang:"pob", providerName:"OpenSubtitles v3"},
 {downloadUrl:"https://example.invalid/en.vtt", lang:"eng", providerName:"Other provider"}
]
entries = TrackPanelEntries(native, external, "subtitle", words)
Harness_Equal(entries.Count(), 4, "malformed native entries are excluded")
Harness_Equal(entries[1].code, "pt-BR", "raw sidecar metadata retains Brazilian Portuguese")
Harness_Equal(entries[2].code, "pt", "generic Portuguese is not relabelled Brazilian")
Harness_Equal(entries[1].format, "SRT", "subtitle format ignores the query string")
Harness_Equal(entries[1].title, "OpenSubtitles v3", "addon provider is visible instead of a URL")
Harness_Equal(entries[1].language, "Português (Brasil)", "friendly localized language label")
Harness_Equal(entries[1].id, "https://example.invalid/br.srt?token=private", "opaque selector is preserved without editing it")
Harness_Equal(entries[0].provider, "No vídeo", "embedded subtitles remain selectable")
groups = TrackPanelGroups(entries)
Harness_Equal(groups.Count(), 3, "multiple providers group under one language")
Harness_Equal(groups[0].code, "pt-BR", "Brazilian Portuguese has first priority")
Harness_Equal(groups[1].code, "pt", "generic Portuguese remains a separate section")
Harness_Equal(groups[2].entries.Count(), 2, "all English variants remain available")
Harness_Equal(groups[2].entries[0].id, "mkv/en", "track identifiers survive grouping unchanged")
Harness_Equal(TrackLanguageCode("pt_br"), "pt-BR", "locale separators normalize consistently")
Harness_Equal(TrackLanguageCode(""), "und", "missing language becomes a named unknown group")
Harness_Equal(TrackLanguageCode("por"), "pt", "ISO Portuguese code does not imply a country")
Harness_Equal(TrackPanelEntries(invalid, invalid, "subtitle", words).Count(), 0, "an unavailable list is empty without invented tracks")
audio = TrackPanelEntries([{Track:"a/pt",Language:"por",Name:"Português", Format:"AAC"},{Track:"a/en",Language:"eng",Name:"English"}], invalid, "audio", words)
Harness_Equal(audio[0].id, "a/pt", "audio uses Track instead of subtitle TrackName")
Harness_Equal(audio[0].format, "AAC", "audio format is displayed when reported")
Harness_Equal(audio[1].format, "Desconhecido", "missing audio format is not guessed")
Harness_Equal(TrackPanelGroups(audio).Count(), 2, "audio languages have separate groups")
words.off="Desativadas"
rows=TrackPanelRows(entries,true,words)
Harness_Equal(rows.Count(),5,"flat list includes Off and every native track")
Harness_Equal(rows[0].action,"off","Off is first and directly selectable")
Harness_Equal(rows[1].label,"Português (Brasil)","one track has only a readable language label")
Harness_Equal(rows[1].id,entries[1].id,"simplification keeps opaque selectors unchanged")
Harness_Equal(rows[3].label,"Inglês (CC)","closed captions remain distinguishable")
Harness_Equal(TrackPanelRows(invalid,true,words).Count(),1,"Off remains available without subtitles")
Harness_Equal(TrackPanelRows(invalid,false,words).Count(),0,"missing audio does not invent a choice")
duplicates=TrackPanelEntries([{TrackName:"one",Language:"por",Description:"por 1"},{TrackName:"two",Language:"por",Description:"por 2"}],invalid,"subtitle",words)
rows=TrackPanelRows(duplicates,true,words)
Harness_Equal(rows[1].label,"Português","raw native description is hidden")
Harness_Equal(rows[2].label,"Português (2)","duplicate variants remain distinct without unknown-format text")
Harness_Equal(TrackPanelRestoreIndex([{id:"en"}],[{id:"pt"},{id:"en"}],0),1,"late Portuguese tracks do not move the browsed English choice")
Harness_Equal(TrackPanelRestoreIndex([{id:"en"}],[],0),-1,"empty refresh has no focus index")
print "Assertions passed:"; m.passed; " failed:"; m.failed
if m.failed = 0 then print "TRACK PANEL PASS" else print "TRACK PANEL FAIL"
`;
const target=path.join(root,'work','track-panel-run.brs');
fs.writeFileSync(target,fs.readFileSync(path.join(root,'tests','harness.brs'),'utf8')+'\n'+fs.readFileSync(path.join(root,'source','util','TrackPanelModel.brs'),'utf8')+'\n'+cases);
const result=spawnSync(path.join(root,'node_modules/.bin/brs'),['--root',path.join(root,'work'),target],{encoding:'utf8',cwd:root});
process.stdout.write(result.stdout||'');process.stderr.write(result.stderr||'');
if(result.status!==0 || !(result.stdout||'').includes('TRACK PANEL PASS'))process.exit(1);
