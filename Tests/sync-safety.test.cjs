const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

// Exercise the real engine with in-memory reports and simulated API responses.
// No Keychain access, user database, timers, or network writes are involved.
function engine(report) {
    const context = {
        module: { exports: {} }, process: { env: {}, pid: 1 },
        require(name) {
            if (name === 'node:fs') return {
                ...fs, readFileSync: () => JSON.stringify(report),
                writeFileSync() {}, renameSync() {},
            };
            if (name === 'node:timers/promises') return { setTimeout: async () => {} };
            return require(name);
        },
    };
    vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../sync.cjs'), 'utf8')
        + '\nmodule.exports = { preservingLocalOrder, apply, digest };', context);
    return context.module.exports;
}

function fixture({ tracks = ['9', '2', '1'], ordered = ['1', '2'], additions = [] } = {}) {
    const target = { uid: '42', id: '99', tracks };
    const report = { target, entries: ordered.map(id => ({ id })), additions,
        desired: [...ordered, ...tracks.filter(id => !ordered.includes(id))], stats: {} };
    const api = engine(report);
    report.sourceDigest = api.digest([]);
    let current = structuredClone(target);
    const writes = [], events = [];
    return {
        api, report, target, writes, events,
        get current() { return current; },
        set current(value) { current = value; },
        favorites: async () => structuredClone(current),
        request: async (name, params) => {
            if (name === 'likelist') return { ids: current.tracks };
            writes.push({ name, ...params });
            if (name === 'playlist_tracks') {
                assert.equal(params.op, 'add');
                current.tracks = [...params.tracks.split(','), ...current.tracks];
            } else if (name === 'song_order_update') {
                current.tracks = JSON.parse(params.ids).map(String);
            } else throw new Error('Unexpected request: ' + name);
            return {};
        },
        async apply(favorites = this.favorites, request = this.request) {
            await api.apply([], target, request, favorites, () => {}, 0,
                (kind, fields) => events.push({ kind, ...fields }));
        },
    };
}

test('NetEase-only new favorite stays at the top while matched slots are sorted', () => {
    const { preservingLocalOrder } = engine({});
    assert.deepEqual(Array.from(preservingLocalOrder(['1', '2'], ['9', '2', '8', '1'])), ['9', '1', '8', '2']);
    assert.deepEqual(Array.from(preservingLocalOrder(['3', '1', '2'], ['9', '2', '8', '1'])), ['3', '9', '1', '8', '2']);
});

test('legacy reports cannot move an unmatched heart to the tail', async () => {
    const f = fixture();
    await f.apply();
    assert.deepEqual(f.current.tracks, ['9', '1', '2']);
    assert.equal(f.writes.length, 1);
    assert.equal(f.events.at(-1).kind, 'done');
});

test('order-only sync rereads favorites and aborts when a new heart appears', async () => {
    const f = fixture();
    f.current.tracks.unshift('7');
    await assert.rejects(f.apply());
    assert.equal(f.writes.length, 0);
    assert.ok(f.current.tracks.includes('7'));
});

test('a heart added just before ordering is not overwritten', async () => {
    const f = fixture();
    let reads = 0;
    await assert.rejects(f.apply(async () => {
        if (++reads === 2) f.current.tracks.unshift('7');
        return f.favorites();
    }));
    assert.equal(f.writes.length, 0);
    assert.ok(f.current.tracks.includes('7'));
});

test('concurrent manual unlikes stop ordering without re-adding the song', async () => {
    const f = fixture();
    f.current.tracks = ['9', '2'];
    await assert.rejects(f.apply());
    assert.equal(f.writes.length, 0);
});

test('additions retain unmatched positions and verify the final membership', async () => {
    const f = fixture({ ordered: ['3', '1', '2'], additions: ['3'] });
    await f.apply();
    assert.deepEqual(f.current.tracks, ['3', '9', '1', '2']);
    assert.equal(f.writes[0].op, 'add');
    assert.equal(f.events.at(-1).additions, 1);
});

test('new heart during additions prevents a subsequent stale full-list update', async () => {
    const f = fixture({ ordered: ['3', '1', '2'], additions: ['3'] });
    await assert.rejects(f.apply(f.favorites, async (name, params) => {
        const response = await f.request(name, params);
        if (name === 'playlist_tracks') f.current.tracks.unshift('7');
        return response;
    }));
    assert.equal(f.writes.filter(x => x.name === 'song_order_update').length, 0);
    assert.ok(f.current.tracks.includes('7'));
});
