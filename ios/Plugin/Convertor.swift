import MediaPlayer
import MusicKit

@available(iOS 16.0, *)
class Convertor {
    static let baseUrl = "https://api.music.apple.com"
    static let sSize = 300
    static let mSize = 400
    static let lSize = 600

    static func getDataRequestJSON(_ url: String, params: [String: String] = [:]) async throws -> [String: Any] {
        var urlComponents = URLComponents(string: "\(baseUrl)\(url)")
        urlComponents?.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }

        guard let url = urlComponents?.url else {
            return [:]
        }
        let data = try await MusicDataRequest(urlRequest: URLRequest(url: url)).response().data
        if data.count > 0 {
            return try JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
        } else {
            return [:]
        }
    }

    static func toPlayParameters(_ optPlayParameters: PlayParameters?) -> [String: Any]? {
        do {
            guard let playParameters = optPlayParameters else {
                return nil
            }
            let data = try JSONEncoder().encode(playParameters)
            return try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        } catch {
            return nil
        }
    }

    static func formatISOString(_ optDate: Date?) -> String? {
        guard let date = optDate else {
            return nil
        }
        return ISO8601DateFormatter().string(from: date)
    }

    static func toMediaItem(
        item: MusicKit.MusicPlayer.Queue.Entry.Item?,
        artworkUrl optArtworkUrl: String? = nil,
        size optSize: Int? = nil
    ) async -> [String: Any?]? {
        switch item {
        case let .song(song):
            return await toMediaItem(item: song, artworkUrl: optArtworkUrl, size: optSize)
        default: return nil
        }
    }

    static func toMediaItem(
        item optSong: Song?,
        artworkUrl optArtworkUrl: String? = nil,
        size optSize: Int? = nil,
        isPlayable: Bool = true
    ) async -> [String: Any?]? {
        guard let song = optSong else {
            return nil
        }

        var artworkUrl: String? = optArtworkUrl
        if let size = optSize {
            artworkUrl = await toBase64Image(song.artwork, size)
        }

        let duration = Double(song.duration ?? 0) * 1000
        var playbackDuration = 0.0
        if isPlayable {
            playbackDuration = duration
        } else {
            playbackDuration = duration > 30000 ? 30000 : duration
        }

        return [
            "albumInfo": song.albumTitle,
            "albumName": song.albumTitle,
            "artistName": song.artistName,
            "artwork": ["url": artworkUrl],
            "artworkURL": artworkUrl,
            "attributes": nil,
            "contentRating": song.contentRating == .clean ? "clean" : "explicit",
            "discNumber": song.discNumber,
            "id": song.id.rawValue,
            "info": song.title,
            "isExplicitItem": song.contentRating == .explicit,
            "isPlayable": true,
            "isPreparedToPlay": nil,
            "isrc": song.isrc,
            "playbackDuration": playbackDuration,
            "playlistArtworkURL": artworkUrl,
            "playlistName": song.albumTitle,
            "previewURL": song.previewAssets?.first?.url?.absoluteString,
            "releaseDate": formatISOString(song.releaseDate),
            "title": song.title,
            "trackNumber": song.trackNumber,
            "type": "songs",
        ]
    }

    static func toLibraryArtists(
        items: MusicItemCollection<Artist>,
        hasNext: Bool,
        size: Int? = sSize
    ) async -> [String: Any] {
        var data: [[String: Any]?] = []
        for item in items {
            data.append(await toLibraryArtist(item: item))
        }
        return [
            "data": data.compactMap { $0 },
            "next": hasNext ? "hasNext" : nil,
        ]
    }

    static func toLibraryArtist(
        item optItem: Artist?,
        size optSize: Int? = nil
    ) async -> [String: Any]? {
        guard let item = optItem else {
            return nil
        }

        var artworkUrl: String? = nil
        if let size = optSize {
            artworkUrl = await toBase64Image(item.artwork, size)
        }

        return [
            "id": item.id.rawValue,
            "type": "library-artists",
            "attributes": [
                "artwork": ["url": artworkUrl],
                "name": item.name,
            ],
        ]
    }

    static func toLibraryAlbums(
        items: MusicItemCollection<Album>,
        hasNext: Bool,
        size: Int? = sSize
    ) async -> [String: Any] {
        var data: [[String: Any]?] = []
        for item in items {
            data.append(await toLibraryAlbum(item: item, size: size))
        }
        return [
            "data": data.compactMap { $0 },
            "next": hasNext ? "hasNext" : nil,
        ]
    }

    static func toLibraryAlbum(
        item optItem: Album?,
        size optSize: Int? = nil
    ) async -> [String: Any]? {
        guard let item = optItem else {
            return nil
        }

        var artworkUrl: String? = nil
        if let size = optSize {
            artworkUrl = await toBase64Image(item.artwork, size)
        }

        return [
            "id": item.id.rawValue,
            "type": "library-albums",
            "attributes": [
                "artistName": item.artistName,
                "artwork": ["url": artworkUrl],
                "contentRating": item.contentRating == .clean ? "clean" : "explicit",
                "dateAdded": formatISOString(item.libraryAddedDate),
                "genreNames": item.genreNames,
                "name": item.title,
                "playParams": toPlayParameters(item.playParameters),
                "releaseDate": formatISOString(item.releaseDate),
                "trackCount": item.trackCount,
            ],
        ]
    }

    static func toLibrarySongs(
        items: MusicItemCollection<Song>,
        hasNext: Bool,
        size: Int? = sSize
    ) async -> [String: Any] {
        var data: [[String: Any]?] = []
        for item in items {
            data.append(await toLibrarySong(item: item, size: size))
        }
        return [
            "data": data.compactMap { $0 },
            "next": hasNext ? "hasNext" : nil,
        ]
    }

    static func toLibrarySong(
        item optItem: Song?,
        size optSize: Int? = nil
    ) async -> [String: Any]? {
        guard let song = optItem else {
            return nil
        }
        return await toLibraryItem(item: song, size: optSize)
    }
    static func toLibraryItem(
            item: Song,
            size: Int? = nil
        ) async -> [String: Any]? {
            await buildDictionary(
                id: item.id.rawValue,
                type: "library-songs",
                artwork: item.artwork,
                size: size,
                albumTitle: item.albumTitle,
                artistName: item.artistName,
                duration: item.duration,
                title: item.title,
                playParams: item.playParameters,
                trackNumber: item.trackNumber,
                extras: [
                    "discNumber": item.discNumber,
                    "genreNames": item.genreNames,
                    "hasLyrics": item.hasLyrics,
                    "releaseDate": formatISOString(item.releaseDate)
                ]
            )
        }
        
        static func toLibraryItem(
            item: MusicVideo,
            size: Int? = nil
        ) async -> [String: Any]? {
            await buildDictionary(
                id: item.id.rawValue,
                type: "library-music-videos",
                artwork: item.artwork,
                size: size,
                albumTitle: item.albumTitle,
                artistName: item.artistName,
                duration: item.duration,
                title: item.title,
                playParams: item.playParameters,
                trackNumber: item.trackNumber,
                extras: [
                    "genreNames": item.genreNames,
                    "releaseDate": formatISOString(item.releaseDate)
                ]
            )
        }
        
        static func toLibraryItem(
            item: Track,
            size: Int? = nil
        ) async -> [String: Any]? {
            switch item {
            case .song(let song):
                return await toLibraryItem(item: song, size: size)
            case .musicVideo(let mv):
                return await toLibraryItem(item: mv, size: size)
            @unknown default:
                return nil
            }
        }
        
        // MARK: - Shared helper
        
        private static func buildDictionary(
            id: String,
            type: String,
            artwork: Artwork?,
            size: Int?,
            albumTitle: String?,
            artistName: String,
            duration: TimeInterval?,
            title: String,
            playParams: PlayParameters?,
            trackNumber: Int?,
            extras: [String: Any?]
        ) async -> [String: Any]? {
            
            var artworkUrl: String? = nil
            if let size = size {
                artworkUrl = await toBase64Image(artwork, size)
            }
            
            var attributes: [String: Any?] = [
                "albumName": albumTitle,
                "artistName": artistName,
                "artwork": ["url": artworkUrl],
                "durationInMillis": Double(duration ?? 0) * 1000,
                "name": title,
                "playParams": toPlayParameters(playParams),
                "trackNumber": trackNumber,
            ]
            
            for (k, v) in extras {
                attributes[k] = v
            }
            
            return [
                "id": id,
                "type": type,
                "attributes": attributes.compactMapValues { $0 }
            ]
        }

    static func toLibraryPlaylists(
        items: MusicItemCollection<Playlist>,
        hasNext: Bool,
        size: Int? = sSize
    ) async -> [String: Any] {
        var data: [[String: Any]?] = []
        for item in items {
            data.append(await toLibraryPlaylist(item: item, size: size))
        }
        return [
            "data": data.compactMap { $0 },
            "next": hasNext ? "hasNext" : nil,
        ]
    }

    static func toLibraryPlaylist(
        item optItem: Playlist?,
        size optSize: Int? = nil
    ) async -> [String: Any]? {
        guard let item = optItem else {
            return nil
        }

        var artworkUrl: String? = nil
        if let size = optSize {
            artworkUrl = await toBase64Image(item.artwork, size)
        }

        // Convert tracks in parallel
        let tracksArray: [[String: Any]] = await withTaskGroup(of: [String: Any]?.self) { group in
            // Safely unwrap tracks, fallback to empty
            for track in item.tracks ?? [] {
                group.addTask {
                    await toLibraryItem(item: track, size: optSize)
                }
            }

            var results: [[String: Any]] = []
            for await result in group {
                if let dict = result {
                    results.append(dict)
                }
            }
            return results
        }

        return [
            "id": item.id.rawValue,
            "type": "library-playlists",
            "attributes": [
                "artwork": ["url": artworkUrl],
                "name": item.name,
                "description": item.description,
                "playParams": toPlayParameters(item.playParameters),
                "dateAdded": formatISOString(item.libraryAddedDate),
                "tracks": tracksArray
            ],
        ]
    }

    static func toBase64Image(_ artwork: MPMediaItemArtwork?, _ size: Int) -> String? {
        if let artworkItem = artwork {
            do {
                let image = artworkItem.image(at: CGSize(width: size, height: size))
                if let data = image?.jpegData(compressionQuality: 0.1) {
                    return data.base64EncodedString()
                }
            } catch {
                return nil
            }
        }
        return nil
    }

    static func toBase64Image(_ artwork: Artwork?, _ size: Int) async -> String? {
        do {
            let image = await toImage(artwork, size)
            if let imageData = image?.jpegData(compressionQuality: 0.1) {
                return imageData.base64EncodedString()
            }
        } catch {
            return nil
        }
        return nil
    }

    static func toMPMediaItemArtwork(_ artwork: Artwork?, _ size: Int) async -> MPMediaItemArtwork?
    {
        let image = await toImage(artwork, size)
        if let imageData = image {
            return MPMediaItemArtwork(
                boundsSize: CGSize(width: size, height: size),
                requestHandler: { _ in
                    return imageData
                })
        }
        return nil
    }

    static func toImage(_ artwork: Artwork?, _ size: Int) async -> UIImage? {
        do {
            guard let url = artwork?.url(width: size, height: size) else {
                return nil
            }

            let imageRequest = URLRequest(url: url)
            let (data, _) = try await URLSession.shared.data(for: imageRequest)
            guard let image = UIImage(data: data) else {
                return nil
            }
            return image
        } catch {
            return nil
        }
    }
}
