package com.nativedevps.futurenotes

/** Dependency-free JVM regression checks; not packaged in the application. */
fun main() {
    val queue = NotificationUpdateQueue<Int>()
    queue.replace(linkedMapOf("a" to 1, "b" to 1))
    check(queue.take() == ("a" to 1))
    repeat(100) { queue.replace(linkedMapOf("a" to it + 2, "b" to it + 2)) }
    check(queue.take() == ("b" to 101)) // Latest bytes, without starving the second job.
    check(queue.take() == ("a" to 101))
    queue.replace(linkedMapOf("a" to 101, "b" to 101))
    check(!queue.hasPending) // Heartbeats never repost identical notifications.
    queue.replace(linkedMapOf("a" to 102, "b" to 102))
    queue.replace(mapOf("b" to 102))
    check(queue.take() == ("b" to 102)) // Completion removes a queued update immediately.
    check(queue.take() == null)
    queue.replace(mapOf("b" to 103))
    queue.replace(emptyMap())
    check(!queue.hasPending)
    queue.replace(mapOf("b" to 103))
    check(queue.take() == ("b" to 103)) // A genuinely new lifetime can be posted.
    queue.replace(mapOf("b" to 104))
    queue.replace(mapOf("b" to 103))
    check(!queue.hasPending) // Reverted pending presentation cannot resurrect stale data.
    println("Notification queue checks passed: coalescing, fairness, deduplication, completion, cancellation, reactivation")
}
