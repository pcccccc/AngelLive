import CoreGraphics
import Foundation

// Compile alongside the real FullUI geometry source without player dependencies.
@main
enum PlayerVideoGeometryTests {
    static func main() {
        let landscape = CGSize(width: 1920, height: 1080)
        let portrait = CGSize(width: 1080, height: 1920)
        let cases: [(String, CGSize, UInt16, CGSize?, CGSize?)] = [
            ("landscape track", landscape, 0, nil, landscape),
            ("portrait track", portrait, 0, nil, portrait),
            ("quarter turn", landscape, 90, nil, portrait),
            ("reverse quarter turn", landscape, 270, nil, portrait),
            ("rounded rotation below", landscape, 89, nil, portrait),
            ("rounded rotation above quarter turn", landscape, 91, nil, portrait),
            ("rounded rotation below reverse quarter turn", landscape, 269, nil, portrait),
            ("rounded rotation above", landscape, 271, nil, portrait),
            ("outside rotation tolerance", landscape, 88, nil, landscape),
            ("half turn", landscape, 180, nil, landscape),
            ("display size is already rotated", landscape, 90, portrait, portrait),
            ("display size overrides track", portrait, 0, landscape, landscape),
            ("unavailable display size", landscape, 90, .zero, portrait),
            ("nonfinite display size", landscape, 90, CGSize(width: CGFloat.infinity, height: 1920), portrait),
            ("nan display size", landscape, 90, CGSize(width: CGFloat.nan, height: 1920), portrait),
            ("placeholder display size", landscape, 90, CGSize(width: 1, height: 1), portrait),
            ("missing track", .zero, 0, portrait, nil),
            ("nonfinite track", CGSize(width: CGFloat.nan, height: 1080), 0, portrait, nil),
            ("infinite track", CGSize(width: 1920, height: CGFloat.infinity), 0, portrait, nil),
            ("negative track", CGSize(width: -1920, height: 1080), 0, portrait, nil),
            ("placeholder track", CGSize(width: 1, height: 1), 0, nil, nil),
        ]
        for (name, track, rotation, display, expected) in cases {
            let actual = PlayerVideoSizeResolver.resolve(trackSize: track, rotation: rotation, presentationSize: display)
            guard actual == expected else {
                fatalError("\(name): expected \(String(describing: expected)), received \(String(describing: actual))")
            }
        }
        // A later display size must replace an initially usable track fallback.
        let initial = PlayerVideoSizeResolver.resolve(trackSize: landscape, rotation: 0, presentationSize: .zero)
        let updated = PlayerVideoSizeResolver.resolve(trackSize: landscape, rotation: 0, presentationSize: portrait)
        precondition(initial == landscape && updated == portrait)
        print("Passed \(cases.count + 1) video geometry cases")
    }
}
