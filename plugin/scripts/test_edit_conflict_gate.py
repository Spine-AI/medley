#!/usr/bin/env python3
# Table-driven tests for edit-conflict-gate.py (the PreToolUse lockdown gate).
# Runs with the stdlib only: python3 -m unittest test_edit_conflict_gate  — or just
# python3 test_edit_conflict_gate.py. Each case invokes the gate as a subprocess with
# a synthetic hook payload, exactly the way Claude Code does.
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

GATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "edit-conflict-gate.py")


def run_gate(payload, env_extra=None, tmpdir=None):
    """Run the gate; return (exit_code, parsed_decision_or_None)."""
    env = {k: v for k, v in os.environ.items() if k != "MEDLEY_WORKER"}
    if tmpdir:
        env["TMPDIR"] = tmpdir  # keep warn-once markers out of the real temp dir
    if env_extra:
        env.update(env_extra)
    proc = subprocess.run(
        [sys.executable, GATE],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        env=env,
    )
    decision = None
    if proc.stdout.strip():
        decision = json.loads(proc.stdout)["hookSpecificOutput"]["permissionDecision"]
    return proc.returncode, decision


class GateTestCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.repo = os.path.realpath(self._tmp.name)
        os.makedirs(os.path.join(self.repo, ".medley"))
        self.addCleanup(self._tmp.cleanup)

    def write_state(self, lockdown=True, pid=None, title="Ship the widget", engine=None):
        state = {
            "updatedAt": 1234567890000,
            "lockdown": lockdown,
            "pid": os.getpid() if pid is None else pid,
            "mission": {"id": "m1", "title": title, "status": "running"},
            "reason": "mission running — repo is read-only for the host session",
            "escape": "mission_pause releases the repo; mission_stop cancels",
        }
        if engine is not None:
            state["engine"] = engine
        with open(os.path.join(self.repo, ".medley", "mission-state.json"), "w") as f:
            json.dump(state, f)

    def payload(self, tool_name, tool_input):
        return {
            "hook_event_name": "PreToolUse",
            "tool_name": tool_name,
            "tool_input": tool_input,
            "cwd": self.repo,
            "session_id": "test-session",
        }

    def gate(self, tool_name, tool_input, env_extra=None):
        return run_gate(self.payload(tool_name, tool_input), env_extra, tmpdir=self.repo)

    def dead_pid(self):
        proc = subprocess.Popen(["true"])
        proc.wait()
        return proc.pid


class TestBypassAndFallthrough(GateTestCase):
    def test_worker_bypass_ignores_lockdown(self):
        self.write_state(lockdown=True)
        for tool, tool_input in [
            ("Edit", {"file_path": os.path.join(self.repo, "a.py")}),
            ("Task", {"prompt": "do stuff"}),
            ("Bash", {"command": "rm -rf ."}),
        ]:
            code, decision = self.gate(tool, tool_input, env_extra={"MEDLEY_WORKER": "1"})
            self.assertEqual((code, decision), (0, None), f"{tool} should bypass for workers")

    def test_no_state_file_falls_through(self):
        # No mission-state.json, no active-work.json → everything allowed.
        for tool, tool_input in [
            ("Edit", {"file_path": os.path.join(self.repo, "a.py")}),
            ("Task", {"prompt": "do stuff"}),
            ("Bash", {"command": "rm -rf ."}),
        ]:
            code, decision = self.gate(tool, tool_input)
            self.assertEqual((code, decision), (0, None), f"{tool} should fall through")

    def test_lockdown_false_falls_through(self):
        self.write_state(lockdown=False)
        code, decision = self.gate("Bash", {"command": "npm test"})
        self.assertEqual((code, decision), (0, None))

    def test_stale_pid_falls_through(self):
        self.write_state(lockdown=True, pid=self.dead_pid())
        for tool, tool_input in [
            ("Edit", {"file_path": os.path.join(self.repo, "a.py")}),
            ("Task", {"prompt": "do stuff"}),
            ("Bash", {"command": "npm test"}),
        ]:
            code, decision = self.gate(tool, tool_input)
            self.assertEqual((code, decision), (0, None), f"{tool} should treat state as stale")

    def test_fallthrough_still_warns_once_on_claimed_file(self):
        # The original active-work warn-once behavior is preserved when no lockdown.
        work = {"tasks": [{"taskId": "t1", "title": "Task One", "mission": "M",
                           "files": ["src/a.py"]}]}
        with open(os.path.join(self.repo, ".medley", "active-work.json"), "w") as f:
            json.dump(work, f)
        target = os.path.join(self.repo, "src", "a.py")
        code, decision = self.gate("Edit", {"file_path": target})
        self.assertEqual(decision, "deny")
        code, decision = self.gate("Edit", {"file_path": target})
        self.assertEqual((code, decision), (0, None), "second touch should pass (warn-once)")


