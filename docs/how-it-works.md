# How it works

Findings from one PC (Windows 11, RX 9070 XT, driver 32.0.32015.12012), 10 November 2026.

## 1. The utility's write counter

`Win32_Process.WriteTransferCount` for `atieclxx.exe`, 31 hours after boot:

```
atieclxx.exe   WriteMB 70657   WriteOps 465
```

That's about 70 GB, while the write-operation count barely moves. Over 20 seconds it grew by 12.9 MB with 0 new operations. The program writes into the file cache, and the System process flushes that to disk, so the disk writes are counted elsewhere.

## 2. Process Monitor, 30 seconds

The same sequence repeats about once a second:

```
CreateFile   C:\Program Files\AMD\amdkmpfd_in                       NAME COLLISION
CreateFile   C:\Program Files\AMD\amdkmpfd_in\amdkmpfd.inf          NAME NOT FOUND
CreateFile   C:\Windows\System32\AMD\AMDKMPFD\amdkmpfd.itz          PATH NOT FOUND
CreateFile   C:\Program Files\AMD\amdkmpfd_un                       NAME NOT FOUND
-- copy itself --
SetBasicInformationFile  ...\systemprofile\AppData\Local\AMD\atieclxx.exe   (clears read-only)
CreateFile               ...\systemprofile\AppData\Local\AMD\atieclxx.exe   Disposition: OverwriteIf
SetEndOfFileInformationFile                                                 EndOfFile: 677,392
ReadFile   ...\DriverStore\FileRepository\u0205499.inf_amd64_...\atieclxx.exe   Length: 677,392
```

The flushes to disk come from the System process:

```
System  WriteFile  ...\AppData\Local\AMD\atieclxx.exe  Offset: 0, Length: 679,936, I/O Flags: Non-cached, Paging I/O
```

In 30 seconds there were 22 of those non-cached writes, 14.3 MB in total, or about 0.48 MB/s to the SSD.

`amdkmpfd` is AMD's PCI filter driver. The `.inf` and `.itz` files the utility looks for don't exist on this PC, which fits AMD's explanation that the bug comes from a filter-driver incompatibility. Section 5 shows what the utility is doing with them.

## 3. What didn't work: read-only

Setting the read-only attribute on the copy changes nothing, because the utility clears attributes before copying (`SetBasicInformationFile ... FileAttributes: ANNCI`).

## 4. What works: a deny rule for SYSTEM

```
icacls "<copy>" /deny *S-1-5-18:(W,D)
```

After that, the copy attempts end in `CreateFile ... ACCESS DENIED`, and in the next 30-second capture:

- the utility's write counter grew by 0 bytes (it was 22 MB over the same window before)
- one final flush of already-cached data, then nothing
- total event count for `atieclxx.exe` unchanged (31,403 vs 31,352), so no faster retry loop
- the process kept running with the same PID

After restarting the service, the new process wrote 0 bytes in its first 70 seconds.

## 5. What the loop is: a driver install that can't finish

The utility is trying to install the `amdkmpfd` PCI filter driver, and the driver package no longer contains it.

**The driver package (`oem5.inf`, driver 32.0.32015.12012).** The INF still tells the utility where the filter driver's files are, through a value in the display adapter's registry key:

```
HKR,,AMDKMPFD,%REG_EXPAND_SZ%,%%SystemDrive%%\Windows\System32\AMD\AMDKMPFD
```

But the list of files it copies to that folder is empty:

```
[DestinationDirs]
R300.AMDKMPFD = 11, AMD\amdkmpfd
...
[R300.AMDKMPFD]

[DS.Graphics]
```

Ten install sections still reference that empty list: Navi31, Navi32, Navi33, Navi48, Phoenix, Strix, StrixHalo, GorgonHalo, Krackan and Krackan2e. The same INF sets `PciFilterDriverInstallEnabled = 0` under `HKLM\SYSTEM\CurrentControlSet\services\amdkmdap`, but `atieclxx.exe` never reads that value in the trace.

**The three files are the driver.** `atieclxx.exe` contains the names of other AMD drivers in pairs: `amdfendr.itz` and `amdfendr.inf`, `amdfendr.stz` and `amdfendr.sys`, `amdfendr.ctz` and `amdfendr.cat`. So `amdkmpfd.itz`, `.stz` and `.ctz` are the filter driver's INF, SYS and CAT under staging names. Adrenalin 26.3.1 and older put them in `C:\Windows\System32\AMD\amdkmpfd\`; newer packages don't.

**The installer is inside the utility.** Strings in `atieclxx.exe`:

