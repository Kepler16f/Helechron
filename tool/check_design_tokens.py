#!/usr/bin/env python3
"""CI Guard: 禁止在已迁移的设计系统与业务页面中直接硬编码颜色或旧图标库。

规则：
1. 原始色值字面量只允许出现在 `lib/design/tokens/`（及未迁移完毕前的旧 `lib/design/custom_colors.dart`）。
2. 图标库底层映射只允许出现在 `lib/design/icons/`。
3. 所有受控目录（`lib/design/theme/`、`lib/design/components/`）以及 `ENFORCED_FILES` 中列出的已迁移业务文件，
   一律禁止出现：
   - `Color(0x...` / `Color.fromARGB` / `Color.fromRGBO`
   - `Colors.` / `CupertinoColors.`
   - `Icons.` / `CupertinoIcons.`
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

ENFORCED_DIRS = [
    "lib/design/theme",
    "lib/design/components",
]

ENFORCED_FILES = [
    "lib/page/home_page.dart",
    "lib/page/flow/exam_week_banner.dart",
    "lib/page/flow/flow_view.dart",
    "lib/page/calendar/calendar_view.dart",
    "lib/page/calendar/schedule_view.dart",
    "lib/page/option/appearance_section.dart",
]

FORBIDDEN_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("硬编码十六进制颜色 Color(0x...)", re.compile(r"\bColor\(\s*0x[0-9A-Fa-f]+")),
    ("硬编码 RGB/ARGB 颜色", re.compile(r"\bColor\.from(?:ARGB|RGBO)\s*\(")),
    ("直接使用 Material Colors.*", re.compile(r"\bColors\.[a-zA-Z0-9_]+")),
    ("直接使用 CupertinoColors.*", re.compile(r"\bCupertinoColors\.[a-zA-Z0-9_]+")),
    ("直接使用 Material Icons.*", re.compile(r"\bIcons\.[a-zA-Z0-9_]+")),
    ("直接使用 CupertinoIcons.*", re.compile(r"\bCupertinoIcons\.[a-zA-Z0-9_]+")),
]


def iter_enforced_files() -> list[pathlib.Path]:
    files: set[pathlib.Path] = set()
    for rel_dir in ENFORCED_DIRS:
        p = ROOT / rel_dir
        if p.is_dir():
            files.update(p.rglob("*.dart"))
    for rel_file in ENFORCED_FILES:
        p = ROOT / rel_file
        if p.is_file():
            files.add(p)
    return sorted(files)


def strip_comment(line: str) -> str:
    idx = line.find("//")
    return line[:idx] if idx >= 0 else line


def main() -> int:
    enforced = iter_enforced_files()
    violations: list[str] = []

    for path in enforced:
        rel = path.relative_to(ROOT).as_posix()
        lines = path.read_text(encoding="utf-8").splitlines()
        for lineno, raw_line in enumerate(lines, start=1):
            code = strip_comment(raw_line)
            if not code.strip():
                continue
            for label, pattern in FORBIDDEN_PATTERNS:
                match = pattern.search(code)
                if match:
                    violations.append(
                        f"  {rel}:{lineno}: [{label}] `{match.group(0)}` -> {raw_line.strip()}"
                    )

    if violations:
        print("❌ 设计令牌规范检查失败（已迁移禁止直接写颜色/旧图标）：", file=sys.stderr)
        for v in violations:
            print(v, file=sys.stderr)
        return 1

    print(f"✅ 设计令牌规范检查通过（已覆盖 {len(enforced)} 个受控文件，0 违规）。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
