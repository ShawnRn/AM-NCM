const { DatabaseSync } = require("node:sqlite");
const { homedir } = require("node:os");
const { join } = require("node:path");
const { existsSync, readFileSync, renameSync, writeFileSync } = require("node:fs");
const { createHash } = require("node:crypto");
const { setTimeout: delay } = require("node:timers/promises");
const { parseArgs } = require("node:util");

const directory = join(homedir(), "Library", "Application Support", "AM-NCM");
const dbPath = join(directory, "library.sqlite3");
const reportPath = join(directory, "netease-plan.json");
const overridePath = join(directory, "netease-overrides.json");

const normalized = value => (value ?? "").normalize("NFKC").toLowerCase()
    .replace(/[’']/gu, "").replace(/[^\p{L}\p{M}\p{N}]+/gu, " ").trim();
const artistAliases = new Map([
    ["布兰妮 斯皮尔斯", "britney spears"],
    ["布蘭妮 斯皮爾斯", "britney spears"],
    ["西野加奈", "西野カナ"],
    ["西野 カナ", "西野カナ"],
    ["kana nishino", "西野カナ"],
    ["平井大", "hiraidai"],
    ["平井 大", "hiraidai"],
]);
const artistKey = value => {
    const name = normalized(value);
    return artistAliases.get(name) ?? name;
};
const artistNames = value => (value ?? "").split(/\s+(?:feat\.?|ft\.?)\s+|\s*[、,，&＆;；]\s*/iu)
    .map(artistKey).filter(Boolean).sort().join("|");

const version = /\b(?:live|remix|remaster(?:ed)?|acoustic|instrumental|demo|karaoke|sped up|slowed|radio edit|mono|stereo|re recorded|extended|version|edit)\b|现场|現場|混音|伴奏|重制|重製/iu;
const albumName = value => normalized(value).replace(/ (?:single|ep)$/u, "");
const key = song => normalized(song.title);

function credit(song) {
    const title = song.title ?? "";
    const feature = title.match(/\s*[\[(]\s*(?:feat\.?|ft\.?)\s+([^)\]]+)[)\]]\s*$/iu);
    const artists = [...new Set(artistNames([song.artist, feature?.[1]].filter(Boolean).join(", ")).split("|"))]
        .filter(Boolean).join("|");
    return {
        title: normalized(feature ? title.slice(0, feature.index) : title),
        artists,
        featured: feature ? artistNames(feature[1]).split("|").filter(Boolean) : [],
    };
}

function venueVersion(title, album) {
    const suffix = title.match(/^(.*?) (live(?: (?:at|from) .*)?)$/u);
    if (!suffix) return null;
    return suffix[2] === "live" || suffix[2].startsWith(album + " ") || suffix[2] === album
        ? suffix[1] : null;
}

function lookupKeys(song) {
    const { title } = credit(song);
    const album = albumName(song.album);
    return new Set([key(song), title, venueVersion(title, album)].filter(Boolean));
}
const candidate = song => ({
    id: String(song.id), title: song.name, aliases: [...(song.alia ?? song.alias ?? []), ...(song.tns ?? [])],
    artist: (song.ar ?? song.artists)?.map(artist => artist.name).join(", "),
    album: (song.al ?? song.album)?.name, duration: (song.dt ?? song.duration) / 1000,
});

function compare(source, target) {
    if (!source.artist || !target.artist || !source.duration || !target.duration) return false;
    const sourceCredit = credit(source);
    const targetCredit = credit(target);
    if (sourceCredit.artists !== targetCredit.artists) return false;
    if (Math.abs(source.duration - target.duration) > 2.5) return false;
    if (!albumName(source.album) || albumName(source.album) !== albumName(target.album)) return false;
    if (sourceCredit.title === targetCredit.title) return true;
    const album = albumName(source.album);
    const sourceLive = venueVersion(sourceCredit.title, album);
    const targetLive = venueVersion(targetCredit.title, album);
    if (album.startsWith("live ") && sourceLive && sourceLive === targetLive
        && (sourceCredit.title.endsWith(" live") || targetCredit.title.endsWith(" live"))) return true;
    // A translated title may be an alias. Never use an alias to ignore a version label.
    return !version.test(key(source)) && !version.test(key(target))
        && target.aliases.some(alias => normalized(alias) === key(source));
}

