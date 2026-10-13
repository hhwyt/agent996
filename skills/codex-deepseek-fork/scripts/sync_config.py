#!/usr/bin/env python3
"""Copy one CC Switch Codex provider (default: "DeepSeek") into a separate CODEX_HOME.

Writes <target>/config.toml and <target>/auth.json from the provider stored in
~/.cc-switch/cc-switch.db. Only reads the CC Switch database; never touches ~/.codex.

Usage: sync_config.py [--provider DeepSeek] [--target ~/.codex-deepseek]
"""
import argparse
import json
import os
import re
import shutil
import sqlite3
import sys

home = os.path.expanduser("~")
parser = argparse.ArgumentParser()
parser.add_argument("--provider", default="DeepSeek", help="CC Switch Codex provider name")
parser.add_argument("--target", default=os.path.join(home, ".codex-deepseek"))
parser.add_argument("--db", default=os.path.join(home, ".cc-switch", "cc-switch.db"))
args = parser.parse_args()

if not os.path.exists(args.db):
    sys.exit(f"CC Switch database not found: {args.db}")

con = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)
rows = con.execute(
    "select settings_config from providers where app_type='codex' and name=?", (args.provider,)
).fetchall()
if len(rows) != 1:
    names = [r[0] for r in con.execute("select name from providers where app_type='codex'")]
    sys.exit(f"Expected exactly one Codex provider named {args.provider!r}, found {len(rows)}. "
             f"Codex providers in CC Switch: {names}")
provider_settings = json.loads(rows[0][0])

config_toml = provider_settings.get("config", "")
auth = provider_settings.get("auth") or {}
if not config_toml.strip():
    sys.exit(f"Provider {args.provider!r} has an empty config.toml in CC Switch")

os.makedirs(args.target, mode=0o700, exist_ok=True)

# CC Switch writes the expanded model catalog to ~/.codex/cc-switch-model-catalog.json
# when this provider is active. Reuse it if it lists this provider's models; otherwise
# drop the reference so Codex falls back to its default model metadata.
catalog_line = re.compile(r'^model_catalog_json\s*=.*\n?', re.M)
provider_models = {m.get("model") for m in (provider_settings.get("modelCatalog") or {}).get("models", [])}
main_catalog = os.path.join(home, ".codex", "cc-switch-model-catalog.json")
catalog_copied = False
if catalog_line.search(config_toml) and provider_models and os.path.exists(main_catalog):
    with open(main_catalog) as f:
        catalog_slugs = {m.get("slug") or m.get("model") for m in json.load(f).get("models", [])}
    if provider_models <= catalog_slugs:
        shutil.copyfile(main_catalog, os.path.join(args.target, "cc-switch-model-catalog.json"))
        catalog_copied = True
if not catalog_copied:
    config_toml = catalog_line.sub("", config_toml)


# CC Switch's third-party Codex template writes `requires_openai_auth = false`, which makes
# Codex send no Authorization header (DeepSeek answers 401 "Authentication Fails"). The key
# lives in auth.json as OPENAI_API_KEY, so tell Codex to use it.
if auth.get("OPENAI_API_KEY") and "env_key" not in config_toml:
    config_toml = re.sub(r'^requires_openai_auth\s*=\s*false', "requires_openai_auth = true", config_toml, flags=re.M)


def write_private(path, content):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(content)


write_private(os.path.join(args.target, "config.toml"), config_toml)
write_private(os.path.join(args.target, "auth.json"), json.dumps(auth, indent=2) + "\n")

model = re.search(r'^model\s*=\s*"([^"]+)"', config_toml, re.M)
base_url = re.search(r'^base_url\s*=\s*"([^"]+)"', config_toml, re.M)
print(f"Synced CC Switch provider {args.provider!r} -> {args.target}")
print(f"  model:    {model.group(1) if model else '(default)'}")
print(f"  base_url: {base_url.group(1) if base_url else '(default)'}")
print(f"  catalog:  {'copied' if catalog_copied else 'not used'}")
