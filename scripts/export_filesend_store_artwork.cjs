// 将图像生成工具完成的宣传成图导出为 Apple 素材规格，保留宽高比和全部画面。
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require('sharp');
const root = path.resolve(__dirname, '../marketing/file-send-2026-10-26');
const pages = [
  ['connect', '手机电脑，轻松互传'], ['receive', '批量接收，进度清晰'],
  ['send', '手机文件，发送到电脑'], ['edit', '发送前，随时整理'], ['completed', '传输完成，有序保存']
];

async function main() {
  const manifest = [];
  for (const [device, folder, width, height, count] of [
    ['iphone', 'iphone-medium', 1206, 2622, 5],
    ['duo', 'iphone-duo', 1398, 2034, 4],
    ['ipad', 'ipad-13', 2064, 2752, 4]
  ]) {
    const tiles = [];
    fs.mkdirSync(path.join(root, folder), {recursive: true});
    for (const [index, [page, title]] of pages.slice(0, count).entries()) {
      const file = `${folder}/${String(index+1).padStart(2,'0')}-filesend-20261026-${page}.png`;
      const destination = path.join(root, file);
      await sharp(path.join(root, 'sources/posters', device, page+'.png'))
        .resize(width, height, {fit:'contain',background:'#291c89'})
        .flatten({background:'#291c89'}).removeAlpha().toColourspace('srgb').png().toFile(destination);
      const meta = await sharp(destination).metadata();
      if (meta.width !== width || meta.height !== height || meta.hasAlpha || meta.channels !== 3) throw Error('尺寸/透明验收失败 '+file);
      manifest.push({file,width,height,title,sha256:crypto.createHash('sha256').update(fs.readFileSync(destination)).digest('hex')});
      tiles.push({input:await sharp(destination).resize(240,520,{fit:'contain',background:'#291c89'}).png().toBuffer(),left:index*240,top:0});
    }
    await sharp({create:{width:count*240,height:520,channels:3,background:'#291c89'}}).composite(tiles).png().toFile(path.join(root,device+'-功能预览.png'));
  }
  fs.mkdirSync(path.join(root,'creative'), {recursive:true});
  for (const [name,title,placementType] of [
    ['header','产品页页首图','PRODUCT_PAGE_HEADER_ASSET'],
    ['search','搜索结果图','APP_STORE_SEARCH_RESULTS_ASSET']
  ]) {
    const file=`creative/filesend-20261026-${name}.png`;
    const target=path.join(root,file);
    await sharp(path.join(root,'sources/posters',name+'.png')).resize(5244,2950,{fit:'contain',background:'#291c89'})
      .flatten({background:'#291c89'}).removeAlpha().toColourspace('srgb').png().toFile(target);
    manifest.push({file,width:5244,height:2950,title,category:'CREATIVE_ASSETS',placementType,
      sha256:crypto.createHash('sha256').update(fs.readFileSync(target)).digest('hex')});
  }
  if (manifest.length!==15 || new Set(manifest.map(item=>item.sha256)).size!==15) throw Error('必须有15张不同功能/尺寸素材');
  fs.writeFileSync(path.join(root,'文件验收清单.json'),JSON.stringify(manifest,null,2));
  console.log('已导出并验收15张 file send 宣传图');
}
main().catch(error=>{console.error(error);process.exitCode=1;});
