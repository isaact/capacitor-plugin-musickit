import Capacitor
import Foundation
import MediaPlayer
import MusicKit

typealias NotifyListeners = ((String, [String: Any]?) -> Void)

enum CapacitorMusicKitError: Error {
    case missingParameter(name: String)
}

@available(iOS 16.0, *)
@objc public class CapacitorMusicKit: NSObject {
    let musicKitPlayer = MusicKitPlayer()
    let previewPlayer = PreviewPlayer()
    let storefront = "jp"
    var isPreview = false
    let player = MPMusicPlayerController.applicationMusicPlayer
    var notifyListeners: NotifyListeners?

    func load() {
        musicKitPlayer.notifyListeners = notifyListeners
        previewPlayer.notifyListeners = notifyListeners

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.togglePlayPauseCommand.addTarget {
            (commandEvent) -> MPRemoteCommandHandlerStatus in
            Task {
                if self.isPreview {
                    try await self.previewPlayer.playOrPause()
                }
            }
            return MPRemoteCommandHandlerStatus.success
        }
        commandCenter.nextTrackCommand.addTarget { (commandEvent) -> MPRemoteCommandHandlerStatus in
            Task {
                if self.isPreview {
                    try await self.previewPlayer.nextPlay()
                }
            }
            return MPRemoteCommandHandlerStatus.success
        }
        commandCenter.previousTrackCommand.addTarget {
            (commandEvent) -> MPRemoteCommandHandlerStatus in
            Task {
                if self.isPreview {
                    try await self.previewPlayer.previousPlay()
                }
            }
            return MPRemoteCommandHandlerStatus.success
        }
        commandCenter.changePlaybackPositionCommand.addTarget {
            (commandEvent) -> MPRemoteCommandHandlerStatus in
            Task {
                if self.isPreview, let event = commandEvent as? MPChangePlaybackPositionCommandEvent
                {
                    self.previewPlayer.seekToTime(event.positionTime)
                }
            }
            return MPRemoteCommandHandlerStatus.success
        }
        changeCommandCenterStatus(false)
    }

    func changeCommandCenterStatus(_ status: Bool) {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.togglePlayPauseCommand.isEnabled = status
        commandCenter.nextTrackCommand.isEnabled = status
        commandCenter.previousTrackCommand.isEnabled = status
        commandCenter.changePlaybackPositionCommand.isEnabled = status
    }

    var prevPlaybackState: MPMusicPlaybackState = .stopped
    var started = false
    @objc public func playbackStateDidChange() -> String? {
        var result: String? = nil
        
        let currentDuration =
            MPMusicPlayerController.applicationMusicPlayer.nowPlayingItem?.playbackDuration ?? 0.0

        // 曲が終わる3秒前に一時停止をした場合は曲が再生終了したとみなす
        if started && player.playbackState == .paused && prevPlaybackState == .playing
            && player.currentPlaybackTime + 3 >= currentDuration
        {
            result = "completed"
            prevPlaybackState = .stopped
            started = false
        } else if player.playbackState == .playing && prevPlaybackState != .playing {
            result = "playing"
            started = true
        } else if player.playbackState == .paused && prevPlaybackState != .paused {
            result = "paused"
        } else if player.playbackState == .stopped && prevPlaybackState != .stopped {
            result = "stopped"
//      以下は プレビュー時に completed した後に paused してしまうためコメントアウト
//        } else if player.playbackState == .interrupted && prevPlaybackState != .interrupted {
//            result = "paused"
        }

        prevPlaybackState = player.playbackState

        return result
    }

    @objc public func nowPlayingItemDidChange() async -> [String: Any] {
        return ["item": await currentSong() as Any, "index": player.indexOfNowPlayingItem]
    }

    @objc public func authorizationStatusDidChange() -> String? {
        var result: String? = nil
        let status = MusicAuthorization.currentStatus

        if status == .notDetermined {
            result = "notDetermined"
        } else if status == .denied {
            result = "denied"
        } else if status == .restricted {
            result = "restricted"
        } else if status == .authorized {
            result = "authorized"
        }

        return result
    }

    @objc func isAuthorized() -> Bool {
        var result = false
        if MusicAuthorization.currentStatus == .authorized {
            result = true
        }
        return result
    }

    @objc func hasMusicSubscription() async -> Bool {
        var result = false
        do {
            let subscription = try await MusicSubscription.current
            result = subscription.canPlayCatalogContent
        } catch {

        }
        return result
    }

