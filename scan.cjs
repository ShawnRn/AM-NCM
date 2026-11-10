const { execFileSync } = require("node:child_process");
const { mkdirSync } = require("node:fs");
const { homedir } = require("node:os");
const { join } = require("node:path");
const { DatabaseSync } = require("node:sqlite");

function scan() {
    let snapshot;
    try {
        const data = execFileSync("/usr/bin/osascript", ["-l", "JavaScript", join(__dirname, "music-scan.js")], {
            encoding: "utf8", timeout: 120000, maxBuffer: 32 * 1024 * 1024, stdio: ["ignore", "pipe", "pipe"],
        });
        snapshot = JSON.parse(data);
    } catch (error) {
        if (error.stderr?.includes("-1743")) {
            throw new Error("请在系统设置的「隐私与安全性 → 自动化」中，允许 AM-NCM 访问音乐。");
        }
        if (error.code === "ETIMEDOUT") throw new Error("音乐资料库响应超时。请打开音乐 App 后重试。");
        throw new Error("暂时读不到音乐资料库。请确认音乐 App 已登录且资料库已加载。");
    }

    const [source] = snapshot.playlists;
    const tracks = new Map(snapshot.tracks.map(track => [track.id, track]));
    if (tracks.size !== snapshot.tracks.length || source.members.some(id => !tracks.has(id))) {
        throw new Error("扫描期间音乐资料库发生变化，请重试。");
    }
    const rows = source.members.map((id, index) => ({ id, source: index + 1, date: tracks.get(id).date_added }));
    const dated = rows.filter(row => row.date).sort((a, b) => Date.parse(b.date) - Date.parse(a.date));
    const directory = join(homedir(), "Library", "Application Support", "AM-NCM");
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    const db = new DatabaseSync(join(directory, "library.sqlite3"));
    try {
        db.exec(`
            PRAGMA busy_timeout = 5000;
            PRAGMA foreign_keys = ON;
            BEGIN IMMEDIATE;
            CREATE TABLE IF NOT EXISTS track (
                id TEXT PRIMARY KEY, title TEXT NOT NULL, artist TEXT, album TEXT,
                duration REAL, date_added TEXT, media_kind TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS playlist (id TEXT PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS member (
                playlist_id TEXT NOT NULL REFERENCES playlist(id), track_id TEXT NOT NULL REFERENCES track(id),
                source_position INTEGER NOT NULL, position INTEGER NOT NULL, PRIMARY KEY (playlist_id, position)
            );
            DELETE FROM member; DELETE FROM playlist; DELETE FROM track;
        `);
        const insert = db.prepare("INSERT INTO track VALUES (?, ?, ?, ?, ?, ?, ?)");
        for (const track of tracks.values()) {
            insert.run(track.id, track.title, track.artist ?? null, track.album ?? null,
                track.duration ?? null, track.date_added ?? null, track.media_kind);
        }
        db.prepare("INSERT INTO playlist VALUES (?, ?, ?)").run(source.id, source.name, source.kind);
        const member = db.prepare("INSERT INTO member VALUES (?, ?, ?, ?)");
        let offset = 0;
        for (const [index, row] of rows.entries()) {
            const item = row.date ? dated[offset++] : row;
            member.run(source.id, item.id, item.source, index + 1);
        }
        db.exec("COMMIT");
    } finally {
        db.close();
    }
    return tracks.size;
}

module.exports = { scan };
