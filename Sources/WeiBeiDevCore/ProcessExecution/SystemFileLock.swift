import Darwin

/// Invokes the POSIX `flock(2)` function whose C name conflicts with Darwin's `flock` structure.
@_silgen_name("flock")
func systemFlock(_ descriptor: Int32, _ operation: Int32) -> Int32