function decide(source, candidates, existingOnly = false) {
    let exact = candidates.filter(song => compare(source, song));
    if (!exact.length && existingOnly) {
        const sourceCredit = credit(source);
        const sourceAlbum = albumName(source.album);
        const primary = artistKey(source.artist);
        if (sourceCredit.featured.length && sourceAlbum && primary) {
            exact = candidates.filter(song => {
                const targetCredit = credit(song);
                const targetPrimary = artistKey(song.artist?.split(", ", 1)[0]);
                const targetArtists = new Set(targetCredit.artists.split("|"));
                return sourceCredit.title === targetCredit.title && primary === targetPrimary
                    && sourceAlbum === albumName(song.album)
                    && Math.abs(source.duration - song.duration) <= 2.5
                    && sourceCredit.featured.every(artist => targetArtists.has(artist));
            });
        }
    }
    // A copy already favorited is a strong tie-breaker across ordinary releases.
    if (!exact.length && existingOnly && !version.test(key(source)) && !version.test(albumName(source.album))) {
        exact = candidates.filter(song => key(source) === key(song)
            && source.artist && artistNames(source.artist) === artistNames(song.artist)
            && Math.abs(source.duration - song.duration) <= 1.5
            && !version.test(albumName(song.album)));
    }
    return {
        status: exact.length === 1 ? "matched" : candidates.length ? "review" : "missing",
        id: exact.length === 1 ? exact[0].id : null,
        candidates: (exact.length ? exact : candidates).slice(0, 5),
    };
}

const alternateVersion = /\b(?:sessions?|first take|english ver|japanese ver|korean ver|spedup|slowed down|edit(?:ed)?|clean|explicit|mix|medley|reprise|reimagined|recorded at|unplugged|rerecorded|taylor s version)\b|现场|現場|混音|伴奏|重制|重製|翻唱|演唱会|演唱會|串烧|串燒/iu;

function crossAlbumCandidate(source, candidates) {
    const ordinary = song => song.duration > 0 && albumName(song.album)
        && ![key(song), albumName(song.album)].some(text => version.test(text) || alternateVersion.test(text));
    if (!ordinary(source)) return null;
    const sourceCredit = credit(source);
    if (!sourceCredit.title || !sourceCredit.artists) return null;

    const nearby = candidates.filter(song => {
        const targetCredit = credit(song);
        return targetCredit.title === sourceCredit.title && targetCredit.artists === sourceCredit.artists
            && song.duration > 0 && Math.abs(song.duration - source.duration) <= 2.5;
    });
    if (nearby.length !== 1) return null;
    const [song] = nearby;
    if (!ordinary(song) || albumName(song.album) === albumName(source.album)
        || Math.abs(song.duration - source.duration) > 0.1) return null;
    return song;
}

function indexSongs(index, songs) {
    for (const song of songs) {
        for (const title of new Set([...lookupKeys(song), ...song.aliases.map(normalized)])) {
            if (!index.has(title)) index.set(title, []);
            index.get(title).push(song);
        }
    }
}

const sameOrder = (left, right) => left.length === right.length && left.every((id, index) => id === right[index]);

function uniqueSongs(songs) {
    return [...new Map(songs.map(song => [song.id, song])).values()];
}

function digest(songs) {
    return createHash("sha256").update(JSON.stringify(songs)).digest("hex");
}

function writeReport(report) {
    const temp = reportPath + "." + process.pid + ".tmp";
    writeFileSync(temp, JSON.stringify(report, null, 2) + "\n", { mode: 0o600 });
    renameSync(temp, reportPath);
}

