// Run with osascript -l JavaScript. Bulk property reads keep Apple Events
// independent of the number of songs.
function run() {
    const music = Application("Music");
    const library = music.libraryPlaylists[0];
    const tracks = library.tracks;
    const ids = tracks.persistentID();
    const titles = tracks.name();
    const artists = tracks.artist();
    const albums = tracks.album();
    const durations = tracks.duration();
    const dates = tracks.dateAdded();
    const mediaKinds = tracks.mediaKind();
    for (const values of [titles, artists, albums, durations, dates, mediaKinds]) {
        if (values.length !== ids.length) {
            throw new Error("Music library changed during the scan; try again.");
        }
    }

    const songs = ids.map((id, index) => ({
        id,
        title: titles[index],
        artist: artists[index],
        album: albums[index],
        duration: durations[index],
        date_added: dates[index],
        media_kind: mediaKinds[index],
    })).filter(song => song.media_kind === "song");

    const source = {
        id: library.persistentID(),
        name: "资料库 → 歌曲",
        members: songs.map(song => song.id),
    };
    const currentIds = tracks.persistentID();
    if (currentIds.length !== ids.length || currentIds.some((id, index) => id !== ids[index])) {
        throw new Error("Music library changed during the scan; try again.");
    }
    return JSON.stringify({tracks: songs, playlists: [{...source, kind: "library"}]});
}
