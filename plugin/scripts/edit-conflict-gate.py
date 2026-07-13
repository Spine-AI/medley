#!/usr/bin/env python3
# PreToolUse gate (Edit|Write|MultiEdit|NotebookEdit|Task|Bash) with two modes:
#
# 1. LOCKDOWN — while an orchestrated Medley mission is live, the daemon writes
#    .medley/mission-state.json with {"lockdown": true, ...}. The repo becomes read-only
#    for the HOST session: subagents (Task) are denied, edits inside the repo are denied,
#    and Bash is allowed only when every command segment is read-only. Every denial
#    repeats (no warn-once) and names the escape hatch: mission_pause.
# 2. Otherwise (no state file / lockdown:false / stale daemon pid) — the original
#    per-file behavior: warn ONCE before the host edits a file a running worker owns
#    (from .medley/active-work.json); the same edit goes through on retry.
#
# Stdlib only, fast, never invokes the engine. No JSON output = allow.
import sys, json, os, hashlib, pathlib, re, shlex

# Workers inherit the plugin (settingSources) and edit exactly the files listed in
# active-work.json — their OWN files. The gate is for the HOST session only.
if os.environ.get("MEDLEY_WORKER") == "1":
    sys.exit(0)

try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(0)

if payload.get("hook_event_name") != "PreToolUse":
    sys.exit(0)

EDIT_TOOLS = ("Edit", "Write", "MultiEdit", "NotebookEdit")
tool_name = payload.get("tool_name")
if tool_name not in EDIT_TOOLS + ("Task", "Bash"):
    sys.exit(0)

tool_input = payload.get("tool_input") or {}
project = payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()


def deny(reason: str) -> None:
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": reason,
                }
            }
        )
    )
    sys.exit(0)


# ---------------------------------------------------------------------------
# Lockdown mode: .medley/mission-state.json (written atomically by the daemon)
# ---------------------------------------------------------------------------


def load_lockdown_state(root: str):
    """Return the mission-state dict iff lockdown is live; None → fall through."""
    path = os.path.join(root, ".medley", "mission-state.json")
    try:
        with open(path) as f:
            state = json.load(f)
    except Exception:
        return None
    if not isinstance(state, dict) or state.get("lockdown") is not True:
        return None
    # Stale after a daemon SIGKILL: the file carries the daemon pid so we can
    # liveness-check it. A dead pid means the lockdown no longer applies.
    pid = state.get("pid")
    if isinstance(pid, int) and pid > 0:
        try:
            os.kill(pid, 0)  # signal 0 = existence probe
        except PermissionError:
            pass  # exists, owned by someone else — still alive
        except Exception:
            return None  # dead (or unprobeable) daemon → stale file
    return state


# --- Bash read-only allowlist ---------------------------------------------
# A command passes iff EVERY segment (split on && || ; | and newlines) starts with a
# read-only token. Any parse anomaly, redirect, subshell, or backtick → deny.
# False negatives are accepted; every denial names mission_pause.

SIMPLE_READONLY = {
    "ls", "cat", "head", "tail", "wc", "grep", "rg", "fd", "tree", "pwd",
    "echo", "printf", "which", "file", "stat", "du", "df", "ps", "date",
    "sort", "uniq", "cut", "tr",
}
# NOT in SIMPLE_READONLY (handled specially in segment_is_readonly):
#   env  — `env [VAR=x…] CMD` EXECUTES CMD; only bare env / env-wrapped-allowlisted passes.
#   find — has mutating/executing primaries (-delete, -exec, …).
#   sed  — `w`/`W` write files and GNU `e` executes, regardless of -n.
GIT_READONLY_SUBS = {
    "status", "diff", "log", "show", "blame", "rev-parse", "ls-files",
    "describe", "shortlog", "grep",
}
# find primaries that mutate the tree or execute commands — deny any find carrying one.
FIND_MUTATING = {
    "-delete", "-exec", "-execdir", "-ok", "-okdir",
    "-fprint", "-fprintf", "-fprint0", "-fls",
}
# sed scripts are WHITELISTED, not blacklisted: numeric/$ addresses + print-only commands
# (p d q n =). Regex-address forms like /foo/p are conservatively denied — false negatives
# are accepted; `sed -n 'w file'` writes and `sed -n 'e cmd'` executes even under -n.
SED_SAFE_SCRIPT = re.compile(r"[0-9,$;=pdqn!\s]*\Z")
CONNECTORS = {"&&", "||", ";", "|"}
PUNCT_CHARS = set("();<>|&")