    @objc func authorize() async -> Bool {
        var result = false
        let status = await MusicAuthorization.request()
        if status == .authorized {
            result = true
        } else {
            guard let settingsURL = URL(string: UIApplication.openSettingsURLString)
            else {
                return result
            }
            await UIApplication.shared.open(settingsURL, options: [:], completionHandler: nil)
        }
        return result
    }

    @objc func unauthorize() async {
        // 設定アプリに遷移するだけなので authorizationStatusDidChange は発火させない
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        await UIApplication.shared.open(settingsURL, options: [:], completionHandler: nil)
    }

    func buildParams(_ optIds: [String]?, _ optLimit: Int?, _ optOffset: Int?) -> [String: String] {
        var params: [String: String] = [:]

        if let ids = optIds {
            params["ids"] = ids.joined(separator: "%2C")
        } else {
            if let limit = optLimit {
                params["limit"] = String(limit)
            }
            if let offset = optOffset {
                params["offset"] = String(offset)
            }
        }
        return params
    }

    func getParams(from call: CAPPluginCall) -> [String: String] {
        let paramsObject = call.getObject("params") ?? [:]
        var params: [String: String] = [:]
        for (key, value) in paramsObject {
            params[key] = String(describing: value)
        }
        return params
    }
    
    @objc func api(_ call: CAPPluginCall) async throws -> [String: Any] {
        let url = call.getString("url")!
        let params = getParams(from: call)
        return try await Convertor.getDataRequestJSON(url, params: params)
    }

    @objc func getLibraryArtists(_ call: CAPPluginCall) async throws -> [String: Any] {
        let limit = call.getInt("limit") ?? 1
        let offset = call.getInt("offset") ?? 0
        let ids = call.getArray("ids", String.self)

        let optAlbumId = call.getString("albumId")
        let optSongId = call.getString("songId")
        let optMusicVideoId = call.getString("musicVideoId")

        var url = "/v1/me/library/artists"
        let params = buildParams(ids, limit, offset)

        if let albumId = optAlbumId {
            url = "/v1/me/library/albums/\(albumId)/artists"
        } else if let songId = optSongId {
            url = "/v1/me/library/songs/\(songId)/artists"
        } else if let musicVideoId = optMusicVideoId {
            url = "/v1/me/library/music-videos/\(musicVideoId)/artists"
        }

        return try await Convertor.getDataRequestJSON(url, params: params)
    }

    @objc func getLibraryAlbums(_ call: CAPPluginCall) async throws -> [String: Any] {
        let limit = call.getInt("limit") ?? 1
        let offset = call.getInt("offset") ?? 0
        let ids = call.getArray("ids", String.self)

        let optCatalogId = call.getString("catalogId")
        let optArtistId = call.getString("artistId")
        let optSongId = call.getString("songId")
        let optMusicVideoId = call.getString("musicVideoId")

        var url = "/v1/me/library/albums"
        let params = buildParams(ids, limit, offset)

        if let catalogId = optCatalogId {
            url = "/v1/catalog/\(storefront)/albums/\(catalogId)/library"
        } else if let artistId = optArtistId {
            url = "/v1/me/library/artists/\(artistId)/albums"
        } else if let songId = optSongId {
            url = "/v1/me/library/songs/\(songId)/albums"
        } else if let musicVideoId = optMusicVideoId {
            url = "/v1/me/library/music-videos/\(musicVideoId)/albums"
        }

        return try await Convertor.getDataRequestJSON(url, params: params)
    }
    
