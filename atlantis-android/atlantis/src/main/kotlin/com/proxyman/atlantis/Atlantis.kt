package com.proxyman.atlantis

import android.content.Context
import android.util.Log
import okhttp3.Headers
import okhttp3.Request as OkHttpRequest
import okhttp3.Response as OkHttpResponse
import okhttp3.WebSocketListener
import java.lang.ref.WeakReference
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Atlantis - Capture HTTP/HTTPS traffic from Android apps and send to Proxyman for debugging
 * 
 * Atlantis is an Android library that captures all HTTP/HTTPS traffic from OkHttp
 * (including Retrofit and Apollo) and sends it to Proxyman macOS app for inspection.
 * 
 * ## Quick Start
 * 
 * 1. Initialize Atlantis in your Application class:
 * ```kotlin
 * class MyApplication : Application() {
 *     override fun onCreate() {
 *         super.onCreate()
 *         if (BuildConfig.DEBUG) {
 *             Atlantis.start(this)
 *         }
 *     }
 * }
 * ```
 * 
 * 2. Add the interceptor to your OkHttpClient:
 * ```kotlin
 * val client = OkHttpClient.Builder()
 *     .addInterceptor(Atlantis.getInterceptor())
 *     .build()
 * ```
 * 
 * ## Features
 * - Automatic OkHttp traffic interception
 * - Works with Retrofit and Apollo
 * - Network Service Discovery to find Proxyman
 * - Direct connection support for emulators
 * 
 * @see <a href="https://proxyman.com">Proxyman</a>
 * @see <a href="https://github.com/ProxymanApp/atlantis">GitHub Repository</a>
 */
object Atlantis {
    
    private const val TAG = "Atlantis"
    
    /**
     * Build version of Atlantis Android
     * Must match Proxyman's expected version for compatibility
     */
    const val BUILD_VERSION = "1.0.0"
    
    // MARK: - Private Properties
    
    private var contextRef: WeakReference<Context>? = null
    private var transporter: Transporter? = null
    private var configuration: Configuration? = null
    private var delegate: WeakReference<AtlantisDelegate>? = null
    
    private val isEnabled = AtomicBoolean(false)
    private val interceptor = AtlantisInterceptor()

    // MARK: - WebSocket caches (mirrors iOS Atlantis.swift)

    private val webSocketPackages = ConcurrentHashMap<String, TrafficPackage>()
    private val waitingWebsocketPackages = ConcurrentHashMap<String, MutableList<TrafficPackage>>()
    private val wsLock = Any()
    
    // MARK: - Public API
    
    /**
     * Start Atlantis and begin looking for Proxyman app
     * 
     * This will:
     * 1. Initialize the transporter
     * 2. Start NSD discovery (for real devices) or direct connection (for emulators)
     * 3. Begin sending captured traffic to Proxyman
     * 
     * @param context Application context
     * @param hostName Optional hostname to connect to a specific Proxyman instance.
     *                 If null, will connect to any Proxyman found on the network.
     *                 You can find your Mac's hostname in Proxyman -> Certificate menu -> 
     *                 Install Certificate for iOS -> With Atlantis
     */
    @JvmStatic
    @JvmOverloads
    fun start(context: Context, hostName: String? = null) {
        if (isEnabled.getAndSet(true)) {
            Log.d(TAG, "Atlantis is already running")
            return
        }
        
        val appContext = context.applicationContext
        contextRef = WeakReference(appContext)
        
        // Create configuration
        configuration = Configuration.default(appContext, hostName)
        
        // Start transporter
        transporter = Transporter(appContext).also {
            it.start(configuration!!)
        }
        
        printStartupMessage(hostName)
    }
    
    /**
     * Stop Atlantis
     * 
     * This will:
     * 1. Stop NSD discovery
     * 2. Close all connections to Proxyman
     * 3. Clear any pending packages
     */
    @JvmStatic
    fun stop() {
        if (!isEnabled.getAndSet(false)) {
            Log.d(TAG, "Atlantis is not running")
            return
        }
        
        transporter?.stop()
        transporter = null
        configuration = null
        contextRef = null

        synchronized(wsLock) {
            webSocketPackages.clear()
            waitingWebsocketPackages.clear()
        }
        
        Log.d(TAG, "Atlantis stopped")
    }
    
    /**
     * Get the OkHttp interceptor to add to your OkHttpClient
     * 
     * Usage:
     * ```kotlin
     * val client = OkHttpClient.Builder()
     *     .addInterceptor(Atlantis.getInterceptor())
     *     .build()
     * ```
     * 
     * Note: The interceptor will only capture traffic when Atlantis is started.
     */
    @JvmStatic
    fun getInterceptor(): AtlantisInterceptor {
        return interceptor
    }
    
    /**
     * Check if Atlantis is currently running
     */
    @JvmStatic
    fun isRunning(): Boolean {
        return isEnabled.get()
    }
    
