# Save PDF to Obsidian

A macOS [PDF Services](https://developer.apple.com/library/archive/documentation/Printing/Conceptual/PDF_Workflow_ManPage/Introduction/Introduction.html)
script that adds a **Save PDF to Obsidian** item to the PDF menu of the system
print dialog. Choosing it:

1. Shows a single dialog with a vault dropdown, a note-name field (prefilled
   from the print job title), and a multi-line text box.
2. Copies the generated PDF into the vault's attachments folder, with a
   timestamp appended to the filename.
3. Creates a Markdown note that contains the text you entered (if any)
   followed by an `![[...]]` embed of the PDF.
4. Opens the new note in Obsidian.

## Installation

Copy the script (keeping it executable) into `~/Library/PDF Services/`,
creating that folder if needed:

```bash
mkdir -p ~/Library/PDF\ Services
cp "Save PDF to Obsidian" ~/Library/PDF\ Services/
```

The filename is the menu label, so rename it if you want different wording in
the print dialog. It appears immediately in the PDF menu (the dropdown in the
lower-left of the print dialog); no restart needed.

Requirements: the Xcode Command Line Tools' `/usr/bin/python3` (standard
library only — no packages to install). Everything else is built into macOS.

## Configuration

Edit the `CONFIGURE` block at the top of the script:

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
  vault you open in Obsidian shows up in the dropdown with no script changes.
  Vaults whose folder no longer exists are skipped. The list is sorted by name.
- **Remembered vault.** The vault you save to is preselected the next time.
  It is stored in `~/Library/Application Support/obsidian-print/state.json`.
  If that vault has disappeared, the first vault in the list is preselected.
- **Note naming.** The name is sanitized (characters illegal in filenames or
  meaningful to Obsidian links become `-`). If a note with that name already
  exists, a `YYYYMMDD-HHMMSS` timestamp is appended instead of overwriting.
  The PDF always gets the timestamp, so repeated prints can't collide.
- **Cancel.** Pressing Cancel (or Escape, or emptying the name field) saves
  nothing.
- **Empty note text** still produces one blank line above the embed, so the
  cursor at the top of the note sits on an empty line rather than on the link.
- **Keyboard.** Return saves and Escape cancels, except that in the text box
  Return inserts a newline (and Tab inserts a tab — click or Ctrl-Tab to
  leave it). ⌘V/⌘C/⌘X/⌘A/⌘Z work as usual, and undo steps back through
  roughly one-second bursts of typing. The text box shows a blue focus
  border while it has the cursor, like the name field.
- **Clipboard utilities** (e.g. Copy 'Em Paste) paste into whichever app owns
  the menu bar. macOS won't let the dialog take the menu bar on its own, so
  click in the dialog first; it then shows its own menu bar ("osascript") and
  a Dock icon while open, and the utility pastes into it.
- To link the PDF instead of embedding it, change `![[...]]` to `[[...]]` in
  the line noted in the script.

## How it works

macOS runs PDF Services scripts with the print job title as the first
argument and the path to an already-generated temporary PDF as the last. The
script is plain Python (stdlib only); the one non-obvious part is the dialog.

AppleScript's `display dialog` supports only a single text field, and neither
tkinter nor PyObjC can be counted on outside of extra installs, so the dialog
is built with native AppKit via a small AppleScriptObjC program run through
`osascript` (source embedded in the Python file as `DIALOG_SCRIPT`). It is an
`NSAlert` whose accessory view holds an `NSPopUpButton` (vaults), an
`NSTextField`, and a scrollable `NSTextView`. Python passes in the vault names
and the index to preselect; the dialog returns the chosen index, name, and
text on stdout joined by a random delimiter. Cancel becomes AppleScript error
−128, i.e. a nonzero exit. The note is opened via
`obsidian://open?vault=<vault ID>`, using the ID from Obsidian's registry so
two vaults with the same folder name can't be confused.

Quirks of running AppKit UI from `osascript`, worked around in
`DIALOG_SCRIPT`:

- **No menu bar**, so ⌘V and friends are dead until a (never-displayed) Edit
  menu with the standard key equivalents is installed as the app's main menu.
- **No custom classes.** `osascript` can call Objective-C but cannot define
  subclasses (`Can't get class "NSObject"`), which rules out delegates,
  notification observers, and custom views. It also can't hold opaque C
  pointers, so `beginModalSessionForWindow:` is unusable.
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
- `alert's |window|()` uses method-call syntax so AppleScript doesn't parse
  `window` as an element specifier; likewise `|string|()`, `|count|()`,
  `|type|()`, and `|center|()` escape method names that collide with
  AppleScript keywords.

## Credits

Written by Nat Kuhn with Claude. The original two-dialog shell script was
written by Claude in Claude Desktop; the Python rewrite (single dialog,
paste/undo support) was written by Claude Fable 5, and multi-vault support and
the text box focus ring by Claude Opus 5.5, both in Claude Code.