function catalogClient(request, output, event) {
    let next = 0;
    let pausedUntil = 0;
    return async (method, params) => {
        for (let attempt = 0; ; attempt++) {
            // Reserve request slots in order, including when multiple workers
            // finish together. A rate-limit response pauses the whole catalog.
            while (Math.max(next, pausedUntil) > Date.now()) {
                await delay(Math.max(next, pausedUntil) - Date.now());
            }
            next = Date.now() + 350;
            try {
                return await request(method, params);
            } catch (error) {
                if (attempt === 2 || !/（(?:405|429|50[024])）/.test(error.message)) throw error;
                const until = Date.now() + (attempt === 0 ? 30000 : 60000);
                if (pausedUntil <= Date.now()) {
                    const text = "网易云暂时限制搜索，稍等后自动重试";
                    event("waiting", { text });
                    if (!process.env.AMNCM_EMBEDDED) output(text);
                }
                pausedUntil = Math.max(pausedUntil, until);
            }
        }
    };
}

async function search(catalog, source) {
    const keywords = `${source.title} ${source.artist ?? ""}`;
    const response = await catalog("search", { keywords, limit: 15 });
    if (!response.result || (response.result.songs !== undefined && !Array.isArray(response.result.songs))) {
        throw new Error("网易云搜索结果格式异常。");
    }
    return (response.result.songs ?? []).map(candidate);
}

async function albumSongs(catalog, source) {
    const keywords = `${source.album} ${source.artist}`;
    const response = await catalog("search", { keywords, type: 10, limit: 12 });
    const albums = (response.result?.albums ?? []).filter(album => {
        const artist = album.artists?.length ? album.artists.map(person => person.name).join(", ") : album.artist?.name;
        return albumName(source.album) === albumName(album.name)
            && artistNames(source.artist) === artistNames(artist);
    });
    if (albums.length !== 1) return [];
    const detail = await catalog("album", { id: albums[0].id });
    return (detail.songs ?? []).map(candidate);
}

function duplicateRecordings(entry) {
    if (entry.id || entry.status !== "review" || entry.candidates.length >= 5) return [];
    const exact = entry.candidates.filter(song => compare(entry.source, song));
    if (exact.length < 2) return [];
    const first = exact[0];
    return exact.every(song => key(song) === key(first) && credit(song).artists === credit(first).artists
        && albumName(song.album) === albumName(first.album) && Math.abs(song.duration - first.duration) <= 0.1)
        ? exact : [];
}

async function verifyCatalog(entries, current, request) {
    const duplicates = entries.map(duplicateRecordings);
    const ids = [...new Set(entries.flatMap((entry, index) =>
        entry.id ? [entry.id] : duplicates[index].map(song => song.id)))].filter(id => !current.has(id));
    const available = new Map();
    for (let start = 0; start < ids.length; start += 200) {
        const batch = ids.slice(start, start + 200);
        const result = await request("song_detail", { ids: batch.join(",") });
        if (!Array.isArray(result.songs) || !Array.isArray(result.privileges)) {
            throw new Error("网易云未返回歌曲播放权限，已保存搜索缓存。");
        }
        const detail = new Set(result.songs.map(song => String(song.id)));
        for (const info of result.privileges) {
            const id = String(info.id);
            if (detail.has(id) && info.st >= 0 && info.pl > 0) available.set(id, info.pl);
        }
    }

    for (const [index, entry] of entries.entries()) {
        if (entry.id && !current.has(entry.id) && !available.has(entry.id)) {
            entry.unavailableId = entry.id;
            entry.id = null;
            entry.status = "unavailable";
        } else if (duplicates[index].length) {
            const options = duplicates[index].filter(song => current.has(song.id) || available.has(song.id));
            options.sort((a, b) => Number(current.has(b.id)) - Number(current.has(a.id))
                || (available.get(b.id) ?? 0) - (available.get(a.id) ?? 0));
            if (options.length) {
                entry.id = options[0].id;
                entry.status = "matched";
                entry.reason = "equivalent_catalog_ids";
            }
        }
    }
}

