package com.example.navi

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import java.security.MessageDigest

/**
 * Resolves the Android package name and signing SHA-1 fingerprint used to
 * authorize Android-restricted Google Cloud API keys via HTTP headers.
 */
object AndroidAppIdentity {
    fun getCredentials(context: Context): Map<String, String> = mapOf(
        "package" to context.packageName,
        "cert" to getSigningCertificateSha1(context),
    )

    private fun getSigningCertificateSha1(context: Context): String {
        return try {
            val certs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val signingInfo = context.packageManager.getPackageInfo(
                    context.packageName,
                    PackageManager.GET_SIGNING_CERTIFICATES,
                ).signingInfo
                if (signingInfo?.hasMultipleSigners() == true) {
                    signingInfo.apkContentsSigners
                } else {
                    signingInfo?.signingCertificateHistory
                }
            } else {
                @Suppress("DEPRECATION")
                context.packageManager.getPackageInfo(
                    context.packageName,
                    PackageManager.GET_SIGNATURES,
                ).signatures
            }
            val cert = certs?.firstOrNull()?.toByteArray() ?: return ""
            val md = MessageDigest.getInstance("SHA-1")
            md.digest(cert).joinToString("") { "%02x".format(it) }
        } catch (_: Exception) {
            ""
        }
    }
}

