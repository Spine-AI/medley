#!/usr/bin/env python3
# PreToolUse gate (Edit|Write): warn ONCE before the host session edits a file a running
# Medley worker owns. Reads .medley/active-work.json (maintained by the engine); denies
# the first touch of a claimed file with an explanation — the same edit goes through on
# retry after the user's OK. No JSON output = allow.
import sys, json, os, hashlib, pathlib

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
if payload.get("tool_name") not in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
    sys.exit(0)

tool_input = payload.get("tool_input") or {}
file_path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
if not file_path:
    sys.exit(0)

project = payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
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

print(
    json.dumps(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": (
                    f'STOP: a running Medley task is changing this file right now — "{hit.get("title")}" '
                    f'(mission "{hit.get("mission")}") has touched {target}. Editing it under a live worker '
                    "can clobber its work. Tell the user about the overlap and get their explicit OK before "
                    "retrying; once they agree, the same edit will go through."
                ),
            }
        }
    )
)
