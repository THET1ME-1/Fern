// Взято из пакета receive_sharing_intent 1.8.1 (Kasem Mohamed, Apache-2.0)
// и вставлено в расширение как есть.
//
// ПОЧЕМУ КОПИЯ, А НЕ `import receive_sharing_intent`: модуль пакета тянет
// заголовок плагина с `#import <Flutter/Flutter.h>`, а расширение Flutter не
// линкует — сборка падает на «'Flutter/Flutter.h' file not found». Сам этот
// код от Flutter не зависит: обмен с приложением идёт через общий контейнер
// App Group и URL-схему.
//
// При обновлении пакета сверять файл с оригиналом:
// ~/.pub-cache/hosted/pub.dev/receive_sharing_intent-*/ios/Classes/

import Foundation
import UniformTypeIdentifiers

// Ключи общего контейнера. Их же читает плагин на стороне приложения:
// разойтись значениям нельзя, иначе расширение сложит материал туда,
// куда Fern не заглядывает.
public let kSchemePrefix = "ShareMedia"
public let kUserDefaultsKey = "ShareKey"
public let kUserDefaultsMessageKey = "ShareMessageKey"
public let kAppGroupIdKey = "AppGroupId"

public class SharedMediaFile: Codable {
    var path: String
    var mimeType: String?
    var thumbnail: String? // video thumbnail
    var duration: Double? // video duration in milliseconds
    var message: String? // post message
    var type: SharedMediaType
    
    
    public init(
        path: String,
        mimeType: String? = nil,
        thumbnail: String? = nil,
        duration: Double? = nil,
        message: String?=nil,
        type: SharedMediaType) {
            self.path = path
            self.mimeType = mimeType
            self.thumbnail = thumbnail
            self.duration = duration
            self.message = message
            self.type = type
        }
}

public enum SharedMediaType: String, Codable, CaseIterable {
    case image
    case video
    case text
//     case audio
    case file
    case url

    public var toUTTypeIdentifier: String {
        if #available(iOS 14.0, *) {
            switch self {
            case .image:
                return UTType.image.identifier
            case .video:
                return UTType.movie.identifier
            case .text:
                return UTType.text.identifier
    //         case .audio:
    //             return UTType.audio.identifier
            case .file:
                return UTType.fileURL.identifier
            case .url:
                return UTType.url.identifier
            }
        }
        switch self {
        case .image:
            return "public.image"
        case .video:
            return "public.movie"
        case .text:
            return "public.text"
//         case .audio:
//             return "public.audio"
        case .file:
            return "public.file-url"
        case .url:
            return "public.url"
        }
    }
}