class TestLockdownDenials(GateTestCase):
    def setUp(self):
        super().setUp()
        self.write_state(lockdown=True)

    def deny_reason(self, tool, tool_input):
        payload = self.payload(tool, tool_input)
        env = {k: v for k, v in os.environ.items() if k != "MEDLEY_WORKER"}
        env["TMPDIR"] = self.repo
        proc = subprocess.run([sys.executable, GATE], input=json.dumps(payload),
                              capture_output=True, text=True, env=env)
        out = json.loads(proc.stdout)["hookSpecificOutput"]
        self.assertEqual(out["permissionDecision"], "deny")
        return out["permissionDecisionReason"]

    def test_task_denied(self):
        reason = self.deny_reason("Task", {"prompt": "go implement it"})
        self.assertIn("Ship the widget", reason)
        self.assertIn("mission_pause", reason)

    def test_edit_inside_repo_denied(self):
        reason = self.deny_reason("Edit", {"file_path": os.path.join(self.repo, "src", "a.py")})
        self.assertIn("Ship the widget", reason)
        self.assertIn("mission_pause", reason)

    def test_relative_edit_inside_repo_denied(self):
        self.deny_reason("Write", {"file_path": "src/a.py"})

    def test_edit_outside_repo_allowed(self):
        with tempfile.TemporaryDirectory() as outside:
            code, decision = self.gate("Edit", {"file_path": os.path.join(outside, "plan.md")})
            self.assertEqual((code, decision), (0, None))

    def test_edit_escaping_repo_via_dotdot_allowed(self):
        # realpath resolves ../ — a path that leaves the repo is outside it.
        code, decision = self.gate("Edit", {"file_path": os.path.join(self.repo, "..", "x.md")})
        self.assertEqual((code, decision), (0, None))

    def test_denials_repeat_every_time(self):
        # NO warn-once in the lockdown branch.
        self.deny_reason("Task", {"prompt": "again"})
        self.deny_reason("Task", {"prompt": "again"})

    ALLOWED_BASH = [
        "git status && git diff",
        "rg -n foo | head",
        "ls -la; pwd",
        "node --version",
        "sed -n 5p file",
        "cat README.md",
        "git log --oneline | head -20",
        "grep -r TODO src/ | wc -l",
        "find . -name '*.py' | xargs grep -n main",
        "git branch -a",
        "git stash list",
        "git remote -v",
        "cd src && ls",
        "echo 'a > b'",  # redirect inside quotes is just a string
        "python3 -v",  # bare version probe
        "env",  # bare env prints the environment
        "env FOO=1 ls",  # env-wrapped allowlisted command
        "env git status",
        "sed -n '1,20p' file",
        "sed -n -e 5p -e 10q file",
        "find . -name '*.py' -type f",
        # Leading VAR=value assignments are inert — same rule as the env branch.
        "FOO=1 git status",
        "CLAUDE_PROJECT_DIR=/x ls",
        "FOO=bar",  # pure assignment executes nothing
    ]

    DENIED_BASH = [
        "git checkout x",
        "echo hi > f",
        "npm test",
        "sed -i s/a/b/ f",
        "python3 -c 'print(1)'",
        "cat f | tee g",
        "$(rm -rf x)",
        "`rm -rf x`",
        "echo `rm -rf x`",
        "ls $(rm -rf x)",
        "git status && rm -rf .",  # every segment must pass
        "ls\nrm -rf x",  # newline is a separator too
        "git push",
        "git branch -D main",
        "git remote add origin url",
        "git stash pop",
        "xargs rm",
        "sed s/a/b/ f",  # sed without -n
        "cat f >> g",
        "ls & rm -rf x",  # background & is not a connector
        "(rm -rf x)",  # subshell parens
        "echo 'unbalanced",  # parse anomaly
        "FOO=bar make",
        "python3",
        "",
        # env runs its trailing command — wrapping must not bypass the allowlist.
        "env rm -rf .",
        "env VAR=1 rm -rf x",
        "env node evil.js",
        "env git push",
        "find . | xargs env rm",
        "env -S 'rm -rf x'",
        # find's mutating/executing primaries.
        "find . -delete",
        "find . -exec rm {} \\;",
        "find . -exec rm -rf {} +",
        "find . -execdir sh -c 'rm -rf .' \\;",
        "find . -ok rm {} \\;",
        # sed writes files via w/W and executes via e, even under -n.
        "sed -n 'w /tmp/pwn' input",
        "sed -n 'e touch /tmp/pwn' /dev/null",
        "sed -n 's/a/b/w out' f",
        "sed -n -f script.sed f",  # script from file is unknowable
        "sed -n '/foo/p' f",  # regex address: conservative false negative
        # Assignment stripping must not weaken the check on the command that follows.
        "PATH=/evil rm -rf x",
        "FOO=1 npm test",
        # Only NAME=value with a valid identifier is an assignment — these are COMMANDS.
        "./build=release.sh",
        "./deploy=prod.sh ls",
        "=foo",
    ]

    def test_bash_allowlist(self):
        for cmd in self.ALLOWED_BASH:
            code, decision = self.gate("Bash", {"command": cmd})
            self.assertEqual((code, decision), (0, None), f"should ALLOW: {cmd!r}")
        for cmd in self.DENIED_BASH:
            reason = self.deny_reason("Bash", {"command": cmd})
            self.assertIn("mission_pause", reason, f"deny for {cmd!r} must name mission_pause")
            self.assertIn("Ship the widget", reason)


