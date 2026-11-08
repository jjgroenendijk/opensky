/// What the world adapters use of `LocalizedLabels`.
public protocol LocalizedLabelsPort: AnyObject {
    func label(for token: String) -> String
}
