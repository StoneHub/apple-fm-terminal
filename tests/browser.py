"""Optional browser launcher boundaries; fictional paths and no model/browser access."""
import argparse
import importlib.util
from pathlib import Path
from unittest import TestCase, main, mock

spec = importlib.util.spec_from_file_location("management", Path(__file__).resolve().parents[1] / "scripts/management.py")
management = importlib.util.module_from_spec(spec)
spec.loader.exec_module(management)


class BrowserLauncher(TestCase):
    def args(self, **changes):
        values = dict(adapter="/fictional/adapter", node="/fictional/node", server="/fictional/server.mjs",
                      prompt="Read my granted test tab; $(never-execute)", check_bridge=False, check_model=False, wait_for_tab=120)
        values.update(changes)
        return argparse.Namespace(**values)

    def test_missing_adapter_fails_without_launch(self):
        with mock.patch.object(management.subprocess, "run") as run:
            with self.assertRaises(ValueError): management.browser(self.args(adapter=None))
            run.assert_not_called()

    @mock.patch.object(management.os, "access", return_value=True)
    @mock.patch.object(Path, "is_file", return_value=True)
    def test_prompt_is_literal_argv_without_shell_or_context(self, *_):
        args = self.args()
        with mock.patch.object(management.subprocess, "run", return_value=argparse.Namespace(returncode=0)) as run:
            with self.assertRaises(SystemExit) as result: management.browser(args)
            self.assertEqual(result.exception.code, 0)
            run.assert_called_once_with([args.adapter, "--node", args.node, "--server", args.server,
                                         "--prompt", args.prompt, "--wait-for-tab", "120"], check=False)

    @mock.patch.object(management.os, "access", return_value=True)
    @mock.patch.object(Path, "is_file", return_value=True)
    def test_ambiguous_mode_rejected(self, *_):
        with mock.patch.object(management.subprocess, "run") as run:
            with self.assertRaises(ValueError): management.browser(self.args(check_model=True))
            run.assert_not_called()


if __name__ == "__main__": main()
