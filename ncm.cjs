const { spawnSync } = require("node:child_process");
const { mkdtempSync, writeFileSync, rmSync } = require("node:fs");
const { tmpdir } = require("node:os");
const { join } = require("node:path");
const { setTimeout: delay } = require("node:timers/promises");
const output = console.log.bind(console);
// The upstream client can include cookies in its diagnostic output.
for (const method of ["log", "info", "warn", "error", "debug"]) console[method] = () => {};
const api = require("@neteasecloudmusicapienhanced/api");
const service = "local.am-ncm.netease";

function saveCookie(cookie) {
    const encoded = Buffer.from(cookie).toString("base64");
    const result = spawnSync("/usr/bin/security", ["-i"], {
        input: `add-generic-password -U -s ${service} -a session -w ${encoded}\n`,
        encoding: "utf8",
    });
    if (result.status !== 0 || result.stderr.includes("SecKeychain")) {
        throw new Error("无法保存网易云登录到 macOS 钥匙串。");
    }
}

let sessionCookie;
function readCookie() {
    if (sessionCookie) return sessionCookie;
    const result = spawnSync("/usr/bin/security", [
        "find-generic-password", "-s", service, "-a", "session", "-w",
    ], { encoding: "utf8" });
    if (result.status !== 0) throw new Error("请先运行 node ncm.cjs login。");
    sessionCookie = Buffer.from(result.stdout.trim(), "base64").toString();
    return sessionCookie;
}

async function login() {
    const { body } = await api.login_qr_key({ timeout: 10000 });
    const key = body?.data?.unikey;
    if (!key) throw new Error("网易云没有返回登录二维码。");
    const qr = await api.login_qr_create({ key, qrimg: true });
    const folder = mkdtempSync(join(tmpdir(), "am-ncm-"));
    const path = join(folder, "login.png");
    writeFileSync(path, Buffer.from(qr.body.data.qrimg.split(",")[1], "base64"), { mode: 0o600 });
    spawnSync("/usr/bin/open", [path]);
    output(path);
    try {
        for (let attempt = 0; attempt < 80; attempt++) {
            await delay(2500);
            let check;
            try {
                check = (await api.login_qr_check({ key, timeout: 8000 })).body;
            } catch {
                continue;
            }
            if (check.code === 800) break;
            if (check.code === 803 && check.cookie) {
                saveCookie(check.cookie);
                output("网易云已登录，凭证已写入 macOS 钥匙串。");
                return;
            }
        }
        throw new Error("二维码已过期，请重新运行登录命令。");
    } finally {
        rmSync(folder, { recursive: true, force: true });
    }
}

async function request(method, params) {
    const cookie = ["search", "album"].includes(method) ? {} : readCookie();
    try {
        const response = await api[method]({ ...params, cookie, timeout: 12000 });
        const body = response.body?.body ?? response.body;
        if (body?.code !== 200 && body?.data?.code !== 200) {
            throw new Error(String(body?.code ?? response.status ?? "unknown"));
        }
        return body;
    } catch (error) {
        const code = error?.body?.code ?? (error instanceof Error ? error.message : error?.status);
        throw new Error(`网易云 ${method} 请求失败（${/^\d+$/.test(code) ? code : "网络或会话异常"}）。`);
    }
}

async function favorites() {
    const { data } = await request("login_status", {});
    const uid = data?.profile?.userId;
    if (!uid) throw new Error("登录已失效，请重新扫码。");
    const { playlist } = await request("user_playlist", { uid, limit: 1 });
    const target = playlist?.[0];
    // The account's first list is normally favorites. Require the service's
    // special-type marker and ownership before accepting the ID.
    if (target?.specialType !== 5 || String(target.userId) !== String(uid)) {
        throw new Error("无法确认当前账号的「我喜欢的音乐」歌单。");
    }
    const { playlist: detail } = await request("playlist_detail", { id: target.id });
    const tracks = detail?.trackIds?.map(track => String(track.id)) ?? [];
    if (!detail || tracks.length < Number(detail.trackCount) || tracks.some(id => !/^\d+$/.test(id))) {
        throw new Error(`网易云未返回完整的喜欢歌单曲目（有序 ID ${tracks.length} / 总数 ${detail?.trackCount}）。`);
    }
    return { uid: String(uid), id: String(target.id), name: detail.name, tracks, reportedCount: detail.trackCount };
}

async function main() {
    const command = process.argv[2];
    if (command === "login") await login();
    else if (command === "favorites") output(JSON.stringify(await favorites()));
    else if (command === "check") {
        const target = await favorites();
        const { ids } = await request("likelist", { uid: target.uid });
        const liked = new Set(ids.map(String));
        const tracks = new Set(target.tracks);
        output(JSON.stringify({
            ordered: tracks.size, count: target.reportedCount, liked: liked.size,
            orderOnly: [...tracks].filter(id => !liked.has(id)).length,
            likeOnly: [...liked].filter(id => !tracks.has(id)).length,
        }));
    }
    else if (["plan", "apply", "report"].includes(command)) {
        await require("./sync.cjs").run(command, process.argv.slice(3), {request, favorites, output});
    } else throw new Error("用法：node ncm.cjs login | plan | apply | report | check");
}

main().catch(error => {
    process.stderr.write((error instanceof Error ? error.message : "网易云请求失败。") + "\n");
    process.exitCode = 1;
});
