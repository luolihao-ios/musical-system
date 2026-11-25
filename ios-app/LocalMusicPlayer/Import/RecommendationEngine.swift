import Foundation

enum RecallChannel: String, Sendable, Equatable {
    case coreArtist
    case searchOrTag
    case timeContext
    case dailyFresh
    case exploration
}

struct RecallCandidate: Sendable, Equatable {
    let track: CatalogTrack
    let channel: RecallChannel
}

struct DiscoveryRecallPlan: Sendable, Equatable {
    let coreQueries: [String]
    let tagQuery: String?
    let contextQuery: String
    let freshQueries: [String]
    let itunesQuery: String
}

enum RecommendationEngine {
    private static let chineseMorningPool = ["清晨轻音乐", "元气华语", "惬意民谣", "早安流行"]
    private static let chineseAfternoonPool = ["咖啡馆钢琴", "慵懒R&B", "午后轻音乐", "华语流行"]
    private static let chineseEveningPool = ["城市民谣", "微醺爵士", "温柔华语", "夜晚流行"]
    private static let chineseNightPool = ["深夜治愈", "晚安钢琴曲", "安静民谣", "舒缓纯音乐"]

    private static let chineseFreshPool = [
        "华语热歌", "新歌速递", "独立民谣", "都市R&B",
        "华语流行", "吉他弹唱", "国风精选", "经典粤语",
        "电子纯音乐", "爵士钢琴", "怀旧金曲", "治愈钢琴曲"
    ]

    private static let chineseITunesPool = [
        "周杰伦", "陈奕迅", "林俊杰", "陶喆", "孙燕姿",
        "邓紫棋", "毛不易", "王菲", "五月天", "方大同"
    ]

    private static let globalMorningPool = ["morning acoustic", "indie folk", "uplifting pop"]
    private static let globalAfternoonPool = ["lo-fi chill", "coffeehouse piano", "ambient focus"]
    private static let globalEveningPool = ["indie chill", "soulful r&b", "jazz lounge"]
    private static let globalNightPool = ["late night piano", "ambient sleep", "soft acoustic"]

    private static let globalFreshPool = [
        "acoustic", "piano", "electronic", "jazz",
        "indie folk", "ambient", "classical", "chillout"
    ]

    static func recallPlan(for market: DiscoveryMarket, taste: TasteSnapshot) -> DiscoveryRecallPlan {
        let isChineseMarket = ["CN", "TW", "HK", "MO"].contains(market.region.uppercased())
        let offset = max(0, taste.seedDayOffset)

        let sortedArtists = taste.artistAffinities
            .filter { $0.value > 1.2 }
            .sorted {
                $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
            }
            .prefix(6)
            .map { taste.artistDisplayNames[$0.key] ?? $0.key }

        var coreQueries: [String] = []
        if let first = sortedArtists.first {
            coreQueries.append(first)
            if sortedArtists.count >= 2 {
                let tail = Array(sortedArtists.dropFirst())
                let picked = tail[offset % tail.count]
                if !coreQueries.contains(where: { $0.caseInsensitiveCompare(picked) == .orderedSame }) {
                    coreQueries.append(picked)
                }
            }
        }

        let sortedTags = taste.tagAffinities
            .filter { $0.value > 1.5 }
            .sorted {
                $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
            }
            .map { taste.tagDisplayNames[$0.key] ?? $0.key }

        let combinedTagPool = (taste.recentSearchTerms + sortedTags).filter { term in
            let key = TasteProfileStore.normalizedKey(term)
            return (taste.tagAffinities[key] ?? 0) > -1.5
                && !coreQueries.contains(where: { $0.caseInsensitiveCompare(term) == .orderedSame })
        }
        var uniqueTags: [String] = []
        for term in combinedTagPool where !uniqueTags.contains(where: { $0.caseInsensitiveCompare(term) == .orderedSame }) {
            uniqueTags.append(term)
        }
        let tagQuery: String? = uniqueTags.isEmpty ? nil : uniqueTags[offset % uniqueTags.count]

        let contextPool: [String]
        let hour = taste.currentHour
        if isChineseMarket {
            switch hour {
            case 6..<11: contextPool = chineseMorningPool
            case 11..<18: contextPool = chineseAfternoonPool
            case 18..<22: contextPool = chineseEveningPool
            default: contextPool = chineseNightPool
            }
        } else {
            switch hour {
            case 6..<11: contextPool = globalMorningPool
            case 11..<18: contextPool = globalAfternoonPool
            case 18..<22: contextPool = globalEveningPool
            default: contextPool = globalNightPool
            }
        }
        let contextQuery = contextPool[offset % contextPool.count]

        let rawFresh = isChineseMarket ? chineseFreshPool : globalFreshPool
        let filteredFresh = rawFresh.filter { term in
            let key = TasteProfileStore.normalizedKey(term)
            return (taste.tagAffinities[key] ?? 0) >= -1.5
        }
        let effectiveFreshPool = filteredFresh.isEmpty ? rawFresh : filteredFresh
        let usedQueries = coreQueries + (tagQuery.map { [$0] } ?? []) + [contextQuery]
        var freshQueries: [String] = []
        for step in 0..<effectiveFreshPool.count where freshQueries.count < 2 {
            let candidate = effectiveFreshPool[(offset + step * 3) % effectiveFreshPool.count]
            let alreadyUsed = usedQueries.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
                || freshQueries.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
            if !alreadyUsed {
                freshQueries.append(candidate)
            }
        }
        if freshQueries.isEmpty {
            freshQueries = Array(effectiveFreshPool.prefix(2))
        }

        let itunesQuery: String
        if let firstArtist = sortedArtists.first {
            itunesQuery = firstArtist
        } else if isChineseMarket {
            itunesQuery = chineseITunesPool[offset % chineseITunesPool.count]
        } else {
            itunesQuery = market.openQuery
        }

        return DiscoveryRecallPlan(
            coreQueries: coreQueries,
            tagQuery: tagQuery,
            contextQuery: contextQuery,
            freshQueries: freshQueries,
            itunesQuery: itunesQuery
        )
    }

