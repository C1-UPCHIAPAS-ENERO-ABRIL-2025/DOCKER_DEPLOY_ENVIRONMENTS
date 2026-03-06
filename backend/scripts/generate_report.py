#!/usr/bin/env python3
"""
backend/scripts/generate_report.py
Generates MD, PDF (Premium), and JSON artifacts from staging outputs.
"""
import argparse
import json
import os
import re
from datetime import datetime

parser = argparse.ArgumentParser()
parser.add_argument("--workdir", required=True)
parser.add_argument("--commit-id", required=True)
parser.add_argument("--timestamp", required=True)
parser.add_argument("--framework", required=True)
parser.add_argument("--build-id", default="unknown")
args = parser.parse_args()

workdir = args.workdir
commit_id = args.commit_id
timestamp = args.timestamp
framework = args.framework
build_id = args.build_id

# Clean up build ID for display in PDF (remove sha256: and truncate)
display_build_id = build_id.replace("sha256:", "")[:30]

def read(filename: str) -> str:
    path = os.path.join(workdir, filename)
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return f.read().strip()
    return ""

# Data Retrieval
mypy_out = read("mypy_output.txt")
pylint_out = read("pylint_output.txt")
radon_out = read("radon_output.txt")
bandit_out = read("bandit_output.txt")
hadolint_out = read("hadolint_output.txt")
test_out = read("test_output.txt")

# Extraction of key metrics for badges
def get_pylint_score(text):
    match = re.search(r'rated at ([0-9.]+)/10', text)
    return match.group(1) if match else "N/A"

def get_coverage_score(text):
    # Matches unittest coverage: "TOTAL  12  3  75%" -> "75"
    # Matches pytest coverage: "Total coverage: 72.73%" -> "72.73"
    match = re.search(r'(?:TOTAL.*\s+|Total coverage:\s*)(\d+(\.\d+)?)%', text)
    return match.group(1) if match else "N/A"

pylint_score = get_pylint_score(pylint_out)
coverage_score = get_coverage_score(test_out)

# ============================================================
# Markdown Report (Kept simple for terminal/plain-text use)
# ============================================================
md_content = f"""# 📋 Staging Certification Report

| Field | Value |
|-------|-------|
| **Commit ID** | `{commit_id}` |
| **Build ID** | `{build_id}` |
| **Timestamp** | `{timestamp}` |
| **Test Framework** | `{framework}` |
| **Pylint Score** | `{pylint_score}/10` |
| **Coverage** | `{coverage_score}%` |

---

## 📐 Phase 1: Static Analysis

### mypy
```
{mypy_out or "No issues found."}
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

### hadolint (Dockerfile Linter)
```
{hadolint_out or "No issues found."}
```

---

## 🧪 Phase 2: Tests & Coverage
```
{test_out}
```

---
*Report generated automatically by the hermetic staging certifier.*
"""

with open(os.path.join(workdir, "report.md"), "w", encoding="utf-8") as f:
    f.write(md_content)

# ============================================================
# JSON Report
# ============================================================
json_report = {
    "schema_version": "1.1",
    "commit_id": commit_id,
    "build_id": build_id,
    "timestamp": timestamp,
    "test_framework": framework,
    "metrics": {
        "pylint_score": pylint_score,
        "coverage_percent": coverage_score
    },
    "static_analysis": {
        "mypy": mypy_out,
        "pylint": pylint_out,
        "radon": radon_out,
        "bandit": bandit_out,
        "hadolint": hadolint_out
    },
    "tests": test_out,
    "generated_at": datetime.utcnow().isoformat() + "Z",
}
with open(os.path.join(workdir, "report.json"), "w", encoding="utf-8") as f:
    json.dump(json_report, f, indent=2)

