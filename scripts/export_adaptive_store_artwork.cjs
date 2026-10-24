// 仅将已生成的宣传成图导出为 Apple 要求的精确尺寸和无透明 RGB PNG。
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require('sharp');
const root = path.resolve(__dirname, '../marketing/app-store-2026-10-24');
const titles = ['你的音乐，随身珍藏', '封面随歌，色彩随心', '每一句，都跟得上', '搜到喜欢，即刻试听'];
const pages = ['01-local', '02-artwork', '03-lyrics', '04-online'];
async function main() {
  const manifestPath = path.join(root, '文件验收清单.json');
  const old = JSON.parse(fs.readFileSync(manifestPath));
  const manifest = old.filter(x => x.file.startsWith('iphone-medium/'));
  // 兼容从上一轮 14 张清单重新导出：手机四图以现有精确尺寸文件为准。
  if (manifest.length === 0) {
    for (const [i, page] of pages.entries()) {
      const file='iphone-medium/'+page.slice(0,2)+'-aiyue-20261024-'+page.slice(3)+'.png';
      const bytes=fs.readFileSync(path.join(root,file));
      manifest.push({file,width:1206,height:2622,title:titles[i],sha256:crypto.createHash('sha256').update(bytes).digest('hex')});
    }
  }
  for (const [device, folder, width, height] of [['ipad', 'ipad-13', 2064, 2752], ['duo', 'iphone-duo', 1398, 2034]]) {
    fs.mkdirSync(path.join(root, folder), {recursive:true});
    const tiles = [];
    for (const [i, page] of pages.entries()) {
      const source = path.join(root, 'sources/posters', device, page+'.png');
      const filename = page.slice(0,2)+'-aiyue-20261024-v2-'+page.slice(3)+'.png';
      const file = folder+'/'+filename;
      const destination = path.join(root, file);
      await sharp(source).resize(width,height,{fit:'contain',background:'#090b10'})
        .flatten({background:'#090b10'}).removeAlpha().toColourspace('srgb').png().toFile(destination);
      const meta = await sharp(destination).metadata();
      if (meta.width!==width || meta.height!==height || meta.hasAlpha || meta.channels!==3) throw Error('尺寸/透明验收失败 '+file);
      manifest.push({file,width,height,title:titles[i],sha256:crypto.createHash('sha256').update(fs.readFileSync(destination)).digest('hex')});
      tiles.push({input:await sharp(destination).resize(300,400,{fit:'contain',background:'#090b10'}).toBuffer(),left:i*300,top:0});
    }
    await sharp({create:{width:1200,height:400,channels:3,background:'#090b10'}}).composite(tiles)
      .png().toFile(path.join(root,device+'-四图预览.png'));
  }
  for (const [name, title, placementType] of [
    ['header', '产品页页首宣传图', 'PRODUCT_PAGE_HEADER_ASSET'],
    ['search', '搜索结果宣传图', 'APP_STORE_SEARCH_RESULTS_ASSET']
  ]) {
    const file = 'creative/aiyue-20261024-v2-'+name+'.png';
    const target = path.join(root,file);
    await sharp(path.join(root,'sources/posters',name+'.png'))
      .resize(5244,2950,{fit:'contain',background:'#090b10'}).flatten({background:'#090b10'})
      .removeAlpha().toColourspace('srgb').png().toFile(target);
    manifest.push({file,width:5244,height:2950,title,category:'CREATIVE_ASSETS',placementType,
      sha256:crypto.createHash('sha256').update(fs.readFileSync(target)).digest('hex')});
  }
  if (manifest.length !== 14) throw Error('只允许四张 iPhone、四张 Duo、四张 iPad 和两张独立宣传图');
  fs.writeFileSync(manifestPath,JSON.stringify(manifest,null,2));
  console.log('已验收素材总数 '+manifest.length);
}
main().catch(error=>{console.error(error);process.exit(1)});
