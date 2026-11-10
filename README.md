# atieclxx-fix

Stops the AMD Radeon driver from writing about **40–55 GB a day** to your system SSD, without turning off the AMD service.

In late 2026, Radeon owners noticed `atieclxx.exe` (the "AMD External Events Utility" that ships with Adrenalin) writing to disk nonstop, even with the PC idle. AMD confirmed the bug and says the fix will come in Adrenalin 26.11.1. Until that release, the usual advice is to disable the service, which can cost you Adrenalin hotkeys and possibly FreeSync.

This repo finds what the utility is actually writing and blocks only that.

## What's going on

About once a second, `atieclxx.exe` copies its own program file (677 KB) from the driver store to:

```
C:\Windows\System32\config\systemprofile\AppData\Local\AMD\atieclxx.exe
```

The copy is byte-for-byte identical every time, but Windows still writes it to the drive. Each pass also checks for the setup files of AMD's PCIe filter driver (`amdkmpfd`). When those files are missing, the check never passes and the loop never stops.

On the test PC that came to **662 KB/s, or about 55 GB a day**. Process Monitor showed about 0.48 MB/s of it reaching the SSD as real disk writes. Details and raw traces: [docs/how-it-works.md](docs/how-it-works.md).

## Am I affected?

Open PowerShell (no admin needed) and run:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/candygoogy/atieclxx-fix/main/atieclxx-fix.ps1))) -Check
```

It watches `atieclxx.exe` for 15 seconds and tells you how much it's writing. Anything over about 50 KB/s means you have the bug.

You can also check by hand: open Task Manager → Details, right-click a column header → Select columns → add **I/O write bytes**, and watch `atieclxx.exe`. If the number climbs every second, you're affected.

## Fix it

1. Download this repo (green **Code** button → **Download ZIP**) and extract it.
2. Double-click **`Fix-SSD-Writes.cmd`** and accept the admin prompt.
3. Press **F**.

The script measures the writes, applies the fix and measures again, so you can watch the number drop to zero. If the writes don't stop, your PC has a different cause: the script undoes its change and tells you so.

From an admin PowerShell, the same steps are:

```powershell
.\atieclxx-fix.ps1 -Check   # measure only
.\atieclxx-fix.ps1 -Fix     # apply and verify
.\atieclxx-fix.ps1 -Undo    # put things back
```

## What the fix changes

One permission on one file. The SYSTEM account loses write and delete access to the copied `atieclxx.exe` above. When the utility tries its once-a-second copy, Windows refuses, and nothing is written.

- The AMD service keeps running, so hotkeys and display events keep working.
- The existing copy stays in place and is identical to the original.
- The utility doesn't retry any faster; it just keeps failing quietly.
- Nothing is deleted, disabled or patched. AMD's files are untouched.
- The fix survives reboots.

## Before you update the AMD driver

**Run `Undo` first** (`Fix-SSD-Writes.cmd` → **U**). Otherwise the new driver's utility can't refresh its copy. After the update, run **Check**: if AMD's fix works, you're done; if not, apply this fix again.

## Tested on

- Windows 11, Radeon RX 9070 XT, driver 32.0.32015.12012 (dated 28 Oct 2026)
- Windows PowerShell 5.1 and PowerShell 7

Reports from other GPUs and driver versions are welcome. Open an issue with the output of `-Check`, whether the fix worked or not.

## Not affiliated with AMD

This is an independent workaround. Use it at your own risk; `Undo` puts everything back.

## License

MIT
