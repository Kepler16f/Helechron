#!/usr/bin/env python3
"""开发者身份信息：应用内文本与在线协议页共用的唯一 Python 来源。

协议文本（``assets/legal/*.txt``）用占位符描述“当前生效的主体”，例如
``{{DEVELOPER_NAME}}``。应用内由 Dart 侧 ``lib/utils/legal_links.dart`` 的
``legalPlaceholders`` 在运行时替换，在线协议页由
``tool/store/build_legal_html.py`` 在构建时替换。

**默认值必须与 ``lib/utils/legal_links.dart`` 保持一致。**
``tool/store/check_release.py`` 会逐项比对两边的默认值，不一致直接 FAIL。
上架审核会核对「应用内协议展示的名称」与「AppGallery Connect 开发者信息」
是否逐字一致，个人主体填实名姓名，必须与 AGC 的「开发者信息」完全相同。

发布时用环境变量覆盖默认，例如（Windows PowerShell）::

    $env:DEVELOPER_NAME = "胡天泽"
    $env:DEVELOPER_SUBJECT_TYPE = "个人开发者"
    $env:ICP_FILING_NUMBER = "浙ICP备2026XXXXXX号"
    python tool/store/build_legal_html.py
    python tool/store/check_release.py

注意：``ICP_FILING_NUMBER`` 目前仍是占位文本，ICP 备案号批复后必须用真实
备案号重新生成 ``docs/privacy.html`` / ``docs/terms.html`` 并重新打包应用。
"""

from __future__ import annotations

import os
from typing import Dict, List

# ---------------------------------------------------------------------------
# 默认值：必须与 lib/utils/legal_links.dart 中的 defaultValue 逐字相同。
# ---------------------------------------------------------------------------

DEFAULT_DEVELOPER_NAME = "胡天泽"
DEFAULT_DEVELOPER_SUBJECT_TYPE = "个人开发者"
DEFAULT_ICP_FILING_NUMBER = "【ICP备案号待补充】"""

# 环境变量名：与 Dart 侧 `--dart-define=DEVELOPER_NAME=...` 的 key 对齐。
ENV_DEVELOPER_NAME = "DEVELOPER_NAME"
ENV_DEVELOPER_SUBJECT_TYPE = "DEVELOPER_SUBJECT_TYPE"
ENV_ICP_FILING_NUMBER = "ICP_FILING_NUMBER"

#: 所有已知占位符名（不含大括号）。
PLACEHOLDER_NAMES: List[str] = [
    "DEVELOPER_NAME",
    "DEVELOPER_SUBJECT_TYPE",
    "ICP_FILING_NUMBER",
]

#: 所有已知占位符（含大括号），可直接用于文本替换与残留扫描。
PLACEHOLDERS: List[str] = ["{{%s}}" % name for name in PLACEHOLDER_NAMES]


def _from_env(env_key: str, default: str) -> str:
    """读取环境变量；未设置或只含空白时回退到默认值。"""
    raw = os.environ.get(env_key)
    if raw is None:
        return default
    stripped = raw.strip()
    return stripped if stripped else default


def developer_name() -> str:
    """当前生效的开发者名称（个人主体填实名姓名，企业主体填营业执照全称）。"""
    return _from_env(ENV_DEVELOPER_NAME, DEFAULT_DEVELOPER_NAME)


def developer_subject_type() -> str:
    """当前生效的开发者主体类型，例如“个人开发者”或“企业”。"""
    return _from_env(ENV_DEVELOPER_SUBJECT_TYPE, DEFAULT_DEVELOPER_SUBJECT_TYPE)


def icp_filing_number() -> str:
    """当前生效的工信部 APP 备案号（未批复时为占位文本）。"""
    return _from_env(ENV_ICP_FILING_NUMBER, DEFAULT_ICP_FILING_NUMBER)


def values() -> Dict[str, str]:
    """返回「占位符 -> 当前生效的值」映射。"""
    return {
        "{{DEVELOPER_NAME}}": developer_name(),
        "{{DEVELOPER_SUBJECT_TYPE}}": developer_subject_type(),
        "{{ICP_FILING_NUMBER}}": icp_filing_number(),
    }


def substitute(text: str) -> str:
    """把文本中的已知占位符替换成当前生效的主体信息。

    未知占位符（不在 :data:`PLACEHOLDERS` 中）保持原样，由
    ``tool/store/check_release.py`` 报错，避免拼写错误被静默发布。
    """
    if not text:
        return text
    result = text
    for placeholder, value in values().items():
        result = result.replace(placeholder, value)
    return result


if __name__ == "__main__":
    print("开发者名称      : %s" % developer_name())
    print("主体类型        : %s" % developer_subject_type())
    print("APP 备案号      : %s" % icp_filing_number())
    print("已知占位符      : %s" % ", ".join(PLACEHOLDERS))
