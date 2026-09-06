const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const nodes=new Map();
function element(){return{hidden:false,value:'',textContent:'',classList:{add(){},remove(){},toggle(){}},replaceChildren(){},append(){},click(){}}}
const context={document:{getElementById:id=>{if(!nodes.has(id))nodes.set(id,element());return nodes.get(id)},body:element(),createElement:element},Blob,File,TextEncoder,Uint8Array,DataView,URL,Math,Error,setTimeout,fetch:async()=>{throw Error('offline')}};
vm.createContext(context);
vm.runInContext(fs.readFileSync('transfer-ios-next/MuseTransfer/WebAssets/app.js','utf8'),context);
(async()=>{
  context.inputs=[new File(['mp3 bytes'],'你好.MP3'),new File(['[00:01]歌词'],'你好.lrc'),new File(['cover'],'你好.png'),new File(['ignore'],'notes.txt')];
  const full=await vm.runInContext('musicPackages(inputs)',context);assert.equal(full.length,1);
  fs.mkdirSync('transfer-ios-next/build/web-tests',{recursive:true});fs.writeFileSync('transfer-ios-next/build/web-tests/full.aiyuepack',Buffer.from(await full[0].arrayBuffer()));
  context.inputs=[new File(['mp3 bytes'],'solo.mp3')];const solo=await vm.runInContext('musicPackages(inputs)',context);assert.equal(solo.length,1);fs.writeFileSync('transfer-ios-next/build/web-tests/solo.aiyuepack',Buffer.from(await solo[0].arrayBuffer()));
  context.inputs=[new File(['lyrics'],'song.lrc')];await assert.rejects(()=>vm.runInContext('musicPackages(inputs)',context),/MP3/);
  console.log('Browser packaging: companions, MP3-only and missing MP3 cases passed.');
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
    await nodes.get('device').onclick();
    assert.equal(nodes.get('phase').textContent,'已完成');
    assert.equal(vm.runInContext('chosen.length',context),0);
    assert.equal(vm.runInContext('batch',context),null);
  }
  assert.equal(uploads,2);
  decision='rejected';vm.runInContext("select(inputs,'files')",context);
  await nodes.get('device').onclick();
  assert.equal(nodes.get('result').textContent,'对方拒绝了请求');
  assert.equal(vm.runInContext('chosen.length',context),1);
  console.log('Browser transfer UI: consecutive completed batches reset selection; rejection preserves selection.');
})().catch(e=>{console.error(e);process.exitCode=1});