```
InstallFilterDriver: CreateInstallPackage fails.
InstallFilterDriver: The preinstall using SetupCopyOEMInfA failed.
Merge: original lowerfilters already contains PCIF.
UninstallPciBusFilter: DiUninstallDriver failed with GetLastError() = %d.
EeuClientPathForPciFilterUnInstall
SetupCopyOEMInfA   DiInstallDriverA   UpdateDriverForPlugAndPlayDevicesA
```

**One pass of the loop** (Process Monitor, registry and file events together):

```
RegQueryValue  HKLM\SYSTEM\Setup\SystemSetupInProgress                      0
RegQueryValue  ...\Class\{4d36e968-...}\0000\KMD_InstallUncertifiedPFD     NAME NOT FOUND
RegQueryValue  HKLM\SOFTWARE\AMD\EEU\KMD_InstallUncertifiedPFD             NAME NOT FOUND
RegQueryValue  ...\Class\{4d36e968-...}\0000\amdkmpfd                      %SystemDrive%\Windows\System32\AMD\AMDKMPFD
RegQueryValue  HKLM\SOFTWARE\AMD\EEU\RebootIsPending                       NAME NOT FOUND
CreateFile     C:\Program Files\AMD\amdkmpfd_in                            (creates the folder if it's missing)
-- copies itself to ...\systemprofile\AppData\Local\AMD\atieclxx.exe --
CreateFile     C:\Program Files\AMD\amdkmpfd_un                            NAME NOT FOUND
CreateFile     C:\Program Files\AMD\amdkmpfd_in\amdkmpfd.inf               NAME NOT FOUND
CreateFile     C:\Windows\System32\AMD\AMDKMPFD\amdkmpfd.itz               PATH NOT FOUND  (4 tries)
-- one second later, the same again --
```

Before that, each pass also reads the hardware ID of every device and opens every AMD PCI device.

So the utility reads where the files should be, starts building an install package in `amdkmpfd_in`, can't find the first file, and starts over a second later. The self-copy appears to be a spare of the utility kept for removing the filter driver later (`EeuClientPathForPciFilterUnInstall`). There is no retry limit. u/KiKiHUN1 reached the same picture by reverse engineering the executable.

**The test PC has no amdkmpfd driver at all.** There's no `amdkmpfd` service and no `amdkmpfd.sys`, with AMD Chipset Software 8.09.28.1124 installed (X870E). The bug also shows up on an Intel B660 motherboard ([issue #1](https://github.com/candygoogy/atieclxx-fix/issues/1)), so it doesn't depend on the AMD chipset driver.

