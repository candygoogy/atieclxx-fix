# atieclxx-fix

Stops the AMD Radeon driver from writing **40–55 GB a day** to your system SSD, and keeps the AMD service running.

Quick start in other languages: [简体中文](docs/README.zh-CN.md) · [Português (Brasil)](docs/README.pt-BR.md) · [Español](docs/README.es.md)

## Do I still need this?

AMD fixed the bug in **Adrenalin 26.11.1** (12 November 2026) for RX 7000 and newer. Polaris and Vega cards aren't fixed yet.

| Your card | What to do |
|---|---|
| **RX 7000, RX 9000** | Update to Adrenalin 26.11.1. If you applied this fix, run it once more and press **F**: it removes the block when the new driver no longer needs it. |
| **RX 5000, RX 6000** | Not named in AMD's release notes. Update, then press **C**. If it says AFFECTED, press **F**. |
| **RX 400/500 series, Vega** | **Not fixed by AMD yet. Use this fix ([steps below](#fix-it)).** |

Since version 1.1.0, **Check** also says which of these applies to your PC.

- **Polaris and Vega:** they use a separate driver branch (the 26.5.2 Polaris driver is on it), and the bug is confirmed there on an RX 560 and an RX 580. AMD's rep u/AMD_Vik [says](https://www.reddit.com/r/Amd/comments/1xrpb1o/amd_confirms_radeon_driver_bug_causing_constant/19sfum5ywvcw0/) the filter driver works differently on these cards, so the fix "may take us a while to work in".
- **The test PC on 26.11.1** (RX 9070 XT, installed over 26.10.2): with the block removed, the utility wrote nothing new in 13 hours. 26.11.1 doesn't bring back the missing amdkmpfd files; the driver no longer starts that install at all ([details](docs/how-it-works.md#7-amds-fix-in-adrenalin-26111)).

In November 2026, Radeon owners noticed `atieclxx.exe` (the "AMD External Events Utility" that ships with Adrenalin) writing to disk nonstop, even on an idle PC. AMD confirmed the bug and fixed it in Adrenalin 26.11.1 (see above). Before that, the usual advice was to disable the service, which breaks FreeSync on some PCs.

This repo finds what the utility is actually writing and blocks only that. Users have confirmed it on RX 580, RX 6700 XT, RX 7800 XT, RX 7900 XTX, RX 9060 XT, RX 9070 and RX 9070 XT, on Windows 10 and 11.

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

The copy is byte-for-byte identical every time, but Windows still writes it to the drive.

The copy is one step of a driver install that can never finish. The utility is trying to install a small AMD driver, the `amdkmpfd` PCI filter driver. Current Radeon driver packages still tell the utility where that driver's setup files are, but no longer include the files. So every attempt fails, and the utility starts over a second later, with no retry limit.

On the test PC that came to **662 KB/s, or about 55 GB a day**. Process Monitor showed about 0.48 MB/s of it reaching the SSD as real disk writes. Traces and details: [docs/how-it-works.md](docs/how-it-works.md).

At that rate it's about 20 TB a year. A typical 1 TB SSD is rated for around 600 TB of writes, so this alone won't wear one out quickly; small and cheap drives are rated for much less. Either way, it's constant writing that does nothing, and it's easy to stop.

## Am I affected?

Open PowerShell (no admin needed) and paste:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/candygoogy/atieclxx-fix/main/atieclxx-fix.ps1))) -Check
```

It watches `atieclxx.exe` for 15 seconds and tells you how much it's writing.

You can also check without running anything: Task Manager → **Details** → right-click a column header → **Select columns** → tick **I/O write bytes**, then watch `atieclxx.exe`. If the number climbs every second, you're affected.

Not every PC is affected, even with the same card and driver. See [Who is affected](#who-is-affected).

## Fix it

1. Download **[atieclxx-fix.zip](https://github.com/candygoogy/atieclxx-fix/releases/latest/download/atieclxx-fix.zip)** and extract it (right-click → **Extract All**). Running it from inside the zip doesn't work.
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

Don't want to run a script? The fix is one command in an admin terminal, and the second line undoes it:

```
icacls "C:\Windows\System32\config\systemprofile\AppData\Local\AMD\atieclxx.exe" /deny *S-1-5-18:(W,D)
icacls "C:\Windows\System32\config\systemprofile\AppData\Local\AMD\atieclxx.exe" /remove:d *S-1-5-18
```

## What the fix changes

One permission on one file. The SYSTEM account loses write and delete access to the copied `atieclxx.exe` above. When the utility tries its once-a-second copy, Windows refuses before anything is written.

- The AMD service keeps running, so hotkeys, FreeSync and display events keep working.
- The existing copy stays in place and is identical to the original.
- The utility doesn't retry any faster; it just keeps failing quietly.
- Nothing is deleted, disabled or patched, and no background task is installed.

No service, scheduled task or startup entry points to that copy. The utility appears to keep it as a spare for removing the filter driver later. The fix only denies write and delete access.

## Reboots and driver updates

**Reboots:** the fix is a file permission, so it's stored on the drive and survives restarts. When the AMD service starts again, the copy fails right away. On the test PC, 14 minutes after a full reboot, `atieclxx.exe` had written 3.8 KB in total, where the bug would have written about 550 MB.

**Driver updates:** the AMD installer leaves the copy alone, so the block stays in place and the new driver's utility can't refresh its copy. After updating, run **`Fix-SSD-Writes.cmd` → F** once:

- the status line shows `APPLIED, but the driver changed since`
- the script lifts the block and lets the new driver refresh its copy
- if the new driver still has the bug, it blocks it again; if AMD's fix works, it leaves the block off and says so

You don't need to undo anything before updating. If you'd rather start clean, **U** removes the fix.

**DDU:** Display Driver Uninstaller has no cleanup step for the folder the copy is in (checked in its source), so the block should stay through a DDU reinstall too. One user reported 0 B/s after DDU and a fresh 26.10.2 install, with the fix applied beforehand. Run **F** once afterwards, the same as after any driver update.

## Other workarounds

**Disable the service.** Set "AMD External Events Utility" to Disabled in `services.msc`. That stops the writes, but it can break FreeSync. [Dauntless-One measured it](https://github.com/Dauntless-One/amd-eeu-ssd-write-fix) with PresentMon: with the service disabled, VRR stopped working; with the service running and the same permission fix as this repo, VRR kept working. If you don't use FreeSync or Adrenalin hotkeys, disabling the service is fine. FSR 4 keeps working with it disabled (u/Erihknull).

**Put the amdkmpfd files back.** The install the utility keeps retrying needs three files that Adrenalin 26.3.1 and older put in `C:\Windows\System32\AMD\amdkmpfd\`: `amdkmpfd.ctz`, `amdkmpfd.itz` and `amdkmpfd.stz` (names via u/BitRunner64). Copying them back from the 26.3.1 package stops the writes; u/lt_catscratch [tested it both ways](https://www.reddit.com/r/AMDHelp/comments/1xsx6t3/comment/19sfx766fx8w2/). u/Neoony posted this workaround [in r/buildapc](https://www.reddit.com/r/buildapc/comments/1x4153i/comment/19rh3g0s9wyit/) in October, with the steps.

- Those three files are the filter driver itself: its `.inf`, `.sys` and `.cat` under other extensions. With them in place, the utility can finish its install, so this workaround most likely leaves the 26.3.1 version of `amdkmpfd.sys` installed as a boot driver. We haven't watched that install happen on the test PC, which doesn't have the files.
- People using it report no stutters or driver timeouts.
- **Don't remove the `amdkmpfd` driver by hand.** It's a boot filter on the PCI bus. Deleting it with `sc delete amdkmpfd` leaves Windows unable to boot (`INACCESSIBLE_BOOT_DEVICE`, confirmed by u/lt_catscratch, who had to use a restore point).

**Turn off Resizable BAR.** u/ViperIXI tested it both ways on an RX 7900 XTX (Adrenalin 26.10.2) and an RX 9070 XT (26.9.2 and 26.10.2): with Resizable BAR (AMD calls it Smart Access Memory) off in the BIOS, the writes stop, and with it on they come back. On an RX 580 the writes continued with it off (u/DavidAstonish). AMD's rep u/AMD_Vik also said in that r/buildapc thread that disabling it works around the bug. It hasn't been tested on the test PC. necanditool's README describes amdkmpfd as the Smart Access Memory filter driver, which would explain why the setting matters. The cost is whatever performance Resizable BAR gives you in games.

**The same fix, found separately.** Two other projects found the same permission block on 9 November, a day before this repo. [necanditool/Radeon-atieclxx-SSD-Fix](https://github.com/necanditool/Radeon-atieclxx-SSD-Fix) was first. It has a German interface and adds a scheduled task that keeps the block in place after driver updates, and its README already linked the loop to the amdkmpfd files. [Dauntless-One/amd-eeu-ssd-write-fix](https://github.com/Dauntless-One/amd-eeu-ssd-write-fix) followed a few hours later. Any of them does the job; you only need one.

| | This repo | amdkmpfd files | Resizable BAR off | Disable service |
|---|---|---|---|---|
| Stops the writes | yes | yes | on the newer cards tested, not on an RX 580 | yes |
| Service keeps running | yes | yes | yes | no |
| FreeSync keeps working | yes (measured) | no problems reported | not reported | not on every PC |
| What it changes | one permission | adds 3 driver files, which the utility then installs | a BIOS setting, at some cost in game performance | disables a service |

## Tested on

- Windows 11, Radeon RX 9070 XT, Adrenalin 26.10.2 (driver 32.0.32015.12012), AMD X870E motherboard
- The same PC on Adrenalin 26.11.1 (driver 32.0.32015.16001): AMD's fix works there, with no writes after the block was removed
- Windows PowerShell 5.1 and PowerShell 7

Reports from users (thanks!):

| GPU | Adrenalin | Result | Reported by |
|---|---|---|---|
| RX 9070 XT | 26.9.2, 26.10.1, 26.10.2 | fixed, on Windows 10 and 11 | u/Corvius, u/Maplane, u/Poquito-Mal, u/manolid, u/Thankyoumr |
| RX 9070 | 26.10.2 | fixed, 617 KB/s → 0 B/s, on an Intel B660 motherboard | KiKiHUN1 ([#1](https://github.com/candygoogy/atieclxx-fix/issues/1)) |
| RX 9070 | 26.10.2 (driver only, with RadeonTuner) | fixed, about 0.8 MB/s → 0, on a B550 motherboard | VACekToxic ([#6](https://github.com/candygoogy/atieclxx-fix/issues/6)) |
| RX 9060 XT | 26.10.1, 26.10.2 | fixed, 662 KB/s → 0 B/s, on Windows 26H2, and still fixed after DDU and a clean reinstall | SkittlezAU ([#5](https://github.com/candygoogy/atieclxx-fix/issues/5)); loop also seen by u/Halicos93 |
| RX 7900 XTX | 26.9.2, 26.10.1, 26.10.2 | fixed, 54 GB/day → 0 B/s | u/schnepy and a friend, u/Electrical-Bobcat435 |
| RX 7800 XT | 26.10.1 | fixed | u/Antique-Editor-9001 |
| RX 7600 | latest | same loop seen, about 1.3 MB/s | u/skylog6593 |
| RX 6700 XT | not given | fixed | u/enduser1980 |
| RX 580 | 26.5.2 | fixed | u/DavidAstonish |

Also reported fixed, card not given: u/wankerbanker85, u/Any_Juggernaut_112, u/FlurrySlurer, u/Romaryu, u/Careful_Climate1589, u/John-333.

## Who is affected

The bug has been seen on RX 560 (u/zaudio33), RX 580, RX 6700 XT, RX 7600, RX 7800 XT, RX 7900 XTX, RX 9060 XT, RX 9070 and RX 9070 XT, with Adrenalin 26.5.1 and 26.5.2, and 26.9.2 to 26.10.2, on AMD and Intel motherboards. 26.3.1 and older still shipped the amdkmpfd files, so the change came between 26.3.1 and 26.5.1. The oldest report is an RX 9070 XT on 26.5.1 that had written 890 GB in 256 hours (u/dangderr).

Other people with the same cards and drivers see no writes at all. Reports of no loop so far: RX 6750 XT, RX 6800 XT, RX 6950 XT, some RX 7900 XTX, RX 9070 and RX 9070 XT owners, a Radeon 780M laptop on an older driver ([#2](https://github.com/candygoogy/atieclxx-fix/issues/2)), another 780M laptop on Adrenalin 26.10.1 (u/xeizoo), and a Ryzen 5 5600G on Adrenalin 24.3.1.

What we know about why:

- Installing only the driver, without AMD Software, doesn't avoid it: the utility comes with the driver itself ([#6](https://github.com/candygoogy/atieclxx-fix/issues/6)).
- PCs that still have the three amdkmpfd files from an older driver don't loop. Updating over an old driver keeps them; a clean install or DDU removes them.
- Some PCs with an empty `amdkmpfd` folder don't loop either. It isn't because the filter driver is already installed: an RX 6600 on Adrenalin 26.10.1 with no filter driver and none of the files doesn't loop ([#3](https://github.com/candygoogy/atieclxx-fix/issues/3)). The reverse doesn't hold either: the RX 9070 XT on 26.5.1 above loops with the filter driver installed (and none of the files). What decides it is still unknown.
- On a PC that has never looped, the copied `atieclxx.exe` doesn't exist at all: the folder holds only shader caches (`DxCache`, `DxcCache`). **Check**, run as administrator, shows that as `not applied (the utility has made no copy on this PC)`.
- Resizable BAR seems to matter on newer cards. With it off, the loop stops on an RX 7900 XTX and an RX 9070 XT (u/ViperIXI). An RX 580 loops with it off, and the RX 6600 above has it on and doesn't loop, so it isn't the whole answer.

**Check** prints an `amdkmpfd:` line (whether the driver is installed and how many of the three files are there). If you're not affected, that line is the most useful thing you can report.

Reports from other GPUs and driver versions help. [Open an issue](https://github.com/candygoogy/atieclxx-fix/issues/new?template=report.md) with the output of **Check**, whether the fix worked or not.

## Not affiliated with AMD

This is an independent workaround, not an AMD product. Use it at your own risk; **Undo** puts everything back.

## License

[MIT](LICENSE)
