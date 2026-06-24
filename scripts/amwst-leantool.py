#!/usr/bin/env python3
"""amwst-leantool — run tsc / eslint / vitest / pytest / log and emit ERRORS ONLY.

Raw tool output is mostly noise the agent doesn't need (progress, "no issues"
lines, passed-test lists, banners) — and it rides forward in the transcript
every turn. This wrapper runs the tool and prints a compact, greppable summary:
a count line + one line per real problem (file:line:col  CODE message). Nothing
else. On a clean run it prints just "TSC: 0 errors" etc.

Stdlib only (subprocess, json, re) — run with `python3 amwst-leantool.py <sub> ...`.
Exit code mirrors the underlying tool (non-zero on any error) so it is CI-safe.

NEVER swallow a real failure: if structured parsing is uncertain, it falls back
to passing through the tool's own error-ish lines.

Subcommands:
  tsc     [extra tsc args]      -> npx tsc --noEmit --pretty false
  eslint  [paths...]            -> npx eslint -f json (defaults to ".")
  vitest  [extra vitest args]   -> npx vitest run --reporter=json
  pytest  [extra pytest args]   -> python3 -m pytest -q -rf --tb=line (failures only)
  log     <path> [--tail N] [--pattern RE]  -> error/fail/exception lines only, never the whole log
  selftest                      -> parse synthetic fixtures, assert lean output
"""
import json
import re
import subprocess
import sys

# ───────────────────────── pure parsers (testable) ─────────────────────────

_TSC_RE = re.compile(r"^(?P<file>.+?)\((?P<line>\d+),(?P<col>\d+)\):\s+error\s+(?P<code>TS\d+):\s+(?P<msg>.*)$")

def parse_tsc(text):
    """tsc --pretty false lines -> (count, [lines]). Faithful: counts every 'error TSxxxx'."""
    out = []
    for ln in text.splitlines():
        m = _TSC_RE.match(ln.strip())
        if m:
            out.append(f"  {m['file']}:{m['line']}:{m['col']}  {m['code']} {m['msg']}")
    # Faithful count cross-check: tsc prints "Found N errors" — trust the line regex,
    # but if a "Found N errors" total disagrees, surface the larger (never under-report).
    total = len(out)
    mtot = re.search(r"Found (\d+) error", text)
    if mtot and int(mtot.group(1)) > total:
        out.append(f"  (tsc reported {mtot.group(1)} errors; {total} were line-parsed — see raw output)")
        total = int(mtot.group(1))
    return total, out

def parse_eslint(text):
    """eslint -f json -> (errors, warnings, [lines])."""
    data = json.loads(text)  # raises if not JSON -> caller falls back
    errs = warns = 0
    out = []
    for f in data:
        path = f.get("filePath", "?")
        for m in f.get("messages", []):
            sev = m.get("severity")
            rule = m.get("ruleId") or "(core)"
            line = m.get("line", "?")
            col = m.get("column", "?")
            msg = (m.get("message") or "").strip()
            if sev == 2:
                errs += 1
                out.append(f"  {path}:{line}:{col}  {rule} {msg}")
            elif sev == 1:
                warns += 1
                out.append(f"  {path}:{line}:{col}  [warn] {rule} {msg}")
    return errs, warns, out

def parse_vitest(text):
    """vitest --reporter=json -> (failed, passed, [lines]). Failures only."""
    data = json.loads(text)
    failed = data.get("numFailedTests", 0)
    passed = data.get("numPassedTests", 0)
    out = []
    for f in data.get("testResults", []):
        fname = f.get("name", "?")
        for a in f.get("assertionResults", []):
            if a.get("status") == "failed":
                title = " > ".join(a.get("ancestorTitles", []) + [a.get("title", "?")])
                fm = " ".join((a.get("failureMessages") or []))
                fm = re.sub(r"\s+", " ", fm).strip()[:160]
                out.append(f"  {fname} > {title}  {fm}")
    return failed, passed, out

# pytest -q -rf --tb=line emits "FAILED nodeid - msg" / "ERROR nodeid - msg" short-summary lines.
_PYTEST_RE = re.compile(r"^(?:FAILED|ERROR)\s+(?P<node>\S+)\s*(?:-\s*(?P<msg>.*))?$")

