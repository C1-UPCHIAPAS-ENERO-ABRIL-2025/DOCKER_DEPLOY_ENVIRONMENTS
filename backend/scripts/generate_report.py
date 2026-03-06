#!/usr/bin/env python3
"""
backend/scripts/generate_report.py
Generates MD, PDF, and JSON artifacts from staging outputs.
Lives in backend/scripts/ so it is accessible inside the container
at /app/scripts/generate_report.py (volume: ./backend:/app:ro).
"""
import argparse
import json
import os
from datetime import datetime

parser = argparse.ArgumentParser()
parser.add_argument("--workdir", required=True)
parser.add_argument("--commit-id", required=True)
parser.add_argument("--timestamp", required=True)
parser.add_argument("--framework", required=True)
args = parser.parse_args()

workdir = args.workdir
commit_id = args.commit_id
timestamp = args.timestamp
framework = args.framework


def read(filename: str) -> str:
    """Read a file from the workdir, return empty string if missing."""
    path = os.path.join(workdir, filename)
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return f.read()
    return "*File not found*"


mypy_out = read("mypy_output.txt")
pylint_out = read("pylint_output.txt")
radon_out = read("radon_output.txt")
bandit_out = read("bandit_output.txt")
test_out = read("test_output.txt")

# ============================================================
# Markdown Report
# ============================================================
md_content = f"""# 📋 Staging Certification Report

| Field | Value |
|-------|-------|
| **Commit ID** | `{commit_id}` |
| **Timestamp** | `{timestamp}` |
| **Test Framework** | `{framework}` |

---

## 📐 Phase 1: Static Analysis

### mypy
```
{mypy_out}
```

### pylint
```
{pylint_out}
```

### radon (Maintainability Index)
```
{radon_out}
```

### bandit (Security Scan)
```
{bandit_out}
```

---

## 🧪 Phase 2: Tests & Coverage
```
{test_out}
```

---
*Report generated automatically by the hermetic staging certifier.*
"""

md_path = os.path.join(workdir, "report.md")
with open(md_path, "w", encoding="utf-8") as f:
    f.write(md_content)
print("  ✅ report.md written.")

# ============================================================
# JSON Report
# ============================================================
json_report = {
    "schema_version": "1.0",
    "commit_id": commit_id,
    "timestamp": timestamp,
    "test_framework": framework,
    "static_analysis": {
        "mypy": mypy_out,
        "pylint": pylint_out,
        "radon": radon_out,
        "bandit": bandit_out,
    },
    "tests": test_out,
    "generated_at": datetime.utcnow().isoformat() + "Z",
}
json_path = os.path.join(workdir, "report.json")
with open(json_path, "w", encoding="utf-8") as f:
    json.dump(json_report, f, indent=2)
print("  ✅ report.json written.")

# ============================================================
# PDF Report via weasyprint
# ============================================================
try:
    from weasyprint import HTML  # type: ignore

    simple_html = f"""<!DOCTYPE html>
<html><head>
<meta charset="utf-8"/>
<style>
  body {{ font-family: monospace; margin: 2rem; font-size: 10px; }}
  h1 {{ color: #6c63ff; }} h2 {{ color: #445; }}
  pre {{ background: #f5f5f5; padding: 0.5rem; border-radius: 4px;
        overflow-wrap: break-word; white-space: pre-wrap; }}
  table {{ border-collapse: collapse; }}
  td, th {{ border: 1px solid #ccc; padding: 0.3rem 0.6rem; }}
</style></head><body>
<pre>{md_content}</pre>
</body></html>"""
    pdf_path = os.path.join(workdir, "report.pdf")
    HTML(string=simple_html).write_pdf(pdf_path)
    print("  ✅ report.pdf written.")
except ImportError:
    pdf_path = os.path.join(workdir, "report.pdf")
    with open(pdf_path, "w", encoding="utf-8") as f:
        f.write("[PDF unavailable — weasyprint not installed]\n")
    print("  ⚠️  report.pdf: weasyprint not available, stub created.")