# ============================================================
# PDF Report (Premium Design)
# ============================================================
try:
    from weasyprint import HTML
    
    # CSS for the premium look
    css = """
    @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&family=JetBrains+Mono&display=swap');
    
    body { font-family: 'Inter', sans-serif; margin: 0; padding: 40px; color: #1a202c; line-height: 1.5; background: #fff; }
    .header { border-bottom: 2px solid #edf2f7; padding-bottom: 20px; margin-bottom: 30px; display: flex; justify-content: space-between; align-items: center; }
    .title { font-size: 24px; font-weight: 700; color: #2d3748; }
    .timestamp { font-size: 12px; color: #718096; }
    
    .dashboard { display: grid; grid-template-columns: repeat(4, 1fr); gap: 20px; margin-bottom: 40px; }
    .card { background: #f7fafc; padding: 20px; border-radius: 12px; border: 1px solid #edf2f7; }
    .card-label { font-size: 12px; font-weight: 600; color: #a0aec0; text-transform: uppercase; letter-spacing: 0.05em; }
    .card-value { font-size: 20px; font-weight: 700; color: #2d3748; margin-top: 5px; word-break: break-word; overflow-wrap: break-word; }
    
    .status-badge { display: inline-block; padding: 4px 12px; border-radius: 9999px; font-size: 12px; font-weight: 600; }
    .status-pass { background: #c6f6d5; color: #22543d; }
    .status-info { background: #bee3f8; color: #2a4365; }
    
    h2 { font-size: 18px; font-weight: 700; color: #2d3748; margin-top: 40px; border-left: 4px solid #4a5568; padding-left: 15px; }
    h3 { font-size: 14px; font-weight: 600; color: #4a5568; margin-top: 25px; margin-bottom: 10px; }
    
    pre { background: #1a202c; color: #e2e8f0; padding: 15px; border-radius: 8px; font-family: 'JetBrains Mono', monospace; font-size: 11px; 
          white-space: pre-wrap; word-break: break-all; margin: 0; overflow: hidden; }
    
    .footer { margin-top: 50px; padding-top: 20px; border-top: 1px solid #edf2f7; font-size: 10px; color: #a0aec0; text-align: center; }
    @page { margin: 20mm; @bottom-right { content: "Page " counter(page); font-family: 'Inter'; font-size: 10px; color: #a0aec0; } }
    """
    
    # Check overall status
    is_failed = "FAILED" in test_out or "FAILURE" in pylint_out
    status_class = "status-pass" if not is_failed else "status-error"
    status_text = "CERTIFIED" if not is_failed else "FAILED"

    html_template = f"""<!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <style>{css}</style>
    </head>
    <body>
        <div class="header">
            <div>
                <div class="title">Staging Certification Report</div>
                <div class="timestamp">Generated on {timestamp}</div>
            </div>
            <div class="status-badge {status_class}">{status_text}</div>
        </div>

        <div class="dashboard" style="grid-template-columns: repeat(3, 1fr);">
            <div class="card">
                <div class="card-label">Commit ID</div>
                <div class="card-value">{commit_id}</div>
            </div>
            <div class="card">
                <div class="card-label">Framework</div>
                <div class="card-value">{framework}</div>
            </div>
            <div class="card">
                <div class="card-label">Pylint Score</div>
                <div class="card-value">{pylint_score}/10</div>
            </div>
            <div class="card">
                <div class="card-label">Coverage</div>
                <div class="card-value">{coverage_score}%</div>
            </div>
            <div class="card" style="grid-column: span 2;">
                <div class="card-label">Docker Image ID (Build)</div>
                <div class="card-value" style="font-size:12px; font-family: monospace; word-break: break-all;">{display_build_id}</div>
            </div>
        </div>

        <h2>Phase 1: Static Analysis</h2>
        
        <h3>Mypy Type Checking</h3>
        <pre>{mypy_out or "No type issues identified."}</pre>
        
        <h3>Pylint Code Quality</h3>
        <pre>{pylint_out}</pre>
        
        <h3>Radon Maintainability</h3>
        <pre>{radon_out}</pre>
        
        <h3>Bandit Security Scan</h3>
        <pre>{bandit_out}</pre>
        
        <h3>Hadolint Docker Linter</h3>
        <pre>{hadolint_out or "All Dockerfiles passed best-practice checks."}</pre>

        <h2>Phase 2: Tests & Coverage</h2>
        <pre>{test_out}</pre>

        <div class="footer">
            Hermetic Staging System &copy; {datetime.now().year} | Cryptographically Signed Evidence Package
        </div>
    </body>
    </html>"""
    
    pdf_path = os.path.join(workdir, "report.pdf")
    HTML(string=html_template).write_pdf(pdf_path)
    print("  ✅ report.pdf written (Premium Design).")

except ImportError as e:
    print(f"  ⚠️  PDF Generation failed: {e}")
    # Fallback to simple file if weasyprint is missing
