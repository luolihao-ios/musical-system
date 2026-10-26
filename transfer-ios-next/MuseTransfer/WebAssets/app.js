'use strict';
const $ = id => document.getElementById(id);
const { t, apply: applyTranslations } = fileSendI18n;
applyTranslations();

let chosen = [], path = '', batch = null, xhr = null, cancelled = false, mode = 'files', urls = [], connected = false, editing = false, destination = '', outboundDownloads = new Set();
const uid = () => 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, character => { const random = Math.random() * 16 | 0; return (character === 'x' ? random : (random & 3 | 8)).toString(16); });
const size = bytes => bytes < 1024 ? `${bytes} B` : bytes < 1048576 ? `${(bytes / 1024).toFixed(1)} KB` : `${(bytes / 1048576).toFixed(1)} MB`;

function message(value) { $('message').textContent = value; }
function appRoot() { return t('filesRoot'); }

async function recover() {
  const pending = (await api('/web/uploads')).find(item => ['waiting', 'accepted'].includes(item.state));
  $('recover').hidden = !pending;
  if (pending) {
    message(t('previousIncomplete'));
    $('recover').onclick = async () => { try { await api(`/web/uploads/${pending.id}`, 'DELETE'); $('recover').hidden = true; message(t('readyToSend')); } catch (error) { message(error.message); } };
  }
}

async function api(url, method = 'GET', value) {
  const response = await fetch(url, { method, headers: value ? { 'Content-Type': 'application/json' } : {}, body: value ? JSON.stringify(value) : undefined });
  const data = await response.json();
  if (!response.ok) throw Error(data.error || t('requestFailed'));
  return data;
}

function page(id) {
  for (const view of ['login', 'send', 'receive', 'files', 'settings', 'progress']) $(view).hidden = view !== id;
  document.body.classList.toggle('transferring', id === 'progress');
  $('sendTab').classList.toggle('active', ['send', 'progress'].includes(id));
  $('receiveTab').classList.toggle('active', id === 'receive');
  $('settingsTab').classList.toggle('active', id === 'settings');
}

function render() {
  urls.forEach(URL.revokeObjectURL); urls = [];
  $('selected').replaceChildren();
  $('summary').textContent = chosen.length ? t('selectedSummary', chosen.length, size(chosen.reduce((total, file) => total + file.size, 0))) : t('noFiles');
  $('edit').hidden = !chosen.length; $('edit').textContent = editing ? t('done') : t('edit'); $('clear').hidden = !chosen.length || !editing;
  chosen.forEach((file, index) => {
    const row = document.createElement('div'); row.className = 'file-card';
    if (file.type.startsWith('image/')) { const image = document.createElement('img'); image.src = URL.createObjectURL(file); urls.push(image.src); row.append(image); }
    else { const icon = document.createElement('span'); icon.className = 'file-icon'; icon.textContent = /\.(mp3|aiyuepack)$/i.test(file.name) ? '♫' : '▤'; row.append(icon); }
    const label = document.createElement('span'); label.className = 'file-name'; label.textContent = file.webkitRelativePath || file.name; label.title = label.textContent;
    const bytes = document.createElement('span'); bytes.className = 'file-size'; bytes.textContent = size(file.size);
    const remove = document.createElement('button'); remove.textContent = t('delete'); remove.hidden = !editing; remove.onclick = () => { chosen.splice(index, 1); render(); };
    row.append(label, bytes, remove); $('selected').append(row);
  });
}

function select(files, selectedMode = 'files') {
  const incoming = Array.from(files), seen = new Set(chosen.map(file => `${file.name}\u0000${file.size}`));
  for (const file of incoming) { const key = `${file.name}\u0000${file.size}`; if (!seen.has(key)) { chosen.push(file); seen.add(key); } }
  mode = selectedMode; render(); message('');
}

$('choose').onclick = () => $('fileInput').click(); $('folder').onclick = () => $('folderInput').click();
for (const id of ['fileInput', 'folderInput']) $(id).onchange = event => { select(event.target.files); event.target.value = ''; };

async function droppedFiles(dataTransfer) {
  const items = Array.from(dataTransfer.items || []), result = [];
  async function visit(entry, prefix = '') {
    if (entry.isFile) { await new Promise(resolve => entry.file(file => { try { Object.defineProperty(file, 'webkitRelativePath', { value: prefix + file.name }); } catch {} result.push(file); resolve(); }, resolve)); return; }
    if (entry.isDirectory) { const reader = entry.createReader(); await new Promise(resolve => reader.readEntries(async entries => { for (const child of entries) await visit(child, `${prefix}${entry.name}/`); resolve(); })); }
  }
  for (const item of items) { const entry = item.webkitGetAsEntry?.(); if (entry) await visit(entry); else if (item.kind === 'file') { const file = item.getAsFile(); if (file) result.push(file); } }
  const files = Array.from(dataTransfer.files || []); return files.length > result.length ? files : result;
}

