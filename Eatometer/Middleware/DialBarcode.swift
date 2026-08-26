import Foundation

/// Role: barcode normalisation. Extracts digit runs and expands UPC-A to EAN-13.
enum DialBarcode {
    static func digitRuns(in raw: String) -> [String] {
        var runs: [String] = []
        var current = ""
        for character in raw where character.isASCII {
            if character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                runs.append(current)
                current = ""
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    static func candidates(from raw: String) -> [String] {
        let kept = digitRuns(in: raw).filter { (8...14).contains($0.count) }
        var seen = Set<String>()
        var out: [String] = []
        for run in kept {
            let padded = run.count == 12 ? "0" + run : run
            if seen.insert(padded).inserted {
                out.append(padded)
            }
            if padded != run, seen.insert(run).inserted {
                out.append(run)
            }
        }
        return out
    }

    static func primary(from raw: String) -> String? {
        candidates(from: raw).first
    }
}
