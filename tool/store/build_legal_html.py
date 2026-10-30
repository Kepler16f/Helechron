#!/usr/bin/env python3
"""把 assets/legal 下的纯文本协议转换为可托管的静态网页。

协议文本里的 ``{{DEVELOPER_NAME}}`` 等占位符会在转换前由
``tool/store/legal_identity.py`` 替换成当前生效的开发者名称、主体类型与
ICP 备案号，因此生成出来的页面里不会出现 ``{{...}}`` 残留。

发布时可用环境变量覆盖默认值（与 Dart 侧 `--dart-define=` 对齐）::

    $env:DEVELOPER_NAME = "胡天泽"
    $env:DEVELOPER_SUBJECT_TYPE = "个人开发者"
    $env:ICP_FILING_NUMBER = "浙ICP备2026XXXXXX号"

用法: python tool/store/build_legal_html.py
输出: docs/privacy.html, docs/terms.html
"""

from __future__ import annotations

import html
import re
import sys
from pathlib import Path

# 允许从任意目录调用本脚本：把同目录的 legal_identity 加入模块搜索路径。
sys.path.insert(0, str(Path(__file__).resolve().parent))

from legal_identity import substitute  # noqa: E402  (需在 sys.path 调整之后导入)

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / "docs"

TEMPLATE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} - Helechron</title>
<style>
  :root {{
    color-scheme: light dark;
    --bg: #ffffff;
    --fg: #1c1c1e;
    --muted: #6b6b70;
    --line: #e5e7eb;
    --accent: #3478f6;
  }}
  @media (prefers-color-scheme: dark) {{
    :root {{
      --bg: #000000;
      --fg: #f2f2f7;
      --muted: #98989f;
      --line: #2c2c2e;
      --accent: #6aa5ff;
    }}
  }}
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0;
    background: var(--bg);
    color: var(--fg);
    font: 16px/1.75 -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC",
      "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
  }}
  main {{ max-width: 760px; margin: 0 auto; padding: 40px 22px 72px; }}
  h1 {{ font-size: 30px; line-height: 1.3; margin: 0 0 8px; letter-spacing: -0.3px; }}
  h2 {{ font-size: 19px; margin: 34px 0 10px; }}
  p {{ margin: 0 0 12px; }}
  p.meta {{ color: var(--muted); font-size: 14px; margin: 0 0 4px; }}
  p.bullet {{ padding-left: 1.1em; text-indent: -1.1em; }}
  a {{ color: var(--accent); word-break: break-all; }}
  nav {{ margin-bottom: 28px; font-size: 14px; }}
  nav a {{ text-decoration: none; }}
  footer {{ margin-top: 56px; padding-top: 18px; border-top: 1px solid var(--line);
    color: var(--muted); font-size: 13px; }}
</style>
</head>
<body>
<main>
<nav><a href="./index.html">Helechron</a> / {title}</nav>
<h1>{title}</h1>
{body}
<footer>Helechron 是基于 Celechron 开源项目移植并扩展功能的非官方版本，由本项目维护者负责移植适配、独立开发新增功能及后续维护与发布。本应用不是 Celechron 官方应用，不代表 Celechron 原项目或其维护团队，也不是浙江大学官方应用。 与 Celechron 原项目及浙江大学无隶属、品牌授权、合作或背书关系。本页面内容与应用内文本不一致时，以应用内最新版本为准。</footer>
</main>
</body>
</html>
"""

URL_RE = re.compile(r"https?://[^\s<]+")


def linkify(text: str) -> str:
    escaped = html.escape(text)
    return URL_RE.sub(lambda m: f'<a href="{m.group(0)}">{m.group(0)}</a>', escaped)


def convert(text: str) -> tuple[str, str]:
    lines = [line.rstrip() for line in text.splitlines()]
    title = lines[0].strip()
    parts: list[str] = []
    for raw in lines[1:]:
        line = raw.strip()
        if not line:
            continue
        if line.startswith("更新日期：") or line.startswith("生效日期：") or line.startswith("版本："):
            parts.append(f'<p class="meta">{linkify(line)}</p>')
        elif re.match(r"^[一二三四五六七八九十]+、", line) or (
            line.startswith("【") and line.endswith("】")
        ):
            parts.append(f"<h2>{linkify(line)}</h2>")
        elif line.startswith("·"):
            parts.append(f'<p class="bullet">{linkify(line)}</p>')
        else:
            parts.append(f"<p>{linkify(line)}</p>")
    return title, "\n".join(parts)


def main() -> None:
    DOCS.mkdir(exist_ok=True)
    sources = {
        "privacy": ROOT / "assets" / "legal" / "privacy_policy.txt",
        "terms": ROOT / "assets" / "legal" / "user_agreement.txt",
    }
    for name, source in sources.items():
        raw = source.read_text(encoding="utf-8")
        # 先把占位符替换成具体的主体信息，再转 HTML。
        title, body = convert(substitute(raw))
        target = DOCS / f"{name}.html"
        target.write_text(
            TEMPLATE.format(title=title, body=body),
            encoding="utf-8",
        )
        print(f"wrote {target}")


if __name__ == "__main__":
    main()