**What putting the files back does.** Findings from u/lt_catscratch (7900 XTX, Adrenalin 26.9.2) in [the Reddit thread](https://www.reddit.com/r/AMDHelp/s/Bchh9rfWuv):

- With the three files from the 26.3.1 package copied into that folder, the writes stop.
- With the files removed again, the writes come back.
- On that PC, `amdkmpfd.sys` ("AMD PCI Root Bus Lower Filter") is a `BOOT_START` driver in load order group "Boot Bus Extender". Deleting its service with `sc delete amdkmpfd` left the PC unable to boot (`INACCESSIBLE_BOOT_DEVICE`).

Given the installer code above, the files most likely let the utility finish and install the 26.3.1 filter driver. That install hasn't been watched on the test PC, which doesn't have the files.

**Resizable BAR.** u/ViperIXI switched Resizable BAR on and off on an RX 7900 XTX (Adrenalin 26.10.2) and an RX 9070 XT (26.9.2 and 26.10.2): the writes stop with it off and return with it on. An RX 580 on 26.5.2 keeps writing with it off (u/DavidAstonish). [necanditool/Radeon-atieclxx-SSD-Fix](https://github.com/necanditool/Radeon-atieclxx-SSD-Fix) describes amdkmpfd as the Smart Access Memory filter driver, which would explain the link. The utility's strings never mention Resizable BAR. They do name other install conditions (`InstallPciF4MSIX`, `KMD_DoNotInstallPciF4PSP`, `Global\AMDPCIFNoInstall`), so if the link is real, the decision to install the filter probably comes from the kernel driver. AMD's fix in 26.11.1 points the same way (section 7). The Resizable BAR link itself hasn't been tested on the test PC. Resizable BAR being on isn't enough by itself: an RX 6600 on 26.10.1 has it on and doesn't loop ([#3](https://github.com/candygoogy/atieclxx-fix/issues/3)).

**Not explained yet.** Some PCs have an empty `amdkmpfd` folder and no loop. An earlier guess was that an older driver had already installed the filter, so the utility had nothing to do. Issue [#3](https://github.com/candygoogy/atieclxx-fix/issues/3) rules that out: an RX 6600 on 26.10.1 has no filter driver, none of the files, Resizable BAR on, and no loop. The opposite case exists too: an RX 9070 XT on Adrenalin 26.5.1 shows the filter driver installed, none of the files, and loops, with 890 GB written in 256 hours (u/dangderr). So whether the filter is installed doesn't decide it. The script's **Check** prints the driver and file state, which is the most useful thing to report from an unaffected PC.

On PCs that have never looped, the copy doesn't exist at all ([issue #2](https://github.com/candygoogy/atieclxx-fix/issues/2); u/thegreatsquare found only `DxCache` and `DxcCache` in the folder). Every pass of the loop creates the file if it's missing, so a missing copy means the loop has never run there.

A related test: deleting the empty `C:\Program Files\AMD\amdkmpfd_in` folder doesn't help, because the utility recreates it within seconds.

## 6. Reboots and driver updates

- **Who uses the copy:** no service, scheduled task, Run key or running process points to `...\systemprofile\AppData\Local\AMD\atieclxx.exe`. The service runs `atiesrxx.exe` from the DriverStore, and that starts `atieclxx.exe` from the DriverStore too. The utility's own strings suggest it keeps the copy for removing the filter driver later (section 5). The fix only denies write and delete access to it.
- **Driver installs leave it alone:** the copy on the test PC was created on 29 Oct, and the current driver package was installed on 30 Oct (`setupapi.dev.log`, DriverStore folder date). The installer didn't delete or recreate it; the utility kept overwriting it in place.
- **DDU:** Display Driver Uninstaller's AMD cleanup goes through each user's `AppData\Local\AMD` under `C:\Users`, and in the system profile it only clears `D3DSCache` (`GPUCleanup.vb`, WPF branch, read on 11 November 2026). It has no step for `systemprofile\AppData\Local\AMD`, so the copy and its block should survive a DDU reinstall. u/schnepy reported 0 B/s after DDU and a fresh 26.10.2 install, with the fix applied beforehand, which fits. Not tested on the test PC.
- **One limit:** SYSTEM has full control of the parent folder, so it can still *delete* the copy and create a new one, which would carry normal permissions. Tested with a dummy file and a task running as SYSTEM. The current utility never deletes; it only overwrites, and that's what the block stops. If a future driver deletes the file first, the fix would be lost, and **Check** would show the writes again.
- **Stale copy after an update:** the script compares the copy's SHA-256 with the running `atieclxx.exe`. When they differ, **Fix** lifts the block, lets the new driver refresh its copy, measures again, and blocks again only if the writes are back. Simulated by changing one byte of the copy: Fix refreshed it, measured 595 KB/s, blocked again, and ended at 0 B/s.

## 7. AMD's fix in Adrenalin 26.11.1

The 26.11.1 release notes (12 November 2026) list under Fixed Issues: "Excessive writes to the system drive may be observed while the system is idle on Radeon™ RX 7000 series graphics products and above."

What changed, checked on the test PC:

- **The missing files are still missing.** In the 26.11.1 package (INF `DriverVer` 32.0.32015.16001), the `[R300.AMDKMPFD]` file list is still empty, and there are no `amdkmpfd.itz`, `.stz` or `.ctz` files.
- **The utility barely changed.** The new `atieclxx.exe` is version 6.14.11.1290, 666,768 bytes (677,392 before). Comparing their readable strings, the only difference besides a newer Microsoft signing certificate is one log message, which now adds an error code ("Failed to send process exclusion. GetLastError: %d").
- **The install is no longer started.** After installing 26.11.1 over 26.10.2, `C:\Windows\System32\AMD\amdkmpfd` no longer exists and the amdkmpfd service isn't installed. With the block removed, `atieclxx.exe` wrote 0 B/s in two measurements (30 s and 15 s); its total stayed at 2.5 MB, all written when it started.
- **Where the fix was made.** AMD's u/AMD_Vik confirmed [in r/buildapc](https://www.reddit.com/r/buildapc/comments/1x4153i/comment/19rh3g0s9wyit/) that the disk write issue would be fixed in this release, and the same thread says it "was fixed recently by a friend in kmd", the kernel-mode driver. That fits the above: the utility is nearly unchanged, and the driver no longer sets up the filter install, so there's nothing for the utility to retry.

Not tested yet: a clean install of 26.11.1, and cards older than RX 7000, which had the bug (RX 580, RX 6700 XT) but aren't named in the release notes.