async function plan(db, songs, target, limit, request, output, event) {
    event("progress", { text: "正在读取网易云的「我喜欢的音乐」" });
    const index = new Map();
    const readDetails = db.prepare("SELECT metadata FROM netease_detail WHERE id = ?");
    const storeDetails = db.prepare("INSERT OR REPLACE INTO netease_detail VALUES (?, ?)");
    const unknown = [];
    for (const id of target.tracks) {
        const row = readDetails.get(id);
        if (row) indexSongs(index, [JSON.parse(row.metadata)]);
        else unknown.push(id);
    }
    for (let start = 0; start < unknown.length; start += 200) {
        const ids = unknown.slice(start, start + 200);
        const requested = new Set(ids);
        const details = await request("song_detail", { ids: ids.join(",") });
        if (!Array.isArray(details.songs)) throw new Error("网易云歌曲详情返回异常。");
        const metadata = details.songs.map(candidate).filter(song => requested.has(song.id));
        indexSongs(index, metadata);
        db.exec("BEGIN");
        try {
            for (const song of metadata) storeDetails.run(song.id, JSON.stringify(song));
            db.exec("COMMIT");
        } catch (error) {
            db.exec("ROLLBACK");
            throw error;
        }
    }
    const overrides = existsSync(overridePath) ? JSON.parse(readFileSync(overridePath, "utf8")) : {};
    const sourceIds = new Set(songs.map(song => song.id));
    const overridesById = new Map(Object.entries(overrides));
    for (const [sourceId, targetId] of overridesById) {
        if (!sourceIds.has(sourceId) || (targetId !== null && (typeof targetId !== "string" || !/^\d+$/.test(targetId)))) {
            throw new Error(`人工匹配条目无效（${sourceId}）。请检查 ${overridePath}。`);
        }
    }
    const read = db.prepare("SELECT result FROM netease_match WHERE fingerprint = ?");
    const write = db.prepare("INSERT OR REPLACE INTO netease_match VALUES (?, ?)");
    const entries = [];
    const catalog = catalogClient(request, output, event);
    const groups = new Map();
    const groupKey = source => JSON.stringify([albumName(source.album), artistNames(source.artist)]);
    const local = songs.map(source => {
        if (overridesById.has(source.id)) return { source };
        const existing = uniqueSongs([...lookupKeys(source)].flatMap(title => index.get(title) ?? []));
        const initial = decide(source, existing, true);
        const fingerprint = initial.id ? null : digest([1, source]);
        const cached = fingerprint ? read.get(fingerprint) : null;
        const group = groupKey(source);
        if (fingerprint && !cached && source.album && source.artist) {
            groups.set(group, (groups.get(group) ?? 0) + 1);
        }
        return { source, existing, initial, fingerprint, cached, group };
    });
    const albumJobs = new Map();
    const albumRead = db.prepare("SELECT result FROM netease_album WHERE fingerprint = ?");
    const albumWrite = db.prepare("INSERT OR REPLACE INTO netease_album VALUES (?, ?)");
    let queries = 0;
    let albumQueries = 0;
    let reused = 0;
    let failed = 0;
    const searchAndSave = async (source, existing, fingerprint) => {
        queries++;
        try {
            const found = await search(catalog, source);
            const candidates = uniqueSongs([...existing, ...found]);
            let result = decide(source, candidates);
            if (result.status === "review" && !candidates.some(song => compare(source, song))) {
                const match = crossAlbumCandidate(source, candidates);
                if (match) result = { status: "matched", id: match.id, candidates: [match], reason: "cross_album" };
            }
            write.run(fingerprint, JSON.stringify({ ...result, crossAlbumChecked: true }));
            return result;
        } catch (error) {
            failed++;
            return { status: "error", id: null, candidates: existing.slice(0, 5), error: error.message };
        }
    };
    const resolve = async ({ source, existing, initial, fingerprint, cached, group }) => {
        if (overridesById.has(source.id)) {
            const id = overridesById.get(source.id);
            return { source, id, status: id === null ? "skipped" : "manual", candidates: [] };
        }
        let result = initial;
        if (result.id) {
            reused++;
        } else if (existing.filter(song => compare(source, song)).length <= 1) {
            if (cached) {
                const saved = JSON.parse(cached.result);
                const album = albumRead.get(group);
                const albumTracks = album ? JSON.parse(album.result) : [];
                const candidates = uniqueSongs([...existing, ...albumTracks, ...saved.candidates]);
                result = saved.id ? saved : decide(source, candidates);
                if (!result.id && result.candidates.filter(song => compare(source, song)).length < 2) result = saved;
                // Old reports retain only a shortlist. Search again before accepting a cross-album match.
                if (!result.id && !saved.crossAlbumChecked && queries < limit
                    && crossAlbumCandidate(source, candidates)) {
                    result = await searchAndSave(source, existing, fingerprint);
                }
            } else if (queries < limit) {
                if (limit === Infinity && groups.get(group) >= 3) {
                    if (!albumJobs.has(group)) {
                        const saved = albumRead.get(group);
                        albumJobs.set(group, saved ? Promise.resolve(JSON.parse(saved.result)) :
                            albumSongs(catalog, source).then(found => {
                                albumWrite.run(group, JSON.stringify(found));
                                albumQueries++;
                                return found;
                            }).catch(() => []));
                    }
                    const found = await albumJobs.get(group);
                    result = decide(source, uniqueSongs([...existing, ...found]));
                }
                if (result.id) {
                    write.run(fingerprint, JSON.stringify(result));
                } else {
                    result = await searchAndSave(source, existing, fingerprint);
                }
            } else {
                result = { status: "pending", id: null, candidates: existing.slice(0, 5) };
            }
        }
        return { source, ...result };
    };
    event("progress", { text: "正在匹配歌曲", completed: 0, total: songs.length });
    let lastProgress = 0;
    let lastProgressTime = Date.now();
    let consecutiveFailures = 0;
    const size = limit === Infinity ? 4 : 1;
    for (let i = 0; i < songs.length; i += size) {
        const batch = await Promise.all(local.slice(i, i + size).map(resolve));
        entries.push(...batch);
        consecutiveFailures = batch.every(entry => entry.status === "error") ? consecutiveFailures + 1 : 0;
        if (consecutiveFailures === 2 && queries < limit) {
            output("网易云连续拒绝搜索，剩余曲目先使用本地缓存与红心匹配。");
            limit = queries;
        }
        const now = Date.now();
        if (entries.length === songs.length || (entries.length - lastProgress >= 20 && now - lastProgressTime >= 100)) {
            lastProgress = entries.length;
            lastProgressTime = now;
            event("progress", { text: "正在匹配歌曲", completed: entries.length, total: songs.length });
        }
        if (!process.env.AMNCM_EMBEDDED && entries.length % 100 === 0) {
            output(`已处理 ${entries.length}/${songs.length} 首。`);
        }
    }
    const current = new Set(target.tracks);
    if (!failed && entries.every(entry => entry.status !== "pending")) {
        output("正在批量核验新匹配的网易云歌曲及播放权限。");
        await verifyCatalog(entries, current, request);
    }
    const ordered = [...new Set(entries.map(entry => entry.id).filter(Boolean))];
    const matched = new Set(ordered);
    const additions = ordered.filter(id => !current.has(id));
    const desired = [...ordered, ...target.tracks.filter(id => !matched.has(id))];
    const stats = {
        source: songs.length, matched: entries.filter(entry => entry.id).length,
        reused, queries, albumQueries, failed, manual: entries.filter(entry => entry.status === "manual").length,
        skipped: entries.filter(entry => entry.status === "skipped").length, additions: additions.length,
        review: entries.filter(entry => entry.status === "review").length,
        missing: entries.filter(entry => entry.status === "missing").length,
        unavailable: entries.filter(entry => entry.status === "unavailable").length,
        pending: entries.filter(entry => entry.status === "pending").length,
        targetOnly: desired.length - ordered.length,
    };
    writeReport({ sourceDigest: digest(songs), target, additions, desired, stats, entries });
    event("plan", { count: songs.length, matched: stats.matched, additions: additions.length,
        review: stats.review + stats.missing + stats.unavailable, incomplete: stats.failed + stats.pending,
        updatesOrder: !sameOrder([...target.tracks, ...additions], desired),
        uid: target.uid, ids: target.tracks });
    if (!process.env.AMNCM_EMBEDDED) {
        output(JSON.stringify(stats));
        output(reportPath);
    }
}

