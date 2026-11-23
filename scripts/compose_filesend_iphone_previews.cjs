// 用户明确要求真实运行截图：界面原图直接按比例排版，禁止生成模型重画界面。
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require('sharp');
const root = path.resolve(__dirname, '../marketing/file-send-2026-10-26');
const pages = ['connect','receive','send','edit','completed'];
const width = 1206, height = 2622;

async function main() {
  const folder = path.join(root,'iphone-medium');
  fs.mkdirSync(folder,{recursive:true});
  const records = [], tiles = [];
  for (const [index,page] of pages.entries()) {
    const actual = path.join(root,'sources/actual/iphone',page+'.png');
    const original = fs.readFileSync(actual);
    const screenshot = await sharp(original).metadata();
    const imageHeight = Math.floor(height*0.70);
    const imageWidth = Math.round(imageHeight*screenshot.width/screenshot.height);
    if (imageWidth > width-90) throw Error('截图宽高比不符合 iPhone 页面：'+page);
    const left = Math.floor((width-imageWidth)/2), top = Math.floor(height*0.275);
    const screenBuffer = await sharp(original).resize(imageWidth,imageHeight,{fit:'fill'}).png().toBuffer();
    const filename = `${String(index+1).padStart(2,'0')}-filesend-20261026-${page}.png`;
    const target = path.join(folder,filename);
    const frame = Buffer.from(`<svg width="${width}" height="${height}"><rect x="${left-5}" y="${top-5}" width="${imageWidth+10}" height="${imageHeight+10}" rx="7" fill="#5b50bd"/></svg>`);
    await sharp(path.join(root,'sources/templates',page+'.png')).resize(width,height,{fit:'cover'})
      .composite([{input:frame,left:0,top:0},{input:screenBuffer,left,top}])
      .flatten({background:'#291c89'}).removeAlpha().toColourspace('srgb').png().toFile(target);
    // 回读宣传图中的整个界面区域，确保与同比例原截图逐像素一致。
    const inserted = await sharp(target).extract({left,top,width:imageWidth,height:imageHeight}).removeAlpha().raw().toBuffer();
    const expected = await sharp(screenBuffer).removeAlpha().toColourspace('srgb').raw().toBuffer();
    if (!inserted.equals(expected)) throw Error('实际界面像素被改变：'+page);
    records.push({file:'iphone-medium/'+filename,page,width,height,
      sha256:crypto.createHash('sha256').update(fs.readFileSync(target)).digest('hex'),
      sourceScreenshotSha256:crypto.createHash('sha256').update(original).digest('hex'),
      actualScreenshotPixelVerified:true,screenBounds:{left,top,width:imageWidth,height:imageHeight}});
    tiles.push({input:await sharp(target).resize(302,656).png().toBuffer(),left:index*302,top:0});
  }
  await sharp({create:{width:1510,height:656,channels:3,background:'#291c89'}}).composite(tiles).png().toFile(path.join(root,'iphone-五项功能预览.png'));
  fs.writeFileSync(path.join(root,'iPhone预览验收清单.json'),JSON.stringify(records,null,2));
  console.log('五张 iPhone 预览成图已生成，界面区域与真实截图逐像素校验通过；未上传素材库。');
}
main().catch(error=>{console.error(error);process.exitCode=1;});
