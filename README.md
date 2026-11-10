# atieclxx-fix

Stops the AMD Radeon driver from writing **40–55 GB a day** to your system SSD, and keeps the AMD service running.

In November 2026, Radeon owners noticed `atieclxx.exe` (the "AMD External Events Utility" that ships with Adrenalin) writing to disk nonstop, even on an idle PC. AMD confirmed the bug and says the fix will come in Adrenalin 26.11.1. Until that release, the usual advice is to disable the service, which can cost you Adrenalin hotkeys and possibly FreeSync.

This repo finds what the utility is actually writing and blocks only that.

```
Before:
  662 KB/s
  Applied: SYSTEM can no longer overwrite or delete the copy.

After:
  0 B/s

  FIXED. The constant writes have stopped.
```

## What's going on

About once a second, `atieclxx.exe` copies its own program file (677 KB) from the driver store to:

```
C:\Windows\System32\config\systemprofile\AppData\Local\AMD\atieclxx.exe
```

The copy is byte-for-byte identical every time, but Windows still writes it to the drive. Each pass also checks for the setup files of AMD's PCIe filter driver (`amdkmpfd`). When those files are missing, the check never passes and the loop never stops.

On the test PC that came to **662 KB/s, or about 55 GB a day**. Process Monitor showed about 0.48 MB/s of it reaching the SSD as real disk writes. Traces and details: [docs/how-it-works.md](docs/how-it-works.md).

## Am I affected?

Open PowerShell (no admin needed) and paste:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/candygoogy/atieclxx-fix/main/atieclxx-fix.ps1))) -Check
```

It watches `atieclxx.exe` for 15 seconds and tells you how much it's writing.

You can also check without running anything: Task Manager → **Details** → right-click a column header → **Select columns** → tick **I/O write bytes**, then watch `atieclxx.exe`. If the number climbs every second, you're affected.

## Fix it

1. Download **[atieclxx-fix.zip](https://github.com/candygoogy/atieclxx-fix/releases/latest/download/atieclxx-fix.zip)** and extract it.
2. Double-click **`Fix-SSD-Writes.cmd`** and accept the admin prompt.
3. Press **F**.

The script measures the writes, applies the fix and measures again, so you can watch the number drop to zero. If your PC isn't writing, it changes nothing. If the fix doesn't stop the writes, your PC has a different cause, and the script undoes its change and says so.

If Windows shows a warning ("Windows protected your PC" or "Open File – Security Warning"), click **More info → Run anyway** or **Run**. Windows shows that for any script downloaded from the internet. The whole fix is one readable PowerShell file, [`atieclxx-fix.ps1`](atieclxx-fix.ps1).

From an admin PowerShell, the same steps are:

```powershell
.\atieclxx-fix.ps1 -Check   # measure only
.\atieclxx-fix.ps1 -Fix     # apply and verify
.\atieclxx-fix.ps1 -Undo    # put things back
```

## What the fix changes

One permission on one file. The SYSTEM account loses write and delete access to the copied `atieclxx.exe` above. When the utility tries its once-a-second copy, Windows refuses before anything is written.

- The AMD service keeps running, so hotkeys and display events keep working.
- The existing copy stays in place and is identical to the original.
- The utility doesn't retry any faster; it just keeps failing quietly.
- Nothing is deleted, disabled or patched, and no background task is installed.

Nothing on Windows launches that copy: no service, scheduled task or startup entry points to it. Blocking it only stops the rewriting.

## Reboots and driver updates

**Reboots:** the fix is a file permission, so it's stored on the drive and survives restarts. When the AMD service starts again, the copy fails right away; in testing, a restarted service wrote 0 bytes.

**Driver updates:** the AMD installer leaves the copy alone, so the block stays in place. The new driver's utility can't refresh its copy, which is harmless because nothing runs it. After updating, run **`Fix-SSD-Writes.cmd` → F** once:

- the status line shows `APPLIED, but the driver changed since`
- the script lifts the block and lets the new driver refresh its copy
- if the new driver still has the bug, it blocks it again; if AMD's fix works, it leaves things alone

You don't need to undo anything before updating. If you'd rather start clean, **U** removes the fix.

## Tested on

- Windows 11, Radeon RX 9070 XT, driver 32.0.32015.12012 (28 Oct 2026)
- Windows PowerShell 5.1 and PowerShell 7

Reports from other GPUs and driver versions help. [Open an issue](https://github.com/candygoogy/atieclxx-fix/issues/new?template=report.md) with the output of **Check**, whether the fix worked or not.

## Not affiliated with AMD

This is an independent workaround, not an AMD product. Use it at your own risk; **Undo** puts everything back.

## License

[MIT](LICENSE)