    static func continuationQueries(for track: TrackSnapshot, taste: TasteSnapshot?) -> [String] {
        let trimmedArtist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let artistKey = TasteProfileStore.normalizedKey(trimmedArtist)
        let isGeneric = TasteProfileStore.isGenericArtist(trimmedArtist)
        let artistAffinity = taste?.artistAffinities[artistKey] ?? 0
        let hasCJK = (track.title + trimmedArtist).unicodeScalars.contains {
            $0.value >= 0x4E00 && $0.value <= 0x9FFF
        }

        let scenePool = hasCJK
            ? ["华语热歌", "治愈流行", "独立民谣", "都市R&B", "晚安钢琴曲", "经典粤语"]
            : ["acoustic", "indie folk", "chill electronic", "jazz piano"]
        let seed = max(0, (taste?.seedDayOffset ?? 1) + abs(stableHash(track.title)))

        let positiveArtists = (taste?.artistAffinities ?? [:])
            .filter { $0.value > 1.2 && $0.key != artistKey }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .compactMap { taste?.artistDisplayNames[$0.key] ?? $0.key }

        let positiveTag = (taste?.tagAffinities ?? [:])
            .filter { $0.value > 1.5 && $0.key != artistKey }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .compactMap { taste?.tagDisplayNames[$0.key] ?? $0.key }
            .first

        var queries: [String] = []
        if isGeneric || artistAffinity < -1.5 {
            let pivotPrimary = positiveArtists.first ?? scenePool[seed % scenePool.count]
            queries.append(pivotPrimary)
            let pivotSecondary = positiveTag ?? positiveArtists.dropFirst().first ?? scenePool[(seed + 2) % scenePool.count]
            if !queries.contains(where: { $0.caseInsensitiveCompare(pivotSecondary) == .orderedSame }) {
                queries.append(pivotSecondary)
            }
        } else {
            queries.append(trimmedArtist)
            let companion = positiveArtists.first ?? positiveTag ?? scenePool[seed % scenePool.count]
            if !queries.contains(where: { $0.caseInsensitiveCompare(companion) == .orderedSame }) {
                queries.append(companion)
            }
        }
        return queries
    }

    static func score(
        _ candidate: RecallCandidate,
        taste: TasteSnapshot,
        now: Date = .now
    ) -> Double? {
        guard let preview = candidate.track.previewURL,
              preview.scheme?.lowercased() == "https",
              let host = preview.host, !host.isEmpty, !host.lowercased().hasSuffix(".invalid") else {
            return nil
        }

        let cid = TasteProfileStore.canonicalTrackID(candidate.track.id)
        if taste.dislikedTrackIDs.contains(cid) { return nil }

        let feedback = taste.trackFeedback[cid]
        if let feedback {
            if feedback.isDisliked { return nil }
            if feedback.quickSkipCount >= 2 {
                let isRecent = feedback.lastPlayedAt.map { now.timeIntervalSince($0) < 30 * 86_400 } ?? true
                if isRecent { return nil }
            }
        }

        var value: Double = 0

        let artistKey = TasteProfileStore.normalizedKey(candidate.track.artist)
        if let aff = taste.artistAffinities[artistKey] {
            value += min(16, max(-12, aff * 1.4))
        }

        let titleKey = candidate.track.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let positiveTagMatched = taste.tagAffinities.contains { key, tagScore in
            tagScore > 0 && !key.isEmpty && (titleKey.contains(key) || artistKey.contains(key))
        }
        if positiveTagMatched {
            value += 3.5
        } else if taste.tagAffinities.contains(where: { key, tagScore in
            tagScore < -1.5 && !key.isEmpty && (titleKey.contains(key) || artistKey.contains(key))
        }) {
            value -= 3.0
        }

        switch candidate.channel {
        case .coreArtist: value += 3.0
        case .searchOrTag: value += 2.5
        case .timeContext: value += 1.8
        case .dailyFresh: value += 1.2
        case .exploration: value += 1.0
        }

        value += !candidate.track.isShortPreview ? 3.5 : -2.5
        value += candidate.track.artworkURL != nil ? 1.5 : -1.0

        if let playedAt = feedback?.lastPlayedAt {
            let elapsed = max(0, now.timeIntervalSince(playedAt))
            if elapsed < 12 * 3_600 {
                value -= 16.0
            } else if elapsed < 48 * 3_600 {
                value -= 7.0
            } else if elapsed < 7 * 86_400 {
                value -= 2.0
            }
        }

        if let shownAt = feedback?.lastShownAt {
            let notPlayedSince = feedback?.lastPlayedAt.map { shownAt > $0 } ?? true
            if notPlayedSince {
                let elapsed = max(0, now.timeIntervalSince(shownAt))
                if elapsed < 12 * 3_600 {
                    value -= 4.5
                } else if elapsed < 24 * 3_600 {
                    value -= 2.0
                }
            }
        }

        if feedback?.quickSkipCount == 1 {
            value -= 6.5
        }

        let hashBucket = abs(stableHash("\(cid)#\(taste.seedDayOffset)")) % 1000
        let jitter = (Double(hashBucket) / 999.0) * 2.2
        return value + jitter
    }

