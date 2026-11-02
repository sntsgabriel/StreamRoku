// Execute the real route and catalog selection handlers with Roku node doubles.
const fs = require('fs');
const path = require('path');
const {spawnSync} = require('child_process');
const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'components/DiscoverScreen.brs'), 'utf8');
function extract(name) {
  const found = source.match(new RegExp(`^(?:sub|function) ${name}\\([^]*?^end (?:sub|function)`, 'mi'));
  if (!found) throw Error(name);
  return found[0];
}
const handlers = ['OnEnter', 'ApplyRoute', 'TypeGroups', 'TypeKey', 'TypeOrder', 'TypeLabel', 'TypeMatches', 'SelectDefaults', 'CatalogsForType', 'SameCatalog'].map(extract).join('\n');
const mocks = `
sub RefreshTexts()
end sub
function Lang(section as string, key as string) as string
 return key
end function
sub CancelLoad()
 m.cancelled = m.cancelled + 1
 m.loadTask = invalid
end sub
sub CancelSources()
 m.sourcesTask = invalid
end sub
sub ResetDiscover()
 m.metas = []
 m.grid.content = invalid
 m.loaded = false
end sub
function CatalogSignature() as string
 return "same"
end function
sub EnsureGenre()
 if m.genre = "" then m.genre = "all"
end sub
sub EnsureSources()
 if SelectDefaults()
  m.requested.Push(m.selectedCatalog.rawType)
 else
  m.requested.Push("empty")
 end if
end sub
`;
const cases = `
m.cancelled = 0 : m.requested = []
m.routeType = "" : m.typeKey = "" : m.selectedCatalog = invalid : m.genre = ""
m.metas = [] : m.header = {} : m.status = {} : m.sourcesSignature = "same"
m.grid = {focusCount:0, SetFocus:sub(value) : m.focusCount = m.focusCount + 1 : end sub}
m.filterBar = {callFunc:function(name) : return false : end function}
m.top = {nodes:{discoverTitle:{},discoverSub:{}},FindNode:function(id) : return m.nodes[id] : end function}
m.stores = {addons:{callFunc:function(name,descriptor=invalid,sourceName=invalid)
 if name="AddonsCatalogCapabilities" then return {feed:true}
 return descriptor.name
end function}}
m.sources = [{address:"example",name:"Provider",catalogs:[{id:"popular",type:"movie",name:"Movies"},{id:"popular",type:"series",name:"Series"}]}]
OnEnter({type:"series"})
Harness_Equal(m.requested[0],"series","Series route fetches series even though movies sort first")
Harness_Equal(m.top.nodes.discoverTitle.text,"series","Series has a distinct screen title")
Harness_Equal(TypeGroups().Count(),1,"Series type filter contains only the requested family")
m.metas = [{id:"series1"}] : m.genre = "Drama"
OnEnter(invalid)
Harness_Equal(m.genre,"Drama","Details Back keeps selected genre")
Harness_Equal(m.metas[0].id,"series1","Details Back keeps series results")
Harness_Equal(m.requested.Count(),1,"Details Back does not refetch loaded catalog")
Harness_Equal(m.grid.focusCount,1,"Details Back restores grid focus")
OnEnter({type:"movie"})
Harness_Equal(m.requested[1],"movie","switch to Movies issues a movie request")
Harness_Equal(m.top.nodes.discoverTitle.text,"movies","Movies has its own screen title")
Harness_Equal(m.metas.Count(),0,"switch clears the previous family immediately")
Harness_Equal(m.genre,"all","new family resets previous genre")
Harness_Equal(m.selectedCatalog.rawType,"movie","same catalog ID cannot reuse another type")
OnEnter({type:"series"})
Harness_Equal(m.requested[2],"series","second visit to Series replaces movie selection")
m.sources = [{address:"example",name:"Provider",catalogs:[{id:"popular",type:"movie",name:"Movies"}]}]
m.selectedCatalog = invalid
Harness_Equal(SelectDefaults(),false,"missing series catalog never falls back to movies")
Harness_Equal(m.typeKey,"series","empty series section retains requested family")
OnEnter({})
Harness_Equal(TypeGroups()[0].key,"movie","generic Discover still permits available types")
Harness_Equal(m.top.nodes.discoverTitle.text,"title","generic entry restores Discover title")
print "Assertions passed:";m.passed;" failed:";m.failed
if m.failed=0 then print "DISCOVER ROUTE PASS" else print "DISCOVER ROUTE FAIL"
`;
const target = path.join(root, 'work/discover-route-run.brs');
fs.writeFileSync(target, fs.readFileSync(path.join(root, 'tests/harness.brs'), 'utf8')+'\n'+mocks+'\n'+handlers+'\n'+cases);
const result = spawnSync(path.join(root,'node_modules/.bin/brs'),['--root',path.join(root,'work'),target],{encoding:'utf8',cwd:root});
process.stdout.write(result.stdout||'');process.stderr.write(result.stderr||'');
if (result.status!==0 || !(result.stdout||'').includes('DISCOVER ROUTE PASS')) process.exit(1);