    @objc func getLibrarySongs(_ call: CAPPluginCall) async throws -> [String: Any] {
        let limit = call.getInt("limit") ?? 1
        let offset = call.getInt("offset") ?? 0
        let ids = call.getArray("ids", String.self)
        
        let optAlbumId = call.getString("albumId")
        let optPlaylistId = call.getString("playlistId")
        
        // Handle album tracks request
        if let albumId = optAlbumId {
            var albumRequest = MusicLibraryRequest<Song>()
            albumRequest.filter(matching: \.id, equalTo: MusicItemID(albumId))
            let albumResponse = try await albumRequest.response()
            
            guard let album = albumResponse.items.first else {
                return ["data": []]
            }
            
            // Get tracks from the album
            let tracksResponse = try await album.tracks
            
            // Apply limit and offset if needed
            let allTracks = tracksResponse.items
            let startIndex = min(offset, allTracks.count)
            let endIndex = min(startIndex + limit, allTracks.count)
            let limitedTracks = Array(allTracks[startIndex..<endIndex])
            
            return await Convertor.toLibrarySongs(items: limitedTracks, hasNext: endIndex < allTracks.count)
        }
        
        // Handle playlist tracks request
        if let playlistId = optPlaylistId {
            var playlistRequest = MusicLibraryRequest<Song>()
            playlistRequest.filter(matching: \.id, equalTo: MusicItemID(playlistId))
            let playlistResponse = try await playlistRequest.response()
            
            guard let playlist = playlistResponse.items.first else {
                return ["data": []]
            }
            
            // Get tracks from the playlist
            let tracksResponse = try await playlist.tracks
            
            // Apply limit and offset if needed
            let allTracks = tracksResponse.items
            let startIndex = min(offset, allTracks.count)
            let endIndex = min(startIndex + limit, allTracks.count)
            let limitedTracks = Array(allTracks[startIndex..<endIndex])
            
            return await Convertor.toLibrarySongs(items: limitedTracks, hasNext: endIndex < allTracks.count)
        }
        
        // Handle general library songs request
        var request = MusicLibraryRequest<Song>()
        
        // Apply limit only if no specific IDs are requested
        if ids == nil {
            request.limit = limit
        }
        
        // Apply ID filtering if provided
        if let songIds = ids {
            request = MusicLibraryRequest<Song>()
            request.filter(matching: \.id, memberOf: songIds.map { MusicItemID($0) })
        }
        
        let response = try await request.response()
        
        // Apply offset manually since MusicLibraryRequest doesn't directly support it
        let allItems = response.items
        let startIndex = ids == nil ? min(offset, allItems.count) : 0
        let limitedItems = ids == nil ? Array(allItems[startIndex..<min(startIndex + limit, allItems.count)]) : allItems
        let hasNext = ids == nil ? startIndex + limit < allItems.count : false
        
        return await Convertor.toLibrarySongs(items: limitedItems, hasNext: hasNext)
    }
    
    @objc func getLibraryPlaylists(_ call: CAPPluginCall) async throws -> [String: Any] {
        let limit = call.getInt("limit") ?? 1
        let offset = call.getInt("offset") ?? 0
        let ids = call.getArray("ids", String.self)

//        let optCatalogId = call.getString("catalogId")

        // Use MusicLibraryRequest<Playlist> for library playlists
        var request = MusicLibraryRequest<Playlist>()
//        if(optCatalogId != nil) {
//            request.filter(matching: \., contains: optCatalogId!)
//        }
        
        // Apply limit and offset if no specific IDs are requested
        if ids == nil {
            request.limit = limit
        }
        
        // Apply offset only if no specific IDs are requested
        if ids == nil && offset > 0 {
            // MusicLibraryRequest doesn't directly support offset, so we'll need to handle it differently
            // For now, we'll just fetch with limit and let the caller handle pagination
        }
        
        // Apply ID filtering if provided
        if let playlistIds = ids {
            request = MusicLibraryRequest<Playlist>()
            request.filter(matching: \.id, memberOf: playlistIds.map { MusicItemID($0) })
        }
        
        let response = try await request.response()
        return await Convertor.toLibraryPlaylists(items: response.items, hasNext: false)
    }

    @objc func getLibraryPlaylist(_ call: CAPPluginCall) async throws -> [String: Any] {
        guard let id = call.getString("id") else {
            throw CapacitorMusicKitError.missingParameter(name: "id")
        }
        let playlistID = MusicItemID(id)

        // Use MusicLibraryRequest<Playlist> to fetch a specific playlist
        var request = MusicLibraryRequest<Playlist>()
        request.filter(matching: \.id, equalTo: playlistID)
        let response = try await request.response()
        
        // Convert single playlist to the expected format
        guard let playlist = response.items.first else {
            return ["data": []]
        }
        
        let playlistDict = await Convertor.toLibraryPlaylist(item: playlist)
        return ["data": playlistDict == nil ? [] : [playlistDict]]
    }

