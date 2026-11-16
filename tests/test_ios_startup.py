import subprocess
import unittest
from unittest.mock import patch

from tools.run_ios_startup import find_vm_service


class SimulatorLogTests(unittest.TestCase):
    uri = 'http://127.0.0.1:53654/example=/'

    @patch('tools.run_ios_startup.subprocess.run')
    def test_console_announcement_needs_no_history(self, run):
        output = 'The Dart VM service is listening on ' + self.uri
        self.assertEqual(find_vm_service('test-device', output), self.uri)
        run.assert_not_called()

    @patch('tools.run_ios_startup.subprocess.run')
    def test_retained_log_recovers_announcement_missed_by_stream(self, run):
        run.return_value.stdout = (
            '2026-11-16 06:33:51.667 Df Runner[123:456] (Flutter) flutter: '
            'The Dart VM service is listening on ' + self.uri + '\n'
        )
        self.assertEqual(find_vm_service('test-device', 'All tests passed!'), self.uri)
        command = run.call_args.args[0]
        self.assertEqual(command[:6], ['xcrun', 'simctl', 'spawn', 'test-device', 'log', 'show'])

    @patch('tools.run_ios_startup.subprocess.run')
    def test_missing_announcement_remains_pending(self, run):
        run.return_value.stdout = 'No matching events'
        self.assertIsNone(find_vm_service('test-device', ''))

    @patch('tools.run_ios_startup.subprocess.run')
    def test_history_timeout_allows_next_poll(self, run):
        run.side_effect = subprocess.TimeoutExpired('log', 10)
        self.assertIsNone(find_vm_service('test-device', ''))


if __name__ == '__main__':
    unittest.main()
