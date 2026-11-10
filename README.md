# AM-NCM

把 Apple Music「资料库 → 歌曲」同步到网易云音乐现有的「我喜欢的音乐」。已匹配的歌曲按 Apple Music 添加日期从新到旧排在前面。网易云原有的其他红心歌曲保留在后面，维持它们原有的相对顺序。

## 使用

需要 macOS、Music.app、Python 3.11+ 和 Node.js 22.13+。首次扫描时，macOS 可能要求授予终端控制 Music 的自动化权限。

```sh
npm ci --ignore-scripts
python3 am2ncm.py scan
python3 am2ncm.py preview --limit 10
node ncm.cjs login
node ncm.cjs plan
node ncm.cjs apply
node ncm.cjs report
```

`login` 打开二维码，用手机网易云音乐扫码确认。登录凭证存在 macOS 钥匙串。脚本通过固定版本的社区 API 直接连接网易云，匹配时会向网易云发送歌曲标题和艺人用于搜索。

`plan` 只读网易云账号数据，优先匹配已点红心的曲目，然后按需搜索。搜索结果逐首缓存，初次运行时间取决于曲目数量和网易云限流情况，中断后可重新执行。用 `plan --limit 10` 可以只发起至多 10 次新搜索，查看预览。

`apply` 使用最近一次完整计划，将高置信度匹配加入喜欢歌单，然后回读核验红心集合和完整顺序。已有匹配不会重复添加。执行前会保存原曲目顺序。如果写入中断，可用同一份计划重试。计划生成后若歌单有额外的增删，先重新运行 `plan`。

## 数据与人工复核

快照和匹配缓存存在 `~/Library/Application Support/AM-NCM/library.sqlite3`。同目录下的 `netease-plan.json` 包含统计、原始目标顺序、拟写入顺序和逐首匹配结果。可用 `node ncm.cjs report --review` 查看待复核曲目。版本或录音有歧义的歌曲会进入复核；计划可应用到其余已确认匹配。仍待搜索或搜索失败的曲目需要先重跑计划。

如果要确认个别曲目，可以在同目录创建 `netease-overrides.json`，以计划中的 Apple Music 曲目 ID 为键、网易云曲目 ID 字符串为值。填 `null` 可跳过这首歌。保存后重跑 `plan`。例如：

```json
{
  "APPLE_TRACK_PERSISTENT_ID": "123456789",
  "ANOTHER_APPLE_TRACK_PERSISTENT_ID": null
}
```

添加时间相同的歌曲保留 Music 返回的相对顺序。缺少添加日期的歌曲保留源位置，数量记录在扫描预览的 `missing_date_count`。
