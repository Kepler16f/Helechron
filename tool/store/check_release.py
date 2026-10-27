#!/usr/bin/env python3
"""上架前自检：一次性检查协议占位符、图标尺寸与版本号是否一致。

用法::

    python tool/store/check_release.py            # 在仓库根目录执行
    python tool/store/check_release.py --root D:\\Helechron
    python tool/store/check_release.py --help

检查项：

1. 占位符一致性 —— ``lib/utils/legal_links.dart`` 里三个
   ``String.fromEnvironment`` 的 ``defaultValue`` 必须与
   ``tool/store/legal_identity.py`` 的默认值逐字相同。
2. 协议文本无未替换占位符 —— ``assets/legal/*.txt`` 中只允许出现已知占位符
   （应用内运行时才替换），``docs/*.html`` 中不允许出现任何 ``{{...}}``。
   加 ``--strict-asset-placeholders`` 可让 ``assets/legal/*.txt`` 中的已知
   占位符也算失败。
3. 在线协议与离线协议主体一致 —— ``docs/privacy.html`` 与
   ``docs/terms.html`` 必须出现当前生效的开发者名称与 APP 备案号。
4. 鸿蒙单层图标尺寸 —— ``app_icon.png`` 与 ``icon.png`` 必须为 1024×1024
   （上架检测硬性要求）；同时打印 ohosTest 模块图标尺寸作为提示。
5. 版本号一致 —— ``lib/worker/fuse.dart`` 的 ``displayVersion``、
   ``ohos/AppScope/app.json5`` 的 ``versionName`` / ``versionCode`` 与
   ``pubspec.yaml`` 的 ``version: x.y.z+build`` 必须互相吻合。

有 FAIL 时进程退出码为 1，可直接接入 CI 或发版脚本。
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Dict, List, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent))

import legal_identity  # noqa: E402  (需在 sys.path 调整之后导入)
from legal_identity import PLACEHOLDERS  # noqa: E402

try:
    from PIL import Image
except ImportError:  # pragma: no cover - 缺 Pillow 时只影响图标检查
    Image = None  # type: ignore[assignment]

DEFAULT_ROOT = Path(__file__).resolve().parents[2]

# `{{任意内容}}` 形式的占位符残留
PLACEHOLDER_RE = re.compile(r"\{\{[^{}]*\}\}")

# Dart: const String xxx = String.fromEnvironment('KEY', defaultValue: '...');
DART_FROM_ENV_RE = re.compile(
    r"const\s+String\s+(?P<name>\w+)\s*=\s*String\.fromEnvironment\s*\(\s*"
    r"'(?P<key>\w+)'\s*,\s*defaultValue:\s*'(?P<value>[^']*)'",
    re.S,
)

# Dart: String get displayVersion => '0.1.7';
DART_DISPLAY_VERSION_RE = re.compile(
    r"displayVersion\s*=>\s*'(?P<value>[^']+)'"
)

# app.json5: "versionName": "0.1.7" / "versionCode": 100
JSON5_VERSION_NAME_RE = re.compile(r'"versionName"\s*:\s*"(?P<value>[^"]+)"')
JSON5_VERSION_CODE_RE = re.compile(r'"versionCode"\s*:\s*(?P<value>\d+)')

# pubspec.yaml: version: 0.1.7+100
PUBSPEC_VERSION_RE = re.compile(
    r"^version\s*:\s*(?P<name>[0-9A-Za-z.\-]+)\s*\+\s*(?P<code>\d+)\s*$",
    re.M,
)

# Dart 常量名 -> (环境变量名, legal_identity 中的默认值)
DART_CONSTANTS: Dict[str, Tuple[str, str]] = {
    "developerName": (
        legal_identity.ENV_DEVELOPER_NAME,
        legal_identity.DEFAULT_DEVELOPER_NAME,
    ),
    "developerSubjectType": (
        legal_identity.ENV_DEVELOPER_SUBJECT_TYPE,
        legal_identity.DEFAULT_DEVELOPER_SUBJECT_TYPE,
    ),
    "icpFilingNumber": (
        legal_identity.ENV_ICP_FILING_NUMBER,
        legal_identity.DEFAULT_ICP_FILING_NUMBER,
    ),
}


class Checker:
    """收集检查结果并统一输出。"""

    def __init__(self) -> None:
        self.passed = 0
        self.failed = 0
        self.details: List[str] = []

    def report(self, title: str, ok: bool, lines: List[str]) -> None:
        status = "PASS" if ok else "FAIL"
        if ok:
            self.passed += 1
        else:
            self.failed += 1
        print(f"[{status}] {title}")
        for line in lines:
            print(f"       {line}")
        self.details.append(f"[{status}] {title}")


def _rel(root: Path, path: Path) -> str:
    try:
        return str(path.relative_to(root)).replace("\\", "/")
    except ValueError:
        return str(path)


# ---------------------------------------------------------------------------
# 1. 占位符默认值一致性
# ---------------------------------------------------------------------------
def check_placeholder_consistency(root: Path, checker: Checker) -> None:
    title = "占位符默认值一致性 (legal_links.dart vs legal_identity.py)"
    dart_file = root / "lib" / "utils" / "legal_links.dart"
    if not dart_file.exists():
        checker.report(title, False, [f"找不到 {dart_file}"])
        return

    source = dart_file.read_text(encoding="utf-8")
    found = {
        m.group("name"): m.group("value")
        for m in DART_FROM_ENV_RE.finditer(source)
    }

    lines: List[str] = []
    ok = True
    for const_name, (env_key, py_default) in DART_CONSTANTS.items():
        if const_name not in found:
            ok = False
            lines.append(
                f"{const_name}: 在 {dart_file.name} 中找不到 "
                f"String.fromEnvironment('{env_key}') 定义"
            )
            continue
        dart_value = found[const_name]
        if dart_value != py_default:
            ok = False
            lines.append(
                f"{const_name} 不一致 | Dart 默认值 = {dart_value!r} | "
                f"Python 默认值 = {py_default!r}（env {env_key}）"
            )
        else:
            lines.append(
                f"{const_name} = {dart_value!r}（env {env_key}）一致"
            )

    effective = {
        "developerName": legal_identity.developer_name(),
        "developerSubjectType": legal_identity.developer_subject_type(),
        "icpFilingNumber": legal_identity.icp_filing_number(),
    }
    overridden = [
        f"{key}={value!r}"
        for key, value in effective.items()
        if value != DART_CONSTANTS[key][1]
    ]
    if overridden:
        lines.append("当前生效值（已被环境变量覆盖）: " + ", ".join(overridden))
    else:
        lines.append("当前生效值: 使用默认值（未设置环境变量覆盖）")

    checker.report(title, ok, lines)


# ---------------------------------------------------------------------------
# 2. 协议文本无未替换占位符
# ---------------------------------------------------------------------------
def check_no_placeholder_residue(root: Path, checker: Checker, strict_assets: bool) -> None:
    title = "协议文本无未替换占位符"
    targets = [
        root / "assets" / "legal" / "privacy_policy.txt",
        root / "assets" / "legal" / "user_agreement.txt",
        root / "docs" / "privacy.html",
        root / "docs" / "terms.html",
    ]
    lines: List[str] = []
    ok = True
    for path in targets:
        if not path.exists():
            ok = False
            lines.append(f"{_rel(root, path)}: 文件不存在")
            continue
        text = path.read_text(encoding="utf-8")
        hits = sorted(set(PLACEHOLDER_RE.findall(text)))
        if not hits:
            lines.append(f"{_rel(root, path)}: 无占位符残留")
            continue
        is_asset = path.suffix == ".txt"
        unknown = [h for h in hits if h not in PLACEHOLDERS]
        if is_asset:
            # 离线文本由应用运行时替换，已知占位符属于预期内容。
            if unknown or strict_assets:
                ok = False
                reason = "未知占位符" if unknown else "--strict-asset-placeholders 已启用"
                lines.append(f"{_rel(root, path)}: {reason} -> {', '.join(hits)}")
            else:
                lines.append(
                    f"{_rel(root, path)}: 含已知占位符（应用内运行时替换）"
                    f" -> {', '.join(hits)}"
                )
        else:
            ok = False
            lines.append(f"{_rel(root, path)}: 在线页面不应残留占位符 -> {', '.join(hits)}")

    checker.report(title, ok, lines)


# ---------------------------------------------------------------------------
# 3. 在线协议与离线协议主体一致
# ---------------------------------------------------------------------------
def check_subject_consistency(root: Path, checker: Checker) -> None:
    title = "在线协议与离线协议主体一致"
    name = legal_identity.developer_name()
    icp = legal_identity.icp_filing_number()
    targets = [
        root / "docs" / "privacy.html",
        root / "docs" / "terms.html",
    ]
    lines: List[str] = []
    ok = True
    for path in targets:
        if not path.exists():
            ok = False
            lines.append(f"{_rel(root, path)}: 文件不存在")
            continue
        text = path.read_text(encoding="utf-8")
        missing = []
        for label, value in (("开发者名称", name), ("APP 备案号", icp)):
            if value not in text:
                missing.append(label)
        if missing:
            ok = False
            lines.append(
                f"{_rel(root, path)}: 缺少 {', '.join(missing)}"
                f"（开发者名称={name!r}, APP 备案号={icp!r}）"
            )
        else:
            lines.append(
                f"{_rel(root, path)}: 已包含开发者名称 {name!r} 与 APP 备案号 {icp!r}"
            )
    checker.report(title, ok, lines)


# ---------------------------------------------------------------------------
# 4. 鸿蒙单层图标尺寸
# ---------------------------------------------------------------------------
def check_harmony_icons(root: Path, checker: Checker) -> None:
    title = "鸿蒙单层图标尺寸 (1024x1024)"
    required = [
        root / "ohos" / "AppScope" / "resources" / "base" / "media" / "app_icon.png",
        root / "ohos" / "entry" / "src" / "main" / "resources" / "base" / "media" / "icon.png",
    ]
    hint = root / "ohos" / "entry" / "src" / "ohosTest" / "resources" / "base" / "media" / "icon.png"

    if Image is None:
        checker.report(title, False, ["未安装 Pillow，无法读取图标尺寸（pip install pillow）"])
        return

    lines: List[str] = []
    ok = True
    for path in required:
        if not path.exists():
            ok = False
            lines.append(f"{_rel(root, path)}: 文件不存在")
            continue
        with Image.open(path) as img:
            width, height = img.size
        if (width, height) != (1024, 1024):
            ok = False
            lines.append(
                f"{_rel(root, path)}: {width}x{height}，不满足 1024x1024 规范"
            )
        else:
            lines.append(f"{_rel(root, path)}: {width}x{height} OK")

    if hint.exists():
        with Image.open(hint) as img:
            width, height = img.size
        lines.append(
            f"提示 { _rel(root, hint) }: {width}x{height}"
            "（测试模块，不参与发布，允许不满足 1024x1024）"
        )
    else:
        lines.append(f"提示 {_rel(root, hint)}: 文件不存在（测试模块，可忽略）")

    checker.report(title, ok, lines)


# ---------------------------------------------------------------------------
# 5. 版本号一致
# ---------------------------------------------------------------------------
def check_versions(root: Path, checker: Checker) -> None:
    title = "版本号一致 (fuse.dart / app.json5 / pubspec.yaml)"
    lines: List[str] = []
    ok = True

    fuse_file = root / "lib" / "worker" / "fuse.dart"
    app_json5 = root / "ohos" / "AppScope" / "app.json5"
    pubspec = root / "pubspec.yaml"

    display_version = None
    if not fuse_file.exists():
        ok = False
        lines.append(f"{_rel(root, fuse_file)}: 文件不存在")
    else:
        match = DART_DISPLAY_VERSION_RE.search(fuse_file.read_text(encoding="utf-8"))
        if not match:
            ok = False
            lines.append(f"{_rel(root, fuse_file)}: 找不到 displayVersion")
        else:
            display_version = match.group("value")
            lines.append(f"{_rel(root, fuse_file)}: displayVersion = {display_version}")

    version_name = None
    version_code = None
    if not app_json5.exists():
        ok = False
        lines.append(f"{_rel(root, app_json5)}: 文件不存在")
    else:
        text = app_json5.read_text(encoding="utf-8")
        name_match = JSON5_VERSION_NAME_RE.search(text)
        code_match = JSON5_VERSION_CODE_RE.search(text)
        if not name_match:
            ok = False
            lines.append(f"{_rel(root, app_json5)}: 找不到 versionName")
        else:
            version_name = name_match.group("value")
            lines.append(f"{_rel(root, app_json5)}: versionName = {version_name}")
        if not code_match:
            ok = False
            lines.append(f"{_rel(root, app_json5)}: 找不到 versionCode")
        else:
            version_code = int(code_match.group("value"))
            lines.append(f"{_rel(root, app_json5)}: versionCode = {version_code}")

    pub_name = None
    pub_code = None
    if not pubspec.exists():
        ok = False
        lines.append(f"{_rel(root, pubspec)}: 文件不存在")
    else:
        match = PUBSPEC_VERSION_RE.search(pubspec.read_text(encoding="utf-8"))
        if not match:
            ok = False
            lines.append(f"{_rel(root, pubspec)}: 找不到 version: x.y.z+build")
        else:
            pub_name = match.group("name")
            pub_code = int(match.group("code"))
            lines.append(
                f"{_rel(root, pubspec)}: version = {pub_name}+{pub_code}"
            )

    # 交叉比对
    if display_version and version_name and display_version != version_name:
        ok = False
        lines.append(
            f"版本名不一致: fuse.dart={display_version} vs app.json5={version_name}"
        )
    if pub_name and version_name and pub_name != version_name:
        ok = False
        lines.append(
            f"版本名不一致: pubspec={pub_name} vs app.json5={version_name}"
        )
    if pub_name and display_version and pub_name != display_version:
        ok = False
        lines.append(
            f"版本名不一致: pubspec={pub_name} vs fuse.dart={display_version}"
        )
    if pub_code is not None and version_code is not None and pub_code != version_code:
        ok = False
        lines.append(
            f"versionCode 不一致: pubspec={pub_code} vs app.json5={version_code}"
        )

    if ok:
        lines.append(
            f"三者一致: 版本 {display_version or pub_name} / versionCode "
            f"{version_code if version_code is not None else pub_code}"
        )

    checker.report(title, ok, lines)


def main(argv: List[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="上架前自检：占位符一致性、图标尺寸、版本号一致性。",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "示例:\n"
            "  python tool/store/check_release.py\n"
            "  python tool/store/check_release.py --strict-asset-placeholders\n"
        ),
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=DEFAULT_ROOT,
        help=f"仓库根目录（默认: {DEFAULT_ROOT}）",
    )
    parser.add_argument(
        "--strict-asset-placeholders",
        action="store_true",
        help="assets/legal/*.txt 中出现已知占位符也算失败（默认只允许已知占位符）",
    )
    args = parser.parse_args(argv)

    root = args.root.resolve()
    print(f"上架前自检  root = {root}")
    print("=" * 64)

    checker = Checker()
    check_placeholder_consistency(root, checker)
    check_no_placeholder_residue(root, checker, args.strict_asset_placeholders)
    check_subject_consistency(root, checker)
    check_harmony_icons(root, checker)
    check_versions(root, checker)

    print("=" * 64)
    total = checker.passed + checker.failed
    if checker.failed:
        print(
            f"汇总: {total} 项检查, {checker.passed} PASS, {checker.failed} FAIL "
            "-> 上架自检未通过"
        )
        return 1
    print(f"汇总: {total} 项检查, {checker.passed} PASS, 0 FAIL -> 上架自检通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