    /**
     * Set a delegate to receive traffic packages
     * 
     * This allows you to observe captured traffic in your app, 
     * in addition to sending it to Proxyman.
     */
    @JvmStatic
    fun setDelegate(delegate: AtlantisDelegate?) {
        this.delegate = delegate?.let { WeakReference(it) }
    }
    
    /**
     * Set a connection listener to monitor Proxyman connection status
     */
    @JvmStatic
    fun setConnectionListener(listener: Transporter.ConnectionListener?) {
        transporter?.connectionListener = listener
    }

    /**
     * Wrap an OkHttp WebSocketListener to capture WebSocket messages and send them to Proxyman.
     *
     * Usage:
     * ```kotlin
     * val listener = Atlantis.wrapWebSocketListener(object : WebSocketListener() { ... })
     * client.newWebSocket(request, listener)
     * ```
     */
    @JvmStatic
    fun wrapWebSocketListener(listener: WebSocketListener): AtlantisWebSocketListener {
        return AtlantisWebSocketListener(listener)
    }
    
    // MARK: - Internal API (used by AtlantisInterceptor)
    
    /**
     * Send a traffic package to Proxyman
     * Called internally by AtlantisInterceptor
     */
    internal fun sendPackage(trafficPackage: TrafficPackage) {
        if (!isEnabled.get()) {
            return
        }
        
        // Notify delegate
        delegate?.get()?.onTrafficCaptured(trafficPackage)
        
        // Build and send message
        val configuration = configuration ?: return
        val message = Message.buildTrafficMessage(configuration.id, trafficPackage)
        
        transporter?.send(message)
    }

    // MARK: - Internal API (used by AtlantisWebSocketListener)

    internal fun onWebSocketOpen(id: String, request: OkHttpRequest, response: OkHttpResponse) {
        if (!isEnabled.get()) return

        val configuration = configuration ?: return
        val transporter = transporter ?: return

        val atlantisRequest = Request.fromOkHttp(
            url = request.url.toString(),
            method = request.method,
            headers = headersToSingleValueMap(request.headers),
            body = null
        )

        val atlantisResponse = Response.fromOkHttp(
            statusCode = response.code,
            headers = headersToSingleValueMap(response.headers)
        )

        val now = System.currentTimeMillis() / 1000.0

        val basePackage: TrafficPackage
        synchronized(wsLock) {
            basePackage = TrafficPackage(
                id = id,
                startAt = now,
                request = atlantisRequest,
                response = atlantisResponse,
                responseBodyData = "",
                endAt = now,
                packageType = TrafficPackage.PackageType.WEBSOCKET
            )
            webSocketPackages[id] = basePackage
        }

        // Send the initial traffic message to register the WebSocket connection in Proxyman.
        // This mirrors iOS: handleDidFinish sends a traffic-type message for the HTTP upgrade.
        val trafficMessage = Message.buildTrafficMessage(configuration.id, basePackage)
        transporter.send(trafficMessage)

        // Flush any queued messages that happened before onOpen
        attemptSendingAllWaitingWSPackages(id)
    }

    internal fun onWebSocketSendText(id: String, text: String) {
        sendWebSocketMessage(
            id = id
        ) { WebsocketMessagePackage.createStringMessage(id = id, message = text, type = WebsocketMessagePackage.MessageType.SEND) }
    }

    internal fun onWebSocketSendBinary(id: String, bytes: ByteArray) {
        sendWebSocketMessage(
            id = id
        ) { WebsocketMessagePackage.createDataMessage(id = id, data = bytes, type = WebsocketMessagePackage.MessageType.SEND) }
    }

    internal fun onWebSocketReceiveText(id: String, text: String) {
        sendWebSocketMessage(
            id = id
        ) { WebsocketMessagePackage.createStringMessage(id = id, message = text, type = WebsocketMessagePackage.MessageType.RECEIVE) }
    }

    internal fun onWebSocketReceiveBinary(id: String, bytes: ByteArray) {
        sendWebSocketMessage(
            id = id
        ) { WebsocketMessagePackage.createDataMessage(id = id, data = bytes, type = WebsocketMessagePackage.MessageType.RECEIVE) }
    }

    internal fun onWebSocketClosing(id: String, code: Int, reason: String?) {
        if (!isEnabled.get()) return
        val configuration = configuration ?: return
        val transporter = transporter ?: return

        // Atomically remove the base package so only the FIRST close call sends a message.
        // Subsequent calls (proxy close, onClosing callback, onClosed callback) will find
        // nothing in the cache and return early.
        val basePackage = synchronized(wsLock) {
            val pkg = webSocketPackages.remove(id) ?: return
            waitingWebsocketPackages.remove(id)
            pkg
        }

        val wsPackage = WebsocketMessagePackage.createCloseMessage(id = id, closeCode = code, reason = reason)
        val messageTrafficPackage = basePackage.copy(websocketMessagePackage = wsPackage)

        val delegate = delegate?.get()
        if (delegate is AtlantisWebSocketDelegate) {
            delegate.onWebSocketMessageCaptured(messageTrafficPackage)
        }

        val message = Message.buildWebSocketMessage(configuration.id, messageTrafficPackage)
        transporter.send(message)
    }

