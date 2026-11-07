-- Source of "Save PDF to Obsidian.app" (build with build.sh). Installed in
-- ~/Library/PDF Services, it appears in the PDF menu of the print dialog;
-- macOS opens the printed PDF with it. This half shows the dialog;
-- obsidian_print.py (bundled in Contents/Resources) does the file work.
--
-- It is an app rather than a PDF Services script because scripts run inside
-- the printing app's sandbox, which blocks reading Obsidian's vault list and
-- writing to vaults outside iCloud.

use framework "AppKit"
use scripting additions

on run
	display alert "Save PDF to Obsidian" message "Use this from the PDF menu in a Print dialog."
end run

on open theFiles
	set pdfPath to POSIX path of (item 1 of theFiles)
	set py to quoted form of POSIX path of (path to resource "obsidian_print.py")
	try
		set prep to paragraphs of (do shell script "/usr/bin/python3 " & py & " prepare " & quoted form of pdfPath)
		if item 1 of prep is not "OK" then error (item 2 of prep)
		set answer to showDialog(item 2 of prep, (item 3 of prep) as integer, items 4 thru -1 of prep)
		if answer is missing value then return -- cancelled
		do shell script "/usr/bin/python3 " & py & " save " & quoted form of pdfPath & " " & (item 1 of answer) & " " & quoted form of (item 2 of answer) & " " & quoted form of (item 3 of answer)
	on error errMsg number errNum
		if errNum is not -128 then display alert "Save to Obsidian" message errMsg as critical
	end try
end open

