// These are the parts of the editor harness also executed by Catalyst CI.
export function genuiMeasurementObserver(source) {
  return source.match(/private static let genuiMeasurementObserver = #"""([\s\S]*?)"""#/)[1];
}

export function genuiLabelGeometry(source) {
  return source.match(/private func verifyGenuiLabelGeometry[\s\S]*?let script = """([\s\S]*?)"""/)[1];
}
