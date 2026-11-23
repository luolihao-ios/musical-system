"""播放器发布护栏；外部 Apple HTTP 用内存服务器代替，业务逻辑真实执行。"""
from copy import deepcopy
from pathlib import Path
import plistlib
import tempfile
import sys
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import music_release as release


class Server:
    def __init__(self):
        self.bundle = 'com.luolihao.musicalsystem'
        self.version = {'id': 'draft', 'attributes': {'versionString': '0.2.2', 'platform': 'IOS', 'appStoreState': 'PREPARE_FOR_SUBMISSION'}}
        self.builds = [{'id': 'b47', 'attributes': {'version': '47', 'processingState': 'VALID', 'expired': False, 'buildAudienceType': 'APP_STORE_ELIGIBLE'}}]
        self.train = '0.2.2'
        self.linked = None
        self.reviews = []
        self.items = []
        self.writes = []

    def list_all(self, route):
        if route.startswith('apps/6806107359/appStoreVersions?'):
            return [deepcopy(self.version)]
        if route.startswith('builds?'):
            return deepcopy(self.builds)
        if route.startswith('reviewSubmissions?'):
            return deepcopy(self.reviews)
        if route.startswith('reviewSubmissions/') and '/items?' in route:
            return deepcopy(self.items)
        raise AssertionError(route)

    def call(self, route, method='GET', payload=None):
        if method != 'GET':
            self.writes.append((route, method, deepcopy(payload)))
        if route == 'apps/6806107359':
            return {'data': {'id': '6806107359', 'attributes': {'bundleId': self.bundle}}}
        if route.startswith('builds/') and route.endswith('/preReleaseVersion'):
            return {'data': {'id': 'train', 'attributes': {'version': self.train, 'platform': 'IOS'}}}
        if route == 'appStoreVersions/draft/relationships/build':
            if method == 'PATCH':
                self.linked = deepcopy(payload['data'])
            return {'data': deepcopy(self.linked)}
        if route == 'reviewSubmissions' and method == 'POST':
            assert payload['data']['relationships']['app']['data'] == {'type': 'apps', 'id': '6806107359'}
            item = {'id': 'review', 'attributes': {'state': 'READY_FOR_REVIEW', 'platform': 'IOS', 'submittedDate': None}}
            self.reviews.append(item)
            return {'data': deepcopy(item)}
        if route == 'reviewSubmissionItems' and method == 'POST':
            assert payload['data']['relationships']['reviewSubmission']['data'] == {'type': 'reviewSubmissions', 'id': 'review'}
            assert payload['data']['relationships']['appStoreVersion']['data'] == {'type': 'appStoreVersions', 'id': 'draft'}
            item = {'id': 'item', 'attributes': {'state': 'READY_FOR_REVIEW'}, 'relationships': deepcopy(payload['data']['relationships'])}
            self.items.append(item)
            return {'data': deepcopy(item)}
        if route == 'reviewSubmissions/review':
            return {'data': deepcopy(self.reviews[0])}
        if route == 'builds/b47/buildBetaDetail':
            return {'data': {'id': 'beta', 'attributes': {'internalBuildState': 'IN_BETA_TESTING', 'externalBuildState': 'READY_FOR_BETA_SUBMISSION'}}}
        raise AssertionError((route, method))


