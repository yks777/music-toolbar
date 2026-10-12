import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Item {
  id: root

  property var shell: null

  // Settings are reactive Service properties. UI bindings update immediately;
  // their change handlers below only queue persistence to the private config.
  property string selectedPlayerKey: ""
  property string visualizerStyle: "wave"
  property bool showText: true
  property bool showControls: false
  property bool showPlayerIcon: true
  // When true the pill visualizer is muted, the pill turns transparent, and
  // a transparent click-through overlay paints the wave across the topbar.
  // Persisted to config.json; never touches shell.json.
  property bool fullBarCava: false
  readonly property int cavaBarCount: 96
  property var cavaBars: [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  ]
  property bool cavaAvailable: true
  property bool cavaConfigReady: false
  property bool cavaProcessDesiredRunning: false
  property int cavaRestartAttempts: 0
  property bool panelVisible: false
  property bool configReady: false
  // Bounded retries for the async settings write below: a transient failure
  // must never silently drop a toggle. Reset on every successful write.
  property int configWriteRetries: 0
  property string pendingConfigText: ""
  property int playbackVersion: 0
  property int positionVersion: 0
  property int playSerial: 0
  property var playerStartedAt: ({})
  property string lastActivePlayerKey: ""

  readonly property string homeDirectory: Quickshell.env("HOME") || ""
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (homeDirectory + "/.config")
  readonly property string pluginDirectory: configHome + "/omarchy/plugins/music-toolbar"
  // Runtime preferences live OUTSIDE the plugin directory on purpose: the
  // shell watches ~/.config/omarchy/plugins with inotify and reloads the
  // whole plugin on every write there, so saving config.json inside the
  // plugin dir would blink the entire bar on each toggle. Host bar
  // placement is install/uninstall-only and is never written from this service.
  readonly property string runtimeConfigDir: configHome + "/music-toolbar"
  readonly property string configPath: runtimeConfigDir + "/config.json"
  // Previous releases stored preferences inside the watched plugin dir.
  // Kept read-only for the one-time startup migration below; never written.
  readonly property string legacyConfigPath: pluginDirectory + "/config.json"
  readonly property string configStorePath: pluginDirectory + "/config_store.py"
  readonly property string cavaSourceConfigPath: pluginDirectory + "/cava.ini"
  // Stage the bundled fixed-resolution config once at startup; settings changes
  // never rewrite it, and CAVA uses this runtime copy for the whole process.
  readonly property string cavaConfigPath: "/tmp/music-toolbar/cava.ini"

  readonly property var allPlayers: Mpris.players ? Mpris.players.values : []
  readonly property var eligiblePlayers: {
    var version = playbackVersion
    var list = allPlayers || []
    if (!selectedPlayerKey) return list
    var result = []
    for (var i = 0; i < list.length; i++) {
      if (playerKey(list[i]) === selectedPlayerKey) result.push(list[i])
    }
    return result
  }

  readonly property var playerChoices: {
    var version = playbackVersion
    var list = allPlayers || []
    var result = []
    var seen = ({})
    for (var i = 0; i < list.length; i++) {
      var player = list[i]
      if (!player) continue
      var key = playerKey(player)
      if (!key || seen["$" + key]) continue
      seen["$" + key] = true
      result.push({
        key: key,
        name: playerLabel(player),
        icon: sourceIconForKey(key),
        identity: String(player.identity || ""),
        desktopEntry: String(player.desktopEntry || ""),
        isPlaying: player.isPlaying === true
      })
    }
    return result
  }

  // A fixed source is resolved only inside its own normalized MPRIS identity.
  // Auto mode selects the most recently started player, then remembers the last
  // active source when every player is paused. No actions are routed elsewhere.
  readonly property var activePlayer: {
    var version = playbackVersion
    var order = playerStartedAt
    var list = eligiblePlayers || []
    if (list.length === 0) return null

    var newest = null
    var newestOrder = -1
    for (var i = 0; i < list.length; i++) {
      var candidate = list[i]
      if (!candidate || candidate.isPlaying !== true) continue
      var key = playerKey(candidate)
      var started = order[key]
      if (started === undefined) started = i + 1
      if (started > newestOrder) {
        newest = candidate
        newestOrder = started
      }
    }
    if (newest) return newest

    if (!selectedPlayerKey && lastActivePlayerKey) {
      for (var j = 0; j < list.length; j++) {
        if (playerKey(list[j]) === lastActivePlayerKey) return list[j]
      }
    }

    for (var k = 0; k < list.length; k++) {
      if (hasTrackMetadata(list[k])) return list[k]
    }
    return list[0]
  }

  readonly property bool isPlaying: activePlayer ? activePlayer.isPlaying === true : false
  readonly property bool isWaiting: selectedPlayerKey !== "" && !isPlaying
  readonly property string activePlayerKey: activePlayer ? playerKey(activePlayer) : selectedPlayerKey
  readonly property string selectedPlayerLabel: selectedPlayerKey ? playerLabelForKey(selectedPlayerKey) : "Auto"
  readonly property real position: {
    var version = positionVersion
    return activePlayer ? Math.max(0, Number(activePlayer.position) || 0) : 0
  }
  readonly property real duration: activePlayer && activePlayer.lengthSupported
    ? Math.max(0, Number(activePlayer.length) || 0)
    : 0
  readonly property string title: activePlayer ? cleanText(activePlayer.trackTitle || metadataValue(activePlayer, "xesam:title")) : ""
  readonly property string artist: activePlayer ? artistText(activePlayer) : ""
  readonly property string album: activePlayer ? cleanText(activePlayer.trackAlbum || metadataValue(activePlayer, "xesam:album")) : ""
  readonly property string publisher: activePlayer ? cleanText(metadataValue(activePlayer, "xesam:publisher") || metadataValue(activePlayer, "xesam:label")) : ""
  readonly property string artUrl: activePlayer ? String(activePlayer.trackArtUrl || "") : ""
  readonly property real cavaIntensity: {
    var values = cavaBars || []
    if (values.length === 0) return 0
    var total = 0
    for (var i = 0; i < values.length; i++) total += Math.max(0, Math.min(255, Number(values[i]) || 0))
    return total / (values.length * 255)
  }

  property alias lyrics: lyricPipeline

  function cleanText(value) {
    return String(value || "").replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim()
  }

  function metadataValue(player, key) {
    if (!player || !player.metadata) return ""
    var value = player.metadata[key]
    if (Array.isArray(value)) return value.join(", ")
    return value === undefined || value === null ? "" : String(value)
  }

  function artistText(player) {
    var artist = player.trackArtist || metadataValue(player, "xesam:artist")
    if (!artist && player.trackArtists) {
      artist = Array.isArray(player.trackArtists)
        ? player.trackArtists.join(", ")
        : String(player.trackArtists)
    }
    if (!artist) artist = player.trackAlbumArtist || metadataValue(player, "xesam:albumArtist")
    return cleanText(artist)
  }

  function hasTrackMetadata(player) {
    return Boolean(player && (player.trackTitle || player.trackArtist || player.trackAlbum || (player.metadata && player.metadata["xesam:title"])))
  }

  function normalizePlayerKey(value) {
    return String(value || "").toLowerCase().replace(/[^a-z0-9]/g, "")
  }

  function playerKey(player) {
    if (!player) return ""
    return normalizePlayerKey(player.desktopEntry || player.identity || "")
  }

  function playerLabel(player) {
    if (!player) return "Music player"
    var identity = cleanText(player.identity || player.desktopEntry || "")
      .replace(/\.desktop$/i, "")
      .replace(/[._-]+/g, " ")
    if (!identity) return "Music player"
    return identity
  }

  function playerLabelForKey(key) {
    var normalized = normalizePlayerKey(key)
    if (normalized.indexOf("spotify") !== -1) return "Spotify"
    if (normalized.indexOf("youtube") !== -1) return "YouTube"
    if (normalized.indexOf("firefox") !== -1) return "Firefox"
    if (normalized.indexOf("zen") !== -1) return "Zen"
    if (normalized.indexOf("chrom") !== -1) return "Chromium"
    if (normalized.indexOf("brave") !== -1) return "Brave"
    if (normalized.indexOf("edge") !== -1) return "Edge"
    if (normalized.indexOf("mpv") !== -1) return "MPV"
    if (normalized.indexOf("vlc") !== -1) return "VLC"
    if (normalized.indexOf("celluloid") !== -1) return "Celluloid"
    for (var i = 0; i < playerChoices.length; i++) {
      if (playerChoices[i].key === normalized) return playerChoices[i].name
    }
    return normalized ? normalized.charAt(0).toUpperCase() + normalized.slice(1) : "Music player"
  }

  function sourceIconForKey(key) {
    var normalized = normalizePlayerKey(key)
    if (normalized.indexOf("spotify") !== -1) return "󰓇"
    if (normalized.indexOf("firefox") !== -1 || normalized.indexOf("zen") !== -1) return "󰈹"
    if (normalized.indexOf("chrom") !== -1 || normalized.indexOf("brave") !== -1 || normalized.indexOf("edge") !== -1) return "󰊯"
    if (normalized.indexOf("mpv") !== -1 || normalized.indexOf("vlc") !== -1 || normalized.indexOf("celluloid") !== -1) return "󰐹"
    if (normalized.indexOf("youtube") !== -1) return "󰗃"
    return "󰝚"
  }

  function setPanelVisible(value) {
    var next = value === true
    if (panelVisible === next) return "ok"
    panelVisible = next
    if (panelVisible && activePlayer) {
      try { activePlayer.positionChanged() } catch (error) { }
      positionVersion += 1
    }
    return "ok"
  }

  function setPlayer(key) {
    var normalized = String(key || "").trim().toLowerCase()
    if (normalized === "auto") normalized = ""
    normalized = normalizePlayerKey(normalized)
    if (selectedPlayerKey === normalized) return true
    selectedPlayerKey = normalized
    return true
  }

  function setVisualizerStyle(style) {
    var normalized = String(style || "").toLowerCase()
    if (normalized !== "wave" && normalized !== "bars" && normalized !== "dots") return false
    if (visualizerStyle !== normalized) visualizerStyle = normalized
    return true
  }

  function setShowText(value) {
    if (typeof value !== "boolean") return false
    showText = value
    return true
  }

  function setShowControls(value) {
    if (typeof value !== "boolean") return false
    showControls = value
    return true
  }

  function setShowPlayerIcon(value) {
    if (typeof value !== "boolean") return false
    showPlayerIcon = value
    return true
  }

  function setFullBarCava(value) {
    if (typeof value !== "boolean") return false
    fullBarCava = value
    return true
  }

  function markPlayerStarted(player) {
    var key = playerKey(player)
    if (!key) return
    var next = ({})
    for (var oldKey in playerStartedAt) {
      if (Object.prototype.hasOwnProperty.call(playerStartedAt, oldKey)) next[oldKey] = playerStartedAt[oldKey]
    }
    playSerial += 1
    next[key] = playSerial
    playerStartedAt = next
    lastActivePlayerKey = key
    playbackVersion += 1
  }

  function markPlayerStopped(player) {
    var key = playerKey(player)
    if (!key) return
    var next = ({})
    for (var oldKey in playerStartedAt) {
      if (Object.prototype.hasOwnProperty.call(playerStartedAt, oldKey) && oldKey !== key)
        next[oldKey] = playerStartedAt[oldKey]
    }
    playerStartedAt = next
    playbackVersion += 1
  }

  function playerPlaybackChanged(player) {
    if (player && player.isPlaying === true) markPlayerStarted(player)
    else markPlayerStopped(player)
  }

  function playerForKey(key) {
    var normalized = normalizePlayerKey(key)
    var list = allPlayers || []
    for (var i = 0; i < list.length; i++) {
      if (playerKey(list[i]) === normalized) return list[i]
    }
    return null
  }

  function runOnActivePlayer(methodName) {
    var player = activePlayer
    if (!player || typeof player[methodName] !== "function") return false
    player[methodName]()
    return true
  }

  function playPause() {
    var player = activePlayer
    if (!player) return false
    if (player.canTogglePlaying && typeof player.togglePlaying === "function") {
      player.togglePlaying()
      return true
    }
    if (player.isPlaying && player.canPause && typeof player.pause === "function") {
      player.pause()
      return true
    }
    if (!player.isPlaying && player.canPlay && typeof player.play === "function") {
      player.play()
      return true
    }
    return false
  }

  function play() {
    var player = activePlayer
    if (!player) return false
    if (player.canPlay && typeof player.play === "function") {
      player.play()
      return true
    }
    return false
  }

  function pause() {
    var player = activePlayer
    if (!player) return false
    if (player.canPause && typeof player.pause === "function") {
      player.pause()
      return true
    }
    return false
  }

  function next() {
    var player = activePlayer
    if (!player || !player.canGoNext || typeof player.next !== "function") return false
    player.next()
    return true
  }

  function previous() {
    var player = activePlayer
    if (!player || !player.canGoPrevious || typeof player.previous !== "function") return false
    player.previous()
    return true
  }

  function seek(seconds) {
    var player = activePlayer
    var target = Number(seconds)
    if (!player || !player.canSeek || !player.positionSupported || !isFinite(target)) return false
    player.position = Math.max(0, Math.min(duration, target))
    return true
  }

  function playersJson() {
    var choices = playerChoices
    var result = []
    for (var i = 0; i < choices.length; i++) {
      result.push({
        key: choices[i].key,
        identity: choices[i].identity,
        desktopEntry: choices[i].desktopEntry,
        isPlaying: choices[i].isPlaying
      })
    }
    return JSON.stringify(result)
  }

  function statusJson() {
    return JSON.stringify({
      selectedPlayerKey: selectedPlayerKey,
      activePlayerKey: activePlayerKey,
      isPlaying: isPlaying,
      isWaiting: isWaiting,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      position: position,
      visualizerStyle: visualizerStyle,
      showText: showText,
      showControls: showControls,
      showPlayerIcon: showPlayerIcon,
      fullBarCava: fullBarCava,
      cavaAvailable: cavaAvailable
    })
  }

  function emptyCavaBars() {
    var values = []
    for (var i = 0; i < cavaBarCount; i++) values.push(0)
    return values
  }

  // CAVA always emits 96 samples. Keep that process resolution stable; each
  // CavaVisualizer slices the array to its own width without restarting the
  // process during font, theme, or widget-size changes.
  function consumeCavaLine(line) {
    var cleaned = String(line || "").trim().replace(/;$/, "")
    if (!cleaned) return
    var parts = cleaned.split(";")
    if (parts.length < cavaBarCount) return
    var next = []
    for (var i = 0; i < cavaBarCount; i++) {
      var value = parseInt(parts[i], 10)
      if (!isFinite(value)) value = 0
      next.push(Math.max(0, Math.min(255, value)))
    }
    cavaBars = next
    cavaRestartAttempts = 0
  }

  function syncCavaProcess() {
    if (!cavaAvailable || !cavaConfigReady) return
    // CAVA is one long-lived system-audio process. Source, style, and display
    // preference changes only update QML properties; they never stop or relaunch it.
    cavaProcessDesiredRunning = true
  }

  function loadConfiguration() {
    configGuard.command = [
      "sh", "-c",
      "command -v python3 >/dev/null 2>&1 || exit 127; exec python3 \"$@\"",
      "music-toolbar-config-read",
      configStorePath,
      "--read",
      configPath
    ]
    configGuard.running = true
  }

  function applyConfigurationText(raw) {
    var text = String(raw || "").trim()
    if (text) {
      try {
        var data = JSON.parse(text)
        if (data && typeof data === "object") {
          if (data.visualizerStyle === "wave" || data.visualizerStyle === "bars" || data.visualizerStyle === "dots")
            visualizerStyle = data.visualizerStyle
          selectedPlayerKey = normalizePlayerKey(data.selectedPlayerKey || "")
          if (typeof data.showText === "boolean") showText = data.showText
          if (typeof data.showControls === "boolean") showControls = data.showControls
          if (typeof data.showPlayerIcon === "boolean") showPlayerIcon = data.showPlayerIcon
          if (typeof data.fullBarCava === "boolean") fullBarCava = data.fullBarCava
        }
      } catch (parseError) {
        console.warn("Music Toolbar settings are invalid; using the default player and bar display options")
      }
    }
    configReady = true
  }

  function saveConfig() {
    if (!configReady) return
    pendingConfigText = JSON.stringify({
      selectedPlayerKey: selectedPlayerKey,
      visualizerStyle: visualizerStyle,
      showText: showText,
      showControls: showControls,
      showPlayerIcon: showPlayerIcon,
      fullBarCava: fullBarCava
    }, null, 2) + "\n"

    if (configWriteProcess.running) configWriteProcess.running = false
    configWriteProcess.command = [
      "sh", "-c",
      "command -v python3 >/dev/null 2>&1 || exit 127; exec python3 \"$@\"",
      "music-toolbar-config-write",
      configStorePath,
      "--write",
      configPath,
      pendingConfigText
    ]
    configWriteProcess.running = true
  }

  // These handlers persist the new values only; dependent widgets and panels
  // update through bindings without a manual refresh or host-layout write.
  onSelectedPlayerKeyChanged: if (configReady) saveTimer.restart()
  onVisualizerStyleChanged: if (configReady) saveTimer.restart()
  onShowTextChanged: if (configReady) saveTimer.restart()
  onShowControlsChanged: if (configReady) saveTimer.restart()
  onShowPlayerIconChanged: if (configReady) saveTimer.restart()
  onFullBarCavaChanged: if (configReady) saveTimer.restart()

  Instantiator {
    model: Mpris.players

    delegate: Connections {
      required property var modelData
      target: modelData

      function onIsPlayingChanged() { root.playerPlaybackChanged(modelData) }
      function onMetadataChanged() { root.playbackVersion += 1 }
      function onTrackTitleChanged() { root.playbackVersion += 1 }
      function onTrackArtistChanged() { root.playbackVersion += 1 }
      function onTrackArtistsChanged() { root.playbackVersion += 1 }
      function onTrackAlbumArtistChanged() { root.playbackVersion += 1 }
      function onTrackAlbumChanged() { root.playbackVersion += 1 }
      function onTrackArtUrlChanged() { root.playbackVersion += 1 }
      function onLengthChanged() { root.playbackVersion += 1 }
      function onIdentityChanged() { root.playbackVersion += 1 }
      function onDesktopEntryChanged() { root.playbackVersion += 1 }
      function onPositionChanged() { root.positionVersion += 1 }
    }

    onObjectAdded: function(index, object) {
      root.playbackVersion += 1
      var player = object && object.modelData ? object.modelData : null
      if (player && player.isPlaying) root.markPlayerStarted(player)
    }
    onObjectRemoved: function(index, object) {
      root.playbackVersion += 1
      var player = object && object.modelData ? object.modelData : null
      if (player && root.playerKey(player) === root.lastActivePlayerKey)
        root.lastActivePlayerKey = ""
    }
  }

  LyricsFetcher {
    id: lyricPipeline
    trackTitle: root.title
    trackArtist: root.artist
    trackAlbum: root.album
    trackDuration: root.duration
    playbackPosition: root.position
  }

  // One startup read hydrates these reactive properties from the runtime
  // config.json (outside the watched plugin dir). The Python helper bounds
  // and validates reads and atomically replaces that file on save; it never
  // touches host bar placement.
  Process {
    id: configMigrateProcess
    command: [
      "sh", "-c",
      "command -v python3 >/dev/null 2>&1 || exit 127; exec python3 \"$@\"",
      "music-toolbar-config-migrate",
      root.configStorePath,
      "--migrate",
      root.legacyConfigPath,
      root.configPath
    ]
    onExited: function(exitCode) {
      if (exitCode !== 0 && exitCode !== 127)
        console.warn("Music Toolbar could not migrate legacy settings; defaults will be used")
      root.loadConfiguration()
    }
  }

  Process {
    id: configGuard
    stdout: StdioCollector { id: configReadOutput }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.applyConfigurationText(configReadOutput.text)
      } else {
        console.warn(exitCode === 127
          ? "Python 3 was not found; Music Toolbar is using in-memory settings only"
          : "Music Toolbar rejected an unsafe or invalid settings file and kept the defaults")
        root.configReady = true
      }
    }
  }

  Process {
    id: configWriteProcess
    stdout: StdioCollector { }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.configWriteRetries = 0
        return
      }
      if (root.configWriteRetries < 2) {
        root.configWriteRetries += 1
        saveTimer.restart()
        return
      }
      root.configWriteRetries = 0
      console.warn(exitCode === 127
        ? "Python 3 was not found; Music Toolbar could not save settings"
        : "Music Toolbar could not save settings; the previous file was left unchanged")
    }
  }

  Process {
    id: cavaConfigProcess
    command: [
      "sh", "-c",
      "command -v python3 >/dev/null 2>&1 || exit 127; exec python3 \"$@\"",
      "music-toolbar-cava-config",
      root.configStorePath,
      "--prepare-cava",
      root.cavaSourceConfigPath,
      root.cavaConfigPath
    ]
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.cavaConfigReady = true
        root.syncCavaProcess()
      } else {
        root.cavaAvailable = false
        root.cavaProcessDesiredRunning = false
        root.cavaBars = root.emptyCavaBars()
        console.warn(exitCode === 127
          ? "Python 3 was not found; CAVA could not prepare its runtime configuration"
          : "CAVA configuration could not be prepared; Music Toolbar will continue without a visualizer")
      }
    }
  }

  Process {
    id: cavaProcess
    command: [
      "sh", "-c",
      "command -v cava >/dev/null 2>&1 || exit 127; exec cava -p \"$1\"",
      "music-toolbar-cava",
      root.cavaConfigPath
    ]
    running: root.cavaProcessDesiredRunning && root.cavaConfigReady
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) { root.consumeCavaLine(line) }
    }
    onExited: function(exitCode) {
      root.cavaProcessDesiredRunning = false
      if (exitCode === 127) {
        root.cavaAvailable = false
        root.cavaBars = root.emptyCavaBars()
        console.info("CAVA was not found; Music Toolbar will continue without a visualizer")
      } else if (root.cavaAvailable) {
        root.cavaRestartAttempts += 1
        if (root.cavaRestartAttempts >= 3) {
          root.cavaAvailable = false
          root.cavaBars = root.emptyCavaBars()
          console.warn("CAVA stopped repeatedly; Music Toolbar will continue without a visualizer")
        } else {
          cavaRestartTimer.restart()
        }
      } else {
        root.cavaRestartAttempts = 0
      }
    }
  }

  Timer {
    id: cavaRestartTimer
    interval: 5000
    repeat: false
    onTriggered: {
      if (root.cavaAvailable && root.cavaConfigReady)
        root.cavaProcessDesiredRunning = true
    }
  }

  // Quickshell MPRIS position is read-on-demand rather than continuously
  // reactive. Refresh it every 250 ms only while the popup is open and playing
  // so the seek bar and synced lyric highlight stay current without idle polling.
  Timer {
    id: positionTimer
    interval: 250
    running: root.panelVisible && root.isPlaying
    repeat: true
    onTriggered: {
      var player = root.activePlayer
      if (player) {
        try { player.positionChanged() } catch (error) { }
      }
      root.positionVersion += 1
    }
  }

  Timer {
    id: saveTimer
    interval: 250
    repeat: false
    onTriggered: root.saveConfig()
  }

  IpcHandler {
    target: "music-toolbar"

    function setPlayer(key: string): string {
      return root.setPlayer(key) ? "ok" : "invalid player"
    }

    function getPlayers(): string {
      return root.playersJson()
    }

    function setVisualizerStyle(style: string): string {
      return root.setVisualizerStyle(style) ? "ok" : "invalid style"
    }

    function setFullBarCava(enabled: bool): string {
      return root.setFullBarCava(enabled) ? "ok" : "invalid value"
    }

    function getFullBarCava(): string {
      return root.fullBarCava ? "true" : "false"
    }

    function playPause(): string { return root.playPause() ? "ok" : "unhandled" }
    function play(): string { return root.play() ? "ok" : "unhandled" }
    function pause(): string { return root.pause() ? "ok" : "unhandled" }
    function next(): string { return root.next() ? "ok" : "unhandled" }
    function previous(): string { return root.previous() ? "ok" : "unhandled" }

    function seek(position: real): string {
      return root.seek(position) ? "ok" : "unhandled"
    }

    function status(): string {
      return root.statusJson()
    }
  }

  Component.onCompleted: {
    for (var i = 0; i < allPlayers.length; i++) {
      if (allPlayers[i] && allPlayers[i].isPlaying) markPlayerStarted(allPlayers[i])
    }
    cavaConfigProcess.running = true
    // Migrate legacy settings out of the watched plugin dir first; the
    // migrate process always chains into the config read on exit.
    configMigrateProcess.running = true
  }
}
