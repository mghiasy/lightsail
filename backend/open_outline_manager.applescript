-- Paste Outline JSON, click Done, rename key to cursor-key, set 2.5TB data limit
-- (2500 GB), then copy the access key from Outline Manager.
-- Avoids walking "entire contents" (hangs on Electron). Uses targeted UI element search.
-- Requires Accessibility permission for the app running this script.
--
-- argv: 1=management JSON, 2=limit GB (default 2500), 3=key name (default cursor-key)

on run argv
	set jsonPayload to item 1 of argv
	set limitGB to "2500"
	set keyName to "cursor-key"
	if (count of argv) ≥ 2 then
		set limitGB to item 2 of argv as text
	end if
	if (count of argv) ≥ 3 then
		set keyName to item 3 of argv as text
	end if
	set the clipboard to jsonPayload

	tell application "Outline Manager" to activate
	delay 1.5

	tell application "System Events"
		if not (exists process "Outline Manager") then error "Outline Manager is not running"
		tell process "Outline Manager"
			set frontmost to true
			delay 0.5

			-- Paste management JSON into the focused field.
			keystroke "v" using command down
			delay 0.8

			-- Click Done / confirm add server.
			if not my clickButtonNamed("Done") then
				my clickButtonNamed("OK")
			end if
			delay 2.5

			-- Rename Key 0 / My access key → cursor-key (best-effort; API also renames).
			my renameFirstAccessKey(keyName)
			delay 0.8

			-- Edit key → Data Limit → 2500 GB → Save
			if not my setDataLimitForKey(keyName, limitGB) then
				error "Could not set data limit in Outline Manager"
			end if
			delay 1.0

			-- Open share menu for the renamed access key.
			my clickShareForKey(keyName)
			delay 0.8

			-- Choose "Copy access key"
			if not my clickMenuOrButton("Copy access key") then
				my clickMenuOrButton("Copy")
			end if
			delay 0.5
		end tell
	end tell

	return the clipboard as text
end run

on isTargetKeyLabel(labelText, keyName)
	if labelText is keyName then return true
	if labelText is "Key 0" or labelText is "Key0" then return true
	if labelText contains "Key 0" then return true
	if labelText is "My access key" then return true
	return false
end isTargetKeyLabel

on renameFirstAccessKey(keyName)
	-- Already renamed (e.g. via API before Manager opened).
	if my keyLabelExists(keyName) then
		return true
	end if

	if not my clickOverflowForKey(keyName) then
		return false
	end if
	delay 0.5
	if not my clickMenuOrButton("Rename") then
		return false
	end if
	delay 0.4
	my focusDataLimitInput()
	delay 0.2
	tell application "System Events"
		keystroke "a" using command down
		delay 0.1
		keystroke keyName
		delay 0.2
		key code 36 -- Return
	end tell
	delay 0.6
	return true
end renameFirstAccessKey

on keyLabelExists(exactName)
	tell application "System Events"
		tell process "Outline Manager"
			try
				repeat with w in windows
					try
						repeat with s in static texts of w
							set labelText to ""
							try
								set labelText to value of s as text
							end try
							if labelText is exactName then
								return true
							end if
						end repeat
					end try
				end repeat
			end try
		end tell
	end tell
	return false
end keyLabelExists

on clickKeyLabel(keyName)
	tell application "System Events"
		tell process "Outline Manager"
			try
				repeat with w in windows
					try
						repeat with s in static texts of w
							set labelText to ""
							try
								set labelText to value of s as text
							end try
							if my isTargetKeyLabel(labelText, keyName) then
								try
									click s
								end try
								return true
							end if
						end repeat
					end try
				end repeat
			end try
		end tell
	end tell
	return false
end clickKeyLabel

on setDataLimitForKey(keyName, limitGB)
	-- Open Data Limit dialog via overflow menu (or direct Data Limit control).
	if not my openDataLimitDialog(keyName) then
		return false
	end if
	delay 0.8

	-- Enable "Set a custom data limit"
	if not my clickCheckboxOrText("Set a custom data limit") then
		my clickMenuOrButton("Set a custom data limit")
	end if
	delay 0.5

	-- Focus the numeric field and type the limit in GB (UI has GB/MB only; 2500 GB = 2.5 TB).
	my focusDataLimitInput()
	delay 0.2
	tell application "System Events"
		keystroke "a" using command down
		delay 0.1
		keystroke limitGB
	end tell
	delay 0.3

	-- Prefer GB unit if the unit dropdown is openable.
	my clickMenuOrButton("GB")
	delay 0.2

	if not my clickButtonNamed("Save") then
		my clickMenuOrButton("Save")
	end if
	delay 0.8
	return true
end setDataLimitForKey

on openDataLimitDialog(keyName)
	-- Prefer an already-visible Data Limit / Data Limits control (admin key shortcut).
	if my clickMenuOrButton("Data Limit") then
		return true
	end if
	if my clickMenuOrButton("Data Limits") then
		return true
	end if

	-- Otherwise open the ⋮ menu on the target key, then Data Limit.
	if my clickOverflowForKey(keyName) then
		delay 0.5
		if my clickMenuOrButton("Data Limit") then
			return true
		end if
	end if
	return false
