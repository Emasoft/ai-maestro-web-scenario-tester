#!/usr/bin/env python3
"""amwst-validate-scenario — lint a .scen.md for the web-scenario-tester DSL (TRDD-74ZS7P9U req 7).

Checks the frontmatter has the required keys, the body has phases + sequential
`#### S<NNN>` steps, and every step carries Action/Goal/Verify. Prints errors-only
(+ warnings) with a count and mirrors a CI gate via exit code: non-zero on any
error; warnings are non-fatal unless --strict (which promotes warnings to errors).
Stdlib only — no PyYAML dependency, so the plugin ships with zero extra deps.

Usage:
  amwst-validate-scenario.py <file.scen.md> [--strict]
"""
import re
import sys

REQUIRED_FM = ["number", "name", "version", "description", "client", "browser_stack"]
RECOMMENDED_FM = ["device", "subsystems", "ui_sections", "prerequisites", "rewipe-list"]
STEP_REQUIRED = ["Action", "Goal", "Verify"]
STEP_RECOMMENDED = ["Creates", "Modifies"]


def validate(text):
    errors = []   # (line_or_None, msg)
    warns = []
    lines = text.splitlines()

    # ── frontmatter ──
    fm_end = 0
    if not lines or lines[0].strip() != "---":
        errors.append((1, "missing YAML frontmatter (file must start with '---')"))
    else:
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                fm_end = i
                break
        if not fm_end:
            errors.append((1, "frontmatter not closed (no second '---')"))
        fm_keys, version_val = set(), None
        for i in range(1, fm_end or 1):
            m = re.match(r"^([A-Za-z0-9_-]+):(.*)$", lines[i])
            if m:
                fm_keys.add(m.group(1))
                if m.group(1) == "version":
                    version_val = m.group(2).strip()
        for k in REQUIRED_FM:
            if k not in fm_keys:
                errors.append((None, f"frontmatter missing required key: {k}"))
        for k in RECOMMENDED_FM:
            if k not in fm_keys:
                warns.append((None, f"frontmatter missing recommended key: {k}"))
        if version_val is not None and not version_val.startswith(('"', "'")):
            warns.append((None, 'version should be quoted (e.g. version: "1.0")'))

    body = lines[fm_end + 1:] if fm_end else lines
    body_off = fm_end + 1 if fm_end else 0

    # ── phases ──
    phases = [p[3:].strip() for p in body if re.match(r"^## ", p)]
    if not phases:
        errors.append((None, "no phases (no '## ' headings) found"))
    else:
        joined = " ".join(p.upper() for p in phases)
        if "SAFE-SETUP" not in joined and "PHASE 0" not in joined:
            warns.append((None, "no SAFE-SETUP phase (Phase 0) found"))
        if "CLEANUP" not in joined:
            warns.append((None, "no CLEANUP phase found"))

    # ── steps ──
    step_hdr = re.compile(r"^#### (S\d+)\b")
    step_ids, blocks, cur = [], {}, None
    for i, ln in enumerate(body):
        m = step_hdr.match(ln)
        if m:
            cur = m.group(1)
            if cur in blocks:
                errors.append((body_off + i + 1, f"duplicate step id {cur}"))
            blocks[cur] = (body_off + i + 1, [])
            step_ids.append(cur)
        elif re.match(r"^#{1,3} ", ln):
            cur = None   # a phase/section heading ends the current step block
        elif cur:
            blocks[cur][1].append(ln)

    if not step_ids:
        errors.append((None, "no steps (no '#### S<NNN>' headers) found"))

    nums = [int(s[1:]) for s in step_ids]
    for idx, n in enumerate(nums):
        if idx == 0 and n != 1:
            warns.append((None, f"first step is S{n:03d}, expected S001"))
        if idx > 0:
            if n <= nums[idx - 1]:
                errors.append((None, f"step numbering not increasing: S{nums[idx-1]:03d} then S{n:03d}"))
            elif n != nums[idx - 1] + 1:
                warns.append((None, f"gap in step numbering: S{nums[idx-1]:03d} -> S{n:03d}"))

    for sid, (ln, blk) in blocks.items():
        joined = "\n".join(blk)
        for field in STEP_REQUIRED:
            if f"**{field}:**" not in joined:
                errors.append((ln, f"step {sid} missing **{field}:**"))
        # Cleanup-style steps use **Removes:** in place of Creates/Modifies — don't nag those.
        if "**Removes:**" not in joined:
            for field in STEP_RECOMMENDED:
                if f"**{field}:**" not in joined:
                    warns.append((ln, f"step {sid} missing **{field}:** (recommended)"))

    return errors, warns


def main():
    args = sys.argv[1:]
    strict = "--strict" in args
    paths = [a for a in args if not a.startswith("--")]
    if not paths:
        print(__doc__)
        return 2
    path = paths[0]
    try:
        with open(path, "r", errors="replace") as fh:
            text = fh.read()
    except OSError as e:
        print(f"VALIDATE: cannot read {path}: {e}")
        return 2
    errors, warns = validate(text)
    if strict:
        errors, warns = errors + warns, []
    print(f"VALIDATE {path}: {len(errors)} error{'' if len(errors) == 1 else 's'}, "
          f"{len(warns)} warning{'' if len(warns) == 1 else 's'}")
    for ln, msg in errors:
        print(f"  ERROR{(':' + str(ln)) if ln else ''}  {msg}")
    for ln, msg in warns:
        print(f"  WARN{(':' + str(ln)) if ln else ''}  {msg}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