def parse_pytest(text):
    """pytest short-summary -> (failed, passed, [lines]). Failures/errors only."""
    out = []
    for ln in text.splitlines():
        m = _PYTEST_RE.match(ln.strip())
        if m:
            msg = re.sub(r"\s+", " ", (m["msg"] or "")).strip()[:160]
            out.append(f"  {m['node']}  {msg}".rstrip())
    msum = re.search(r"(\d+) failed", text)
    psum = re.search(r"(\d+) passed", text)
    # Never under-report: if the summary line claims more failures than parsed, trust the summary.
    failed = max(int(msum.group(1)) if msum else 0, len(out))
    passed = int(psum.group(1)) if psum else 0
    return failed, passed, out

# Default log signal: the substrings that actually mean "something went wrong".
_LOG_RE = re.compile(
    r"\berror\b|\bfail(?:ed|ure)?\b|\bexception\b|\bfatal\b|\bpanic\b|"
    r"\bunhandled\b|traceback|\bECONN|\bEADDR|\bEPERM\b|\b5\d\d\b",
    re.I,
)

def parse_log(text, pattern=None, tail=40):
    """Log text -> (count, [last `tail` matching lines], omitted). ONLY matching lines — never the whole log."""
    rx = re.compile(pattern, re.I) if pattern else _LOG_RE
    matches = [ln.rstrip() for ln in text.splitlines() if rx.search(ln)]
    count = len(matches)
    shown = matches[-tail:] if (tail and count > tail) else matches
    return count, shown, count - len(shown)

# ───────────────────────── runners ─────────────────────────

def _run(cmd):
    p = subprocess.run(cmd, capture_output=True, text=True)
    return p.returncode, (p.stdout or ""), (p.stderr or "")

def _fallback(label, rc, stdout, stderr):
    """Never swallow: print error-ish lines from the raw output."""
    print(f"{label}: parse fallback (exit {rc}) — raw error lines:")
    seen = 0
    for ln in (stdout + "\n" + stderr).splitlines():
        if re.search(r"\berror\b|\bfailed\b|\bFAIL\b|Error:", ln, re.I):
            print("  " + ln.strip())
            seen += 1
            if seen >= 200:
                print("  …(truncated at 200)")
                break
    if seen == 0:
        print("  (no error-ish lines found in raw output)")

def cmd_tsc(args):
    rc, out, err = _run(["npx", "tsc", "--noEmit", "--pretty", "false", *args])
    text = out + "\n" + err
    try:
        n, lines = parse_tsc(text)
        print(f"TSC: {n} error{'' if n == 1 else 's'}")
        for ln in lines:
            print(ln)
    except Exception:
        _fallback("TSC", rc, out, err)
    return rc

def cmd_eslint(args):
    paths = args or ["."]
    rc, out, err = _run(["npx", "eslint", "-f", "json", *paths])
    try:
        e, w, lines = parse_eslint(out)
        print(f"ESLINT: {e} error{'' if e == 1 else 's'}, {w} warning{'' if w == 1 else 's'}")
        for ln in lines:
            print(ln)
    except Exception:
        _fallback("ESLINT", rc, out, err)
    return rc

def cmd_vitest(args):
    rc, out, err = _run(["npx", "vitest", "run", "--reporter=json", *args])
    try:
        f, p, lines = parse_vitest(out)
        print(f"VITEST: {f} failed / {p} passed")
        for ln in lines:
            print(ln)
    except Exception:
        _fallback("VITEST", rc, out, err)
    return rc

def cmd_pytest(args):
    rc, out, err = _run(["python3", "-m", "pytest", "-q", "-rf", "--tb=line", *args])
    text = out + "\n" + err
    try:
        f, p, lines = parse_pytest(text)
        print(f"PYTEST: {f} failed / {p} passed")
        for ln in lines:
            print(ln)
    except Exception:
        _fallback("PYTEST", rc, out, err)
    return rc

