import Foundation

/// Serial-queue admission policy for hover-driven render pipelines: the operation
/// already executing finishes; every queued-but-unstarted operation is cancelled,
/// so after the in-flight one the most recently admitted item runs next.
///
/// Used by the PDF rail preview loader — a fast sweep over uncached pages must end
/// on the page the pointer is currently on, not FIFO order.
enum LatestFirstSerialQueue {
    static func enqueue(_ operation: Operation, on queue: OperationQueue) {
        for pending in queue.operations where !pending.isExecuting {
            pending.cancel()
        }
        queue.addOperation(operation)
    }
}