    internal fun onWebSocketClosed(id: String, code: Int, reason: String?) {
        // Ensure close message is sent (idempotent: onWebSocketClosing no-ops if already removed)
        onWebSocketClosing(id, code, reason)
    }

    internal fun onWebSocketFailure(id: String, t: Throwable, response: OkHttpResponse?) {
        if (!isEnabled.get()) return
        val responseInfo = response?.let { " HTTP ${it.code}" } ?: ""
        Log.e(TAG, "WebSocket failure (id=$id)$responseInfo: ${t.message ?: t.javaClass.simpleName}", t)
        // Best effort: clean up local caches. Transporter will handle reconnect/pending queue.
        synchronized(wsLock) {
            webSocketPackages.remove(id)
            waitingWebsocketPackages.remove(id)
        }
    }

    private fun sendWebSocketMessage(
        id: String,
        wsPackageBuilder: () -> WebsocketMessagePackage
    ) {
        if (!isEnabled.get()) return

        val configuration = configuration ?: return
        val transporter = transporter ?: return

        val basePackage = synchronized(wsLock) { webSocketPackages[id] } ?: return

        val wsPackage = try {
            wsPackageBuilder()
        } catch (_: Exception) {
            return
        }

        // Create a snapshot package per message to avoid mutating the cached basePackage.
        // This is critical because Transporter queues Serializable objects by reference.
        val messageTrafficPackage = basePackage.copy(websocketMessagePackage = wsPackage)

        // Notify delegate
        val delegate = delegate?.get()
        if (delegate is AtlantisWebSocketDelegate) {
            delegate.onWebSocketMessageCaptured(messageTrafficPackage)
        }

        startSendingWebsocketMessage(
            configurationId = configuration.id,
            transporter = transporter,
            package_ = messageTrafficPackage
        )
    }

    private fun startSendingWebsocketMessage(
        configurationId: String,
        transporter: Transporter,
        package_: TrafficPackage
    ) {
        val id = package_.id

        synchronized(wsLock) {
            // If WS response isn't ready yet, queue it (mirrors iOS waitingWebsocketPackages)
            if (package_.response == null) {
                val waitingList = waitingWebsocketPackages[id] ?: mutableListOf()
                waitingList.add(package_)
                waitingWebsocketPackages[id] = waitingList
                return
            }
        }

        // Send all waiting WS packages (if any)
        attemptSendingAllWaitingWSPackages(id)

        val message = Message.buildWebSocketMessage(configurationId, package_)
        transporter.send(message)
    }

    private fun attemptSendingAllWaitingWSPackages(id: String) {
        val transporter = transporter ?: return
        val messagesToSend: List<Message> = synchronized(wsLock) {
            val configurationId = configuration?.id ?: return
            val waitingList = waitingWebsocketPackages.remove(id) ?: return
            val baseResponse = webSocketPackages[id]?.response

            waitingList.map { item ->
                val toSend = if (item.response == null && baseResponse != null) {
                    item.copy(response = baseResponse)
                } else {
                    item
                }
                Message.buildWebSocketMessage(configurationId, toSend)
            }
        }

        messagesToSend.forEach { transporter.send(it) }
    }

    private fun headersToSingleValueMap(headers: Headers): Map<String, String> {
        if (headers.size == 0) return emptyMap()
        val map = LinkedHashMap<String, String>(headers.size)
        for (name in headers.names()) {
            val values = headers.values(name)
            map[name] = values.joinToString(",")
        }
        return map
    }
    
    // MARK: - Private Methods
    
    private fun printStartupMessage(hostName: String?) {
        Log.i(TAG, "---------------------------------------------------------------------------------")
        Log.i(TAG, "---------- \uD83E\uDDCA Atlantis Android is running (version $BUILD_VERSION)")
        Log.i(TAG, "---------- GitHub: https://github.com/ProxymanApp/atlantis")
        if (hostName != null) {
            Log.i(TAG, "---------- Looking for Proxyman with hostname: $hostName")
        } else {
            Log.i(TAG, "---------- Looking for any Proxyman app on the network...")
        }
        Log.i(TAG, "---------------------------------------------------------------------------------")
    }
}

/**
 * Delegate interface for observing captured traffic
 */
interface AtlantisDelegate {
    /**
     * Called when a new traffic package is captured
     * This is called on a background thread
     */
    fun onTrafficCaptured(trafficPackage: TrafficPackage)
}

/**
 * Optional delegate for observing captured WebSocket traffic packages.
 *
 * This is separate from [AtlantisDelegate] to avoid breaking existing implementers
 * (especially Java implementations) when adding new callbacks.
 */
interface AtlantisWebSocketDelegate {
    fun onWebSocketMessageCaptured(trafficPackage: TrafficPackage)
}
