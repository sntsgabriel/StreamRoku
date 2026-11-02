const fs=require('fs');const path=require('path');const {spawnSync}=require('child_process');
const root=path.resolve(__dirname,'..');
function extract(file,name){const src=fs.readFileSync(path.join(root,file),'utf8');const match=src.match(new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`,'mi'));if(!match)throw Error(name);return match[0];}
const handlers=[extract('components/HomeMenu.brs','onChoice').replace('onChoice(', 'MenuChoice('),extract('components/HomeMenu.brs','onKeyEvent').replace('onKeyEvent(', 'MenuKeys('),fs.readFileSync(path.join(root,'source/util/HomeLayout.brs'),'utf8'),...['FocusedHomeContext','AllHomeRows','OpenHomeActions','ShowHomeCustomization','HomeRowLabel','ShowHomeRows','ShowHomeRowEdit','SaveHomeLayout','CloseHomeMenu','HandleHomeMenuBack','onHomeMenuChoice','ApplyHomeTitleAction'].map(n=>extract('components/HomeScreen.brs',n)),...['OnHomeEdit','NextWrite'].map(n=>extract('components/LibraryWriteCoordinator.brs',n))].join('\n');
const mocks=`
function Lang(section as string,key as string) as string
 return key
end function
function StringOf(value as dynamic) as string
 if value=invalid then return ""
 return value.ToStr()
end function
function TypeLabel(value as string) as string
 return value
end function
sub PresentHomeMenu(title as string,subtitle as string,entries as object)
 m.presented=entries
end sub
function LibraryRow() as dynamic
 if m.mockStore.resume=invalid then return invalid
 return m.cwRow
end function
sub ReflowHomeRows()
 m.gridRows=HomeOrderedRows(AllHomeRows(),m.homeLayout)
end sub
sub SetHomeFocus(rail as boolean)
 m.focusRail=rail
end sub
sub UpdateSelectedTitle()
end sub
function ContinueWatchingSignature() as string
 return "fresh"
end function
sub Pump()
 m.pumped=true
end sub
`;
const cases=`
m.mockStore={saved:false,resume:{videoId:"tt1:2:5"},calls:[],layout:{},failSave:false,callFunc:function(name,a=invalid,b=invalid,c=invalid,d=invalid,e=invalid)
 m.calls.Push(name)
 if name="LibraryIsSaved" then return m.saved
 if name="LibraryAddSaved" then m.saved=true : return true
 if name="LibraryRemoveSaved" then m.saved=false : m.resume=invalid : return true
 if name="LibraryResumeFor" then return m.resume
 if name="LibraryRemovePosition" then m.resume=invalid : return true
 if name="LibraryMarkTitleWatched" then m.watched=true
 if name="SettingsSetHomeLayout"
  if m.failSave then return false
  m.layout=a : return true
 end if
 if name="AuthGetSession" then return "stremio"
 if name="LibraryBuildHomeActionItem" then return a
 return invalid
end function}
m.stores={library:m.mockStore,settings:m.mockStore}
m.homeLayout=HomeNormalizeLayout(invalid) : m.menuError="" : m.top={}
m.homeMenu={choice:{},callFunc:sub(name) : m.closed=true : end sub}
meta={id:"tt1",type:"series",name:"Series",poster:"p.jpg",videoId:"tt1:2:5"}
m.cwRow={source:"library",title:"Continue",metas:[meta]}
m.catalogRows=[{source:"catalog",rowKey:"catalog",title:"Popular",metaType:"series",addonAddress:"provider",metas:[meta]}]
m.gridRows=AllHomeRows() : m.catalog={rowItemFocused:[0,0]}
OpenHomeActions()
Harness_Equal(m.presented[1].label,"markSeriesWatched","series mark is explicit about the whole series")
Harness_Equal(m.presented[2].action,"removeContinue","continue row offers remove action")
m.homeMenu.choice={action:"save"}
onHomeMenuChoice()
Harness_Equal(m.mockStore.saved,true,"quick save calls the real library boundary")
Harness_Equal(m.top.libraryChange.added,true,"membership edit is published to account coordinator")
OpenHomeActions()
m.homeMenu.choice={action:"removeContinue"}
onHomeMenuChoice()
Harness_Equal(m.mockStore.resume,invalid,"remove continue clears resume")
Harness_Equal(m.mockStore.saved,true,"remove continue leaves saved favorite intact")
Harness_Equal(m.top.homeEdit.action,"removeContinue","remove edit is published for account synchronization")
m.catalog.rowItemFocused=[0,0]
OpenHomeActions()
Harness_Equal(m.presented[2].action,"customize","catalog offers no misleading remove-continue action")
m.homeMenu.choice={action:"markWatched"}
onHomeMenuChoice()
Harness_Equal(m.mockStore.watched,true,"mark action reaches library state")
Harness_Equal(m.top.homeEdit.action,"markWatched","watched action reaches account pipeline")
m.homeMenuOrigin="rail"
ShowHomeCustomization()
m.homeMenu.choice={action:"deduplicate"}
onHomeMenuChoice()
Harness_Equal(m.homeLayout.deduplicate,true,"deduplicate toggle updates saved layout")
ShowHomeRows()
Harness_Equal(m.presented[0].rowKey,"catalog","row editor includes installed catalog")
ShowHomeRowEdit("catalog")
m.homeMenu.choice={action:"visibility"}
onHomeMenuChoice()
Harness_Equal(m.gridRows.Count(),0,"hiding last row produces an empty catalog")
Harness_Equal(m.menuPage,"row","editor remains reachable when every row is hidden")
m.homeMenu.choice={action:"back"}
onHomeMenuChoice()
Harness_Equal(m.menuPage,"rows","Back leaves row editor without closing the whole flow")
m.homeMenu.choice={action:"back"} : onHomeMenuChoice()
Harness_Equal(m.menuPage,"home","Back from rows returns to customization")
m.homeMenu.choice={action:"reset"} : onHomeMenuChoice()
Harness_Equal(m.gridRows.Count(),1,"reset restores hidden catalogs")
Harness_Equal(m.homeLayout.deduplicate,false,"reset restores duplicate setting")
m.catalogRows.Push({source:"catalog",rowKey:"second",title:"Other",metaType:"movie",addonAddress:"other",metas:[{id:"tt2",type:"movie"}]})
ShowHomeRowEdit("second")
m.homeMenu.choice={action:"moveUp"} : onHomeMenuChoice()
Harness_Equal(HomeRowKey(m.gridRows[0]),"second","move up reorders actual visible rows")
Harness_Equal(m.mockStore.layout.order[0],"second","move up persists stable catalog identity")
m.homeMenu.choice={action:"moveDown"} : onHomeMenuChoice()
Harness_Equal(HomeRowKey(m.gridRows[0]),"catalog","move down restores previous order")
m.mockStore.failSave=true
m.homeMenu.choice={action:"deduplicate"} : onHomeMenuChoice()
Harness_Equal(m.homeLayout.deduplicate,false,"refused save keeps previous preferences")
Harness_Equal(m.menuError,"layoutSaveFailed","refused save is visible to user")
' Writes serialize after an in-flight job, and stale positions cannot undo removal.
m.storeHost=m.mockStore : m.pendingHomeEdits=[]
m.pendingWatchState={metaId:"tt1",position:60} : m.pendingLibraryChange=invalid : m.pendingWatchedChange=invalid
OnHomeEdit({metaId:"tt1",action:"removeContinue"})
Harness_Equal(m.pendingWatchState,invalid,"remove discards an older queued position for the same title")
OnHomeEdit({metaId:"tt2",action:"markWatched"})
Harness_Equal(m.pendingHomeEdits.Count(),2,"different title edits queue independently")
Harness_Equal(NextWrite().item.metaId,"tt1","first edit retains FIFO order")
Harness_Equal(NextWrite().item.metaId,"tt2","second edit is not lost to coalescing")
m.list={rowItemSelected:[1,0]} : m.entries=[{action:"save"},{action:"rows"}] : m.top={}
MenuChoice()
Harness_Equal(m.top.choice.action,"rows","overlay publishes action from selected vertical row")
Harness_Equal(MenuKeys("back",false),false,"key release cannot close menu")
Harness_Equal(MenuKeys("back",true),true,"menu consumes Back before Home navigation")
Harness_Equal(m.top.choice.action,"back","Back publishes menu-level navigation")
Harness_Equal(MenuKeys("left",true),true,"menu traps horizontal keys instead of opening rail behind it")
print "Assertions passed:";m.passed;" failed:";m.failed
if m.failed=0 then print "HOME ACTIONS PASS" else print "HOME ACTIONS FAIL"
`;
const target=path.join(root,'work/home-actions-run.brs');fs.writeFileSync(target,fs.readFileSync(path.join(root,'tests/harness.brs'),'utf8')+'\n'+mocks+'\n'+handlers+'\n'+cases);
const result=spawnSync(path.join(root,'node_modules/.bin/brs'),['--root',path.join(root,'work'),target],{encoding:'utf8',cwd:root});process.stdout.write(result.stdout||'');process.stderr.write(result.stderr||'');if(result.status!==0||!(result.stdout||'').includes('HOME ACTIONS PASS'))process.exit(1);
