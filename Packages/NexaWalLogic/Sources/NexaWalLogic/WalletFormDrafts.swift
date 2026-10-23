import Foundation

public enum AmountInputMode: Equatable {
    case xmr
    case fiat
}

/// Input only: never persist an approval, fee quote, secret, or in-flight send here.
/// The app owns these values for one unlocked session, above adaptive containers.
public struct SendFormDraft: Equatable {
    public var toAddress = ""
    public var amount = ""
    public var amountMode: AmountInputMode = .xmr
    public var paymentDescription = ""
    public var recipientName = ""
    public var fromSubaddressMinor: UInt32 = 0
    public var sendFromSubaddressEnabled = false

    public init() {}
}

public struct ReceiveFormDraft: Equatable {
    public var amount = ""
    public var amountMode: AmountInputMode = .xmr
    public var description = ""
    public var newSubaddressLabel = ""

    public init() {}
}
