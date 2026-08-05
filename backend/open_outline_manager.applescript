-- Paste Outline JSON, click Done, then copy Key 0 access key from Outline Manager.
-- Avoids walking "entire contents" (hangs on Electron). Uses targeted UI element search.
-- Requires Accessibility permission for the app running this script.

on run argv
	set jsonPayload to item 1 of argv
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

			-- Open share menu for the first access key (often labeled Key 0 / Outline key).
			my clickShareForKeyZero()
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
			-- Menu items from share popover
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
				end repeat
			end try
		end tell
	end tell
	return false
end clickMenuOrButton

on clickShareForKeyZero()
	tell application "System Events"
		tell process "Outline Manager"
			try
				repeat with w in windows
					-- Prefer a share/button near Key 0 text.
					try
						repeat with s in static texts of w
							set labelText to ""
							try
								set labelText to value of s as text
							end try
							if labelText is "Key 0" or labelText is "Key0" or labelText contains "Key 0" then
								try
									set parentEl to UI element 1 of s
								end try
								try
									click s
									delay 0.3
								end try
							end if
						end repeat
					end try

					-- Common share control names / descriptions
					set shareNames to {"Share", "share", "Copy access key", "More"}
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
end clickShareForKeyZero