def segment_is_readonly(tokens) -> bool:
    if not tokens:
        return False
    head, rest = tokens[0], tokens[1:]
    # '<bin> --version' / '<bin> -v' probes are harmless for any binary.
    if len(tokens) == 2 and rest[0] in ("--version", "-v"):
        return True
    if head in SIMPLE_READONLY or head == "cd":
        return True
    if head == "env":
        # env executes its trailing COMMAND — allow bare `env` (prints the environment) or an
        # env-wrapped command that is itself allowlisted. Any env flag is denied (-S can
        # smuggle a whole command line inside one token).
        body = list(rest)
        while body and "=" in body[0] and not body[0].startswith("-"):
            body.pop(0)  # leading VAR=value assignments are inert
        if not body:
            return True
        if body[0].startswith("-"):
            return False
        return segment_is_readonly(body)
    if head == "find":
        # find is read-only only without its mutating/executing primaries.
        return not any(t in FIND_MUTATING for t in rest)
    if head == "sed":
        # Print-only sed: -n, NO other flags (-i in-place, -f script-file, -E/-s/…), and every
        # script (from -e/--expression, else the first positional) drawn from the safe
        # print-only grammar — `w`/`W` write files and `e` executes even under -n.
        has_n = False
        scripts, positional = [], []
        i = 0
        while i < len(rest):
            t = rest[i]
            if t in ("-n", "--quiet", "--silent"):
                has_n = True
            elif t in ("-e", "--expression"):
                if i + 1 >= len(rest):
                    return False
                scripts.append(rest[i + 1])
                i += 1
            elif t.startswith("--expression="):
                scripts.append(t.split("=", 1)[1])
            elif t.startswith("-"):
                return False
            else:
                positional.append(t)
            i += 1
        if not scripts:
            if not positional:
                return False
            scripts.append(positional[0])
        return has_n and all(SED_SAFE_SCRIPT.match(s) for s in scripts)
    if head == "xargs":
        # Only when the command xargs itself runs is allowlisted.
        return segment_is_readonly(rest)
    if head == "git":
        if not rest:
            return False
        sub, args = rest[0], rest[1:]
        if sub in GIT_READONLY_SUBS:
            return True
        if sub == "remote":
            return args == ["-v"]
        if sub == "stash":
            return args[:1] == ["list"]
        if sub == "branch":
            return all(a in ("-a", "-v") for a in args)
        return False
    return False


def command_is_readonly(cmd: str) -> bool:
    if not isinstance(cmd, str) or not cmd.strip():
        return False
    # Command substitution can hide anything; deny even inside quotes.
    if "`" in cmd or "$(" in cmd:
        return False
    # Newlines separate commands like ';' does, but shlex eats them as whitespace.
    cmd = cmd.replace("\r", ";").replace("\n", ";")
    try:
        lex = shlex.shlex(cmd, posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        tokens = list(lex)
    except ValueError:
        return False  # unbalanced quotes etc. → parse anomaly
    segments, cur = [], []
    for tok in tokens:
        if tok and all(c in PUNCT_CHARS for c in tok):
            if tok in CONNECTORS:
                segments.append(cur)
                cur = []
            else:
                return False  # unquoted > >> < & ( ) … → deny
        else:
            cur.append(tok)
    segments.append(cur)
    if segments and segments[-1] == []:
        segments.pop()  # trailing ';' is fine
    if not segments or any(not s for s in segments):
        return False  # empty command or dangling connector → parse anomaly
    return all(segment_is_readonly(s) for s in segments)


state = load_lockdown_state(project)
if state is not None:
    mission = state.get("mission") or {}
    title = mission.get("title") or "unknown mission"
    if tool_name == "Task":
        deny(
            f'STOP: Medley mission "{title}" is running — workers are the execution '
            "layer; the host session must not spawn subagents for mission work. Use "
            "task_steer to redirect a worker or mission_plan_submit to add tasks; "
            "mission_pause reclaims the repo for direct work."
        )
    if tool_name in EDIT_TOOLS:
        file_path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
        if not file_path:
            sys.exit(0)
        root = os.path.realpath(project)
        target = os.path.realpath(os.path.join(project, file_path))
        if target == root or target.startswith(root + os.sep):
            deny(
                f'STOP: Medley mission "{title}" is running — the repo is read-only '
                "for the host session while workers execute. Use task_steer to "
                "redirect a worker, mission_plan_submit to add tasks, or "
                "mission_pause to reclaim the repo; mission_stop cancels the mission."
            )
        sys.exit(0)  # outside the repo (scratchpads, ~/.claude plans) → allow
    if tool_name == "Bash":
        cmd = tool_input.get("command") or ""
        if command_is_readonly(cmd):
            sys.exit(0)
        deny(
            f'STOP: Medley mission "{title}" is running — only read-only commands '
            "may run in the repo (reads, read-only git). This command could mutate "
            "the workers' tree. mission_pause reclaims the repo for direct work. If "
            "no mission is actually running (stale state), check with "
            "`medley-engine service status` or delete .medley/mission-state.json."
        )
    sys.exit(0)

# ---------------------------------------------------------------------------
# Fallthrough: original per-file warn-once gate (edit tools only)
# ---------------------------------------------------------------------------

if tool_name not in EDIT_TOOLS:
    sys.exit(0)

file_path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
if not file_path:
    sys.exit(0)

work_file = os.path.join(project, ".medley", "active-work.json")
if not os.path.exists(work_file):
    sys.exit(0)

try:
    with open(work_file) as f:
        work = json.load(f)
except Exception:
    sys.exit(0)


def rel(p: str) -> str:
    p = os.path.normpath(p)
    root = os.path.normpath(project).rstrip("/")
    return p[len(root) + 1 :] if p.startswith(root + "/") else p


target = rel(file_path)
hit = None
for task in work.get("tasks", []):
    if any(rel(f) == target for f in task.get("files", [])):
        hit = task
        break
if hit is None:
    sys.exit(0)

# Warn-once per (session, task, file): a marker in the session temp dir.
session = payload.get("session_id", "nosession")
marker_dir = pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / f"medley-warned-{session}"
marker_dir.mkdir(parents=True, exist_ok=True)
marker = marker_dir / hashlib.sha256(f"{hit.get('taskId')}:{target}".encode()).hexdigest()[:16]
if marker.exists():
    sys.exit(0)
marker.touch()

deny(
    f'STOP: a running Medley task is changing this file right now — "{hit.get("title")}" '
    f'(mission "{hit.get("mission")}") has touched {target}. Editing it under a live worker '
    "can clobber its work. Tell the user about the overlap and get their explicit OK before "
    "retrying; once they agree, the same edit will go through."
)
