#!/usr/bin/env python3
"""Extract Lua blocks from .cea files and run selene on them.

CE .cea files are Auto Assembler scripts with embedded Lua:
    [ENABLE]
    {$lua}
    -- lua code here
    {$asm}
    [DISABLE]
    ...

This script extracts the Lua portions, writes them to a temp file,
runs selene, then maps line numbers back to the original .cea file.
"""

import sys
import os
import re
import subprocess
import tempfile


def extract_lua_blocks(cea_path):
    """Extract Lua code blocks from a .cea file.

    Returns list of (start_line, lua_code) tuples where start_line
    is the 1-based line number in the original file where the block starts.
    """
    blocks = []
    with open(cea_path, "r", encoding="utf-8", errors="replace") as f:
        lines = f.readlines()

    in_lua = False
    block_start = 0
    block_lines = []

    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped == "{$lua}":
            in_lua = True
            block_start = i + 2  # next line (1-based)
            block_lines = []
        elif in_lua and stripped in ("{$asm}", "[DISABLE]", "[ENABLE]"):
            if block_lines:
                blocks.append((block_start, "".join(block_lines)))
            in_lua = False
            block_lines = []
        elif in_lua:
            block_lines.append(line)

    # Handle block that runs to end of file (no closing {$asm})
    if in_lua and block_lines:
        blocks.append((block_start, "".join(block_lines)))

    return blocks


def lint_file(cea_path, selene_path="selene", selene_args=None):
    """Lint a .cea file by extracting Lua blocks and running selene.

    Returns (has_issues, output_text).
    """
    blocks = extract_lua_blocks(cea_path)
    if not blocks:
        return False, ""

    # Combine all blocks with line-number padding so selene reports
    # correct line numbers relative to the original file
    all_output = []
    has_issues = False

    for block_start, lua_code in blocks:
        # Write to temp file with padding lines so selene line numbers
        # match the original file
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".lua", delete=False, encoding="utf-8"
        ) as tmp:
            # Pad with empty lines so line N in temp = line N in original
            tmp.write("\n" * (block_start - 1))
            tmp.write(lua_code)
            tmp_path = tmp.name

        try:
            cmd = [selene_path] + (selene_args or []) + [tmp_path]
            result = subprocess.run(
                cmd, capture_output=True, text=True,
                cwd=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            )
            if result.returncode != 0:
                has_issues = True
                # Replace temp path with original .cea path in output
                output = (result.stderr or result.stdout)
                output = output.replace(tmp_path, cea_path)
                # Also handle forward-slash variant
                output = output.replace(
                    tmp_path.replace("\\", "/"), cea_path
                )
                all_output.append(output)
        finally:
            os.unlink(tmp_path)

    return has_issues, "\n".join(all_output)


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <file.cea> [selene_path]")
        sys.exit(1)

    cea_path = sys.argv[1]
    selene_path = sys.argv[2] if len(sys.argv) > 2 else "C:\\tools\\selene.exe"

    if not os.path.exists(cea_path):
        print(f"File not found: {cea_path}")
        sys.exit(1)

    has_issues, output = lint_file(cea_path, selene_path)
    if output:
        print(output)
    sys.exit(1 if has_issues else 0)


if __name__ == "__main__":
    main()
