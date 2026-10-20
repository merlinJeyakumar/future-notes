package com.nativedevps.futurenotes

/** Latest presentation per identity, in fair order. Removal is never deferred. */
internal class NotificationUpdateQueue<T> {
    private val posted = mutableMapOf<String, T>()
    private val pending = linkedMapOf<String, T>()

    fun replace(desired: Map<String, T>) {
        posted.keys.retainAll(desired.keys)
        pending.keys.retainAll(desired.keys)
        for ((id, value) in desired) {
            if (posted[id] == value) pending.remove(id)
            else pending[id] = value
        }
    }

    val hasPending: Boolean get() = pending.isNotEmpty()

    fun take(): Pair<String, T>? {
        val entry = pending.entries.firstOrNull() ?: return null
        val result = entry.key to entry.value
        pending.remove(entry.key)
        posted[result.first] = result.second
        return result
    }
}