async function reconcileCatalogIds(report, tracks, request, output) {
    const current = new Set(tracks);
    const planned = new Set(report.desired);
    const unexpected = tracks.filter(id => !planned.has(id));
    if (!unexpected.length) return false;
    const missing = report.additions.filter(id => !current.has(id));
    if (unexpected.length > missing.length || report.target.tracks.some(id => !current.has(id))) return false;
    const ids = [...missing, ...unexpected];
    const details = new Map();
    for (let start = 0; start < ids.length; start += 200) {
        const result = await request("song_detail", { ids: ids.slice(start, start + 200).join(",") });
        for (const song of result.songs ?? []) details.set(String(song.id), candidate(song));
    }
    const replacements = new Map();
    for (const id of unexpected) {
        const actual = details.get(id);
        if (!actual?.duration || !actual.artist || !actual.album || !actual.title) return false;
        const equivalent = missing.filter(plannedId => {
            const song = details.get(plannedId);
            return song && key(song) === key(actual)
                && credit(song).artists === credit(actual).artists
                && albumName(song.album) === albumName(actual.album)
                && Math.abs(song.duration - actual.duration) <= 0.1;
        });
        if (equivalent.length !== 1 || replacements.has(equivalent[0])) return false;
        replacements.set(equivalent[0], id);
    }
    report.desired = report.desired.map(id => replacements.get(id) ?? id);
    report.additions = report.additions.map(id => replacements.get(id) ?? id);
    for (const entry of report.entries) {
        if (replacements.has(entry.id)) {
            entry.requestedId = entry.id;
            entry.id = replacements.get(entry.id);
            entry.reason = "netease_catalog_id_redirect";
        }
    }
    output(`已核对并接受网易云重定向的 ${replacements.size} 个同录音曲目 ID。`);
    return true;
}

