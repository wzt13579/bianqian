# 托盘图标资源

请将托盘图标放置在本目录：

- `tray.ico` —— Windows 系统托盘（**必需**，建议 16/32/48 px 多分辨率 ICO）
- `tray.png` —— macOS / Linux 备用（可选，16x16 PNG）

如果文件缺失，应用启动时不会崩溃，仅托盘图标为空（`TrayService` 中已 try/catch 容错）。

## 在线生成 ICO

- [https://icoconvert.com/](https://icoconvert.com/)
- [https://convertio.co/png-ico/](https://convertio.co/png-ico/)
