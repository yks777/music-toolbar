import QtQuick

// Fetches one track at a time: LRCLIB is the primary timed source, with
// lyrics.ovh used after a short pause when LRCLIB has no synced result.
Item {
  id: root

  property string trackTitle: ""
  property string trackArtist: ""
  property string trackAlbum: ""
  property real trackDuration: 0
  property real playbackPosition: 0

  // Lyrics stay in an in-memory FIFO cache capped at 100 entries so replaying
  // a recent track does not make another network request during this session.
  property var lyricLines: []
  property int currentLineIndex: -1
  property string source: ""
  property string lyricsState: "idle"
  property bool synced: false
  property real retryAfterSeconds: 0
  property var lyricsCache: ({})
  property var cacheKeys: []
  property var pendingXhr: null
  property var pendingTrack: null
  property string pendingLrclibPlain: ""
  property string fallbackTrackKey: ""
  property int requestToken: 0

  readonly property string trackSignature: {
    var title = String(trackTitle || "").trim()
    var artist = String(trackArtist || "").trim()
    var album = String(trackAlbum || "").trim()
    if (!title || !artist) return ""
    return artist + "\u001f" + title + "\u001f" + album + "\u001f" + Math.floor(Math.max(0, trackDuration))
  }

  readonly property string statusText: {
    if (lyricsState === "loading") return "Loading..."
    if (lyricsState === "instrumental") return "Instrumental"
    if (lyricsState === "rate-limited") return "Rate limited — retry in " + retryAfterSeconds + "s"
    if (lyricsState === "not-found" || lyricsState === "idle") return "No lyrics found"
    return ""
  }

  function currentTrack() {
    return {
      title: String(trackTitle || "").trim(),
      artist: String(trackArtist || "").trim(),
      album: String(trackAlbum || "").trim(),
      duration: Math.max(0, Number(trackDuration) || 0),
      signature: trackSignature
    }
  }

  function getCacheKey(track) {
    return JSON.stringify([track.artist, track.title, track.album, Math.floor(track.duration)])
  }

  function cacheLookup(key) {
    var storedKey = "$" + key
    if (!Object.prototype.hasOwnProperty.call(lyricsCache, storedKey)) return null
    return lyricsCache[storedKey]
  }

  function rememberCache(key, entry) {
    var storedKey = "$" + key
    var nextCache = {}
    for (var existingKey in lyricsCache) {
      if (Object.prototype.hasOwnProperty.call(lyricsCache, existingKey) && existingKey !== storedKey)
        nextCache[existingKey] = lyricsCache[existingKey]
    }

    var nextKeys = cacheKeys.slice(0)
    var existingIndex = nextKeys.indexOf(storedKey)
    if (existingIndex >= 0) nextKeys.splice(existingIndex, 1)
    nextKeys.push(storedKey)
    nextCache[storedKey] = entry

    while (nextKeys.length > 100) {
      var oldestKey = nextKeys.shift()
      delete nextCache[oldestKey]
    }
    lyricsCache = nextCache
    cacheKeys = nextKeys
  }

  function applyEntry(entry) {
    lyricLines = entry.lyricLines || []
    source = entry.source || ""
    synced = entry.synced === true
    lyricsState = entry.lyricsState || "ready"
    currentLineIndex = -1
    updateCurrentLine()
  }

  function finishWithEntry(track, entry, shouldCache) {
    if (track.signature !== trackSignature) return
    applyEntry(entry)
    if (shouldCache) rememberCache(getCacheKey(track), entry)
  }

  function plainTextToLines(plainText) {
    if (!plainText) return []
    var rawLines = String(plainText).replace(/\r/g, "").split("\n")
    var result = []
    for (var i = 0; i < rawLines.length; i++) {
      var text = rawLines[i].trim()
      if (text.length > 0) result.push({ time: -1, text: text })
    }
    return result
  }

  // Parse one or several timestamps per LRC row, discard blank lyric rows,
  // and sort the result so playback can scan from the newest row back.
  function parseLRC(lrcString) {
    if (!lrcString) return []
    var rawLines = String(lrcString).replace(/\r/g, "").split("\n")
    var result = []
    var timestampPattern = /\[(\d{2}):(\d{2})\.(\d{1,3})\]/g

    for (var i = 0; i < rawLines.length; i++) {
      var line = rawLines[i]
      var timestamps = []
      var match
      var contentStart = 0
      timestampPattern.lastIndex = 0
      while ((match = timestampPattern.exec(line)) !== null) {
        var minutes = parseInt(match[1], 10)
        var seconds = parseInt(match[2], 10)
        var fraction = match[3].length === 1 ? match[3] + "00"
          : match[3].length === 2 ? match[3] + "0" : match[3]
        var milliseconds = parseInt(fraction, 10)
        timestamps.push(minutes * 60 + seconds + milliseconds / 1000)
        contentStart = timestampPattern.lastIndex
      }

      var text = line.slice(contentStart).trim()
      if (text.length === 0) continue
      for (var j = 0; j < timestamps.length; j++)
        result.push({ time: timestamps[j], text: text })
    }

    result.sort(function(left, right) { return left.time - right.time })
    return result
  }

  function updateCurrentLine() {
    if (!synced || lyricLines.length === 0) {
      currentLineIndex = -1
      return
    }

    var position = Math.max(0, Number(playbackPosition) || 0)
    for (var i = lyricLines.length - 1; i >= 0; i--) {
      if (position >= lyricLines[i].time) {
        if (currentLineIndex !== i) currentLineIndex = i
        return
      }
    }
    if (currentLineIndex !== -1) currentLineIndex = -1
  }

  function retryDelayFromHeader(value) {
    var header = String(value || "").trim()
    var seconds = Number(header)
    if (header !== "" && isFinite(seconds)) return Math.min(2147483647, Math.max(1, Math.ceil(seconds)))

    var retryAt = Date.parse(header)
    if (isFinite(retryAt))
      return Math.min(2147483647, Math.max(1, Math.ceil((retryAt - Date.now()) / 1000)))
    return 5
  }

  function cancelPendingRequest() {
    if (pendingXhr) {
      try { pendingXhr.abort() } catch (error) { }
    }
    pendingXhr = null
  }

  function scheduleTrackFetch() {
    requestToken += 1
    debounce.stop()
    fallbackDelay.stop()
    cancelPendingRequest()
    pendingLrclibPlain = ""
    fallbackTrackKey = ""
    pendingTrack = null
    lyricLines = []
    source = ""
    synced = false
    currentLineIndex = -1

    if (!trackSignature) {
      lyricsState = "idle"
      return
    }

    lyricsState = retryAfterSeconds > 0 ? "rate-limited" : "loading"
    debounce.restart()
  }

  function fetchForCurrentTrack() {
    var track = currentTrack()
    if (!track.title || !track.artist || !track.signature) {
      lyricsState = "idle"
      return
    }

    var key = getCacheKey(track)
    var cached = cacheLookup(key)
    if (cached) {
      applyEntry(cached)
      return
    }

    if (retryAfterSeconds > 0) {
      pendingTrack = track
      lyricsState = "rate-limited"
      return
    }

    requestToken += 1
    var token = requestToken
    lyricsState = "loading"
    pendingLrclibPlain = ""
    fetchFromLRCLIB(track, token)
  }

  function encodedQuery(values) {
    var parts = []
    for (var key in values) {
      if (!Object.prototype.hasOwnProperty.call(values, key)) continue
      parts.push(encodeURIComponent(key) + "=" + encodeURIComponent(String(values[key])))
    }
    return parts.join("&")
  }

  function fetchFromLRCLIB(track, token) {
    if (token !== requestToken || track.signature !== trackSignature) return
    lyricsState = "loading"

    var query = {
      track_name: track.title,
      artist_name: track.artist
    }
    if (track.album) query.album_name = track.album
    if (track.duration >= 1 && track.duration <= 3600)
      query.duration = String(Math.floor(track.duration))

    var xhr = new XMLHttpRequest()
    var completed = false
    pendingXhr = xhr
    xhr.open("GET", "https://lrclib.net/api/get?" + encodedQuery(query), true)
    xhr.timeout = 10000
    try {
      xhr.setRequestHeader("User-Agent", "OmarchyMusicToolbar/1.0.0 (https://plugins.omarchy.org)")
    } catch (headerError) {
      try {
        xhr.setRequestHeader("X-User-Agent", "OmarchyMusicToolbar/1.0.0 (https://plugins.omarchy.org)")
        xhr.setRequestHeader("Lrclib-Client", "OmarchyMusicToolbar/1.0.0")
      } catch (fallbackHeaderError) {
        console.warn("Music Toolbar could not set an LRCLIB client identification header")
      }
    }

    function handleResponse() {
      if (completed) return
      completed = true
      if (token !== root.requestToken || track.signature !== root.trackSignature) return
      root.pendingXhr = null

      if (xhr.status === 429) {
        var retryValue = xhr.getResponseHeader("Retry-After") || ""
        root.retryAfterSeconds = root.retryDelayFromHeader(retryValue)
        root.pendingTrack = track
        root.lyricsState = "rate-limited"
        return
      }

      if (xhr.status === 200) {
        var data = null
        try { data = JSON.parse(xhr.responseText || "{}") } catch (parseError) { data = null }
        if (data && data.instrumental === true) {
          var instrumentalEntry = {
            lyricLines: [],
            source: "lrclib",
            synced: false,
            lyricsState: "instrumental"
          }
          root.finishWithEntry(track, instrumentalEntry, true)
          return
        }

        if (data && data.syncedLyrics) {
          var parsed = root.parseLRC(data.syncedLyrics)
          if (parsed.length > 0) {
            var syncedEntry = {
              lyricLines: parsed,
              source: "lrclib",
              synced: true,
              lyricsState: "ready"
            }
            root.finishWithEntry(track, syncedEntry, true)
            return
          }
        }

        root.pendingLrclibPlain = data && data.plainLyrics ? String(data.plainLyrics) : ""
        root.scheduleFallback(track, token)
        return
      }

      root.pendingLrclibPlain = ""
      root.scheduleFallback(track, token)
    }

    xhr.onreadystatechange = function() {
      if (xhr.readyState === 4) handleResponse()
    }
    xhr.onerror = handleResponse
    xhr.ontimeout = handleResponse
    xhr.send(null)
  }

  function scheduleFallback(track, token) {
    if (token !== requestToken || track.signature !== trackSignature) return
    fallbackTrackKey = getCacheKey(track)
    pendingTrack = track
    fallbackDelay.restart()
  }

  // The short pause separates LRCLIB and lyrics.ovh requests and keeps
  // requests sequential, as required by LRCLIB's client guidance.
  function fetchFromLyricsOVH(track, token) {
    if (token !== requestToken || track.signature !== trackSignature) return

    var url = "https://api.lyrics.ovh/v1/" + encodeURIComponent(track.artist) + "/" + encodeURIComponent(track.title)
    var xhr = new XMLHttpRequest()
    var completed = false
    pendingXhr = xhr
    xhr.open("GET", url, true)
    xhr.timeout = 10000

    function handleResponse() {
      if (completed) return
      completed = true
      if (token !== root.requestToken || track.signature !== root.trackSignature) return
      root.pendingXhr = null

      var lyrics = ""
      if (xhr.status === 200) {
        try {
          var data = JSON.parse(xhr.responseText || "{}")
          lyrics = data && data.lyrics ? String(data.lyrics) : ""
        } catch (parseError) {
          lyrics = ""
        }
      }

      var lines = root.plainTextToLines(lyrics)
      if (lines.length > 0) {
        var ovhEntry = {
          lyricLines: lines,
          source: "lyrics.ovh",
          synced: false,
          lyricsState: "ready"
        }
        root.finishWithEntry(track, ovhEntry, true)
        return
      }

      var lrclibPlain = root.plainTextToLines(root.pendingLrclibPlain)
      if (lrclibPlain.length > 0) {
        var plainEntry = {
          lyricLines: lrclibPlain,
          source: "lrclib",
          synced: false,
          lyricsState: "ready"
        }
        root.finishWithEntry(track, plainEntry, true)
        return
      }

      var emptyEntry = {
        lyricLines: [],
        source: "",
        synced: false,
        lyricsState: "not-found"
      }
      root.finishWithEntry(track, emptyEntry, true)
    }

    xhr.onreadystatechange = function() {
      if (xhr.readyState === 4) handleResponse()
    }
    xhr.onerror = handleResponse
    xhr.ontimeout = handleResponse
    xhr.send(null)
  }

  function retryNow() {
    if (!trackSignature) return
    retryAfterSeconds = 0
    pendingTrack = null
    fetchForCurrentTrack()
  }

  onTrackSignatureChanged: scheduleTrackFetch()
  onPlaybackPositionChanged: updateCurrentLine()
  onCurrentLineIndexChanged: updateCurrentLine()

  // Track metadata can arrive in several MPRIS updates; wait 500 ms before
  // starting one request so title, artist, album, and duration settle first.
  Timer {
    id: debounce
    interval: 500
    repeat: false
    onTriggered: root.fetchForCurrentTrack()
  }

  Timer {
    id: fallbackDelay
    interval: 300
    repeat: false
    onTriggered: {
      var track = root.pendingTrack
      if (!track || root.fallbackTrackKey !== root.getCacheKey(track)) return
      root.fetchFromLyricsOVH(track, root.requestToken)
    }
  }

  Timer {
    id: retryTimer
    interval: 1000
    repeat: true
    running: root.retryAfterSeconds > 0
    onTriggered: {
      root.retryAfterSeconds = Math.max(0, root.retryAfterSeconds - 1)
      if (root.retryAfterSeconds > 0 || debounce.running) return
      var track = root.pendingTrack
      root.pendingTrack = null
      if (track && track.signature === root.trackSignature) {
        root.requestToken += 1
        root.fetchFromLRCLIB(track, root.requestToken)
      } else if (root.trackSignature) {
        root.fetchForCurrentTrack()
      } else {
        root.lyricsState = "idle"
      }
    }
  }


  Component.onCompleted: {
    if (trackSignature) scheduleTrackFetch()
  }
}