function redirectedIds(report) {
    return new Map(report.entries.filter(entry => entry.requestedId && entry.id)
        .map(entry => [entry.id, entry.requestedId]));
}

function onlyRedirectedPositionsDiffer(tracks, report) {
    const redirected = redirectedIds(report);
    if (!redirected.size || tracks.length !== report.desired.length) return false;
    const observed = new Set(tracks);
    return report.desired.every(id => observed.has(id))
        && sameOrder(tracks.filter(id => !redirected.has(id)), report.desired.filter(id => !redirected.has(id)));
}

async function apply(songs, target, request, favorites, output, pilot, event) {
    const savedReport = readFileSync(reportPath, "utf8");
    const report = JSON.parse(savedReport);
    if ((!pilot && (report.stats.pending || report.stats.failed)) || report.sourceDigest !== digest(songs)
        || report.target.id !== target.id || report.target.uid !== target.uid) {
        throw new Error("请先对当前资料库及当前网易云账号生成完整计划。");
    }
    if (pilot) {
        const entries = report.entries.slice(0, pilot);
        const ordered = [...new Set(entries.map(entry => entry.id).filter(Boolean))];
        if (entries.length !== pilot || ordered.length !== pilot) {
            throw new Error("试同步需要前 N 首歌曲都有唯一匹配。");
        }
        const existing = new Set(report.target.tracks);
        const selected = new Set(ordered);
        report.additions = ordered.filter(id => !existing.has(id));
        report.desired = [...ordered, ...report.target.tracks.filter(id => !selected.has(id))];
    }
    let reconciled = await reconcileCatalogIds(report, target.tracks, request, output);
    const before = new Set(target.tracks);
    const original = new Set(report.target.tracks);
    let allowed = new Set(report.desired);
    if ([...original].some(id => !before.has(id)) || [...before].some(id => !allowed.has(id))) {
        throw new Error("网易云歌单成员已变化，请重新生成计划。");
    }
    if (!sameOrder(target.tracks, report.desired)
        && !onlyRedirectedPositionsDiffer(target.tracks, report)
        && !sameOrder(target.tracks.filter(id => original.has(id)), report.target.tracks)) {
        throw new Error("网易云歌单的原有顺序已变化，请重新生成计划。");
    }
    if (allowed.size !== report.desired.length || [...allowed].some(id => !/^\d+$/.test(id) || !Number.isSafeInteger(Number(id)))) {
        throw new Error("计划中的网易云曲目 ID 无效。");
    }
    if (!sameOrder(report.additions, report.desired.filter(id => !original.has(id)))) {
        throw new Error("计划中的新增红心与目标顺序不一致，请重新生成计划。");
    }
    const pending = report.additions.filter(id => !before.has(id));
    if (sameOrder(target.tracks, report.desired)) {
        await verifyLikes(target, allowed, request);
        if (reconciled && !pilot && readFileSync(reportPath, "utf8") === savedReport) writeReport(report);
        event("done", { count: target.tracks.length, additions: 0, ids: report.additions, currentIDs: target.tracks, changed: false });
        output(`已核实网易云红心集合和歌单顺序，共 ${target.tracks.length} 首，无需更新。`);
        return;
    }
    const backupPath = join(directory, `netease-before-${Date.now()}.json`);
    writeFileSync(backupPath, JSON.stringify(target) + "\n", { mode: 0o600, flag: "wx" });
    output(`原始曲目顺序已备份到 ${backupPath}`);
    event("progress", { text: "正在添加红心", completed: 0, total: pending.length });
    for (let start = 0; start < pending.length; start += 40) {
        const tracks = pending.slice(start, start + 40).join(",");
        await request("playlist_tracks", { op: "add", pid: target.id, tracks });
        event("progress", { text: "正在添加红心", completed: Math.min(start + 40, pending.length), total: pending.length });
        await delay(500);
    }
    const updated = pending.length ? await favorites() : target;
    if (updated.id === target.id && await reconcileCatalogIds(report, updated.tracks, request, output)) {
        reconciled = true;
        allowed = new Set(report.desired);
    }
    if (updated.id !== target.id || updated.tracks.length !== allowed.size
        || updated.tracks.some(id => !allowed.has(id))) {
        throw new Error("红心写入后回读的曲目集合与计划不同。已保留计划，重新执行前可检查当前歌单。");
    }
    let verified = updated;
    let reordered = false;
    if (!sameOrder(updated.tracks, report.desired)) {
        if (!onlyRedirectedPositionsDiffer(updated.tracks, report)
            && !sameOrder(updated.tracks.filter(id => original.has(id)), report.target.tracks)) {
            throw new Error("添加红心期间歌单顺序发生变化，请重新生成计划。");
        }
        event("progress", { text: "正在调整歌曲顺序" });
        await request("song_order_update", { pid: target.id, ids: JSON.stringify(report.desired.map(Number)) });
        reordered = true;
        if (redirectedIds(report).size) verified = await favorites();
    }
    if (verified.id === target.id && !sameOrder(verified.tracks, report.desired)
        && onlyRedirectedPositionsDiffer(verified.tracks, report)) {
        const redirected = redirectedIds(report);
        const ids = report.desired.map(id => Number(redirected.get(id) ?? id));
        await request("song_order_update", { pid: target.id, ids: JSON.stringify(ids) });
        reordered = true;
    }
    event("progress", { text: "正在等待网易云顺序稳定" });
    verified = await verifyStableOrder(target, report.desired, allowed, favorites, request);
    await verifyLikes(target, allowed, request);
    if (reconciled && !pilot && readFileSync(reportPath, "utf8") === savedReport) writeReport(report);
    event("done", { count: verified.tracks.length, additions: pending.length, ids: report.additions,
        currentIDs: verified.tracks, reordered, changed: !sameOrder(target.tracks, verified.tracks) });
    output(`已核实网易云红心集合和歌单顺序，共 ${verified.tracks.length} 首，本次新增红心 ${pending.length} 首。`);
}

