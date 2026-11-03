"""音乐播放器发布核查、精确选择构建与添加以供审核；不执行最终提审。"""
import argparse
import json
from pathlib import Path
import plistlib
import re
import time
import urllib.error
import zipfile

from app_store_screenshots import AppleAPI

APP = '6806107359'
BUNDLE = 'com.luolihao.musicalsystem'
ROOT = Path(__file__).resolve().parents[1]


class MusicAPI(AppleAPI):
    def __init__(self):
        super().__init__()
        self.minted = time.monotonic()

    def call(self, path, method='GET', payload=None):
        if time.monotonic() - self.minted > 600:
            self.__init__()
        for attempt in range(3):
            try:
                return super().call(path, method, payload)
            except (urllib.error.URLError, TimeoutError, ConnectionError):
                if method != 'GET' or attempt == 2:
                    raise
                time.sleep(1)


def number(text):
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', text):
        raise ValueError('版本或构建号格式不正确')
    values = tuple(int(v) for v in text.split('.'))
    return values + (0,) * (3 - len(values))


def configured_release():
    project = (ROOT / 'ios-app/project.yml').read_text(encoding='utf-8')
    version = re.search(r'MARKETING_VERSION: "([0-9.]+)"', project)
    build = re.search(r'CURRENT_PROJECT_VERSION: "([0-9.]+)"', project)
    if not version or not build:
        raise ValueError('无法读取音乐播放器版本与构建号')
    return version.group(1), build.group(1)


def target_version(api, version):
    number(version)
    app = api.call(f'apps/{APP}')['data']
    if app['id'] != APP or app['attributes']['bundleId'] != BUNDLE:
        raise ValueError('不是授权的音乐播放器，停止')
    versions = api.list_all(f'apps/{APP}/appStoreVersions?filter[platform]=IOS&filter[versionString]={version}&limit=200')
    matches = [v for v in versions if v['attributes']['versionString'] == version and v['attributes']['platform'] == 'IOS']
    if len(matches) != 1 or matches[0]['attributes']['appStoreState'] not in {'PREPARE_FOR_SUBMISSION', 'READY_FOR_REVIEW'}:
        raise ValueError('目标版本不是唯一可操作草稿，停止')
    return matches[0]


def preflight(api, version, build):
    number(build)
    target = target_version(api, version)
    if target['attributes']['appStoreState'] != 'PREPARE_FOR_SUBMISSION':
        raise ValueError('目标已添加以供审核，不重复上传；请只执行关联恢复操作')
    builds = api.list_all(f'builds?filter[app]={APP}&limit=200')
    if builds and number(build) <= max(number(b['attributes']['version']) for b in builds):
        raise ValueError('构建号已经使用或不高于已有构建；不得重传同一构建号')
    versions = api.list_all(f'apps/{APP}/appStoreVersions?filter[platform]=IOS&limit=200')
    approved = [v['attributes']['versionString'] for v in versions if v['attributes']['appStoreState'] == 'READY_FOR_SALE']
    if approved and number(version) <= max(number(v) for v in approved):
        raise ValueError('营销版本不高于已发布版本，停止上传')
    return {'app': APP, 'version': version, 'build': build, 'versionId': target['id'], 'stage': 'PREFLIGHT_PASSED'}


def wait_for_build(api, version, build, timeout=900, clock=time.monotonic, sleep=time.sleep):
    number(build)
    deadline = clock() + timeout
    while True:
        candidates = api.list_all(f'builds?filter[app]={APP}&filter[version]={build}&limit=200')
        candidates = [b for b in candidates if b['attributes']['version'] == build]
        if len(candidates) > 1:
            raise ValueError('构建号对应多个构建，停止自动选择')
        if candidates:
            selected = candidates[0]
            attrs = selected['attributes']
            train = api.call(f"builds/{selected['id']}/preReleaseVersion")['data']['attributes']
            if train['version'] != version or train['platform'] != 'IOS':
                raise ValueError('构建号属于其他营销版本，不能选择')
            if attrs.get('expired') or attrs.get('processingState') in {'INVALID', 'FAILED'}:
                raise ValueError('构建已过期或 Apple 处理失败')
            if attrs.get('buildAudienceType') not in {None, 'APP_STORE_ELIGIBLE'}:
                raise ValueError('构建不允许提交 App Store')
            if attrs['processingState'] == 'VALID':
                return selected
        if clock() >= deadline:
            raise TimeoutError('等待指定构建处理超时；只恢复关联操作，不重复上传同一构建')
        print(f'等待 Apple 处理 {version}（{build}）', flush=True)
        sleep(min(20, max(0, deadline - clock())))


