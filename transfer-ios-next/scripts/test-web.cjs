const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const nodes=new Map();
function element(){return{hidden:false,value:'',textContent:'',classList:{add(){},remove(){},toggle(){}},replaceChildren(){},append(){},click(){}}}
const context={document:{getElementById:id=>{if(!nodes.has(id))nodes.set(id,element());return nodes.get(id)},body:element(),createElement:element},Blob,File,TextEncoder,Uint8Array,DataView,URL,Math,Error,setTimeout,fetch:async()=>{throw Error('offline')}};
vm.createContext(context);
vm.runInContext(fs.readFileSync('transfer-ios-next/MuseTransfer/WebAssets/app.js','utf8'),context);
const browserJS=fs.readFileSync('transfer-ios-next/MuseTransfer/WebAssets/app.js','utf8');
assert.match(browserJS,/\/web\/outbound/);
assert.match(browserJS,/link\.click\(\)/);
assert.match(browserJS,/const direct=Array\.from\(e\.dataTransfer\.files/);
assert.match(browserJS,/receiveTab/);
assert.match(browserJS,/outbound\/decision/);
assert.match(browserJS,/outboundDownloads\.has/);
(async()=>{
  context.inputs=[new File(['mp3 bytes'],'你好.MP3'),new File(['[00:01]歌词'],'你好.lrc'),new File(['cover'],'你好.png'),new File(['ignore'],'notes.txt')];
  vm.runInContext("select(inputs,'files')",context);
  assert.equal(vm.runInContext('chosen.length',context),4);
  assert.equal(vm.runInContext('mode',context),'files');
  context.inputs=[new File(['second'],'second.mp3'),new File(['mp3 bytes'],'你好.MP3')];
  vm.runInContext("select(inputs,'files')",context);
  assert.equal(vm.runInContext('chosen.length',context),5);
  assert.equal(nodes.get('edit').hidden,false);
  const dropped=await vm.runInContext('droppedFiles({items:[],files:[new File(["a"],"a.txt"),new File(["b"],"b.txt")]})',context);
  assert.equal(dropped.length,2);
  // Windows Explorer may expose an incomplete items list; the direct files list is authoritative.
  vm.runInContext('chosen=[]; render()',context);
  const dropEvent={preventDefault(){},dataTransfer:{items:[{kind:'file',getAsEntry(){return {isFile:true,file(cb){cb(new File(["one"],"one.txt"))}}},getAsFile(){return new File(["one"],"one.txt")}}],files:[new File(["one"],"one.txt"),new File(["two"],"two.txt")]}};
  await nodes.get('drop').ondrop(dropEvent);
  assert.equal(vm.runInContext('chosen.length',context),2);
  console.log('Browser selection: MP3, lyrics, cover and ordinary files remain raw transfer items.');
  // Exercise the actual click handler, including a second batch and refusal.
  let uploads=0, decision='accepted';
  context.setTimeout=callback=>callback();
  context.fetch=async(url,options)=>({ok:true,json:async()=>options.method==='POST'?{id:'batch-'+(++uploads),state:'waiting'}:{state:decision}});
  context.XMLHttpRequest=class {
    constructor(){this.upload={};this.status=200}
    open(){}
    send(file){this.upload.onprogress({loaded:file.size});this.onload()}
    abort(){this.onabort()}
  };
  for(let i=0;i<2;i++){
    context.inputs=[new File(['content'],'test.mp3')];
    vm.runInContext("select(inputs,'files')",context);
    await nodes.get('sendNow').onclick();
    assert.equal(nodes.get('phase').textContent,'已完成');
    assert.equal(vm.runInContext('chosen.length',context),0);
    assert.equal(vm.runInContext('batch',context),null);
  }
  assert.equal(uploads,2);
  decision='rejected';vm.runInContext("select(inputs,'files')",context);
  await nodes.get('sendNow').onclick();
  assert.equal(nodes.get('result').textContent,'对方拒绝了请求');
  assert.equal(vm.runInContext('chosen.length',context),1);
  console.log('Browser transfer UI: consecutive completed batches reset selection; rejection preserves selection.');
})().catch(e=>{console.error(e);process.exitCode=1});
