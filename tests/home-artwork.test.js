const fs=require('fs');const path=require('path');const {spawnSync}=require('child_process');
const root=path.resolve(__dirname,'..');
const source=fs.readFileSync(path.join(root,'components/HomeScreen.brs'),'utf8');
const handlers=['UpdateSelectedTitle','UpdateHeroProgressLayout','SelectedHeroItem','onHeroDebounce','MergeHeroMetadata','CancelHeroMeta','onHeroMetadataLoaded','RenderHomeHero','onHeroBgLoaded'].map(name=>{
 const match=source.match(new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`,'mi'));
 if(!match)throw Error(name);return match[0];
}).join('\n');
const mocks=`
function StringOf(value as dynamic) as string
 if value=invalid then return ""
 return value.ToStr()
end function
function TypeLabel(value as string) as string
 return value
end function
function FormatHeroRuntime(value as dynamic) as string
 return value.ToStr()
end function
function MetaAddress() as string
 return "provider"
end function
function AsyncTask_Launch(parent as object, name as string, callback as string, params as object, id as string) as object
 m.launched=m.launched+1
 return params
end function
sub AsyncTask_Reap(task as object, parent as object, stopTask as boolean)
 m.reaped=m.reaped+1
 m.stopped=stopTask
end sub
`;
const cases=`
m.top={screenActive:true} : m.heroGeneration=1 : m.heroMetadata={}
m.heroMetaTask=invalid : m.launched=0 : m.reaped=0
m.heroBg={} : m.heroBgNext={} : m.heroTitle={} : m.heroDesc={} : m.heroLogo={}
m.catalogRows=[] : m.gridRows=[{source:"library"}]
item={title:"South Park",metaId:"tt1",metaType:"series",background:"",hdPosterUrl:"poster.jpg",logo:"",description:"",releaseInfo:"",imdbRating:"",runtime:"",progress:0.4}
row={item:item,GetChild:function(index) : return m.item : end function}
m.catalog={translation:[0,474],rowItemFocused:[0,0],content:{row:row,GetChild:function(index) : return m.row : end function}}
onHeroDebounce()
Harness_Equal(m.heroBgNext.uri,"poster.jpg","old Continue Watching entry has a poster background while metadata loads")
Harness_Equal(m.launched,1,"missing library artwork fetches full metadata")
Harness_Equal(m.heroMetaTask.metaType,"series","metadata request keeps content type")
Harness_Equal(m.heroMetaTask.metaId,"tt1","metadata request keeps content id")
task=m.heroMetaTask
task.result={ok:true,meta:{id:"tt1",type:"series",background:"backdrop.jpg",logo:"logo.png",description:"Synopsis"}}
event={task:task,GetRoSGNode:function() : return m.task : end function}
onHeroMetadataLoaded(event)
Harness_Equal(m.heroBgNext.uri,"backdrop.jpg","full landscape artwork replaces temporary poster")
Harness_Equal(m.heroLogo.uri,"logo.png","library hero receives the same logo as catalog content")
Harness_Equal(m.heroDesc.text,"Synopsis","library hero receives synopsis")
Harness_Equal(item.progress,0.4,"artwork refresh leaves playback progress intact")
item.background="" : item.logo="" : item.description=""
onHeroDebounce()
Harness_Equal(m.launched,1,"revisiting title reuses fetched metadata")
Harness_Equal(m.heroBgNext.uri,"backdrop.jpg","cached artwork survives row rebuilds")
m.heroBgNext.loadStatus="failed"
onHeroBgLoaded()
Harness_Equal(m.heroBgNext.uri,"poster.jpg","failed background falls back to the same title's poster")
onHeroBgLoaded()
Harness_Equal(m.heroBgNext.uri,"","failed fallback does not retry in a loop")
' A previous callback must never claim a newer request slot.
m.heroGeneration=2
m.heroMetaTask={requestGeneration:2,metaId:"tt2",metaType:"movie"}
onHeroMetadataLoaded(event)
Harness_Equal(m.heroMetaTask.metaId,"tt2","stale response cannot clear a newer metadata task")
CancelHeroMeta()
Harness_Equal(m.heroMetaTask,invalid,"leaving selection clears task slot")
Harness_Equal(m.stopped,true,"selection cancellation stops worker")
' Already loaded catalog records can fill historical library entries without fetching.
item.metaId="tt3" : item.background="" : item.logo="" : item.description=""
m.catalogRows=[{metas:[{id:"tt3",type:"series",background:"catalog-bg.jpg"}]}]
onHeroDebounce()
Harness_Equal(m.heroBgNext.uri,"catalog-bg.jpg","library reuses matching catalog artwork")
Harness_Equal(m.launched,1,"matching catalog does not require a network request")
item.metaId="tt4" : item.background="" : m.catalogRows=[]
onHeroDebounce()
task=m.heroMetaTask : task.result={ok:true,meta:{id:"wrong",type:"series",background:"wrong.jpg"}}
event.task=task
onHeroMetadataLoaded(event)
Harness_Equal(m.heroBgNext.uri,"poster.jpg","mismatched metadata cannot paint another title")
item.metaId="tt5" : item.background=""
onHeroDebounce()
task=m.heroMetaTask : task.result={ok:true,meta:{id:"tt5",type:"series",background:"hidden.jpg"}}
event.task=task : m.top.screenActive=false
onHeroMetadataLoaded(event)
Harness_Equal(m.heroBgNext.uri,"poster.jpg","covered Home ignores late artwork")
count=m.launched
onHeroDebounce()
Harness_Equal(m.launched,count,"covered Home cannot start metadata work")
m.heroProgress={translation:[0,298]} : m.heroDesc.visible=true
m.catalog.rowItemFocused=[1,0]
UpdateSelectedTitle()
Harness_Equal(m.catalog.translation[1],474,"moving down keeps catalog anchored during native scrolling")
Harness_Equal(m.heroDesc.visible,true,"moving down keeps synopsis layout stable")
item.resumeInfo="T2 · E5 · Faltam 23 min"
RenderHomeHero(item)
Harness_Equal(m.heroProgress.visible,true,"resume information stays visible when Continue Watching is reordered below the first row")
Harness_Equal(m.catalog.translation[1],474,"late resume information cannot shift the catalog")
item.resumeInfo=""
RenderHomeHero(item)
Harness_Equal(m.heroProgress.visible,false,"ordinary catalog items never retain another title's episode information")
Harness_Equal(m.catalog.translation[1],474,"ordinary titles keep the same catalog anchor")
m.catalog.rowItemFocused=[0,0]
UpdateSelectedTitle()
Harness_Equal(m.catalog.translation[1],474,"reversing upward cannot jump the catalog")
Harness_Equal(m.heroProgress.translation[1],298,"resume label keeps its reserved position")
print "Assertions passed:";m.passed;" failed:";m.failed
if m.failed=0 then print "HOME ARTWORK PASS" else print "HOME ARTWORK FAIL"
`;
const target=path.join(root,'work/home-artwork-run.brs');
fs.writeFileSync(target,fs.readFileSync(path.join(root,'tests/harness.brs'),'utf8')+'\n'+mocks+'\n'+handlers+'\n'+cases);
const result=spawnSync(path.join(root,'node_modules/.bin/brs'),['--root',path.join(root,'work'),target],{encoding:'utf8',cwd:root});
process.stdout.write(result.stdout||'');process.stderr.write(result.stderr||'');
if(result.status!==0||!(result.stdout||'').includes('HOME ARTWORK PASS'))process.exit(1);
