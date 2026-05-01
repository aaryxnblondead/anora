package com.example.anora

import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import com.anorahealth.anora.FLPlatformChannel

class MainActivity: FlutterFragmentActivity() {
	private var flPlatformChannel: FLPlatformChannel? = null

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		flPlatformChannel = FLPlatformChannel(this.applicationContext)
		flPlatformChannel?.setupChannel(flutterEngine)
	}

	override fun onUserInteraction() {
		super.onUserInteraction()
		// Notify the platform channel of user interaction
		flPlatformChannel?.notifyUserInteraction()
	}
}