$('clear').onclick = () => { chosen = []; render(); };
const drop = $('drop'); drop.ondragenter = event => { event.preventDefault(); drop.classList.add('dragging'); }; drop.ondragover = event => event.preventDefault(); drop.ondragleave = () => drop.classList.remove('dragging'); drop.ondrop = async event => { event.preventDefault(); drop.classList.remove('dragging'); const direct = Array.from(event.dataTransfer.files || []); select(direct.length ? direct : await droppedFiles(event.dataTransfer)); };

$('connect').onclick = async () => {
  try { await api('/web/session', 'POST', { code: $('code').value }); $('code').value = ''; connected = true; page('send'); message(t('connected')); await recover(); await loadOutbound(); const info = await api('/web/info'); $('version').textContent = t('browserConnected', info.version); }
  catch (error) { message(error.message); }
};

async function downloadOutbound(file, row) {
  return new Promise((resolve, reject) => {
    const request = new XMLHttpRequest(); request.open('GET', `/web/outbound/download?name=${encodeURIComponent(file.name)}`); request.responseType = 'blob';
    request.onprogress = event => { const value = event.lengthComputable ? event.loaded / event.total : 0; row.progress.value = value; row.status.textContent = t('downloading', size(event.loaded), size(event.total || file.bytes)); api(`/web/outbound/${encodeURIComponent(file.id)}/progress`, 'POST', { progress: value }).catch(() => {}); };
    request.onload = async () => { if (request.status !== 200) { reject(Error(t('downloadFailed'))); return; } const link = document.createElement('a'); link.href = URL.createObjectURL(request.response); link.download = file.name; link.click(); setTimeout(() => URL.revokeObjectURL(link.href), 1000); row.progress.value = 1; row.status.textContent = t('downloaded'); await api(`/web/outbound/${encodeURIComponent(file.id)}/complete`, 'POST').catch(() => {}); resolve(); };
    request.onerror = () => reject(Error(t('connectionInterrupted'))); request.send();
  });
}

async function loadOutbound() {
  if (!connected) return;
  try {
    const files = await api('/web/outbound'), list = $('outboundRequests'); list.replaceChildren(); if (!files.length) return;
    const row = document.createElement('div'); row.className = 'card'; const title = document.createElement('h3'); title.textContent = t('phoneRequest', files.length); row.append(title);
    const rows = files.map(file => { const item = document.createElement('div'); item.className = 'row'; const info = document.createElement('div'); info.className = 'outbound-info'; info.textContent = `${file.name} · ${size(file.bytes)}`; const status = document.createElement('p'); status.textContent = file.state === 'completed' ? t('downloaded') : file.state === 'downloading' ? t('downloading', 0, size(file.bytes)) : file.state === 'accepted' ? t('waitingDownload') : t('waitingReceive'); const progress = document.createElement('progress'); progress.max = 1; progress.value = file.progress || 0; item.append(info, status, progress); row.append(item); return { file, status, progress }; });
    const actions = document.createElement('div'); const accept = document.createElement('button'); accept.textContent = t('accept'); accept.disabled = files.every(file => file.state !== 'waiting'); accept.onclick = async () => { accept.disabled = true; reject.disabled = true; actions.replaceChildren(); try { await api('/web/outbound/decision', 'POST', { accepted: 'true' }); for (const item of rows) { if (outboundDownloads.has(item.file.id) || item.file.state === 'completed') continue; outboundDownloads.add(item.file.id); try { await downloadOutbound(item.file, item); } catch (error) { outboundDownloads.delete(item.file.id); item.status.textContent = error.message; } } } catch (error) { message(error.message); } };
    const reject = document.createElement('button'); reject.textContent = t('reject'); reject.disabled = files.every(file => file.state !== 'waiting'); reject.onclick = async () => { accept.disabled = true; reject.disabled = true; actions.replaceChildren(); try { await api('/web/outbound/decision', 'POST', { accepted: 'false' }); row.remove(); } catch (error) { message(error.message); } };
    actions.append(accept, reject); row.append(actions); list.append(row);
    for (const item of rows) if (item.file.state === 'accepted' && !outboundDownloads.has(item.file.id)) { outboundDownloads.add(item.file.id); downloadOutbound(item.file, item).catch(error => { outboundDownloads.delete(item.file.id); item.status.textContent = error.message; }); }
  } catch { /* polling can race with the phone closing a completed session; retry silently */ }
}
if (typeof setInterval === 'function') setInterval(loadOutbound, 1000);

