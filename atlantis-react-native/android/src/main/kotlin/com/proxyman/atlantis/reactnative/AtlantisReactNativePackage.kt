package com.proxyman.atlantis.reactnative

import com.facebook.react.TurboReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfo
import com.facebook.react.module.model.ReactModuleInfoProvider

/**
 * React Native TurboModule package that registers the AtlantisReactNativeModule.
 * Auto-linked by React Native's autolinking mechanism.
 */
class AtlantisReactNativePackage : TurboReactPackage() {

    override fun getModule(
        name: String,
        reactContext: ReactApplicationContext
    ): NativeModule? {
        return if (name == AtlantisReactNativeModule.NAME) {
            AtlantisReactNativeModule(reactContext)
        } else {
            null
        }
    }

    override fun getReactModuleInfoProvider(): ReactModuleInfoProvider {
        return ReactModuleInfoProvider {
            mapOf(
                AtlantisReactNativeModule.NAME to ReactModuleInfo(
                    AtlantisReactNativeModule.NAME,
                    AtlantisReactNativeModule.NAME,
                    false, // canOverrideExistingModule
                    false, // needsEagerInit
                    false, // isCxxModule
                    true   // isTurboModule
                )
            )
        }
    }
}
