package com.innotrik.aispeaking

import java.util.concurrent.Executor

/** Separates blocking route work from Flutter's platform-thread delivery. */
internal class HfpRouteDispatch(
    private val routeExecutor: Executor,
    private val platformExecutor: Executor,
    private val isRouteThread: () -> Boolean,
) {
    fun run(operation: () -> Unit) {
        if (isRouteThread()) operation() else routeExecutor.execute(operation)
    }

    fun <T> publish(readRoute: () -> T, deliver: (T) -> Unit) {
        run {
            val status = readRoute()
            complete { deliver(status) }
        }
    }

    fun complete(deliver: () -> Unit) { platformExecutor.execute(deliver) }
}
