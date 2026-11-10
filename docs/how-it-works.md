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
