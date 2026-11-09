from pathlib import Path
import subprocess

ROOT = Path(__file__).parent
PAIRS = [
    ("scripts/paper_ui.gd", "paper_ui.candidate.gd"),
    ("scripts/paper_annotations.gd", "paper_annotations.candidate.gd"),
    ("scripts/paper_ink.gd", "paper_ink.candidate.gd"),
    ("scripts/school_session.gd", "school_session.candidate.gd"),
    ("scripts/notebook_store.gd", "notebook_store.candidate.gd"),
    ("scripts/ui/paper_workspace/tools/case.gd", "case.candidate.gd"),
]
patch = b""
for source, candidate in PAIRS:
    result = subprocess.run(
        ["git", "diff", "--no-index", "--", source, str(ROOT / candidate)],
        capture_output=True,
    )
    content = result.stdout.decode("utf-8")
    lines = content.splitlines()
    for i, line in enumerate(lines):
        if line.startswith("diff --git "):
            lines[i] = f"diff --git a/{source} b/{source}"
        elif line.startswith("+++ "):
            lines[i] = f"+++ b/{source}"
    patch += ("\n".join(lines) + "\n").encode("utf-8")
(ROOT / "patches" / "workspace_assembly.patch").write_bytes(patch)
