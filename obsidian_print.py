#!/usr/bin/python3
# File-handling half of "Save PDF to Obsidian.app" (see README). The app's
# AppleScript shows the dialog and calls this script twice:
#
#   obsidian_print.py prepare <pdf>
#       Prints "OK", the note-name prefill, the 0-based index of the vault
#       to preselect, then one vault name per line. On a problem, prints
#       "ERROR" and a message instead.
#
#   obsidian_print.py save <pdf> <vault index> <note name> <note text>
#       Copies the PDF into the vault, writes the note, remembers the vault,
#       and opens the note in Obsidian.

import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.parse

############## CONFIGURE ##############
ATTACH_SUBDIR = "attachments"  # PDFs land here, relative to the vault
NOTE_SUBDIR = "notes"          # new notes land here, relative to the vault
EXCLUDE_VAULTS = ["Obsidian Sandbox"]  # vault names to leave out of the menu
#######################################

# Obsidian's own list of known vaults (overridable for testing)
OBSIDIAN_REGISTRY = os.environ.get("OBSIDIAN_PRINT_REGISTRY") or os.path.expanduser(
    "~/Library/Application Support/obsidian/obsidian.json"
)
# Where the last-chosen vault is remembered (overridable for testing)
STATE_FILE = os.environ.get("OBSIDIAN_PRINT_STATE") or os.path.expanduser(
    "~/Library/Application Support/obsidian-print/state.json"
)

STAMP = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")


def sanitize(name):
    s = re.sub(r'[/\\:*?"<>|#^\[\]]', "-", name)
    s = re.sub(r"-{2,}", "-", s)
    s = s.strip(" .-")
    return s or f"Printed-{STAMP}"


def find_vaults():
    """Return ([(vault_id, name, path)] sorted by name, problem-or-None)."""
    try:
        with open(OBSIDIAN_REGISTRY) as f:
            registry = json.load(f).get("vaults", {})
    except (OSError, ValueError) as e:
        return [], f"Couldn't read {OBSIDIAN_REGISTRY}: {e}"
    vaults, skipped = [], []
    for vault_id, info in registry.items():
        path = info.get("path", "")
        name = os.path.basename(path)
        if name in EXCLUDE_VAULTS:
            continue
        if os.path.isdir(path):
            vaults.append((vault_id, name, path))
        else:
            skipped.append(path)
    if not vaults:
        return [], ("No usable Obsidian vaults listed in "
                    f"{OBSIDIAN_REGISTRY}. Missing or unreadable: "
                    + (", ".join(skipped) or "(none listed)"))
    return sorted(vaults, key=lambda v: v[1].lower()), None


def load_last_vault():
    try:
        with open(STATE_FILE) as f:
            return json.load(f).get("last_vault")
    except (OSError, ValueError):
        return None


def save_last_vault(path):
    try:
        os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
        with open(STATE_FILE, "w") as f:
            json.dump({"last_vault": path}, f)
    except OSError:
        pass  # remembering the choice is a convenience, not worth failing over


def prepare(pdf):
    vaults, problem = find_vaults()
    if problem:
        print("ERROR")
        print(problem)
        return
    paths = [v[2] for v in vaults]
    last = load_last_vault()
    title = os.path.basename(pdf)
    while title.lower().endswith(".pdf"):  # print files can be "Title.pdf.pdf"
        title = title[: -len(".pdf")]
    print("OK")
    print(sanitize(title))
    print(paths.index(last) if last in paths else 0)
    for v in vaults:
        print(v[1])


def save(src_pdf, vault_index, name, body):
    if not name.strip():
        return  # cancel-on-empty, checked on the raw input
    vaults, problem = find_vaults()
    if problem:
        sys.exit(problem)
    vault_id, _, vault = vaults[int(vault_index)]
    save_last_vault(vault)

    safe = sanitize(name)
    pdf_name = f"{safe} {STAMP}.pdf"
    attach_dir = os.path.join(vault, ATTACH_SUBDIR)
    note_dir = os.path.join(vault, NOTE_SUBDIR)
    os.makedirs(attach_dir, exist_ok=True)
    os.makedirs(note_dir, exist_ok=True)

    shutil.copy(src_pdf, os.path.join(attach_dir, pdf_name))

    note_path = os.path.join(note_dir, f"{safe}.md")
    if os.path.exists(note_path):
        note_path = os.path.join(note_dir, f"{safe} {STAMP}.md")

    with open(note_path, "w") as f:
        if body.strip():
            f.write(body.rstrip() + "\n\n")
        else:
            f.write("\n")  # blank line keeps the embed off the note's first line
        f.write(f"![[{pdf_name}]]\n")  # change ![[...]] to [[...]] for a plain link

    rel_noext = os.path.relpath(note_path, vault)[: -len(".md")]
    url = (
        f"obsidian://open?vault={urllib.parse.quote(vault_id)}"
        f"&file={urllib.parse.quote(rel_noext)}"
    )
    if os.environ.get("OBSIDIAN_PRINT_NO_OPEN"):
        print(url)
    else:
        subprocess.run(["open", url])


def main():
    args = sys.argv[1:]
    if len(args) == 2 and args[0] == "prepare":
        prepare(args[1])
    elif len(args) == 5 and args[0] == "save":
        save(*args[1:])
    else:
        sys.exit("usage: obsidian_print.py prepare <pdf> | "
                 "save <pdf> <vault index> <name> <body>")


if __name__ == "__main__":
    main()
