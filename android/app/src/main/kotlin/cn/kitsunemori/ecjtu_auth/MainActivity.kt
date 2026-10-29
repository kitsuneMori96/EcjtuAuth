package cn.kitsunemori.ecjtu_auth

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * 把 Android 的网络状态变化接入与 Windows 相同的通道：
 *
 * - `ecjtu_auth/network_events`（EventChannel）：`connected` / `disconnected`，
 *   载荷 `{"event": ..., "ssid": ...}`，与 NlmMonitor 的 C++ 实现结构一致。
 * - `ecjtu_auth/network_methods`（MethodChannel）：`getCurrentSsid` → `{"ssid": ...}`。
 *
 * 使用 [ConnectivityManager.registerDefaultNetworkCallback]（原生 API，不引入第三方依赖），
 * 只关注「默认网络」，避免同时上报多条链路的抖动。API 24 以下不支持该回调，静默降级为
 * 只响应 `getCurrentSsid`。
 */
class MainActivity : FlutterActivity() {
    private companion object {
        const val EVENT_CHANNEL = "ecjtu_auth/network_events"
        const val METHOD_CHANNEL = "ecjtu_auth/network_methods"
        const val TAG = "EcjtuAuth"
        const val UNKNOWN_SSID = "<unknown ssid>"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    /** 上一次发出的事件（`event|ssid`），用于吞掉 onCapabilitiesChanged 的重复回调。 */
    private var lastEmitted: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    lastEmitted = null
                    registerNetworkCallback()
                    // 补一次当前状态：Dart 侧首次订阅时回调可能还没有触发过，
                    // 不能指望「启动就一定有 onAvailable」。
                    emitCurrentState()
                }

                override fun onCancel(arguments: Any?) {
                    unregisterNetworkCallback()
                    eventSink = null
                    lastEmitted = null
                }
            }
        )

        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCurrentSsid" -> result.success(mapOf("ssid" to currentSsid()))
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        unregisterNetworkCallback()
        eventSink = null
        super.onDestroy()
    }

    // region 网络回调

    private fun registerNetworkCallback() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            Log.w(TAG, "API ${Build.VERSION.SDK_INT} 不支持 registerDefaultNetworkCallback，仅提供 SSID 查询")
            return
        }
        if (networkCallback != null) return

        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        if (manager == null) {
            Log.w(TAG, "无法获取 ConnectivityManager，网络变化监听未启用")
            return
        }

        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                emit("connected", currentSsid())
            }

            override fun onLost(network: Network) {
                // 默认网络丢失；WiFi → 蜂窝切换时可能与 onAvailable 交错，
                // 由去重逻辑与 Dart 侧的连接流程兜底。
                emit("disconnected", null)
            }

            override fun onCapabilitiesChanged(
                network: Network,
                networkCapabilities: NetworkCapabilities,
            ) {
                // 换 SSID / 认证状态变化都会走到这里：SSID 解析成功后补发一次，
                // 让 Dart 侧拿到具体网络名（同 AP 漫游时 SSID 不变，会被去重吞掉）。
                if (networkCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                    emit("connected", currentSsid())
                }
            }
        }

        try {
            manager.registerDefaultNetworkCallback(callback)
            networkCallback = callback
        } catch (e: Exception) {
            // SecurityException（缺 ACCESS_NETWORK_STATE）或 RuntimeException（回调注册过多）
            Log.w(TAG, "注册网络回调失败", e)
        }
    }

    private fun unregisterNetworkCallback() {
        val callback = networkCallback ?: return
        networkCallback = null
        try {
            val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            manager?.unregisterNetworkCallback(callback)
        } catch (e: Exception) {
            Log.w(TAG, "注销网络回调失败", e)
        }
    }

    private fun emitCurrentState() {
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        val active = manager?.activeNetwork
        val capabilities = if (active != null) manager.getNetworkCapabilities(active) else null
        val connected = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
        if (connected) {
            emit("connected", currentSsid())
        } else {
            emit("disconnected", null)
        }
    }

    /** 事件必须回到主线程投递：默认回调运行在 ConnectivityThread 上。 */
    private fun emit(event: String, ssid: String?) {
        val payload = mapOf("event" to event, "ssid" to (ssid ?: ""))
        val key = "$event|${ssid ?: ""}"
        mainHandler.post {
            val sink = eventSink ?: return@post
            if (key == lastEmitted) return@post
            lastEmitted = key
            sink.success(payload)
        }
    }

    // endregion

    // region SSID

    /**
     * 读取当前 WiFi SSID。失败一律返回 null（对应 Dart 侧的 `ssid: ''`）：
     * - 未连接 WiFi（蜂窝/离线）
     * - Android 8.0+ 未授予定位权限时系统返回 `<unknown ssid>`
     */
    private fun currentSsid(): String? {
        return try {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                ?: return null
            @Suppress("DEPRECATION")
            val raw = wifi.connectionInfo?.ssid ?: return null
            val ssid = raw.trim('"').trim()
            if (ssid.isEmpty() || ssid == UNKNOWN_SSID) null else ssid
        } catch (e: SecurityException) {
            Log.d(TAG, "读取 SSID 缺少定位权限，按未知处理")
            null
        } catch (e: Exception) {
            Log.d(TAG, "读取 SSID 失败: ${e.message}")
            null
        }
    }

    // endregion
}
