# Save PDF to Obsidian

A small macOS app that adds a **Save PDF to Obsidian** item to the PDF menu of
the system print dialog (the dropdown in its lower-left corner). Choosing it:

1. Shows a single dialog with a vault dropdown, a note-name field (prefilled
   from the document's title), and a multi-line text box.
2. Copies the PDF into the vault's attachments folder, with a timestamp
   appended to the filename.
3. Creates a Markdown note that contains the text you entered (if any)
   followed by an `![[...]]` embed of the PDF.
4. Opens the new note in Obsidian.

## Installation

```bash
./build.sh --install
```

This builds `build/Save PDF to Obsidian.app` and copies it into
`~/Library/PDF Services/` (replacing any earlier version, including the older
script-only version). It appears in the print dialog's PDF menu immediately;
no restart needed. The app's name is the menu label. Run the same command
again after changing anything.

Requirements: the Xcode Command Line Tools (for `/usr/bin/python3`, standard
library only). Everything else is built into macOS.

## Configuration

Edit the `CONFIGURE` block at the top of `obsidian_print.py`, then rebuild:

| Variable | Meaning |
|---|---|
| `ATTACH_SUBDIR` | Folder inside each vault where PDFs are saved |
| `NOTE_SUBDIR` | Folder inside each vault where notes are created |
| `EXCLUDE_VAULTS` | Vault names to leave out of the dropdown (default: Obsidian's built-in `Obsidian Sandbox`) |

The same folder layout is used for every vault, and the folders are created
if they don't exist.

## Behavior details

- **Vault list.** Vaults are discovered automatically from Obsidian's own
  registry (`~/Library/Application Support/obsidian/obsidian.json`), so any
  vault you open in Obsidian shows up in the dropdown. Vaults whose folder no
  longer exists are skipped. The list is sorted by name.
- **Remembered vault.** The vault you save to is preselected the next time.
  It is stored in `~/Library/Application Support/obsidian-print/state.json`.
  If that vault has disappeared, the first vault in the list is preselected.
- **Note naming.** The prefill is the PDF's filename, which macOS takes from
  the document title. The name is sanitized (characters illegal in filenames
  or meaningful to Obsidian links become `-`). If a note with that name
  already exists, a `YYYYMMDD-HHMMSS` timestamp is appended instead of
  overwriting. The PDF always gets the timestamp, so repeated prints can't
  collide.
- **Cancel.** Pressing Cancel (or Escape, or emptying the name field) saves
  nothing.
- **Empty note text** still produces one blank line above the embed, so the
  cursor at the top of the note sits on an empty line rather than on the link.
- **Keyboard.** Return saves and Escape cancels, except that in the text box
  Return inserts a newline (and Tab inserts a tab — click or Ctrl-Tab to
  leave it). ⌘V/⌘C/⌘X/⌘A/⌘Z work as usual, and undo steps back through
  roughly one-second bursts of typing. The text box shows a blue focus
  border while it has the cursor, like the name field.
- To link the PDF instead of embedding it, change `![[...]]` to `[[...]]` in
  the line noted in `obsidian_print.py`.

## How it works

Files:

- `Save PDF to Obsidian.applescript` — the app: receives the PDF, shows the
  dialog, and calls the Python script.
- `obsidian_print.py` — the file work. `prepare <pdf>` prints the note-name
  prefill, the vault to preselect, and the vault names; `save <pdf> <vault
  index> <name> <text>` copies the PDF, writes the note, remembers the vault,
  and opens the note via `obsidian://open?vault=<vault ID>` (the ID from
  Obsidian's registry, so two vaults with the same folder name can't be
  confused).
- `build.sh` — compiles the AppleScript into an app with `osacompile`, puts
  `obsidian_print.py` in its `Contents/Resources`, sets a bundle ID, and
  re-signs it (ad hoc).

**Why an app and not a script.** PDF Services also accepts plain scripts,
and this started as one. But a script runs inside the printing app's sandbox
(seen with both Chrome and Preview): it couldn't read Obsidian's vault
registry, couldn't write its own settings, and couldn't write to vaults
outside the iCloud Obsidian folder. An app in PDF Services is instead
launched by macOS as a normal app that is handed the PDF, so none of those
restrictions apply. Being a regular app also means it owns the menu bar while
the dialog is up, so clipboard utilities (e.g. Copy 'Em Paste) paste into it.

**The dialog** is an `NSAlert` whose accessory view holds an `NSPopUpButton`
(vaults), an `NSTextField`, and a scrollable `NSTextView`, built with
AppleScriptObjC (AppleScript's `display dialog` supports only one text
field, and the system Python has no GUI toolkit). AppleScriptObjC limitations
shape it:

- **No custom classes** outside of Xcode projects: no subclasses, delegates,
  or notification observers. It also can't hold opaque C pointers, so
  `beginModalSessionForWindow:` is unusable.
- **Hence a hand-rolled event loop.** A text view inside a scroll view gets
  no focus ring, and without delegates there's no way to be told when focus
  changes. So instead of `-[NSAlert runModal]`, the alert window is shown
  normally and the script pumps events itself
  (`nextEventMatchingMask:…` / `sendEvent:`), checking after each event
  whether the text view is first responder and restyling the `NSBox` around
  it as a focus ring (accent color pre-blended with the alert's grey, since
  native rings are translucent over grey but this one is drawn over white).
  Consequences of leaving `runModal`:
  - Each button's target/action is pointed at an `NSMutableArray`'s
    `removeAllObjects`, so a click shows up as the array becoming empty.
  - AppKit doesn't reliably map Return/Escape to the alert's buttons outside
    `runModal`, so the loop intercepts those keys itself.
- **Undo granularity.** `NSTextView` coalesces continuous typing into one
  undo step, so ⌘Z would remove everything typed in one go; repeating timers
  call `breakUndoCoalescing` (timers only need a target and an existing
  selector, so they work without custom classes).
- **Edit menu.** ⌘V and friends need an Edit menu with those key
  equivalents; one is added if the app's menu bar lacks it.
- `alert's |window|()` uses method-call syntax so AppleScript doesn't parse
  `window` as an element specifier; likewise `|string|()`, `|count|()`,
  `|type|()`, and `|center|()` escape method names that collide with
  AppleScript keywords.

**Testing without printing.** `obsidian_print.py` reads the environment
variables `OBSIDIAN_PRINT_REGISTRY` and `OBSIDIAN_PRINT_STATE` (alternate
registry and state files) and `OBSIDIAN_PRINT_NO_OPEN` (print the
`obsidian://` URL instead of opening it), so the app can be run against test
vaults, e.g.:

```bash
open -a "build/Save PDF to Obsidian.app" --env OBSIDIAN_PRINT_REGISTRY=/path/to/test.json \
  --env OBSIDIAN_PRINT_STATE=/tmp/state.json --env OBSIDIAN_PRINT_NO_OPEN=1 some.pdf
```

## Credits

Written by Nat Kuhn with Claude. The original two-dialog shell script was
written by Claude in Claude Desktop; the Python rewrite (single dialog,
paste/undo support) was written by Claude Fable 5, and multi-vault support,
the text box focus ring, and the conversion to an app by Claude Opus 5.5,
both in Claude Code.
