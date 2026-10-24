// 内置图像工具生成后，只做尺寸适配、无透明导出及文件验收。
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require('sharp');
const root = path.resolve(__dirname, '..', 'marketing', 'app-store-2026-10-24');
const generated = 'C:/Users/Administrator/.codex/generated_images/019fb07c-4eba-7580-8a39-6c75ffae99d1';
const sources = [
  ['01-aiyue-20261024-local.png', 'exec-a9199992-ed57-4c27-af80-f06091f62bdc.png', '你的音乐，随身珍藏'],
  ['02-aiyue-20261024-artwork.png', 'exec-69a7aa88-f92f-4d73-a1cc-d27e7c4fd0c5.png', '封面随歌，色彩随心'],
  ['03-aiyue-20261024-lyrics.png', 'exec-f2b56801-8615-4293-b93d-fe8e0f8ca283.png', '每一句，都跟得上'],
  ['04-aiyue-20261024-online.png', 'exec-7cb6d984-0d3b-4941-81d8-96398c966ba2.png', '搜到喜欢，即刻试听']
];
async function main() {
  const manifest = [];
  for (const [folder, width, height, type] of [
    ['iphone-65', 1242, 2688, 'APP_IPHONE_65'],
    ['iphone-large', 1320, 2868, 'APP_IPHONE_67'],
    ['iphone-medium', 1206, 2622, 'APP_IPHONE_61']
  ]) {
    fs.mkdirSync(path.join(root, folder), { recursive: true });
    for (const [filename, source, title] of sources) {
      const destination = path.join(root, folder, filename);
      await sharp(path.join(generated, source)).resize(width, height, {fit: 'contain', background: '#090b10'})
        .flatten({background:'#090b10'}).removeAlpha().toColourspace('srgb').png().toFile(destination);
      const meta = await sharp(destination).metadata();
      if (meta.width !== width || meta.height !== height || meta.hasAlpha || meta.channels !== 3) throw Error('图片验收失败 '+destination);
      manifest.push({file: path.relative(root, destination).replaceAll('\\','/'), width, height, title, type,
        sha256: crypto.createHash('sha256').update(fs.readFileSync(destination)).digest('hex')});
    }
  }
  const tiles = await Promise.all(sources.map(async ([filename], i) => ({input: await sharp(path.join(root,'iphone-65',filename)).resize(310,672).toBuffer(), left:i*310,top:0})));
  await sharp({create:{width:1240,height:672,channels:3,background:'#090b10'}}).composite(tiles).png().toFile(path.join(root,'四张宣传图预览.png'));
  const creative = path.join(root, 'creative', 'aiyue-20261024-universal.png');
  fs.mkdirSync(path.dirname(creative), {recursive:true});
  await sharp(path.join(generated,'exec-8a7f538e-acb4-405d-884d-fb6594be2b68.png'))
    .resize(5244,2950,{fit:'contain',background:'#090b10'}).flatten({background:'#090b10'})
    .removeAlpha().toColourspace('srgb').png().toFile(creative);
  manifest.push({file:'creative/aiyue-20261024-universal.png',width:5244,height:2950,
    title:'产品页页首与搜索结果通用宣传图',category:'CREATIVE_ASSETS',
    sha256:crypto.createHash('sha256').update(fs.readFileSync(creative)).digest('hex')});
  fs.mkdirSync(path.join(root,'ipad-13'),{recursive:true});
  for (const [source,filename,title] of [
    ['ipad-artwork.png','01-aiyue-20261024-ipad-artwork.png','iPad 实际封面播放界面'],
    ['ipad-lyrics.png','02-aiyue-20261024-ipad-lyrics.png','iPad 实际同步歌词界面']
  ]) {
    const destination=path.join(root,'ipad-13',filename);
    const input=path.join(root,'sources',source);
    const inputMeta=await sharp(input).metadata();
    if (inputMeta.width!==2064 || inputMeta.height!==2752) throw Error('iPad 必须使用 13 英寸实际截图');
    await sharp(input).flatten({background:'#000000'}).removeAlpha().toColourspace('srgb').png().toFile(destination);
    const meta=await sharp(destination).metadata();
    if(meta.hasAlpha || meta.channels!==3) throw Error('iPad 不透明导出验收失败');
    manifest.push({file:'ipad-13/'+filename,width:2064,height:2752,title,type:'APP_IPAD_PRO_3GEN_129',
      sha256:crypto.createHash('sha256').update(fs.readFileSync(destination)).digest('hex')});
  }
  fs.writeFileSync(path.join(root,'文件验收清单.json'), JSON.stringify(manifest,null,2));
  console.log(JSON.stringify(manifest.map(({file,width,height})=>({file,width,height})),null,2));
}
main().catch(e=>{console.error(e);process.exit(1)});
