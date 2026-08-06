import SwiftUI
import NexaWalLogic

struct FiatApproxText: View {
    let piconero: UInt64
    let rate: FiatRate?
    var font: Font = .caption
    var color: Color = .secondary

    var body: some View {
        if let text = FiatEstimate.liveApproxText(
            piconero: piconero,
            rate: rate,
            nowMs: Int64(Date().timeIntervalSince1970 * 1000)
        ) {
            Text(text)
                .font(font)
                .foregroundStyle(color)
        }
    }
}
