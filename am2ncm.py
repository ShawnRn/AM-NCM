"""Scan the local Music library and preview source playlist order."""

import argparse
from contextlib import closing
from datetime import datetime
import json
from pathlib import Path
import sqlite3
import subprocess
import sys

SCRIPT = Path(__file__).with_name("music-scan.js")
DEFAULT_DB = Path.home() / "Library/Application Support/AM-NCM/library.sqlite3"

SCHEMA = """
CREATE TABLE IF NOT EXISTS track (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    artist TEXT,
    album TEXT,
    duration REAL,
    date_added TEXT,
    media_kind TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS playlist (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    kind TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS member (
    playlist_id TEXT NOT NULL REFERENCES playlist(id),
    track_id TEXT NOT NULL REFERENCES track(id),
    source_position INTEGER NOT NULL,
    position INTEGER NOT NULL,
    PRIMARY KEY (playlist_id, position)
);
"""


def order_members(members, tracks):
    indexed = list(enumerate(members))

    def added(member):
        value = tracks[member[1]]["date_added"]
        return datetime.fromisoformat(value) if value else None

    dated = iter(sorted(
        (member for member in indexed if added(member) is not None),
        key=added, reverse=True,
    ))
    return [
        next(dated) if added(member) is not None else member
        for member in indexed
    ]


def save_scan(path, snapshot):
    tracks = {track["id"]: track for track in snapshot["tracks"]}
    playlists = snapshot["playlists"]
    if len(tracks) != len(snapshot["tracks"]):
        raise ValueError("Music 返回了重复的资料库曲目 ID，请重试。")
    if any(track_id not in tracks for p in playlists for track_id in p["members"]):
        raise ValueError("有歌单曲目未出现在资料库快照中，请等待 Music 完成同步后重试。")

    path.parent.mkdir(parents=True, exist_ok=True)
    with closing(sqlite3.connect(path)) as db:
        db.execute("PRAGMA foreign_keys = ON")
        db.executescript(SCHEMA)
        with db:
            db.execute("DELETE FROM member")
            db.execute("DELETE FROM playlist")
            db.execute("DELETE FROM track")
            db.executemany(
                """INSERT INTO track VALUES
                   (:id, :title, :artist, :album, :duration, :date_added, :media_kind)""",
                tracks.values(),
            )
            for playlist in playlists:
                playlist_id = playlist["id"]
                db.execute(
                    "INSERT INTO playlist VALUES (?, ?, ?)",
                    (playlist_id, playlist["name"], playlist["kind"]),
                )
                ordered = order_members(playlist["members"], tracks)
                db.executemany(
                    "INSERT INTO member VALUES (?, ?, ?, ?)",
                    ((playlist_id, track_id, source + 1, position)
                     for position, (source, track_id) in enumerate(ordered, 1)),
                )


def preview(path, limit):
    uri = path.resolve().as_uri() + "?mode=ro"
    with closing(sqlite3.connect(uri, uri=True)) as db:
        db.row_factory = sqlite3.Row
        db.execute("BEGIN")
        rows = db.execute(
            """SELECT p.*, count(m.position) AS track_count,
                      count(m.position) - count(t.date_added) AS missing_date_count
               FROM playlist p LEFT JOIN member m ON p.id = m.playlist_id
               LEFT JOIN track t ON t.id = m.track_id
               WHERE p.kind = 'library' GROUP BY p.id""",
        ).fetchall()
        return [
            dict(row, tracks=[dict(track) for track in db.execute(
                """SELECT m.position, m.source_position, t.*
                   FROM member m JOIN track t ON m.track_id = t.id
                   WHERE m.playlist_id = ? ORDER BY m.position LIMIT ?""",
                (row["id"], limit),
            )])
            for row in rows
        ]


def main():
    parser = argparse.ArgumentParser(description="Apple Music → 网易云音乐，本地歌单扫描与顺序预览")
    parser.add_argument("--db", type=Path, default=DEFAULT_DB, help="SQLite 快照路径")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("scan", help="读取 Music.app 并刷新快照")
    view = commands.add_parser("preview", help="读取快照并输出 JSON")
    view.add_argument("--limit", type=int, help="展示的歌曲数，0 表示仅显示统计")

    args = parser.parse_args()
    path = args.db.expanduser()
    try:
        if args.command == "scan":
            command = ["osascript", "-l", "JavaScript", str(SCRIPT)]
            result = subprocess.run(command, capture_output=True, text=True, timeout=120)
            if result.returncode:
                raise ValueError(result.stderr.strip() or "Music.app 读取失败。")
            snapshot = json.loads(result.stdout)
            save_scan(path, snapshot)
            count = len(snapshot["playlists"][0]["members"])
            print(f"已保存 {count:,} 首 Apple Music 资料库歌曲。\n{path}")
        else:
            if not path.is_file():
                raise ValueError("找不到本地快照，请先运行 scan。")
            if args.limit is not None and args.limit < 0:
                parser.error("--limit 必须大于或等于 0。")
            limit = args.limit if args.limit is not None else 5
            print(json.dumps(preview(path, limit), ensure_ascii=False, indent=2))
    except (ValueError, OSError, sqlite3.Error, subprocess.TimeoutExpired) as error:
        print(f"AM-NCM：{error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
