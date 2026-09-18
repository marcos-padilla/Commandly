import CoreGraphics
import Foundation

/// The tabs of the menu bar panel's navigation strip, in display order.
///
/// Raw values are persisted as the remembered tab, so renaming a case would send a returning
/// user back to the first tab; keep them stable.
enum StatusPanelSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case keepAwake
    case volumeMixer
    case system
    case network
    case disk
    case power
    case fans
    case utilities
    case controls
    case quickToggles

    var id: String { rawValue }

    /// Title shown above the section body and in the tab's tooltip.
    var title: String {
        switch self {
        case .keepAwake: return "Keep Awake"
        case .volumeMixer: return "Volume Mixer"
        case .system: return "System"
        case .network: return "Network"
        case .disk: return "Disk"
        case .power: return "Power"
        case .fans: return "Fans"
        case .utilities: return "Utilities"
        case .controls: return "Controls"
        case .quickToggles: return "Quick Toggles"
        }
    }

    /// SF Symbol drawn in the navigation strip.
    var symbolName: String {
        switch self {
        case .keepAwake: return "moon.zzz.fill"
        case .volumeMixer: return "slider.horizontal.3"
        case .system: return "cpu"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .power: return "bolt.fill"
        case .fans: return "fanblades.fill"
        case .utilities: return "wrench.and.screwdriver.fill"
        case .controls: return "switch.2"
        case .quickToggles: return "togglepower"
        }
    }

    /// One line describing what the section will hold, shown while it is still empty.
    var summary: String {
        switch self {
        case .keepAwake:
            return "Holds off sleep for as long as you choose."
        case .volumeMixer:
            return "Output, input, and per-app volume in one place."
        case .system:
            return "Processor, graphics, and memory load at a glance."
        case .network:
            return "Live throughput and the addresses this Mac is using."
        case .disk:
            return "Free space and read/write activity per volume."
        case .power:
            return "Battery health, charge, and what is drawing power."
        case .fans:
            return "Fan speeds and temperature readings."
        case .utilities:
            return "The Commandly windows and shortcuts you reach most."
        case .controls:
            return "Pointer, keyboard, and window behavior switches."
        case .quickToggles:
            return "One-tap switches for everyday macOS settings."
        }
    }

    /// Height the panel reserves for this section before its body has been measured, so a tab
    /// never flashes at zero height while it lays out.
    var estimatedHeight: CGFloat {
        switch self {
        case .keepAwake: return 260
        case .volumeMixer: return 460
        case .system: return 480
        case .network: return 380
        case .disk: return 560
        case .power: return 420
        case .fans: return 260
        case .utilities: return 320
        case .controls: return 560
        case .quickToggles: return 560
        }
    }

    /// Every section now has a body of its own.
    var isImplemented: Bool { true }
}