    func selectSongs(_ ids: [String]) async throws -> [Song] {
        var requestLibrary = MusicLibraryRequest<Song>()
        requestLibrary.filter(matching: \.id, memberOf: ids.map { MusicItemID($0) })
        let responseLibrary = try await requestLibrary.response()

        let libraryIds = responseLibrary.items.map { $0.id.rawValue }
        let catalogIds = ids.filter { !libraryIds.contains($0) }

        var responseCatalog: MusicCatalogResourceResponse<Song>? = nil
        if catalogIds.count > 0 {
            let requestCatalog = MusicCatalogResourceRequest<Song>(
                matching: \.id, memberOf: catalogIds.map { MusicItemID($0) })
            responseCatalog = try await requestCatalog.response()
        }

        // sort songs
        var songs: [Song] = []
        ids.forEach { id in
            let libraryItem = responseLibrary.items.first(where: { $0.id.rawValue == id })
            if let track = libraryItem {
                songs.append(track)
            }

            if let catalog = responseCatalog {
                if let track = catalog.items.first(where: { $0.id.rawValue == id }) {
                    songs.append(track)
                }
            }
        }
        return songs
    }

    func queueSongs() async -> [[String: Any?]] {
        if isPreview {
            return await previewPlayer.queueSongs()
        } else {
            return await musicKitPlayer.queueSongs()
        }
    }

    func currentSong() async -> [String: Any?]? {
        if isPreview {
            return await previewPlayer.currentSong()
        } else {
            return await musicKitPlayer.currentSong()
        }
    }

    @objc func getCurrentIndex() -> Int {
        if isPreview {
            return previewPlayer.getCurrentIndex()
        } else {
            return musicKitPlayer.getCurrentIndex()
        }
    }
    
    @objc func getCurrentPlaybackTime() -> Double {
        if isPreview {
            return previewPlayer.getCurrentPlaybackTime()
        } else {
            return musicKitPlayer.getCurrentPlaybackTime()
        }
    }
    
    @objc func getCurrentPlaybackDuration() -> Double {
        if isPreview {
            return previewPlayer.getCurrentPlaybackDuration()
        } else {
            return musicKitPlayer.getCurrentPlaybackDuration()
        }
    }

    @objc func getRepeatMode() -> String {
        if isPreview {
            return previewPlayer.getRepeatMode()
        } else {
            return musicKitPlayer.getRepeatMode()
        }
    }

    @objc func setRepeatMode(_ call: CAPPluginCall) {
        musicKitPlayer.setRepeatMode(call)
    }

    @objc func getShuffleMode() -> String {
        if isPreview {
            return previewPlayer.getShuffleMode()
        } else {
            return musicKitPlayer.getShuffleMode()
        }
    }

    @objc func setShuffleMode(_ call: CAPPluginCall) {
        musicKitPlayer.setShuffleMode(call)
    }

    @objc func setQueue(_ call: CAPPluginCall) async throws {
        let ids: [String] = call.getArray("ids", String.self) ?? []
        isPreview = false
        let songs = try await selectSongs(ids)
        do {
            try await musicKitPlayer.setQueue(songs)
            changeCommandCenterStatus(false)
        } catch {
            isPreview = true
            try await previewPlayer.setQueue(songs)
            changeCommandCenterStatus(true)
        }
    }

    @objc func play(_ call: CAPPluginCall) async throws {
        let index = call.getInt("index")
        if isPreview {
            musicKitPlayer.pause()
            try await previewPlayer.play(index)
        } else {
            previewPlayer.pause()
            try await musicKitPlayer.play(index)
        }
    }

    @objc func pause() {
        if isPreview {
            previewPlayer.pause()
        } else {
            musicKitPlayer.pause()
        }
    }

    @objc func stop() {
        if isPreview {
            previewPlayer.stop()
        } else {
            musicKitPlayer.stop()
        }
    }

    @objc func nextPlay() async throws {
        if isPreview {
            try await previewPlayer.nextPlay()
        } else {
            try await musicKitPlayer.nextPlay()
        }
    }

    @objc func previousPlay() async throws {
        if isPreview {
            try await previewPlayer.previousPlay()
        } else {
            try await musicKitPlayer.previousPlay()
        }
    }

    @objc func seekToTime(_ call: CAPPluginCall) {
        let playbackTime = call.getDouble("time") ?? 0.0
        if isPreview {
            previewPlayer.seekToTime(playbackTime)
        } else {
            musicKitPlayer.seekToTime(playbackTime)
        }
    }
}