def cmd_log(args):
    """Print ONLY the error/fail/exception lines of a log — never the whole file (L9, technique 7)."""
    path = None
    tail = 40
    pattern = None
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--tail" and i + 1 < len(args):
            tail = int(args[i + 1])
            i += 2
        elif a == "--pattern" and i + 1 < len(args):
            pattern = args[i + 1]
            i += 2
        else:
            path = a
            i += 1
    if not path:
        print("usage: leantool.py log <path> [--tail N] [--pattern REGEX]")
        return 2
    try:
        with open(path, "r", errors="replace") as fh:
            text = fh.read()
    except OSError as e:
        print(f"LOG: cannot read {path}: {e}")
        return 2
    count, shown, omitted = parse_log(text, pattern, tail)
    suffix = f" (last {len(shown)}; {omitted} earlier matches omitted)" if omitted else ""
    print(f"LOG {path}: {count} matching line{'' if count == 1 else 's'}{suffix}")
    for ln in shown:
        print("  " + ln)
    return 0  # extraction succeeded; the count line is the signal (a log is not a pass/fail gate)

# ───────────────────────── selftest ─────────────────────────

def selftest():
    ok = True
    n, lines = parse_tsc(
        "services/foo.ts(42,7): error TS2322: Type 'X' is not assignable to 'Y'.\n"
        "components/Bar.tsx(10,3): error TS2304: Cannot find name 'baz'.\n"
        "src/clean.ts: no errors here, ignore me\n"
        "Found 2 errors in 2 files.\n"
    )
    if n != 2 or "TS2322" not in lines[0] or "TS2304" not in lines[1]:
        print("FAIL tsc parse:", n, lines)
        ok = False

    e, w, lines = parse_eslint(json.dumps([
        {"filePath": "app/page.tsx", "messages": [
            {"severity": 2, "ruleId": "no-unused-vars", "line": 5, "column": 1, "message": "'foo' is defined but never used"},
            {"severity": 1, "ruleId": "eqeqeq", "line": 9, "column": 4, "message": "Expected ==="},
        ]},
        {"filePath": "lib/ok.ts", "messages": []},
    ]))
    if e != 1 or w != 1 or "no-unused-vars" not in lines[0]:
        print("FAIL eslint parse:", e, w, lines)
        ok = False

    f, p, lines = parse_vitest(json.dumps({
        "numFailedTests": 1, "numPassedTests": 12,
        "testResults": [{"name": "tests/x.test.ts", "assertionResults": [
            {"status": "passed", "title": "a", "ancestorTitles": []},
            {"status": "failed", "title": "rejects empty token", "ancestorTitles": ["auth"], "failureMessages": ["expected 401, got 200"]},
        ]}],
    }))
    if f != 1 or p != 12 or "rejects empty token" not in lines[0]:
        print("FAIL vitest parse:", f, p, lines)
        ok = False

    pf, pp, lines = parse_pytest(
        "FAILED tests/test_auth.py::test_rejects_empty_token - AssertionError: expected 401\n"
        "ERROR tests/test_db.py::test_conn - fixture 'pg' not found\n"
        "tests/test_ok.py::test_passes PASSED\n"
        "=== 1 failed, 1 error, 12 passed in 0.4s ===\n"
    )
    if pf < 2 or pp != 12 or "test_rejects_empty_token" not in lines[0]:
        print("FAIL pytest parse:", pf, pp, lines)
        ok = False

    lc, lshown, lomit = parse_log(
        "INFO server started on :23000\n"
        "GET /api/sessions 200 ok\n"
        "ERROR failed to bind pty: EADDRINUSE\n"
        "WARN slow query\n"
        "Unhandled exception in worker: TypeError\n",
        tail=40,
    )
    if lc != 2 or lomit != 0 or "EADDRINUSE" not in lshown[0]:
        print("FAIL log parse:", lc, lshown, lomit)
        ok = False

    print("SELFTEST: PASS" if ok else "SELFTEST: FAIL")
    return 0 if ok else 1

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    sub, rest = sys.argv[1], sys.argv[2:]
    if sub == "selftest":
        return selftest()
    handler = {"tsc": cmd_tsc, "eslint": cmd_eslint, "vitest": cmd_vitest,
               "pytest": cmd_pytest, "log": cmd_log}.get(sub)
    if handler is None:
        print(f"unknown subcommand: {sub}")
        return 2
    return handler(rest)

if __name__ == "__main__":
    sys.exit(main())
