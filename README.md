# Save PDF to Obsidian

A macOS [PDF Services](https://developer.apple.com/library/archive/documentation/Printing/Conceptual/PDF_Workflow_ManPage/Introduction/Introduction.html)
script that adds a **Save PDF to Obsidian** item to the PDF menu of the system
print dialog. Choosing it:

1. Shows a single dialog with a note-name field (prefilled from the print job
   title) and a multi-line text box.
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
| `VAULT` | Absolute path to the Obsidian vault |
| `ATTACH_SUBDIR` | Folder inside the vault where PDFs are saved |
| `NOTE_SUBDIR` | Folder inside the vault where notes are created |
| `VAULT_NAME` | Vault name as Obsidian knows it, for the `obsidian://` URL |

## Behavior details

- **Note naming.** The name is sanitized (characters illegal in filenames or
  meaningful to Obsidian links become `-`). If a note with that name already
  exists, a `YYYYMMDD-HHMMSS` timestamp is appended instead of overwriting.
  The PDF always gets the timestamp, so repeated prints can't collide.
- **Cancel.** Pressing Cancel (or Escape, or emptying the name field) saves
  nothing.
- **Empty note text** still produces one blank line above the embed, so the
  cursor at the top of the note sits on an empty line rather than on the link.
- **Keyboard.** In the name field, Return saves. In the text box, Return
  inserts a newline; ⌘V/⌘C/⌘X/⌘A/⌘Z work as usual, and undo steps back
  through roughly one-second bursts of typing.
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
`NSAlert` whose accessory view holds an `NSTextField` and a scrollable
`NSTextView`. The two values return on stdout joined by a random delimiter;
Cancel becomes AppleScript error −128, i.e. a nonzero exit.

Three quirks of running AppKit UI from `osascript`, worked around in
`DIALOG_SCRIPT`:

- **No menu bar**, so ⌘V and friends are dead until a (never-displayed) Edit
  menu with the standard key equivalents is installed as the app's main menu.
- **Modal run loop vs. undo.** `NSUndoManager` closes undo groups only in the
  default run loop mode, but `-[NSAlert runModal]` runs in the modal-panel
  mode — so every keystroke piles into one undo group and ⌘Z clears the whole
  field. Fix: add `NSModalPanelRunLoopMode` to the window undo manager's
  `runLoopModes`, plus repeating timers that call `breakUndoCoalescing` so
  continuous typing is chopped into undoable chunks.
- **No custom classes.** `osascript` can call Objective-C but cannot define
  subclasses (`Can't get class "NSObject"`), which rules out delegates,
  notification observers, and similar patterns. Hence the timer trick above
  (timers only need a target and an existing selector), and `alert's
  |window|()` — method-call syntax that avoids AppleScript parsing `window`
  as an element specifier.
