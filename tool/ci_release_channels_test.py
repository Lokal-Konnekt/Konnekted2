import unittest
from release_channels import calculate, EPOCH


class Channels(unittest.TestCase):
    spec = 'name: flick\nversion: 1.0.0+1000\n'
    def calc(self, channel, tags=(), **kwargs):
        return calculate(self.spec, channel, tags, '7', now=EPOCH+123456, **kwargs)
    def test_first_stable_and_nightly_share_an_updateable_code(self):
        stable=self.calc('stable');nightly=self.calc('nightly')
        self.assertEqual(stable['tag'],'v1.0.0')
        self.assertEqual(nightly['tag'],'v1.0.0-nightly.7')
        self.assertEqual(stable['build_number'],nightly['build_number'])
        self.assertGreater(int(stable['build_number']),1000)
        self.assertEqual(stable['prerelease'],'false')
        self.assertEqual(nightly['prerelease'],'true')
    def test_next_run_uses_clock_not_independent_workflow_counters(self):
        earlier=calculate(self.spec,'nightly',[],'700',now=EPOCH+123456)
        later=calculate(self.spec,'stable',[],'1',now=EPOCH+123457)
        self.assertGreater(int(later['build_number']),int(earlier['build_number']))
    def test_after_stable_nightly_targets_next_patch(self):
        result=self.calc('nightly',['v1.0.0','beta-60-1','v1.0.0-nightly.2'])
        self.assertEqual(result['version'],'1.0.1-nightly.7')
        self.assertEqual(result['previous'],'v1.0.0')
    def test_previous_notes_baseline_ignores_nightly_and_beta(self):
        self.assertEqual(self.calc('stable',['v0.9.0','v0.8.9','v0.9.1-nightly.7','beta-60-1'])['previous'],'v0.9.0')
    def test_retry_nightly_gets_a_distinct_tag(self):
        self.assertEqual(self.calc('nightly',attempt='2')['tag'],'v1.0.0-nightly.7.r2')
    def test_tag_must_match_pubspec_and_manual_runs_main(self):
        self.assertEqual(self.calc('stable',ref='refs/tags/v1.0.0')['version'],'1.0.0')
        for ref in ['refs/heads/feature','refs/tags/v2.0.0','refs/tags/v1.0.0-rc.1','refs/tags/v1.0.0\nsha=bad']:
            with self.subTest(ref=ref),self.assertRaises(ValueError): self.calc('stable',ref=ref)
        with self.assertRaises(ValueError): self.calc('nightly',ref='refs/tags/v1.0.0')
    def test_lower_codes_overflow_and_unmerged_versions_are_refused(self):
        for code in ['1','0','2100000001','100\nflavors=bad']:
            with self.subTest(code=code),self.assertRaises(ValueError): self.calc('stable',supplied=code)
        with self.assertRaises(ValueError): self.calc('stable',requested='2.0.0')
        self.assertEqual(self.calc('stable',supplied='900000')['build_number'],'900000')


if __name__=='__main__':unittest.main()