-- Shows the dialog. Returns {vault index, note name, note text}, or
-- missing value if cancelled.
on showDialog(prefill, defaultVault, vaultNames)
	set theApp to current application's NSApplication's sharedApplication()
	ensureEditMenu(theApp)

	set alert to current application's NSAlert's alloc()'s init()
	(alert's setMessageText:"Save to Obsidian")
	(alert's addButtonWithTitle:"Save")
	(alert's addButtonWithTitle:"Cancel")

	set container to current application's NSView's alloc()'s initWithFrame:(current application's NSMakeRect(0, 0, 420, 286))

	set vaultLabel to current application's NSTextField's labelWithString:"Vault:"
	(vaultLabel's setFrame:(current application's NSMakeRect(0, 264, 420, 16)))

	set vaultPopup to current application's NSPopUpButton's alloc()'s initWithFrame:(current application's NSMakeRect(-3, 230, 426, 26)) pullsDown:false
	(vaultPopup's addItemsWithTitles:vaultNames)
	(vaultPopup's selectItemAtIndex:defaultVault)

	set nameLabel to current application's NSTextField's labelWithString:"Note name:"
	(nameLabel's setFrame:(current application's NSMakeRect(0, 204, 420, 16)))

	set nameField to current application's NSTextField's alloc()'s initWithFrame:(current application's NSMakeRect(0, 176, 420, 24))
	(nameField's setStringValue:prefill)

	set bodyLabel to current application's NSTextField's labelWithString:"Note text (goes above the PDF):"
	(bodyLabel's setFrame:(current application's NSMakeRect(0, 152, 420, 16)))

	-- A text view in a scroll view gets no focus ring, so it sits in a box
	-- whose border is drawn as a focus ring while the text view has focus
	set textBox to current application's NSBox's alloc()'s initWithFrame:(current application's NSMakeRect(0, 0, 420, 144))
	(textBox's setBoxType:4) -- NSBoxCustom
	(textBox's setTitlePosition:0) -- NSNoTitle
	(textBox's setCornerRadius:5)
	(textBox's setFillColor:(current application's NSColor's textBackgroundColor()))
	(textBox's setContentViewMargins:(current application's NSMakeSize(3, 3)))

	set scrollView to current application's NSScrollView's alloc()'s initWithFrame:(current application's NSMakeRect(0, 0, 414, 138))
	(scrollView's setHasVerticalScroller:true)
	(scrollView's setBorderType:0) -- NSNoBorder
	(scrollView's setDrawsBackground:false)
	(textBox's setContentView:scrollView)

	set textView to current application's NSTextView's alloc()'s initWithFrame:(current application's NSMakeRect(0, 0, 414, 138))
	(textView's setRichText:false)
	(textView's setAllowsUndo:true)
	(textView's setFont:(current application's NSFont's systemFontOfSize:13))
	(textView's setVerticallyResizable:true)
	(textView's setAutoresizingMask:2) -- NSViewWidthSizable
	(scrollView's setDocumentView:textView)

	(container's addSubview:vaultLabel)
	(container's addSubview:vaultPopup)
	(container's addSubview:nameLabel)
	(container's addSubview:nameField)
	(container's addSubview:bodyLabel)
	(container's addSubview:textBox)
	(alert's setAccessoryView:container)

	-- Typing is otherwise coalesced into one undo step until the cursor
	-- moves, so Cmd-Z would wipe out a whole run of typing at once. These
	-- timers break the coalescing so undo steps back through ~1-second
	-- bursts of typing instead.
	set win to alert's |window|()
	set fieldEd to (win's fieldEditor:true forObject:nameField)
	(fieldEd's setAllowsUndo:true)
	set runLoop to current application's NSRunLoop's currentRunLoop()
	set undoTimers to {}
	repeat with target in {textView, fieldEd}
		set t to (current application's NSTimer's timerWithTimeInterval:1.0 target:target selector:"breakUndoCoalescing" userInfo:(missing value) repeats:true)
		(runLoop's addTimer:t forMode:"kCFRunLoopDefaultMode")
		set end of undoTimers to t
	end repeat

	(win's setInitialFirstResponder:nameField)
	(nameField's setNextKeyView:textView)
	(textView's setNextKeyView:vaultPopup)
	(vaultPopup's setNextKeyView:nameField)

	-- Instead of runModal, show the alert as an ordinary window and pump
	-- events here, so the text box border can follow the keyboard focus
	-- (AppleScript can't define delegates to be told of focus changes, and
	-- can't hold the C pointer a modal session needs). Each button is
	-- retargeted to empty a one-item array, so a press shows up as count 0.
	set saveFlag to current application's NSMutableArray's arrayWithObject:"pending"
	set cancelFlag to current application's NSMutableArray's arrayWithObject:"pending"
	set alertButtons to alert's buttons() as list
	repeat with pair in {{item 1 of alertButtons, saveFlag}, {item 2 of alertButtons, cancelFlag}}
		((item 1 of pair)'s setTarget:(item 2 of pair))
		((item 1 of pair)'s setAction:"removeAllObjects")
	end repeat

	-- Native focus rings are translucent accent color over the alert's grey
	-- background; this ring is drawn over white, so pre-blend with that grey
	set appearanceName to ((win's effectiveAppearance())'s bestMatchFromAppearancesWithNames:{"NSAppearanceNameAqua", "NSAppearanceNameDarkAqua"}) as text
	if appearanceName is "NSAppearanceNameDarkAqua" then
		set alertGrey to current application's NSColor's colorWithWhite:0.2 alpha:1
	else
		set alertGrey to current application's NSColor's colorWithWhite:0.69 alpha:1
	end if
	set ringColor to alertGrey's blendedColorWithFraction:0.55 ofColor:(current application's NSColor's controlAccentColor())
	set plainColor to current application's NSColor's separatorColor()

	alert's layout()
	win's |center|()
	(theApp's activateIgnoringOtherApps:true)
	(win's makeKeyAndOrderFront:(missing value))
	set wasFocused to missing value
	repeat
		set ev to (theApp's nextEventMatchingMask:(current application's NSEventMaskAny) untilDate:(current application's NSDate's dateWithTimeIntervalSinceNow:0.05) inMode:"kCFRunLoopDefaultMode" dequeue:true)
		if ev is not missing value then
			-- Outside runModal, AppKit doesn't reliably map Return/Escape to
			-- the alert's buttons, so do it here. Return in the text box
			-- still inserts a newline.
			if (ev's |type|()) as integer is 10 then -- NSEventTypeKeyDown
				set kc to (ev's keyCode()) as integer
				if kc is 53 then -- Escape
					set resp to 1001
					exit repeat
				end if
				if (kc is 36 or kc is 76) and not (((win's firstResponder())'s isEqual:textView) as boolean) then -- Return, Enter
					set resp to 1000
					exit repeat
				end if
			end if
			(theApp's sendEvent:ev)
		end if
		if (saveFlag's |count|()) as integer is 0 then
			set resp to 1000
			exit repeat
		end if
		if (cancelFlag's |count|()) as integer is 0 then
			set resp to 1001
			exit repeat
		end if
		set isFocused to ((win's firstResponder())'s isEqual:textView) as boolean
		if isFocused is not wasFocused then
			if isFocused then
				(textBox's setBorderColor:ringColor)
				(textBox's setBorderWidth:3)
			else
				(textBox's setBorderColor:plainColor)
				(textBox's setBorderWidth:1)
			end if
			set wasFocused to isFocused
		end if
	end repeat
	repeat with t in undoTimers
		t's invalidate()
	end repeat
	(win's orderOut:(missing value))
	if resp is not 1000 then return missing value

	set vaultIndex to (vaultPopup's indexOfSelectedItem()) as integer
	set noteName to nameField's stringValue() as text
	set noteBody to textView's |string|() as text
	return {vaultIndex, noteName, noteBody}
end showDialog

-- Cmd-V/C/X/A/Z only work if the menu bar has an Edit menu with those key
-- equivalents; add one if the applet's menu bar lacks it.
on ensureEditMenu(theApp)
	set mainMenu to theApp's mainMenu()
	if mainMenu is missing value then
		set mainMenu to current application's NSMenu's alloc()'s initWithTitle:"MainMenu"
		(mainMenu's addItemWithTitle:"" action:(missing value) keyEquivalent:"") -- app menu slot
		(theApp's setMainMenu:mainMenu)
	end if
	if (mainMenu's itemWithTitle:"Edit") is not missing value then return
	set editItem to (mainMenu's addItemWithTitle:"Edit" action:(missing value) keyEquivalent:"")
	set editMenu to current application's NSMenu's alloc()'s initWithTitle:"Edit"
	(editMenu's addItemWithTitle:"Undo" action:"undo:" keyEquivalent:"z")
	(editMenu's addItemWithTitle:"Redo" action:"redo:" keyEquivalent:"Z")
	(editMenu's addItem:(current application's NSMenuItem's separatorItem()))
	(editMenu's addItemWithTitle:"Cut" action:"cut:" keyEquivalent:"x")
	(editMenu's addItemWithTitle:"Copy" action:"copy:" keyEquivalent:"c")
	(editMenu's addItemWithTitle:"Paste" action:"paste:" keyEquivalent:"v")
	(editMenu's addItemWithTitle:"Select All" action:"selectAll:" keyEquivalent:"a")
	(mainMenu's setSubmenu:editMenu forItem:editItem)
end ensureEditMenu
