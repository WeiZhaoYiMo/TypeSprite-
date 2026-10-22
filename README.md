# 打字桌宠

一个 Windows 静态桌宠：悬浮显示角色，并在本地统计全局打字次数。

## 分享给其他人

`release\TypingPet.exe` 是单文件便携版，可直接发送并双击运行；`release\TypingPet-Portable.zip` 是便于下载和传输的压缩包版本。对方不需要安装 PowerShell 7，也不需要单独复制脚本或图片。

便携版首次启动会将程序资源释放到 `%LOCALAPPDATA%\TypingPet\app`，统计数据仍保存在 `%LOCALAPPDATA%\TypingPet\stats.json`。这是未使用商业代码签名证书的个人构建，Windows SmartScreen 可能在首次运行时要求用户确认。

## 已实现

- 透明、置顶、无边框桌宠窗口
- 鼠标左键拖动位置，位置会自动保存
- 全局统计常用输入键位，不记录具体按键或输入内容
- 显示今日打字数与历史累计打字数
- 本机日期跨过 `00:00` 后自动清零今日计数，累计数不清零
- 数据每 3 秒及退出时持久化
- 历史累计每达到新的 `10,000` 字里程碑时显示庆祝卡片，并记录已庆祝进度以避免重启后重复弹出
- 右键选择 PNG、JPG、JPEG、BMP 或 GIF 图片更换角色，可选择是否自动抠出主体；图片会等比例缩放到统一的 `512×512` 透明画布并保存为本地 PNG，也可随时恢复默认角色
- 右键菜单可清零今日计数或退出

## 启动

双击 `Start-TypingPet.cmd`。

也可以在 PowerShell 中运行。若安装了 PowerShell 7：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -STA -File .\TypingPet.ps1
```

若未安装 PowerShell 7，建议直接双击 `Start-TypingPet.cmd`，启动器会让 Windows PowerShell 以 UTF-8 方式读取程序。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -STA -File .\TypingPet.ps1
```

如果桌宠位置异常，可执行：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -STA -File .\TypingPet.ps1 -ResetPosition
```

或者直接下载[/a]TypingPet.exe[/a]运行即可

## 数据位置

数据保存在：

```text
%LOCALAPPDATA%\TypingPet\stats.json
```

字段说明：

- `date`：今日计数对应的本机日期
- `todayCount`：今日打字数
- `totalCount`：历史累计打字数
- `lastCelebrated`：上一次已经展示的万字里程碑
- `customImagePath`：用户当前选择的自定义角色图片位置
- `left` / `top`：桌宠上次的位置

## 计数口径与隐私

统计字母、数字、标点、空格、回车、Tab、退格、Delete 等输入相关键位。Ctrl、Shift、Alt 等纯修饰键不计数；系统注入的模拟按键不计数。程序不会保存按键名称、输入内容、所在应用或窗口标题。

角色图片的缩放与可选抠图完全在本机离线完成，不会上传图片。自动抠图采用从图片边缘识别连通背景的方式，纯色、白色或背景干净的图片效果最佳。

## 环境要求

- Windows 10/11
- Windows PowerShell 5.1，或 PowerShell 7
- 对应的 .NET 桌面运行环境（Windows 10/11 默认已具备 Windows PowerShell 5.1 所需环境）

