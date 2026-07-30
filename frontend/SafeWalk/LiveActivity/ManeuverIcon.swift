import Foundation

enum ManeuverIcon {
    static func sfSymbol(for maneuverType: String, modifier: String? = nil) -> String {
        switch maneuverType {
        case "depart":
            return "figure.walk"
        case "arrive":
            return "flag.checkered.2.crossed"
        case "turn":
            switch modifier {
            case "left", "sharp left", "slight left":
                return "arrow.turn.up.left"
            case "right", "sharp right", "slight right":
                return "arrow.turn.up.right"
            case "uturn":
                return "arrow.uturn.down"
            default:
                return "arrow.turn.up.right"
            }
        case "continue", "new name":
            return "arrow.up"
        case "merge":
            return "arrow.merge"
        case "fork":
            if modifier?.contains("left") == true {
                return "arrow.turn.up.left"
            }
            return "arrow.turn.up.right"
        case "roundabout", "rotary":
            return "arrow.triangle.2.circlepath"
        case "end of road":
            if modifier?.contains("left") == true {
                return "arrow.turn.up.left"
            }
            return "arrow.turn.up.right"
        default:
            return "arrow.up"
        }
    }
}