class TestEngineBinaryCarveOut(GateTestCase):
    """The daemon declares its own binary in mission-state.json (engine.execPath/.entry);
    the gate realpath-verifies it and passes its read-only verbs — mission_start's own watch
    command must survive lockdown. Anything else about the binary stays denied."""

    def setUp(self):
        super().setUp()
        self.bindir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.bindir, ignore_errors=True)
        self.engine = os.path.join(self.bindir, "medley-engine")
        with open(self.engine, "w") as f:
            f.write("#!/bin/sh\n")
        os.chmod(self.engine, 0o755)

    def assert_bash(self, cmd, expect_allow, env_extra=None):
        code, decision = self.gate("Bash", {"command": cmd}, env_extra)
        expected = (0, None) if expect_allow else (0, "deny")
        self.assertEqual((code, decision), expected,
                         f"should {'ALLOW' if expect_allow else 'DENY'}: {cmd!r}")

    def test_watch_command_as_handed_out_by_mission_start(self):
        # The exact shape orchestrator-mcp.ts builds for a pkg binary.
        self.write_state(engine={"execPath": self.engine})
        self.assert_bash(
            f'MEDLEY_DATA_DIR="/tmp/data" CLAUDE_PROJECT_DIR="{self.repo}" "{self.engine}" watch',
            expect_allow=True,
        )

    def test_engine_readonly_verbs_allowed(self):
        self.write_state(engine={"execPath": self.engine})
        for cmd in (
            f'"{self.engine}" watch',
            f'"{self.engine}" status',
            f'"{self.engine}" service status',
            f'"{self.engine}" service logs',
        ):
            self.assert_bash(cmd, expect_allow=True)

    def test_engine_mutating_or_unknown_verbs_denied(self):
        self.write_state(engine={"execPath": self.engine})
        for cmd in (
            f'"{self.engine}"',  # bare invocation
            f'"{self.engine}" mcp',
            f'"{self.engine}" service stop',
            f'"{self.engine}" service restart',
            f'"{self.engine}" service',
        ):
            self.assert_bash(cmd, expect_allow=False)

    def test_engine_verb_does_not_bless_other_segments(self):
        # The carve-out is per-segment — a connector chain still checks everything.
        self.write_state(engine={"execPath": self.engine})
        self.assert_bash(f'"{self.engine}" watch && npm test', expect_allow=False)
        self.assert_bash(f'"{self.engine}" watch; rm -rf x', expect_allow=False)

    def test_dev_mode_node_entry_form(self):
        # Dev mode: execPath is node itself, entry is the bundle — BOTH must match.
        bundle = os.path.join(self.bindir, "medley-engine.cjs")
        open(bundle, "w").close()
        self.write_state(engine={"execPath": self.engine, "entry": bundle})
        # The exact dev-mode shape orchestrator-mcp.ts hands out (env prefix included).
        self.assert_bash(
            f'MEDLEY_DATA_DIR="" CLAUDE_PROJECT_DIR="{self.repo}" "{self.engine}" "{bundle}" watch',
            expect_allow=True,
        )
        self.assert_bash(f'"{self.engine}" "{bundle}" watch', expect_allow=True)
        self.assert_bash(f'"{self.engine}" "{os.path.join(self.bindir, "other.cjs")}" watch',
                         expect_allow=False)
        self.assert_bash(f'"{self.engine}" watch', expect_allow=False)  # entry missing

    def test_spoofed_binary_denied(self):
        # Same basename, different file — realpath comparison must reject it.
        otherdir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, otherdir, ignore_errors=True)
        impostor = os.path.join(otherdir, "medley-engine")
        open(impostor, "w").close()
        self.write_state(engine={"execPath": self.engine})
        self.assert_bash(f'"{impostor}" watch', expect_allow=False)

    def test_bare_name_resolves_through_path_and_symlink(self):
        # `medley-engine service status` (the deny message's own suggestion) passes when a
        # PATH shim symlinks to the declared binary.
        shimdir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, shimdir, ignore_errors=True)
        os.symlink(self.engine, os.path.join(shimdir, "medley-engine"))
        self.write_state(engine={"execPath": self.engine})
        path = shimdir + os.pathsep + os.environ.get("PATH", "")
        self.assert_bash("medley-engine service status", expect_allow=True,
                         env_extra={"PATH": path})
        self.assert_bash("medley-engine service stop", expect_allow=False,
                         env_extra={"PATH": path})

    def test_no_engine_declared_keeps_denying(self):
        # Old daemon writing no engine field → today's conservative behavior.
        self.write_state()
        self.assert_bash(f'"{self.engine}" watch', expect_allow=False)


if __name__ == "__main__":
    unittest.main()