$('sendTab').onclick = () => { if (!batch) page(connected ? 'send' : 'login'); }; $('receiveTab').onclick = () => { if (!batch) page(connected ? 'receive' : 'login'); };
async function load() { try { const list = await api(`/web/files?path=${encodeURIComponent(path)}`); page('files'); $('path').textContent = path || t('appName'); $('listing').replaceChildren(); for (const file of list) { const row = document.createElement('div'); row.className = 'row'; const label = document.createElement('div'); label.textContent = `${file.directory ? '📁 ' : '📄 '}${file.name}${file.directory ? '' : ` · ${size(file.size)}`}`; const action = document.createElement(file.directory ? 'button' : 'a'); action.textContent = file.directory ? t('open') : t('download'); if (file.directory) action.onclick = () => { path = file.path; load(); }; else { action.href = `/web/download?path=${encodeURIComponent(file.path)}`; action.download = file.name; } row.append(label, action); $('listing').append(row); } } catch (error) { message(error.message); } }
$('reload').onclick = load; $('up').onclick = () => { path = path.split('/').slice(0, -1).join('/'); load(); }; $('mkdir').onclick = async () => { const name = prompt(t('folderName')); if (!name) return; try { await api('/web/folders', 'POST', { path: `${path ? `${path}/` : ''}${name}` }); await load(); } catch (error) { message(error.message); } };

function upload(file, id, row) { return new Promise((resolve, reject) => { xhr = new XMLHttpRequest(); xhr.open('PUT', `/web/uploads/${batch}/${id}`); xhr.upload.onprogress = event => { row.progress.value = event.loaded / file.size || 0; row.status.textContent = t('uploading', size(event.loaded), size(file.size)); }; xhr.onload = () => { if (xhr.status === 200) { row.progress.value = 1; row.status.textContent = t('savedTo'); resolve(); } else reject(Error(t('saveFailed'))); }; xhr.onerror = () => reject(Error(t('connectionInterrupted'))); xhr.onabort = () => reject(Error(t('cancelled'))); xhr.timeout = 0; xhr.ontimeout = () => reject(Error(t('timeout'))); xhr.send(file); }); }
$('sendNow').onclick = async () => {
  if (!chosen.length) { message(t('selectAtLeastOne')); return; } cancelled = false; const files = chosen; page('progress'); $('done').hidden = true; $('cancel').hidden = false; $('phase').textContent = t('waitingResponse'); $('result').textContent = ''; $('rows').replaceChildren();
  const rows = files.map(file => { const div = document.createElement('div'); div.className = 'card'; const name = document.createElement('p'); name.textContent = `${file.name} · ${size(file.size)}`; const status = document.createElement('p'); status.textContent = t('waitingTransfer'); const progress = document.createElement('progress'); progress.max = 1; progress.value = 0; div.append(name, status, progress); $('rows').append(div); return { status, progress }; });
  try { const manifest = files.map(file => ({ id: uid(), name: `${destination ? `${destination}/` : ''}${file.webkitRelativePath || file.name}`, size: file.size })); const created = await api('/web/uploads', 'POST', manifest); batch = created.id; if (cancelled) { await api(`/web/uploads/${batch}`, 'DELETE'); throw Error(t('cancelled')); } let state = created.state; while (state === 'waiting' && !cancelled) { await new Promise(resolve => setTimeout(resolve, 800)); state = (await api(`/web/uploads/${batch}`)).state; } if (cancelled || state !== 'accepted') throw Error(state === 'rejected' ? t('rejectedRequest') : t('requestCancelled')); $('phase').textContent = t('sendingFiles'); for (let index = 0; index < files.length; index++) { if (cancelled) throw Error(t('cancelled')); await upload(files[index], manifest[index].id, rows[index]); } $('phase').textContent = t('completed'); $('result').textContent = t('savedAll'); chosen = []; render(); } catch (error) { $('phase').textContent = t('incomplete'); $('result').textContent = error.message; if (batch) try { await api(`/web/uploads/${batch}`, 'DELETE'); } catch {} } finally { xhr = null; batch = null; $('cancel').hidden = true; $('done').hidden = false; }
};
$('cancel').onclick = () => { cancelled = true; xhr?.abort(); if (batch) api(`/web/uploads/${batch}`, 'DELETE').catch(() => {}); }; $('done').onclick = () => page('send'); $('edit').onclick = () => { editing = !editing; render(); }; $('settingsTab').onclick = () => { if (!batch) page(connected ? 'settings' : 'login'); };
$('chooseDestination').onclick = () => { const value = prompt(t('destinationPrompt'), destination); if (value === null) return; if (value.startsWith('/') || value.includes('\\') || value.split('/').some(part => part === '..' || part.startsWith('.') || part === '待发送')) { message(t('invalidDestination')); return; } destination = value.replace(/\/$/, ''); $('savePath').textContent = `${appRoot()}${destination ? ` / ${destination}` : ''}`; };
$('copyAddress').onclick = () => { const input = document.createElement('textarea'); input.value = location.origin; document.body.append(input); input.select(); const copied = document.execCommand('copy'); input.remove(); message(copied ? t('copiedAddress') : t('connectionAddress', location.origin)); };
