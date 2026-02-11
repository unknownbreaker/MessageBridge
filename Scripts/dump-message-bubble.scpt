-- Diagnostic script to dump Messages.app message bubble accessibility tree
--
-- Instructions:
-- 1. Open Messages.app manually
-- 2. Select a conversation with at least a few messages
-- 3. Run this script: osascript Scripts/dump-message-bubble.scpt
--
-- FINDINGS (macOS 26.2 Tahoe):
-- - No splitter group at top level — deeply nested groups under group 1 of window 1
-- - Message bubbles are text area [AXTextArea] elements, desc="text entry area"
-- - Message text is in the `value` property
-- - "Reply…" is a direct named action (no need for AXShowMenu → context menu)
-- - Other direct actions: Heart, Thumbs up, Copy, Forward…, Delete…, etc.
-- - Use `entire contents of group 1 of window 1` to find message text areas

tell application "System Events"
	tell process "Messages"
		set output to "=== Messages.app Message Bubbles ===" & linefeed & linefeed

		set allElems to entire contents of group 1 of window 1
		set output to output & "Total elements: " & (count of allElems) & linefeed & linefeed

		set counter to 0
		repeat with elem in allElems
			try
				set eVal to value of elem
				if eVal is not missing value and eVal is not "" then
					set eClass to class of elem as string
					set eRole to role of elem
					set eDesc to ""
					try
						set eDesc to description of elem
					end try
					if (length of (eVal as string)) < 120 then
						set output to output & eClass & " [" & eRole & "] desc=\"" & eDesc & "\" value=\"" & eVal & "\"" & linefeed
						try
							set actionList to name of actions of elem
							if (count of actionList) > 0 then
								set output to output & "  actions: " & (actionList as string) & linefeed
							end if
						end try
						set counter to counter + 1
						if counter > 30 then exit repeat
					end if
				end if
			end try
		end repeat

		set output to output & linefeed & "Elements with values found: " & counter
		return output
	end tell
end tell
