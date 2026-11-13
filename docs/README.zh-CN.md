# atieclxx-fix（简体中文快速指南）

AMD Radeon 驱动自带的 `atieclxx.exe`（AMD External Events Utility）有一个错误：它每秒都把自己（约 677 KB）复制一遍到系统盘，每天写入 **40–55 GB**，即使电脑完全空闲。这个工具只阻止这一个复制操作，AMD 服务照常运行，FreeSync 和快捷键不受影响。

完整说明（英文）：[README](../README.md)

## 我还需要它吗？

AMD 已在 **Adrenalin 26.11.1**（2026 年 11 月 12 日）中为 RX 7000 及更新的显卡修复了这个问题。Polaris 和 Vega 显卡目前还没有修复。

| 你的显卡 | 怎么做 |
|---|---|
| **RX 7000、RX 9000** | 更新到 Adrenalin 26.11.1。如果之前用过这个修复，再运行一次并按 **F**：新驱动不再需要时，它会自动解除阻止。 |
| **RX 5000、RX 6000** | AMD 的更新说明里没有提到。先更新，再按 **C**。如果显示 AFFECTED，按 **F**。 |
| **RX 400/500 系列（如 RX 580）、Vega** | **AMD 还没有修复。请使用这个修复（见下方步骤）。** |

## 使用方法

1. 下载 **[atieclxx-fix.zip](https://github.com/candygoogy/atieclxx-fix/releases/latest/download/atieclxx-fix.zip)** 并解压（右键 → 全部解压缩）。直接在压缩包里运行是不行的。
2. 双击 **`Fix-SSD-Writes.cmd`**，在管理员权限提示中点"是"。
3. 按 **F**。

脚本会先测量写入量，应用修复后再测量一次，你可以看到数值降到 0。如果你的电脑没有这个问题，它不会做任何改动。

- **C**：只检查，不做改动。显示 `AFFECTED` 表示受影响，`OK` 表示正常。
- **U**：撤销修复，恢复原样。
- 如果 Windows 提示"Windows 已保护你的电脑"，点 **更多信息 → 仍要运行**。这是 Windows 对所有从网上下载的脚本都会显示的提示。整个修复就是一个可以直接阅读的 PowerShell 文件。
- 更新 AMD 驱动后，再运行一次并按 **F**。

有问题或结果想反馈？欢迎在 [Issues](https://github.com/candygoogy/atieclxx-fix/issues) 里留言（中文也可以），请附上 **C** 的输出。