class MusicReleaseTests(unittest.TestCase):
    def setUp(self):
        self.api = Server()

    def test_preflight_allows_new_build(self):
        self.api.builds[0]['attributes']['version'] = '46'
        result = release.preflight(self.api, '0.2.2', '47')
        self.assertEqual(result['build'], '47')
        self.assertEqual(self.api.writes, [])

    def test_preflight_rejects_reused_build(self):
        with self.assertRaises(ValueError):
            release.preflight(self.api, '0.2.2', '47')
        self.assertEqual(self.api.writes, [])

    def test_preflight_checks_all_builds_not_just_last_upload(self):
        self.api.builds[0]['attributes']['version'] = '44'
        self.api.builds.append({'id': 'newer', 'attributes': {'version': '48'}})
        with self.assertRaises(ValueError):
            release.preflight(self.api, '0.2.2', '47')

    def test_testflight_allows_new_version_without_creating_a_store_draft(self):
        self.api.version['attributes']['appStoreState'] = 'READY_FOR_SALE'
        result = release.testflight_preflight(self.api, '0.2.3', '48')
        self.assertEqual(result['version'], '0.2.3')
        self.assertEqual(result['build'], '48')
        self.assertNotIn('versionId', result)
        self.assertEqual(self.api.writes, [])

    def test_testflight_still_rejects_reused_build_and_published_version(self):
        self.api.version['attributes']['appStoreState'] = 'READY_FOR_SALE'
        for version, build in [('0.2.3', '47'), ('0.2.2', '48')]:
            with self.subTest(version=version, build=build), self.assertRaises(ValueError):
                release.testflight_preflight(self.api, version, build)
        self.assertEqual(self.api.writes, [])

    def test_wrong_app_is_rejected_before_writes(self):
        self.api.bundle = 'com.luolihao.aiyuetransfer'
        with self.assertRaises(ValueError):
            release.add_for_review(self.api, '0.2.2', '47')
        self.assertEqual(self.api.writes, [])

    def test_wrong_store_version_is_rejected(self):
        self.api.version['attributes']['versionString'] = '0.2.1'
        with self.assertRaises(ValueError):
            release.add_for_review(self.api, '0.2.2', '47')
        self.assertEqual(self.api.writes, [])

    def test_published_version_is_not_mutated(self):
        self.api.version['attributes']['appStoreState'] = 'READY_FOR_SALE'
        with self.assertRaises(ValueError):
            release.add_for_review(self.api, '0.2.2', '47')
        self.assertEqual(self.api.writes, [])

    def test_same_build_number_in_wrong_train_is_rejected(self):
        self.api.train = '0.2.1'
        with self.assertRaises(ValueError):
            release.add_for_review(self.api, '0.2.2', '47')
        self.assertEqual(self.api.writes, [])

    def test_invalid_expired_and_internal_only_builds_are_rejected(self):
        for attrs in ({'processingState': 'INVALID'}, {'expired': True}, {'buildAudienceType': 'INTERNAL_ONLY'}):
            with self.subTest(attrs=attrs):
                api = Server()
                api.builds[0]['attributes'].update(attrs)
                with self.assertRaises(ValueError):
                    release.add_for_review(api, '0.2.2', '47')
                self.assertEqual(api.writes, [])

    def test_missing_build_times_out_without_writes(self):
        self.api.builds = []
        with self.assertRaises(TimeoutError):
            release.wait_for_build(self.api, '0.2.2', '47', timeout=0)
        self.assertEqual(self.api.writes, [])

    def test_processing_build_is_rechecked_until_valid(self):
        self.api.builds[0]['attributes']['processingState'] = 'PROCESSING'
        ticks = []
        def sleep(seconds):
            ticks.append(seconds)
            self.api.builds[0]['attributes']['processingState'] = 'VALID'
        found = release.wait_for_build(self.api, '0.2.2', '47', sleep=sleep)
        self.assertEqual(found['id'], 'b47')
        self.assertEqual(len(ticks), 1)

    def test_add_links_exact_build_and_never_submits(self):
        result = release.add_for_review(self.api, '0.2.2', '47')
        self.assertEqual(self.api.linked, {'type': 'builds', 'id': 'b47'})
        self.assertEqual(result['submissionState'], 'READY_FOR_REVIEW')
        self.assertEqual(result['reviewItemId'], 'item')
        self.assertFalse(result['submitted'])
        self.assertEqual(self.api.reviews[0]['attributes']['submittedDate'], None)
        self.assertEqual(result['beta']['internalBuildState'], 'IN_BETA_TESTING')
        self.assertEqual([r for r, _, _ in self.api.writes], ['appStoreVersions/draft/relationships/build', 'reviewSubmissions', 'reviewSubmissionItems'])

    def test_rerun_reuses_item_and_makes_no_new_writes(self):
        release.add_for_review(self.api, '0.2.2', '47')
        self.api.writes.clear()
        release.add_for_review(self.api, '0.2.2', '47')
        self.assertEqual(self.api.writes, [])
        self.assertEqual(len(self.api.items), 1)

    def test_conflicting_selected_build_is_not_replaced(self):
        self.api.linked = {'type': 'builds', 'id': 'another'}
        with self.assertRaises(ValueError):
            release.add_for_review(self.api, '0.2.2', '47')
        self.assertEqual(self.api.writes, [])

    def test_active_review_is_not_cancelled_or_modified(self):
        self.api.reviews = [{'id': 'active', 'attributes': {'platform': 'IOS', 'state': 'IN_REVIEW'}}]
        with self.assertRaises(ValueError):
            release.add_for_review(self.api, '0.2.2', '47')
        self.assertEqual(self.api.writes, [])

    def test_other_version_in_review_draft_is_not_replaced(self):
        self.api.reviews = [{'id': 'review', 'attributes': {'platform': 'IOS', 'state': 'READY_FOR_REVIEW'}}]
        self.api.items = [{'id': 'old', 'relationships': {'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': 'different'}}}}]
        with self.assertRaises(ValueError):
            release.add_for_review(self.api, '0.2.2', '47')
        self.assertEqual(self.api.writes, [])

    def test_duplicate_matching_builds_are_rejected(self):
        self.api.builds.append(deepcopy(self.api.builds[0]))
        self.api.builds[-1]['id'] = 'duplicate'
        with self.assertRaises(ValueError):
            release.add_for_review(self.api, '0.2.2', '47')
        self.assertEqual(self.api.writes, [])

    def test_store_state_is_rechecked_after_apple_processing_wait(self):
        self.api.builds[0]['attributes']['processingState'] = 'PROCESSING'
        from unittest.mock import patch
        real_wait = release.wait_for_build
        def finish_wait(api, version, build, timeout=900):
            api.version['attributes']['appStoreState'] = 'WAITING_FOR_REVIEW'
            api.builds[0]['attributes']['processingState'] = 'VALID'
            return real_wait(api, version, build, timeout=0)
        with patch.object(release, 'wait_for_build', side_effect=finish_wait):
            with self.assertRaises(ValueError):
                release.add_for_review(self.api, '0.2.2', '47')
        self.assertEqual(self.api.writes, [])

    def test_exported_ipa_must_match_exact_app_version_and_build(self):
        expected = {'CFBundleIdentifier': 'com.luolihao.musicalsystem', 'CFBundleShortVersionString': '0.2.2', 'CFBundleVersion': '47'}
        with tempfile.TemporaryDirectory() as tmp:
            file = Path(tmp) / 'player.ipa'
            for change in ({}, {'CFBundleIdentifier': 'com.luolihao.aiyuetransfer'}, {'CFBundleShortVersionString': '0.2.1'}, {'CFBundleVersion': '46'}):
                with self.subTest(change=change):
                    with zipfile.ZipFile(file, 'w') as archive:
                        archive.writestr('Payload/LocalMusicPlayer.app/Info.plist', plistlib.dumps(expected | change))
                    if change:
                        with self.assertRaises(ValueError):
                            release.verify_ipa(file, '0.2.2', '47')
                    else:
                        self.assertEqual(release.verify_ipa(file, '0.2.2', '47')['build'], '47')
