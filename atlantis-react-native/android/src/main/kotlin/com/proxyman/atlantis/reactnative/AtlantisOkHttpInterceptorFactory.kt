package com.proxyman.atlantis.reactnative

import com.facebook.react.modules.network.OkHttpClientFactory
import com.facebook.react.modules.network.OkHttpClientProvider
import com.proxyman.atlantis.Atlantis
import okhttp3.OkHttpClient
import java.util.concurrent.TimeUnit

/**
 * Custom OkHttpClientFactory that injects the AtlantisInterceptor
 * into React Native's OkHttpClient.
 *
 * When registered via OkHttpClientProvider.setOkHttpClientFactory(),
 * all HTTP/HTTPS requests made through React Native's fetch() API
 * will be captured by Atlantis and forwarded to Proxyman.
 */
class AtlantisOkHttpInterceptorFactory : OkHttpClientFactory {

    override fun createNewNetworkModuleClient(): OkHttpClient {
        return OkHttpClient.Builder()
            .connectTimeout(0, TimeUnit.MILLISECONDS)
            .readTimeout(0, TimeUnit.MILLISECONDS)
            .writeTimeout(0, TimeUnit.MILLISECONDS)
            .cookieJar(java.net.CookieManager().let { manager ->
                com.facebook.react.modules.network.ReactCookieJarContainer().also {
                    it.setCookieJar(okhttp3.JavaNetCookieJar(manager))
                }
            })
            .addInterceptor(Atlantis.getInterceptor())
            .build()
    }
}
