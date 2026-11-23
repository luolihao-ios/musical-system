import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('../MuseTransfer/WebAssets/i18n.js', import.meta.url), 'utf8');

function load(language) {
  const context = { navigator: { languages: [language], language }, globalThis: {} };
  context.globalThis = context;
  vm.runInNewContext(source, context);
  return context.fileSendI18n;
}

assert.equal(load('en-US').locale, 'en');
assert.equal(load('en-US').t('send'), 'Send');
assert.equal(load('zh-CN').locale, 'zh-Hans');
assert.equal(load('zh-CN').t('send'), '发送');
assert.equal(load('zh-TW').locale, 'zh-Hant');
assert.equal(load('zh-TW').t('send'), '傳送');
assert.equal(load('fr-FR').locale, 'en');
assert.equal(load('fr-FR').t('connect'), 'Connect');
console.log('Browser locale selection and strings passed');
