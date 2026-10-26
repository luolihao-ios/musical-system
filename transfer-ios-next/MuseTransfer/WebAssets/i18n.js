'use strict';

globalThis.fileSendI18n = (() => {
  const strings = {
    en: {
      appName: 'fileSend', send: 'Send', receive: 'Receive', settings: 'Settings',
      connectIPhone: 'Connect iPhone', accessCodeHint: 'Enter the access code shown on the iPhone', accessCode: 'Access code', connect: 'Connect',
      choose: 'Choose', file: 'Files', folder: 'Folder', noFiles: 'No files selected', dropHint: 'Drag files or folders here', edit: 'Edit', done: 'Done', delete: 'Delete', clearAll: 'Remove all', endPrevious: 'End unfinished transfer', sendToPhone: 'Send to iPhone',
      phoneToComputer: 'Files sent from iPhone', phoneAutoDownload: 'Files selected on the iPhone download automatically to the browser default download folder.',
      waitingPhoneFiles: 'Waiting for files from iPhone…', receivedFiles: 'Receive', saveLocation: 'Save location', filesRoot: 'Files › fileSend', chooseDestination: 'Choose destination', diagnostics: 'Diagnostics', diagnosticsHint: 'Diagnostics log in the iPhone Files app', downloadDiagnostics: 'Download log', copyAddress: 'Copy address', phoneFiles: 'Phone files', up: 'Up', newFolder: 'New folder', refresh: 'Refresh', waitingPhone: 'Waiting for iPhone…', cancel: 'Cancel',
      previousIncomplete: 'The previous transfer was not completed. End it before sending again.', readyToSend: 'Choose files and send again.', requestFailed: 'Request failed', selectedSummary: 'Files: {0} · Size: {1}', connected: 'Connected', browserConnected: 'Version {0} · Browser connected to iPhone', downloading: 'Downloading {0} / {1}', downloaded: 'Downloaded', downloadFailed: 'Download failed', connectionInterrupted: 'Connection interrupted', phoneRequest: 'iPhone requests to send {0} file(s)', waitingDownload: 'Waiting to download', waitingReceive: 'Waiting for acceptance', accept: 'Accept', reject: 'Decline', rejectedRequest: 'The recipient declined the request.', open: 'Open', download: 'Download', folderName: 'Folder name', uploading: 'Sending {0} / {1}', savedTo: 'Saved to Files › fileSend', saveFailed: 'Save failed, please try again', cancelled: 'Cancelled', timeout: 'Transfer timed out', selectAtLeastOne: 'Select at least one file.', waitingResponse: 'Waiting for iPhone response…', waitingTransfer: 'Waiting to transfer', requestCancelled: 'Request was cancelled or timed out', sendingFiles: 'Sending files', completed: 'Completed', savedAll: 'All files have been saved to the iPhone', incomplete: 'Transfer not completed', destinationPrompt: 'Save to which folder under fileSend? Leave empty to use the root folder.', invalidDestination: 'Enter a folder name inside the shared folder.', copiedAddress: 'Connection address copied', connectionAddress: 'Connection address: {0}'
    },
    'zh-Hans': {
      appName: 'fileSend', send: '发送', receive: '接收', settings: '设置',
      connectIPhone: '连接 iPhone', accessCodeHint: '输入手机“电脑传文件”页面上的访问码', accessCode: '访问码', connect: '连接',
      choose: '选择', file: '文件', folder: '文件夹', noFiles: '尚未选择文件', dropHint: '文件或文件夹可以拖到这里', edit: '编辑', done: '完成', delete: '删除', clearAll: '全部删除', endPrevious: '结束上一批未完成传输', sendToPhone: '发送到手机',
      phoneToComputer: '手机发送给电脑', phoneAutoDownload: '手机选择文件后会自动开始下载到浏览器默认下载目录。',
      waitingPhoneFiles: '等待手机发送文件…', receivedFiles: '接收', saveLocation: '文件保存位置', filesRoot: '文件 › fileSend', chooseDestination: '选择保存位置', diagnostics: '诊断日志', diagnosticsHint: '手机“文件”App 中的诊断日志', downloadDiagnostics: '下载日志', copyAddress: '复制连接地址', phoneFiles: '手机文件', up: '返回上级', newFolder: '新建文件夹', refresh: '刷新', waitingPhone: '等待手机响应…', cancel: '取消',
      previousIncomplete: '上一批传输未完成，可结束后重新发送。', readyToSend: '可以重新选择并发送', requestFailed: '请求失败', selectedSummary: '文件：{0} · 大小：{1}', connected: '已连接', browserConnected: '版本 {0} · 浏览器已连接手机', downloading: '正在下载 {0} / {1}', downloaded: '已下载', downloadFailed: '下载失败', connectionInterrupted: '连接中断', phoneRequest: '手机请求发送 {0} 个文件', waitingDownload: '等待下载', waitingReceive: '等待接收', accept: '接受', reject: '拒绝', rejectedRequest: '对方拒绝了请求', open: '打开', download: '下载', folderName: '文件夹名称', uploading: '正在传输 {0} / {1}', savedTo: '已保存到文件 › fileSend', saveFailed: '保存失败，请重试', cancelled: '已取消', timeout: '传输超时', selectAtLeastOne: '请至少选择一个文件。', waitingResponse: '等待手机响应…', waitingTransfer: '等待传输', requestCancelled: '请求已取消或超时', sendingFiles: '正在发送文件', completed: '已完成', savedAll: '所有文件已保存到手机', incomplete: '传输未完成', destinationPrompt: '保存到手机 fileSend 下的哪个文件夹？留空使用根目录。', invalidDestination: '请输入共享目录内的文件夹名称', copiedAddress: '连接地址已复制', connectionAddress: '连接地址：{0}'
    },
    'zh-Hant': {
      appName: 'fileSend', send: '傳送', receive: '接收', settings: '設定',
      connectIPhone: '連接 iPhone', accessCodeHint: '輸入手機「電腦傳檔案」頁面上的存取碼', accessCode: '存取碼', connect: '連接',
      choose: '選擇', file: '檔案', folder: '資料夾', noFiles: '尚未選擇檔案', dropHint: '可將檔案或資料夾拖曳到此處', edit: '編輯', done: '完成', delete: '刪除', clearAll: '全部刪除', endPrevious: '結束上一批未完成傳輸', sendToPhone: '傳送到手機',
      phoneToComputer: '手機傳送到電腦', phoneAutoDownload: '手機選擇檔案後，會自動下載到瀏覽器的預設下載位置。',
      waitingPhoneFiles: '等待手機傳送檔案…', receivedFiles: '接收', saveLocation: '檔案儲存位置', filesRoot: '檔案 › fileSend', chooseDestination: '選擇儲存位置', diagnostics: '診斷日誌', diagnosticsHint: '手機「檔案」App 中的診斷日誌', downloadDiagnostics: '下載日誌', copyAddress: '複製連接位址', phoneFiles: '手機檔案', up: '返回上層', newFolder: '新增資料夾', refresh: '重新整理', waitingPhone: '等待手機回應…', cancel: '取消',
      previousIncomplete: '上一批傳輸未完成，可結束後重新傳送。', readyToSend: '可以重新選擇並傳送', requestFailed: '請求失敗', selectedSummary: '檔案：{0} · 大小：{1}', connected: '已連接', browserConnected: '版本 {0} · 瀏覽器已連接手機', downloading: '正在下載 {0} / {1}', downloaded: '已下載', downloadFailed: '下載失敗', connectionInterrupted: '連線中斷', phoneRequest: '手機要求傳送 {0} 個檔案', waitingDownload: '等待下載', waitingReceive: '等待接收', accept: '接受', reject: '拒絕', rejectedRequest: '對方拒絕了請求', open: '開啟', download: '下載', folderName: '資料夾名稱', uploading: '正在傳輸 {0} / {1}', savedTo: '已儲存至檔案 › fileSend', saveFailed: '儲存失敗，請重試', cancelled: '已取消', timeout: '傳輸逾時', selectAtLeastOne: '請至少選擇一個檔案。', waitingResponse: '等待手機回應…', waitingTransfer: '等待傳輸', requestCancelled: '請求已取消或逾時', sendingFiles: '正在傳送檔案', completed: '已完成', savedAll: '所有檔案已儲存到手機', incomplete: '傳輸未完成', destinationPrompt: '儲存到手機 fileSend 下的哪個資料夾？留空使用根目錄。', invalidDestination: '請輸入共享目錄內的資料夾名稱', copiedAddress: '連接位址已複製', connectionAddress: '連接地址：{0}'
    }
  };

  const languages = () => Array.from(globalThis.navigator?.languages || [globalThis.navigator?.language || 'en']);
  const pick = () => {
    const values = languages().map(value => String(value).toLowerCase());
    if (values.some(value => value.startsWith('zh-hant') || value.startsWith('zh-tw') || value.startsWith('zh-hk') || value.startsWith('zh-mo'))) return 'zh-Hant';
    if (values.some(value => value.startsWith('zh'))) return 'zh-Hans';
    return 'en';
  };
  const locale = pick();
  const t = (key, ...values) => (strings[locale][key] || strings.en[key] || key).replace(/\{(\d+)\}/g, (_, index) => values[Number(index)] ?? '');
  const apply = () => {
    document.documentElement.lang = locale;
    document.querySelectorAll('[data-i18n]').forEach(element => { element.textContent = t(element.dataset.i18n); });
    document.querySelectorAll('[data-i18n-placeholder]').forEach(element => { element.placeholder = t(element.dataset.i18nPlaceholder); });
    document.querySelectorAll('[data-i18n-aria-label]').forEach(element => { element.setAttribute('aria-label', t(element.dataset.i18nAriaLabel)); });
    document.title = t('appName');
  };
  return { locale, t, apply };
})();
