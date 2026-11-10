# AM-NCM

AM-NCM 是一个 macOS App，用于在 Apple Music 资料库与网易云音乐的「我喜欢的音乐」之间同步歌曲。

从 Apple Music 同步到网易云时，已匹配的歌曲按加入 Apple Music 资料库的时间从新到旧排列。网易云原有的其他红心歌曲会保留在后面，并保持原有的相对顺序。开启双向同步后，网易云新点红心的歌曲也可以加入 Apple Music 资料库。

## 安装与使用

支持 macOS 26 或更新版本。使用 Apple 芯片的 Mac 可从 [GitHub Releases](https://github.com/ShawnRn/AM-NCM/releases) 下载 DMG，打开后将 AM-NCM 拖入「应用程序」。App 内置同步运行环境，日常使用无需另外安装 Node.js 或 Python。

1. 在首页读取 Apple Music 资料库。首次使用时，按 macOS 提示允许 AM-NCM 控制「音乐」App。
2. 用手机网易云音乐扫码登录。首页会显示两边的连接状态和上次同步摘要。
3. 点击「手动同步」。有歌曲待新增时，确认浮层会分方向显示拟新增的数量，并说明网易云的顺序是否需要调整。只需调整顺序时，可以在首页直接确认。没有变化时，首页会显示一行提示。
4. 在「匹配明细」中可按全部曲目、计划新增、待复核和已匹配筛选，也可以搜索歌名、艺人或专辑。选中曲目后，右侧会显示本机可读取的 Apple Music 专辑封面和网易云候选。用 ⌘+、⌘− 在小、标准、大三档之间切换，⌘0 恢复标准大小。

在「匹配明细」中连续点击同一个表头，会依次切换升序、降序和报告原有顺序。

## 双向同步与自动同步

在首页登录 Apple Music，再从「设置」开启「双向同步」。开启时会记录现有的网易云红心，之后只处理新增红心。已在 Apple Music 资料库中的歌曲会跳过。

同步周期可设为仅手动、每 5 分钟、每小时、每天或每周。自动同步在 App 运行时直接执行，关闭主窗口后也能继续。Mac 唤醒或 App 重新启动后会检查是否有到期任务。开启「同步成功」通知后，自动同步只在新增歌曲或调整顺序时发送成功通知。失败通知可单独开关。

## 匹配、数据与复核

- 首次匹配优先查找现有的网易云红心，必要时再搜索曲库。搜索结果会缓存，耗时取决于首次待匹配的歌曲数、网络和服务限流。中断后可再次运行，继续使用已保存的结果。
- 版本或录音存在歧义的曲目会留待复核。同步会回读核对结果，写入网易云之前会备份原有曲目顺序。
- 快照和匹配缓存保存在 `~/Library/Application Support/AM-NCM/library.sqlite3`，同步计划在同目录的 `netease-plan.json`。账号凭证保存在 macOS 钥匙串。搜索匹配会将曲名和艺人提交给对应音乐服务。
- 可在同目录创建 `netease-overrides.json` 来指定个别曲目的匹配。键是报告中的 Apple Music 曲目 ID，值是网易云曲目 ID 字符串。使用 `null` 跳过该曲目，保存后重新生成计划。

```json
{
  "APPLE_TRACK_PERSISTENT_ID": "123456789",
  "ANOTHER_APPLE_TRACK_PERSISTENT_ID": null
}
```

## 本地构建

用 Xcode 27 打开 `AMNCM.xcodeproj`，选择 `AM-NCM` scheme，或运行：

```sh
xcodebuild -project AMNCM.xcodeproj -scheme AM-NCM -configuration Release build
```

首次构建需要联网下载固定版本的 Node.js 和同步依赖。构建产物位于 Xcode 构建目录下的 `AM-NCM.noindex`。

发布用的 DMG 由 npm 版 [create-dmg](https://github.com/sindresorhus/create-dmg) 打包。通过 `npm install --global create-dmg` 安装后，运行 `bash Scripts/package-dmg.sh /路径/AM-NCM.app /路径/AM-NCM.dmg`。脚本会使用 create-dmg 内置的箭头背景，并放入「应用程序」快捷方式。

## 命令行

命令行流程用于 Apple Music → 网易云音乐，需 Python 3.11+ 和 Node.js 22.13+。与 App 共用当前 macOS 用户的快照、报告和网易云钥匙串凭证。

```sh
npm ci --ignore-scripts
python3 am2ncm.py scan
node ncm.cjs login
node ncm.cjs plan
node ncm.cjs report --review
node ncm.cjs apply
```

`plan` 只读网易云账号数据。可用 `plan --limit 10` 限制本次新搜索次数。确认计划完整后再执行 `apply`，它会添加已确认的匹配并更新顺序。计划生成后若歌单成员或顺序发生变化，先重新运行 `plan`。

## 关于

Made with ❤️ by Shawn Rain (feat. Codex)

项目源码采用 [MIT 许可证](LICENSE)。随 App 分发的第三方组件适用各自的许可证。

## 致谢

- 网易云登录、曲库搜索和歌单操作使用 [NeteaseCloudMusicApiEnhanced](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced)。
- DMG 安装镜像使用 [Sindre Sorhus 的 create-dmg](https://github.com/sindresorhus/create-dmg) 和它内置的箭头模板。
