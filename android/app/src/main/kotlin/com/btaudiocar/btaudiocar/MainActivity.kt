package com.btaudiocar.btaudiocar

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), MethodChannel.MethodCallHandler {
    private val CHANNEL = "com.btaudiocar/sco"
    private val BT_PERMISSION_REQUEST = 1001
    private var pendingResult: MethodChannel.Result? = null
    private var audioManager: AudioManager? = null
    private var scoReceiver: BroadcastReceiver? = null
    private var scoActive = false
    private var scoMonitorReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(this)
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startSco" -> startSco(result)
            "stopSco" -> stopSco(result)
            else -> result.notImplemented()
        }
    }

    private fun startSco(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT)
                != PackageManager.PERMISSION_GRANTED
            ) {
                pendingResult = result
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.BLUETOOTH_CONNECT),
                    BT_PERMISSION_REQUEST
                )
                return
            }
        }
        doStartSco(result)
    }

    private fun doStartSco(result: MethodChannel.Result) {
        val am = audioManager ?: run {
            result.success(mapOf("success" to false, "error" to "AudioManager no disponible"))
            return
        }

        val btAdapter = BluetoothAdapter.getDefaultAdapter()
        if (btAdapter == null || !btAdapter.isEnabled) {
            result.success(mapOf("success" to false, "error" to "Bluetooth no está activado"))
            return
        }

        val deviceName = getConnectedHfpDeviceName(btAdapter)

        var receiverFired = false
        scoReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (receiverFired) return
                val state = intent.getIntExtra(
                    AudioManager.EXTRA_SCO_AUDIO_STATE,
                    AudioManager.SCO_AUDIO_STATE_ERROR
                )
                when (state) {
                    AudioManager.SCO_AUDIO_STATE_CONNECTED -> {
                        receiverFired = true
                        scoActive = true
                        startScoMonitor()
                        result.success(mapOf(
                            "success" to true,
                            "deviceName" to (deviceName ?: "Bluetooth")
                        ))
                    }
                    AudioManager.SCO_AUDIO_STATE_ERROR -> {
                        receiverFired = true
                        unregisterScoReceiver()
                        am.stopBluetoothSco()
                        am.isBluetoothScoOn = false
                        result.success(mapOf(
                            "success" to false,
                            "error" to "Error al conectar SCO. ¿Manos libres conectado?"
                        ))
                    }
                }
            }
        }

        registerReceiver(
            scoReceiver,
            IntentFilter(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED)
        )

        am.mode = AudioManager.MODE_IN_COMMUNICATION
        am.isBluetoothScoOn = true
        am.startBluetoothSco()

        // Timeout 5s
        window.decorView.postDelayed({
            if (!receiverFired) {
                receiverFired = true
                if (am.isBluetoothScoOn) {
                    scoActive = true
                    startScoMonitor()
                    result.success(mapOf(
                        "success" to true,
                        "deviceName" to (deviceName ?: "Bluetooth")
                    ))
                } else {
                    unregisterScoReceiver()
                    am.stopBluetoothSco()
                    am.isBluetoothScoOn = false
                    am.mode = AudioManager.MODE_NORMAL
                    result.success(mapOf(
                        "success" to false,
                        "error" to "No se pudo conectar. Asegúrate de que el manos libres está conectado."
                    ))
                }
            }
        }, 5000)
    }

    // Monitor SCO disconnections (e.g. after a phone call) and re-connect
    private fun startScoMonitor() {
        stopScoMonitor()
        scoMonitorReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (!scoActive) return
                val state = intent.getIntExtra(
                    AudioManager.EXTRA_SCO_AUDIO_STATE,
                    AudioManager.SCO_AUDIO_STATE_ERROR
                )
                if (state == AudioManager.SCO_AUDIO_STATE_DISCONNECTED) {
                    // SCO dropped (phone call ended, etc.) — re-establish after short delay
                    window.decorView.postDelayed({
                        if (scoActive) {
                            val am = audioManager ?: return@postDelayed
                            am.mode = AudioManager.MODE_IN_COMMUNICATION
                            am.isBluetoothScoOn = true
                            am.startBluetoothSco()
                        }
                    }, 1500)
                }
            }
        }
        registerReceiver(
            scoMonitorReceiver,
            IntentFilter(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED)
        )
    }

    private fun stopScoMonitor() {
        scoMonitorReceiver?.let {
            try { unregisterReceiver(it) } catch (_: Exception) {}
            scoMonitorReceiver = null
        }
    }

    @Suppress("MissingPermission")
    private fun getConnectedHfpDeviceName(btAdapter: BluetoothAdapter): String? {
        try {
            val method = btAdapter.javaClass.getMethod(
                "getProfileConnectionState", Int::class.javaPrimitiveType
            )
            val hfpState = method.invoke(btAdapter, BluetoothProfile.HEADSET) as Int
            if (hfpState == BluetoothProfile.STATE_CONNECTED) {
                val bondedDevices = btAdapter.bondedDevices
                for (device in bondedDevices) {
                    val deviceClass = device.bluetoothClass
                    if (deviceClass != null) {
                        val majorClass = deviceClass.majorDeviceClass
                        if (majorClass == 0x0400 || majorClass == 0x0200) {
                            return device.name
                        }
                    }
                }
                return bondedDevices.firstOrNull()?.name
            }
        } catch (_: Exception) {}
        return null
    }

    private fun stopSco(result: MethodChannel.Result) {
        scoActive = false
        stopScoMonitor()
        val am = audioManager ?: run {
            result.success(null)
            return
        }
        unregisterScoReceiver()
        am.stopBluetoothSco()
        am.isBluetoothScoOn = false
        am.mode = AudioManager.MODE_NORMAL
        result.success(null)
    }

    private fun unregisterScoReceiver() {
        scoReceiver?.let {
            try { unregisterReceiver(it) } catch (_: Exception) {}
            scoReceiver = null
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == BT_PERMISSION_REQUEST) {
            val result = pendingResult
            pendingResult = null
            if (result != null) {
                if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                    doStartSco(result)
                } else {
                    result.success(mapOf("success" to false, "error" to "Permiso de Bluetooth denegado"))
                }
            }
        }
    }

    override fun onDestroy() {
        scoActive = false
        stopScoMonitor()
        audioManager?.let {
            it.stopBluetoothSco()
            it.isBluetoothScoOn = false
            it.mode = AudioManager.MODE_NORMAL
        }
        unregisterScoReceiver()
        super.onDestroy()
    }
}
