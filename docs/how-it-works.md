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

`amdkmpfd` is AMD's PCIe filter driver. The `.inf` and `.itz` files the utility looks for don't exist on this PC, which fits AMD's explanation that the bug comes from a filter-driver incompatibility.

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

## 5. What the loop is waiting for

The utility looks for three files in `C:\Windows\System32\AMD\amdkmpfd\`: `amdkmpfd.ctz`, `amdkmpfd.itz` and `amdkmpfd.stz`. Adrenalin 26.3.1 and older put them there; newer packages don't.

On the test PC (Ryzen 9800X3D, X870E) the folder doesn't exist, and none of the current AMD installer packages contain the files.

Findings from u/lt_catscratch (7900 XTX, Adrenalin 26.9.2) in [the Reddit thread](https://www.reddit.com/r/AMDHelp/s/Bchh9rfWuv):

- With the three files from the 26.3.1 package copied into that folder, the writes stop.
- With the files removed again, the writes come back.

The files don't install or load anything. The utility only checks that they exist.

Separately, `amdkmpfd.sys` ("AMD PCI Root Bus Lower Filter", a `BOOT_START` driver in load order group "Boot Bus Extender") comes with the AMD chipset driver on AMD motherboards. It runs whether or not the three files are there, and it isn't what the loop is waiting for. Don't delete its service: `sc delete amdkmpfd` left a test PC unable to boot (`INACCESSIBLE_BOOT_DEVICE`).

A related test: deleting the empty `C:\Program Files\AMD\amdkmpfd_in` folder doesn't help, because the utility recreates it within seconds.

## 6. Reboots and driver updates

- **Who uses the copy:** no service, scheduled task, Run key or running process points to `...\systemprofile\AppData\Local\AMD\atieclxx.exe`. The service runs `atiesrxx.exe` from the DriverStore, and that starts `atieclxx.exe` from the DriverStore too. Blocking the copy only stops the rewriting.
- **Driver installs leave it alone:** the copy on the test PC was created on 29 Oct, and the current driver package was installed on 30 Oct (`setupapi.dev.log`, DriverStore folder date). The installer didn't delete or recreate it; the utility kept overwriting it in place.
- **One limit:** SYSTEM has full control of the parent folder, so it can still *delete* the copy and create a new one, which would carry normal permissions. Tested with a dummy file and a task running as SYSTEM. The current utility never deletes; it only overwrites, and that's what the block stops. If a future driver deletes the file first, the fix would be lost, and **Check** would show the writes again.
- **Stale copy after an update:** the script compares the copy's SHA-256 with the running `atieclxx.exe`. When they differ, **Fix** lifts the block, lets the new driver refresh its copy, measures again, and blocks again only if the writes are back. Simulated by changing one byte of the copy: Fix refreshed it, measured 595 KB/s, blocked again, and ended at 0 B/s.
