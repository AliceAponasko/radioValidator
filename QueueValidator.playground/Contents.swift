import Foundation

class Track {

    // MARK: Properties

    var id: Int // id of the track in the DB

    var title: String

    var artist: String
    var album: String

    var queueId: Int // unique ID of this instance of this track in the list
    var position: Int = 0 // position of this track in the list (to sync with the server)

    var length: Int // total play time of the track in milliseconds

    var isValidPosition: Bool = true

    // MARK: Init

    init(id: Int,
         title: String,
         artist: String,
         album: String,
         queueId: Int,
         length: Int) {

        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.queueId = queueId
        self.length = length
    }
}

class QueueValidator {

    // MARK: Debugging

    func debugDescription(_ trackList: [Track]) {
        var validTracks = ""
        _ = trackList.compactMap {
            validTracks += "\($0.isValidPosition ? "✓" : "x") ID: \($0.queueId) (\($0.title) / \($0.album) by \($0.artist))\n"
        }

        print("Track list:\n\(validTracks)")
    }

    // MARK: Track position

    func isValidToAppend(track: Track, to trackList: [Track]) -> Bool {
        var newList = trackList
        newList.append(track)

        newList = validate(trackList: newList)

        if let lastTrack = newList.last {
            return lastTrack.isValidPosition
        }

        return true
    }

    // MARK: Validator

    func validate(trackList originalList: [Track]) -> [Track] {

        _ = originalList.compactMap { $0.isValidPosition = true }

        var i = 0
        while i < originalList.count {
            let remainingSlice = Array(originalList[i..<originalList.count])
            let validatedList = findViolations(in: threeHourValidWindow(from: remainingSlice))

            // Sometimes we need to step back to double check if we invalidated a track
            var shouldStepBack = false

            // If track was invalidated
            for validatedTrack in validatedList where !validatedTrack.isValidPosition {

                // Go through the original list and find the same track
                _ = originalList.compactMap {
                    if $0.queueId == validatedTrack.queueId {
                        // Mark the track in the original list as invalid
                        $0.isValidPosition = false

                        // Reduce i by 1, if possible
                        i = max(0, i - 1)

                        // Do not increment i at the end of this cycle
                        shouldStepBack = true
                    }
                }
            }

            // If we did not take a step back, go to the next track
            if !shouldStepBack {
                i += 1
            }
        }

        return originalList
    }

    // MARK: Helpers

    func threeHourValidWindow(from tracks: [Track]) -> [Track] {

        let threeHoursInMilliseconds = 60 * 60 * 3 * 1000

        // Inclusive, so if the track starts within three hour window, but ends after, we will take it
        var tracksInThreeHours: [Track] = []
        var tracksLength = 0

        for track in tracks {
            // Skip if invalid
            if !track.isValidPosition {
                continue
            }

            if tracksLength < threeHoursInMilliseconds {
                tracksInThreeHours.append(track)
                tracksLength += track.length
            } else {
                break
            }
        }

        return tracksInThreeHours
    }

    // MARK: Violations

    private func findViolations(in trackList: [Track]) -> [Track] {

        guard !trackList.isEmpty else { return trackList }

        // First, we're going to check for duplicate tracks. Those are automatically a violation.
        var result = findDuplicateTracks(in: trackList)
        // If we have more than *4* of the same artist in our window, it's a violation.
        result = findArtistOccurrence(in: result)
        // If we have more than *3* of the same album in our window, it's a violation.
        result = findAlbumOccurrence(in: result)
        // If we have more than *3* of the same artist consecutively in our window, it's a violation.
        result = findArtistConsecutiveOccurrences(in: result)
        // If we have more than *2* of the same album consecutively in our window, it's a violation.
        result = findAlbumConsecutiveOccurrences(in: result)

        return result
    }

    func findDuplicateTracks(in trackList: [Track]) -> [Track] {

        var uniqueTracks: [Track] = []

        for track in trackList {
            guard uniqueTracks.contains(where: { $0.id == track.id }) else {
                // First occurence
                uniqueTracks.append(track)
                continue
            }

            // Mark as invalid
            track.isValidPosition = false
        }

        return trackList
    }

    func findArtistOccurrence(in trackList: [Track]) -> [Track] {

        // If we have more than *4* of the same artist in our window, it's a violation.
        for i in 0..<trackList.count {
            let track = trackList[i]

            // Skip if invalid
            if !track.isValidPosition {
                continue
            }

            var occurrence = 0

            // Subarray from start to current track position
            let slice = Array(trackList[0...i])
            for previousTrack in slice where previousTrack.artist == track.artist {
                occurrence += 1
            }

            if occurrence > 4 {
                // Mark as invalid
                track.isValidPosition = false
            }
        }

        return trackList
    }

    func findAlbumOccurrence(in trackList: [Track]) -> [Track] {

        // If we have more than *3* of the same album by the same artist in our window, it's a violation.
        for i in 0..<trackList.count {
            let track = trackList[i]

            // Skip if invalid
            if !track.isValidPosition {
                continue
            }

            var occurrence = 0

            // Subarray from start to current track position
            let slice = Array(trackList[0...i])
            for previousTrack in slice
                where previousTrack.album == track.album && previousTrack.artist == track.artist {
                    occurrence += 1
            }

            if occurrence > 3 {
                // Mark as invalid
                track.isValidPosition = false
            }
        }

        return trackList
    }