def ref(item, key):
    return (item.get('relationships', {}).get(key, {}).get('data') or {}).get('id')


def add_for_review(api, version, build, timeout=900):
    target = target_version(api, version)
    selected = wait_for_build(api, version, build, timeout=timeout)
    refreshed = target_version(api, version)
    if refreshed['id'] != target['id']:
        raise ValueError('等待期间目标草稿发生变化，停止')
    link_path = f"appStoreVersions/{target['id']}/relationships/build"
    linked = api.call(link_path)['data']
    if linked and linked['id'] != selected['id']:
        raise ValueError('草稿已有不同构建，停止覆盖')
    reviews = api.list_all(f'reviewSubmissions?filter[app]={APP}&limit=200')
    active = [r for r in reviews if r['attributes'].get('platform') in {None, 'IOS'} and r['attributes']['state'] != 'COMPLETE']
    if len(active) > 1 or any(r['attributes']['state'] != 'READY_FOR_REVIEW' for r in active):
        raise ValueError('已有进行中的审核，不能撤回或修改')
    review = active[0] if active else None
    items = api.list_all(f"reviewSubmissions/{review['id']}/items?include=appStoreVersion&limit=200") if review else []
    if any(ref(i, 'appStoreVersion') not in {None, target['id']} for i in items):
        raise ValueError('待审核草稿中已有其他版本，停止替换')
    if not linked:
        api.call(link_path, 'PATCH', {'data': {'type': 'builds', 'id': selected['id']}})
    if (api.call(link_path)['data'] or {}).get('id') != selected['id']:
        raise RuntimeError('关联构建回读不一致，停止')
    if not review:
        review = api.call('reviewSubmissions', 'POST', {'data': {
            'type': 'reviewSubmissions', 'attributes': {'platform': 'IOS'},
            'relationships': {'app': {'data': {'type': 'apps', 'id': APP}}}}})['data']
    matches = [i for i in items if ref(i, 'appStoreVersion') == target['id']]
    if len(matches) > 1:
        raise ValueError('目标版本重复出现在待审核项目中，停止')
    if not matches:
        api.call('reviewSubmissionItems', 'POST', {'data': {'type': 'reviewSubmissionItems', 'relationships': {
            'reviewSubmission': {'data': {'type': 'reviewSubmissions', 'id': review['id']}},
            'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': target['id']}}}}})
    verified = api.list_all(f"reviewSubmissions/{review['id']}/items?include=appStoreVersion&limit=200")
    matches = [i for i in verified if ref(i, 'appStoreVersion') == target['id']]
    final_review = api.call(f"reviewSubmissions/{review['id']}")['data']
    if len(matches) != 1 or final_review['attributes']['state'] != 'READY_FOR_REVIEW' or final_review['attributes'].get('submittedDate'):
        raise RuntimeError('添加以供审核回读不一致，不宣称完成')
    beta = api.call(f"builds/{selected['id']}/buildBetaDetail")['data']['attributes']
    return {'app': APP, 'version': version, 'build': build, 'buildId': selected['id'],
            'buildState': selected['attributes']['processingState'], 'submissionId': review['id'],
            'submissionState': final_review['attributes']['state'], 'reviewItemId': matches[0]['id'],
            'submitted': False, 'beta': beta, 'stage': 'ADDED_FOR_REVIEW_NOT_SUBMITTED'}


def verify_ipa(file, version, build):
    with zipfile.ZipFile(file) as archive:
        names = [n for n in archive.namelist() if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist', n)]
        if len(names) != 1:
            raise ValueError('IPA 必须包含唯一的主应用')
        info = plistlib.loads(archive.read(names[0]))
    if (info.get('CFBundleIdentifier'), info.get('CFBundleShortVersionString'), info.get('CFBundleVersion')) != (BUNDLE, version, build):
        raise ValueError('导出的 IPA 不是指定的播放器版本和构建号')
    return {'app': APP, 'bundle': BUNDLE, 'version': version, 'build': build, 'stage': 'IPA_IDENTITY_VERIFIED'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['preflight', 'add-for-review', 'verify-ipa'])
    parser.add_argument('--ipa', type=Path)
    parser.add_argument('--timeout', type=int, default=900)
    parser.add_argument('--output', default='.api-inspection/music-release.json')
    args = parser.parse_args()
    version, build = configured_release()
    if args.operation == 'verify-ipa':
        if not args.ipa:
            parser.error('verify-ipa 必须指定 --ipa')
        result = verify_ipa(args.ipa, version, build)
    else:
        api = MusicAPI()
        result = preflight(api, version, build) if args.operation == 'preflight' else add_for_review(api, version, build, args.timeout)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