end openDataLimitDialog

on clickOverflowForKey(keyName)
	tell application "System Events"
		tell process "Outline Manager"
			try
				repeat with w in windows
					-- Click the key row first so its controls are active.
					my clickKeyLabel(keyName)
					delay 0.3

					set overflowNames to {"more_vert", "More", "more", "Open menu", "Menu"}
					repeat with overflowName in overflowNames
						try
							repeat with b in buttons of w
								set bName to ""
								try
									set bName to name of b as text
								end try
								if bName is "" then
									try
										set bName to description of b as text
									end try
								end if
								if bName contains overflowName then
									click b
									return true
								end if
							end repeat
						end try
					end repeat

					-- Fallback: last icon-style button on the window is often the ⋮ menu.
					try
						set btns to buttons of w
						if (count of btns) ≥ 1 then
							click item -1 of btns
							return true
						end if
					end try
				end repeat
			end try
		end tell
	end tell
	return false
end clickOverflowForKey

on clickCheckboxOrText(targetName)
	tell application "System Events"
		tell process "Outline Manager"
			try
				repeat with w in windows
					try
						repeat with c in checkboxes of w
							try
								set cName to name of c as text
								if cName contains targetName then
									click c
									return true
								end if
							end try
							try
								set cDesc to description of c as text
								if cDesc contains targetName then
									click c
									return true
								end if
							end try
						end repeat
					end try
					try
						repeat with s in static texts of w
							try
								if (value of s as text) contains targetName then
									click s
									return true
								end if
							end try
						end repeat
					end try
				end repeat
			end try
		end tell
	end tell
	return false
end clickCheckboxOrText

on focusDataLimitInput()
	tell application "System Events"
		tell process "Outline Manager"
			try
				repeat with w in windows
					try
						repeat with t in text fields of w
							try
								set focus of t to true
								return true
							end try
						end repeat
					end try
					try
						-- paper-input may expose as a generic UI element / combo box
						repeat with t in text fields of groups of w
							try
								set focus of t to true
								return true
							end try
						end repeat
					end try
				end repeat
			end try
		end tell
	end tell
	-- Last resort: tab into the dialog field
	try
		tell application "System Events" to key code 48 -- Tab
	end try
	return false
end focusDataLimitInput

on clickButtonNamed(targetName)
	tell application "System Events"
		tell process "Outline Manager"
			try
				repeat with w in windows
					try
						set btns to buttons of w
						repeat with b in btns
							try
								if (name of b as text) contains targetName then
									click b
									return true
								end if
							end try
						end repeat
					end try
					try
						set btns to buttons of groups of w
						repeat with b in btns
							try
								if (name of b as text) contains targetName then
									click b
									return true
								end if
							end try
						end repeat
					end try
				end repeat
			end try
		end tell
	end tell
	return false
end clickButtonNamed

on clickMenuOrButton(targetName)
	tell application "System Events"
		tell process "Outline Manager"
			-- Menu items from share / overflow popover
			try
				repeat with w in windows
					try
						set mis to menu items of menus of w
						repeat with mi in mis
							try
								if (name of mi as text) contains targetName then
									click mi
									return true
								end if
							end try
						end repeat
					end try
					try
						repeat with b in buttons of w
							try
								if (name of b as text) contains targetName then
									click b
									return true
								end if
							end try
						end repeat
					end try
					try
						repeat with r in rows of tables of w
							try
								if (name of r as text) contains targetName or (value of r as text) contains targetName then
									click r
									return true
								end if
							end try
						end repeat
					end try
					try
						repeat with s in static texts of w
							try
								if (value of s as text) contains targetName then
									click s
									return true
								end if
							end try
						end repeat
					end try
					-- Material list items often expose as UI elements / groups
					try
						repeat with g in groups of w
							try
								if (name of g as text) contains targetName then
									click g
									return true
								end if
							end try
							try
								repeat with s in static texts of g
									try
										if (value of s as text) contains targetName then
											click s
											return true
										end if
									end try
								end repeat
							end try
						end repeat
					end try
				end repeat
			end try
		end tell
	end tell
	return false
end clickMenuOrButton

on clickShareForKey(keyName)
	tell application "System Events"
		tell process "Outline Manager"
			try
				repeat with w in windows
					my clickKeyLabel(keyName)
					delay 0.3

					-- Common share control names / descriptions
					set shareNames to {"Share", "share", "Copy access key"}
					repeat with shareName in shareNames
						try
							repeat with b in buttons of w
								set bName to ""
								try
									set bName to name of b as text
								end try
								if bName is "" then
									try
										set bName to description of b as text
									end try
								end if
								if bName contains shareName then
									click b
									return true
								end if
							end repeat
						end try
					end repeat
				end repeat
			end try
		end tell
	end tell
	return false
end clickShareForKey