    static func rankAndDiversify(
        _ candidates: [RecallCandidate],
        taste: TasteSnapshot,
        limit: Int = 12,
        now: Date = .now
    ) -> [CatalogTrack] {
        guard limit > 0 else { return [] }

        struct ScoredEntry {
            let candidate: RecallCandidate
            let canonicalID: String
            let artistKey: String
            let score: Double
        }

        var bestByID: [String: ScoredEntry] = [:]
        for candidate in candidates {
            guard let entryScore = score(candidate, taste: taste, now: now) else { continue }
            let cid = TasteProfileStore.canonicalTrackID(candidate.track.id)
            if let existing = bestByID[cid], existing.score >= entryScore {
                continue
            }
            bestByID[cid] = ScoredEntry(
                candidate: candidate,
                canonicalID: cid,
                artistKey: TasteProfileStore.normalizedKey(candidate.track.artist),
                score: entryScore
            )
        }

        var remaining = bestByID.values.sorted {
            if $0.score == $1.score {
                return $0.canonicalID < $1.canonicalID
            }
            return $0.score > $1.score
        }
        guard !remaining.isEmpty else { return [] }

        var selected: [ScoredEntry] = []
        let heroIndex = remaining.firstIndex {
            !$0.candidate.track.isShortPreview && $0.candidate.track.artworkURL != nil
        } ?? 0
        selected.append(remaining.remove(at: heroIndex))

        let explorationChannels: Set<RecallChannel> = [.timeContext, .dailyFresh, .exploration]

        while selected.count < limit && !remaining.isEmpty {
            let recentArtists = selected.suffix(3).map(\.artistKey)
            var artistCounts: [String: Int] = [:]
            for item in selected {
                artistCounts[item.artistKey, default: 0] += 1
            }

            let explorationCount = selected.filter { explorationChannels.contains($0.candidate.channel) }.count
            let needsExplorationQuota = limit >= 6 && selected.count >= limit - 2 && explorationCount < 2

            func passesSpacing(_ entry: ScoredEntry) -> Bool {
                if TasteProfileStore.isGenericArtist(entry.candidate.track.artist) {
                    return true
                }
                return artistCounts[entry.artistKey, default: 0] < 2
                    && !recentArtists.contains(entry.artistKey)
            }

            func passesFallback(_ entry: ScoredEntry) -> Bool {
                if TasteProfileStore.isGenericArtist(entry.candidate.track.artist) {
                    return true
                }
                return artistCounts[entry.artistKey, default: 0] < 2
                    && selected.last?.artistKey != entry.artistKey
            }

            let pickedIndex: Int
            if needsExplorationQuota,
               let quotaStrict = remaining.firstIndex(where: {
                   explorationChannels.contains($0.candidate.channel) && passesSpacing($0)
               }) {
                pickedIndex = quotaStrict
            } else if needsExplorationQuota,
                      let quotaFallback = remaining.firstIndex(where: {
                          explorationChannels.contains($0.candidate.channel) && passesFallback($0)
                      }) {
                pickedIndex = quotaFallback
            } else if let strict = remaining.firstIndex(where: passesSpacing) {
                pickedIndex = strict
            } else if let relaxed = remaining.firstIndex(where: passesFallback) {
                pickedIndex = relaxed
            } else {
                break
            }

            selected.append(remaining.remove(at: pickedIndex))
        }

        return selected.map(\.candidate.track)
    }

    private static func stableHash(_ text: String) -> Int {
        var hash: UInt64 = 14695981039346656037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return Int(truncatingIfNeeded: hash & 0x7FFF_FFFF)
    }
}