    func findArtistConsecutiveOccurrences(in trackList: [Track]) -> [Track] {

        // If we have more than *3* of the same artist consecutively in our window, it's a violation.
        if trackList.count < 3 {
            return trackList
        }

        for i in 3..<trackList.count {
            let track = trackList[i]

            // Skip if invalid
            if !track.isValidPosition {
                continue
            }

            var concurrentOccurrence = 0

            // Check subarray from (current track position - 1) down to start
            for y in (0...(i - 1)).reversed() {
                let previousTrack = trackList[y]

                if !previousTrack.isValidPosition {
                    continue
                }

                if previousTrack.artist == track.artist {
                    concurrentOccurrence += 1
                } else {
                    break
                }

                if concurrentOccurrence >= 3 {
                    track.isValidPosition = false
                    break
                }
            }
        }

        return trackList
    }

    func findAlbumConsecutiveOccurrences(in trackList: [Track]) -> [Track] {

        // If we have more than *2* of the same album consecutively in our window, it's a violation.
        if trackList.count < 2 {
            return trackList
        }

        for i in 2..<trackList.count {
            let track = trackList[i]

            // Skip if invalid
            if !track.isValidPosition {
                continue
            }

            var concurrentOccurrence = 0

            // Check subarray from (current track position - 1) down to start
            for y in (0...(i - 1)).reversed() {
                let previousTrack = trackList[y]

                if !previousTrack.isValidPosition {
                    continue
                }

                if previousTrack.album == track.album && previousTrack.artist == track.artist {
                    concurrentOccurrence += 1
                } else {
                    break
                }

                if concurrentOccurrence >= 2 {
                    track.isValidPosition = false
                    break
                }
            }
        }

        return trackList
    }
}

// MARK: - Examples

let validator = QueueValidator()

// MARK: 3 hour window (10_800_000 ms)

//let longTrack0 = Track(id: 0, title: "Name 0", artist: "Artist 0", album: "Album 0", queueId: 0, length: 3_000_000)
//let longTrack1 = Track(id: 1, title: "Name 1", artist: "Artist 1", album: "Album 1", queueId: 1, length: 3_000_000)
//let longTrack2 = Track(id: 2, title: "Name 2", artist: "Artist 2", album: "Album 2", queueId: 2, length: 3_000_000)
//let longTrack3 = Track(id: 3, title: "Name 3", artist: "Artist 3", album: "Album 3", queueId: 3, length: 1_799_999)
//let longTrack4 = Track(id: 4, title: "Name 4", artist: "Artist 4", album: "Album 4", queueId: 4, length: 1_000_000)
//let longTrack5 = Track(id: 5, title: "Name 5", artist: "Artist 5", album: "Album 5", queueId: 5, length: 1_000_000)
//
//let longTrackList = [ longTrack0, longTrack1, longTrack2, longTrack3, longTrack4, longTrack5 ]
//
//let validList = validator.threeHourValidWindow(from: longTrackList)
//validator.debugDescription(validList)

// MARK: Setup

let track0 = Track(id: 1, title: "Name 1", artist: "Artist 1", album: "Album 1", queueId: 0, length: 60 * 60 * 1000)
let track1 = Track(id: 1, title: "Name 1", artist: "Artist 1", album: "Album 1", queueId: 1, length: 60 * 60 * 1000)
let track2 = Track(id: 1, title: "Name 1", artist: "Artist 1", album: "Album 1", queueId: 2, length: 60 * 60 * 1000)
let track3 = Track(id: 2, title: "Name 2", artist: "Artist 2", album: "Album 1", queueId: 3, length: 60 * 60 * 1000)
let track4 = Track(id: 1, title: "Name 1", artist: "Artist 1", album: "Album 1", queueId: 4, length: 60 * 60 * 1000)
let track5 = Track(id: 1, title: "Name 1", artist: "Artist 1", album: "Album 1", queueId: 5, length: 60 * 60 * 1000)
let track6 = Track(id: 4, title: "Name 4", artist: "Artist 4", album: "Album 4", queueId: 6, length: 60 * 60 * 1000)
let track7 = Track(id: 5, title: "Name 5", artist: "Artist 4", album: "Album 4", queueId: 7, length: 60 * 60 * 1000)
let track8 = Track(id: 6, title: "Name 6", artist: "Artist 4", album: "Album 4", queueId: 8, length: 60 * 60 * 1000)
let track9 = Track(id: 7, title: "Name 7", artist: "Artist 4", album: "Album 4", queueId: 9, length: 60 * 60 * 1000)

var trackList = [ track0, track1, track2, track3, track4, track5, track6, track7, track8, track9 ]

// MARK: Duplicated track

//validator.findDuplicateTracks(in: trackList)
//validator.debugDescription(trackList)

// MARK: Duplicated artist

//validator.findArtistOccurrence(in: trackList)
//validator.debugDescription(trackList)

// MARK: Duplicate album

//validator.findAlbumOccurrence(in: trackList)
//validator.debugDescription(trackList)

// MARK: Consecutive artist

//validator.findArtistConsecutiveOccurrences(in: trackList)
//validator.debugDescription(trackList)

// MARK: Consecutive album

//validator.findAlbumConsecutiveOccurrences(in: trackList)
//validator.debugDescription(trackList)

// MARK: Full validation

validator.validate(trackList: trackList)
validator.debugDescription(trackList)

// MARK: Search extension

let validTrackToAppend = Track(id: 10, title: "Name 10", artist: "Artist 5", album: "Album 1", queueId: 10, length: 300)
let invalidTrackToAppend = Track(id: 7, title: "Name 7", artist: "Artist 4", album: "Album 4", queueId: 10, length: 300)

print(validator.isValidToAppend(track: validTrackToAppend, to: trackList))
print(validator.isValidToAppend(track: invalidTrackToAppend, to: trackList))