async function verifyStableOrder(target, desired, allowed, favorites, request) {
    let consecutive = 0;
    // The immediate response can show the requested order before it has settled.
    for (const wait of [2000, 5000, 5000]) {
        await delay(wait);
        const observed = await favorites();
        if (observed.uid !== target.uid || observed.id !== target.id
            || observed.tracks.length !== allowed.size || new Set(observed.tracks).size !== allowed.size
            || observed.tracks.some(id => !allowed.has(id))) {
            throw new Error("核验期间网易云歌单成员发生变化，请重新预览。");
        }
        consecutive = sameOrder(observed.tracks, desired) ? consecutive + 1 : 0;
        if (consecutive === 2) return observed;
    }
    await verifyLikes(target, allowed, request);
    throw new Error("网易云红心已核对，但歌曲顺序未稳定。请重新预览后重试。");
}

async function verifyLikes(target, allowed, request) {
    const liked = new Set((await request("likelist", { uid: target.uid })).ids.map(String));
    if (liked.size !== allowed.size || [...allowed].some(id => !liked.has(id))) {
        throw new Error("网易云回读的红心集合与歌单成员不一致。");
    }
}

function showReport(args, output) {
    const { values } = parseArgs({ args, options: { review: { type: "boolean" } } });
    if (!existsSync(reportPath)) throw new Error("没有匹配报告，请先运行 node ncm.cjs plan。");
    const report = JSON.parse(readFileSync(reportPath, "utf8"));
    if (!values.review) {
        output(JSON.stringify(report.stats, null, 2));
        output(reportPath);
        return;
    }
    const unresolved = new Set(["review", "missing", "unavailable", "pending", "error"]);
    const row = cells => cells.map(cell => String(cell ?? "").replace(/[\t\r\n]+/g, " ")).join("\t");
    output(row(["Apple ID", "歌名", "艺人", "专辑", "状态", "网易云候选"]));
    for (const entry of report.entries) {
        if (!unresolved.has(entry.status)) continue;
        const { id, title, artist, album } = entry.source;
        const candidates = (entry.candidates ?? []).map(song => `${song.id} ${song.title} / ${song.artist} / ${song.album}`);
        output(row([id, title, artist, album, entry.status, candidates.join(" | ")]));
    }
}

