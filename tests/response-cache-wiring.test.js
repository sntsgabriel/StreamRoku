// Guard the real SceneGraph boundary: Task fields must carry nodes, not classes.
const fs=require('fs');const path=require('path');const {spawnSync}=require('child_process');
const root=path.resolve(__dirname,'..');
function read(file){return fs.readFileSync(path.join(root,file),'utf8');}
function extract(file,name){const match=read(file).match(new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`,'mi'));if(!match)throw Error(name);return match[0];}
for(const name of ['HomeCatalogsTask','DiscoverLoaderTask','SearchLoaderTask','MetaLoaderTask']){
 const xml=read(`components/${name}.xml`),src=read(`components/${name}.brs`);
 if(!/<field id="responseCache" type="node"/.test(xml)||!/<field id="cacheGeneration" type="integer"/.test(xml))throw Error(`${name} cache interface missing`);
 if(!src.includes('Transport(invalid, m.top.responseCache, m.top.cacheGeneration)'))throw Error(`${name} does not bind shared cache/epoch`);
}
const xml=read('components/ResponseCache.xml');
for(const name of ['Read','Write','Clear','Stats','GetGeneration'])if(!xml.includes(`<function name="${name}"`))throw Error(`Cache interface missing ${name}`);
if(!read('components/MainScene.xml').includes('<ResponseCache id="responseCache"'))throw Error('Scene cache owner missing');
for(const name of ['ReconcileSession','onAddonInstalled','onAddonRemoved','ImportFinished','AdoptAddonSyncResult'])if(!extract('components/MainScene.brs',name).includes('InvalidateContentCache()'))throw Error(`Invalidation missing: ${name}`);
if(!extract('components/HomeScreen.brs','onKeyEvent').includes('InvalidateHomeCache()'))throw Error('Manual refresh does not bypass TTL');
const src=[extract('source/core/AsyncTask.bs','AsyncTask_Launch').replace('CreateObject("roSGNode", taskName)','m.fakeTask'),extract('components/MainScene.brs','InvalidateContentCache'),extract('components/HomeScreen.brs','InvalidateHomeCache')].join('\n');
const cases=`
m.cacheNode={marker:"shared cache",clears:0,callFunc:function(name)
 if name="Clear" then m.clears=m.clears+1
 return 7
end function}
m.scene={cache:m.cacheNode,FindNode:function(id) : return m.cache : end function}
m.parent={scene:m.scene,AppendChild:function(task) : m.child=task : end function,GetScene:function() : return m.scene : end function}
m.fakeTask={HasField:function(name) : return name="responseCache" : end function,ObserveField:function(name,callback) : m.epochBeforeRun=m.cacheGeneration : end function}
task=AsyncTask_Launch(m.parent,"MetaLoaderTask","loaded",{metaId:"tt1"},"meta")
Harness_Equal(task.responseCache.marker,"shared cache","task receives the shared node")
Harness_Equal(task.cacheGeneration,7,"epoch captured at task launch")
Harness_Equal(task.epochBeforeRun,7,"epoch is bound before observers and RUN")
Harness_Equal(task.control,"RUN","cached task still starts normally")
Harness_Equal(task.metaId,"tt1","request arguments remain intact")
m.fakeTask={HasField:function(name) : return false : end function,ObserveField:function(name,callback) : return invalid : end function}
task=AsyncTask_Launch(m.parent,"OtherTask","loaded",{},"other")
Harness_Equal(task.responseCache,invalid,"unrelated tasks do not receive cache fields")
m.top=m.scene
InvalidateContentCache()
Harness_Equal(m.cacheNode.clears,1,"Scene invalidation clears shared owner")
m.top=m.parent
InvalidateHomeCache()
Harness_Equal(m.cacheNode.clears,2,"manual refresh clears same shared owner")
m.scene.cache=invalid
InvalidateHomeCache()
Harness_Equal(m.cacheNode.clears,2,"missing cache safely falls back to normal requests")
print "Assertions passed:";m.passed;" failed:";m.failed
if m.failed=0 then print "CACHE WIRING PASS" else print "CACHE WIRING FAIL"
`;
const target=path.join(root,'work/cache-wiring-run.brs');fs.writeFileSync(target,read('tests/harness.brs')+'\n'+src+'\n'+cases);
const result=spawnSync(path.join(root,'node_modules/.bin/brs'),['--root',path.join(root,'work'),target],{encoding:'utf8',cwd:root});process.stdout.write(result.stdout||'');process.stderr.write(result.stderr||'');if(result.status!==0||!(result.stdout||'').includes('CACHE WIRING PASS'))process.exit(1);
