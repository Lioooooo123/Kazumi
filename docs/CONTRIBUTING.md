# 贡献

小栗子基于 [Kazumi](https://github.com/Predidit/Kazumi)，采用 **GPL-3.0-or-later**。提交到本仓库的改动也使用同一许可证。许可证全文见仓库根目录的 [LICENSE](../LICENSE)。

## 开发

- 应用改动在 `App/`。核心逻辑和可以在 Linux 上运行的测试放在 `Sources/KazumiCore` 与 `Tests/KazumiCoreTests`。
- 每个使用 `KazumiCore` 类型的应用文件都要自己 `import KazumiCore`。
- `ContentUnavailableView` 的说明使用 `Text`，不要传视图闭包。
- 给 `AppSettings` 增加字段时，用 `decodeIfPresent` 保留旧的 `library.json`。

## 检查

```bash
scripts/test.sh
```

在 Mac 上还可以：

```bash
scripts/build-macos.sh
```

打开 `XiaoLizi.xcodeproj`，运行 scheme `XiaoLizi`。最低系统是 macOS 14，需要 Xcode 16 或更新版本。

如果没有在 Mac 上点过界面，请在说明里写清楚测了什么、没测什么。
