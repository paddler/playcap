# PlayCap Setup Guide (on your child's Mac)

Takes about 10 minutes. Log in with a **parent administrator account** to do this.

## 1. Before you start

- Your child's account must be a **Standard user** (not an administrator).
  Check in System Settings > Users & Groups. If they are an administrator, turn off
  "Allow this user to administer this computer". (No data is lost.)
- The installer double-checks this and will stop with instructions if needed.

## 2. Install

1. Copy `PlayCap-installer.zip` to this Mac (AirDrop, USB, etc.) and double-click to extract
2. Open the extracted `PlayCap` folder
3. Double-click **Install.command**
   - If macOS blocks it ("cannot be opened"), right-click the file and choose **Open**, then **Open** again
4. Enter the administrator password when asked
5. Type your child's account name when the list of users appears
6. You should see "Install complete" with the current settings

Default settings: **120 min on weekdays / 180 min on weekends / allowed 07:00-21:00**

## 3. First-time test (5 minutes)

1. Open **PlayCap** from the Applications folder and temporarily set the daily limits to 2 minutes (admin password required)
2. Switch to your child's account and start Roblox — **it should quit automatically after about 2 minutes**
   (if macOS asks to allow notifications, choose Allow)
3. While Roblox is running, you can confirm the process is visible:
   open Terminal and run `ps aux | grep -i roblox` — you should see a process containing "roblox"
4. Switch back to your account and restore the real limits in PlayCap

## 4. Daily use

- **Change settings**: open **PlayCap** in the Applications folder (admin password required to save; your child can look but not change)
- **Extend today only**: the "+30 min today" button (resets automatically tomorrow)
- **Terminal fans**: `playcap status`, `sudo playcap --help`
- **Other games**: add e.g. `roblox,minecraft` in "Monitored apps"
- **History**: the last 7 days are shown in the app; the full log is at
  `/Library/Application Support/PlayCap/usage.log`

## 5. Uninstall

Double-click **Uninstall.command** (or run `sudo ./uninstall.sh`).

## How it works & limitations

- A root-level monitor checks every 30 seconds for the monitored game processes,
  counts play time, warns at 10/5/1 minutes remaining, and quits the game at the limit
  or outside allowed hours
- Your child cannot stop the monitor, change settings, or change the clock, because
  their account is a Standard user
- Time is only counted while the game is actually running (sleep doesn't count)
- Known limitation: a technically savvy child could rename a copied app binary to dodge
  process-name matching. If usage.log shows zero for days while play clearly happened,
  be suspicious
