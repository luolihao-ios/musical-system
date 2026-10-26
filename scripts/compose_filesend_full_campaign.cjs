// 延续已确认的 iPhone 风格；界面原图只缩放排版，并逐像素验收。
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require('sharp');
const root = path.resolve(__dirname, '../marketing/file-send-2026-10-26');
const pages = [['connect','手机电脑，轻松互传'],['receive','批量接收，进度清晰'],
  ['send','手机文件，发送到电脑'],['edit','发送前，随时整理']];
const hash = buffer => crypto.createHash('sha256').update(buffer).digest('hex');

async function screenInsert(device, page, box) {
  const file = `sources/actual/${device}/${page}.png`;
  const original = fs.readFileSync(path.join(root,file));
  const meta = await sharp(original).metadata();
  const scale = Math.min(box.width/meta.width, box.height/meta.height);
  const width = Math.round(meta.width*scale), height = Math.round(meta.height*scale);
  const left = Math.round(box.left+(box.width-width)/2), top = Math.round(box.top+(box.height-height)/2);
  return {input:await sharp(original).resize(width,height).removeAlpha().toColourspace('srgb').png().toBuffer(),
    left,top,width,height,source:file,sourceSha256:hash(original)};
}

async function compose(template, destination, width, height, inserts, overlay) {
  fs.mkdirSync(path.dirname(destination),{recursive:true});
  const frames = inserts.map(item=>`<rect x="${item.left-4}" y="${item.top-4}" width="${item.width+8}" height="${item.height+8}" rx="6" fill="#6156bd"/>`).join('');
  const frame = Buffer.from(`<svg width="${width}" height="${height}">${frames}</svg>`);
  await sharp(template).resize(width,height,{fit:'cover'})
    .composite([...(overlay?[{input:overlay,left:0,top:0}]:[]),{input:frame,left:0,top:0},...inserts.map(({input,left,top})=>({input,left,top}))])
    .flatten({background:'#291c89'}).removeAlpha().toColourspace('srgb').png().toFile(destination);
  const meta = await sharp(destination).metadata();
  if (meta.width!==width || meta.height!==height || meta.hasAlpha || meta.channels!==3) throw Error('成图规格错误 '+destination);
  for (const item of inserts) {
    const actual = await sharp(destination).extract({left:item.left,top:item.top,width:item.width,height:item.height}).raw().toBuffer();
    const expected = await sharp(item.input).raw().toBuffer();
    if (!actual.equals(expected)) throw Error('原始界面像素校验失败 '+item.source);
  }
}

async function main() {
  const iphone = JSON.parse(fs.readFileSync(path.join(root,'iPhone预览验收清单.json')));
  const manifest = iphone.map((item,index)=>({...item,title:[...pages.map(p=>p[1]),'传输完成，有序保存'][index]}));
  for (const [device,folder,width,height] of [['ipad','ipad-13',2064,2752],['duo','iphone-duo',1398,2034]]) {
    if (process.argv.includes('--creative-only')) continue;
    if (process.argv.includes('--ipad-only') && device !== 'ipad') continue;
    const tiles=[];
    for (const [index,[page,title]] of pages.entries()) {
      const file=`${folder}/${String(index+1).padStart(2,'0')}-filesend-20261027-${page}.png`;
      const screen=await screenInsert(device,page,{left:width*0.07,top:height*(device==='duo'?.31:.275),width:width*0.86,height:height*(device==='duo'?.65:.69)});
      const target=path.join(root,file);
      await compose(path.join(root,'sources/templates',device+'-'+page+'.png'),target,width,height,[screen]);
      manifest.push({file,width,height,title,sha256:hash(fs.readFileSync(target)),actualScreenshotPixelVerified:true,
        sourceScreenshot:screen.source,sourceScreenshotSha256:screen.sourceSha256});
      tiles.push({input:await sharp(target).resize(300,440,{fit:'contain',background:'#291c89'}).png().toBuffer(),left:index*300,top:0});
    }
    await sharp({create:{width:1200,height:440,channels:3,background:'#291c89'}}).composite(tiles).png().toFile(path.join(root,device+'-四项功能预览.png'));
  }
  if (process.argv.includes('--ipad-only')) { console.log('四张 iPad 成图及真实截图像素验收完成。'); return; }
  for (const [name,title,placementType] of [['header','产品页页首图','PRODUCT_PAGE_HEADER_ASSET'],['search','搜索结果图','APP_STORE_SEARCH_RESULTS_ASSET']]) {
    const width=5244,height=2950;
    const inserts=name==='header' ? [
      await screenInsert('ipad','receive',{left:width*.43,top:height*.13,width:width*.35,height:height*.75}),
      await screenInsert('iphone','send',{left:width*.80,top:height*.18,width:width*.16,height:height*.70})
    ] : [
      await screenInsert('iphone','edit',{left:width*.055,top:height*.14,width:width*.20,height:height*.75}),
      await screenInsert('iphone','receive',{left:width*.29,top:height*.14,width:width*.20,height:height*.75})
    ];
    const file=`creative/filesend-20261027-${name}.png`,target=path.join(root,file);
    // 页首标题按固定版面排字，避免底图长标题被实际截图遮挡；复用已有背景，不再生成图片。
    const headerText=Buffer.from(`<svg width="${width}" height="${height}"><defs><linearGradient id="panel"><stop stop-color="#170b61" stop-opacity="1"/><stop offset=".93" stop-color="#241278" stop-opacity=".96"/><stop offset="1" stop-color="#241278" stop-opacity="0"/></linearGradient></defs><rect width="2380" height="${height}" fill="url(#panel)"/><g font-family="Microsoft YaHei, sans-serif" fill="white"><text x="220" y="1010" font-size="150" font-weight="600">file send</text><text x="210" y="1390" font-size="230" font-weight="700">手机电脑，</text><text x="210" y="1700" font-size="230" font-weight="700">轻松互传</text><text x="220" y="1990" font-size="76" fill="#ddd6ff">同一 Wi-Fi · 浏览器连接</text><text x="220" y="2120" font-size="76" fill="#ddd6ff">手机与电脑双向传输</text></g></svg>`);
    const template=name==='header'?path.join(root,'sources/campaign-background.png'):path.join(root,'sources/templates',name+'.png');
    await compose(template,target,width,height,inserts,name==='header'?headerText:undefined);
    manifest.push({file,width,height,title,category:'CREATIVE_ASSETS',placementType,sha256:hash(fs.readFileSync(target)),
      actualScreenshotPixelVerified:true,sourceScreenshots:inserts.map(i=>({file:i.source,sha256:i.sourceSha256}))});
  }
  if (process.argv.includes('--creative-only')) { console.log('两张横向成图及真实截图像素验收完成。'); return; }
  if (manifest.length!==15 || new Set(manifest.map(i=>i.sha256)).size!==15) throw Error('全套必须为十五张不同素材');
  for (const item of manifest) {
    if (!item.actualScreenshotPixelVerified || hash(fs.readFileSync(path.join(root,item.file)))!==item.sha256) throw Error('成图验收失败 '+item.file);
  }
  fs.writeFileSync(path.join(root,'文件验收清单.json'),JSON.stringify(manifest,null,2));
  console.log('十五张成图通过尺寸、RGB、SHA-256 和真实截图区域逐像素验收。');
}
main().catch(error=>{console.error(error);process.exitCode=1;});