async function run(command, args, { request, favorites, output, event = () => {} }) {
    if (command === "report") return showReport(args, output);
    const { values } = parseArgs({ args, options: { limit: { type: "string" }, pilot: { type: "string" } } });
    const limit = values.limit === undefined ? Infinity : Number(values.limit);
    if (values.limit !== undefined && (command !== "plan" || !Number.isSafeInteger(limit) || limit < 0)) {
        throw new Error("--limit 只能用于 plan，且必须是非负整数。");
    }
    const pilot = values.pilot === undefined ? 0 : Number(values.pilot);
    if (values.pilot !== undefined && (command !== "apply" || !Number.isSafeInteger(pilot) || pilot < 1 || pilot > 10)) {
        throw new Error("--pilot 仅用于 apply，范围为 1 到 10。");
    }
    if (!existsSync(dbPath)) throw new Error("找不到本地快照，请先运行 python3 am2ncm.py scan。");
    const lock = command === "apply"
        ? new DatabaseSync(join(directory, "netease-write-lock.sqlite3")) : null;
    const db = new DatabaseSync(dbPath);
    try {
        lock?.exec("BEGIN IMMEDIATE");
        db.exec(`PRAGMA busy_timeout = 5000;
            CREATE TABLE IF NOT EXISTS netease_match (fingerprint TEXT PRIMARY KEY, result TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS netease_detail (id TEXT PRIMARY KEY, metadata TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS netease_album (fingerprint TEXT PRIMARY KEY, result TEXT NOT NULL);`);
        const songs = db.prepare(`SELECT t.id, t.title, t.artist, t.album, t.duration, t.date_added
            FROM member m JOIN playlist p ON p.id = m.playlist_id JOIN track t ON t.id = m.track_id
            WHERE p.kind = 'library' ORDER BY m.position`).all();
        if (!songs.length) throw new Error("资料库快照为空，请先运行 python3 am2ncm.py scan。");
        const target = await favorites();
        if (process.env.AMNCM_EXPECTED_UID && target.uid !== process.env.AMNCM_EXPECTED_UID) {
            throw new Error("网易云登录账号已更换，请在 App 内重新连接。");
        }
        if (command === "plan") await plan(db, songs, target, limit, request, output, event);
        else await apply(songs, target, request, favorites, output, pilot, event);
    } finally {
        db.close();
        lock?.close();
    }
}

module.exports = { run };
