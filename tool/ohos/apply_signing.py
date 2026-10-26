#!/usr/bin/env python3
"""把发布签名材料写入鸿蒙工程，供 hvigor 在 CI 中签名打包。

优先读取 base64 环境变量（GitHub Secrets），也支持直接传文件路径：
  OHOS_STORE_FILE_BASE64 / OHOS_STORE_FILE   -> ohos/signature/release.p12
  OHOS_CERT_BASE64      / OHOS_CERT          -> ohos/signature/release.cer
  OHOS_PROFILE_BASE64   / OHOS_PROFILE       -> ohos/signature/release.p7b
  OHOS_STORE_FILE_PASSWORD, OHOS_KEY_ALIAS, OHOS_KEY_PASSWORD

脚本会重写 ohos/build-profile.json5 的 signingConfigs，并把 default 产品
指向 release 签名。签名材料目录已被 .gitignore 忽略，切勿提交。
"""

from __future__ import annotations

import base64
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OHOS_DIR = ROOT / "ohos"
SIGNATURE_DIR = OHOS_DIR / "signature"
BUILD_PROFILE = OHOS_DIR / "build-profile.json5"


def _load_material(base64_key: str, path_key: str, filename: str) -> Path:
    encoded = "".join(os.environ.get(base64_key, "").split())
    file_path = os.environ.get(path_key, "").strip()

    if encoded:
        data = base64.b64decode(encoded, validate=True)
    elif file_path:
        data = Path(file_path).read_bytes()
    else:
        raise SystemExit(f"缺少 {base64_key} 或 {path_key}")

    target = SIGNATURE_DIR / filename
    target.write_bytes(data)
    try:
        target.chmod(0o600)
    except OSError:
        pass
    return target.resolve()


def _strip_json5(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//[^\n]*", "", text)
    text = re.sub(r",(\s*[}\]])", r"\1", text)
    return text


def main() -> int:
    required = [
        "OHOS_STORE_FILE_PASSWORD",
        "OHOS_KEY_ALIAS",
        "OHOS_KEY_PASSWORD",
    ]
    missing = [key for key in required if not os.environ.get(key)]
    if missing:
        print(f"缺少环境变量: {', '.join(missing)}", file=sys.stderr)
        return 2

    SIGNATURE_DIR.mkdir(parents=True, exist_ok=True)

    store_file = _load_material(
        "OHOS_STORE_FILE_BASE64", "OHOS_STORE_FILE", "release.p12"
    )
    cert_file = _load_material("OHOS_CERT_BASE64", "OHOS_CERT", "release.cer")
    profile_file = _load_material("OHOS_PROFILE_BASE64", "OHOS_PROFILE", "release.p7b")

    if not BUILD_PROFILE.exists():
        print(f"找不到 {BUILD_PROFILE}", file=sys.stderr)
        return 2

    data = json.loads(_strip_json5(BUILD_PROFILE.read_text(encoding="utf-8")))
    app_config = data.setdefault("app", {})

    material = {
        "certpath": str(cert_file),
        "storePassword": os.environ["OHOS_STORE_FILE_PASSWORD"],
        "keyAlias": os.environ["OHOS_KEY_ALIAS"],
        "keyPassword": os.environ["OHOS_KEY_PASSWORD"],
        "profile": str(profile_file),
        "signAlg": os.environ.get("OHOS_SIGN_ALG", "SHA256withECDSA"),
        "storeFile": str(store_file),
    }
    app_config["signingConfigs"] = [
        {
            "name": "release",
            "type": "HarmonyOS",
            "material": material,
        }
    ]
    for product in app_config.get("products", []):
        product["signingConfig"] = "release"

    BUILD_PROFILE.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"已写入签名配置: {BUILD_PROFILE}")
    print(f"证书: {cert_file}")
    print(f"Profile: {profile_file}")
    print(f"Keystore: {store_file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
