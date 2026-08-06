package de.atomfritte.axiom

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Der Schluessel der Datenbank — erzeugt, eingewickelt und wieder hervorgeholt.
 *
 * **Warum zwei Schluessel.** Der Android-Keystore gibt Schluesselmaterial nicht
 * heraus; er benutzt es nur. SQLite braucht die Passphrase aber im Klartext.
 * Also gibt es beides: eine zufaellige Passphrase, die SQLite bekommt, und
 * darueber einen Keystore-Schluessel, der sie ver- und entschluesselt. Was auf
 * der Platte liegt, ist die eingewickelte Fassung. Wer die Datei kopiert, hat
 * eine Zeichenkette, die nur auf diesem Geraet etwas bedeutet: Das Auswickeln
 * geht nur durch den Keystore, und der Keystore-Schluessel liegt in der
 * gesicherten Hardware und kann sie nicht verlassen.
 *
 * **Was das schuetzt und was nicht.** Es schuetzt die Datei — eine Kopie, ein
 * versehentlicher `adb`-Auszug, ein Auslesen aus einem ausgeschalteten Geraet.
 * Es schuetzt *nicht* gegen jemanden, der das entsperrte Geraet in der Hand
 * haelt und die App oeffnet: Fuer den entschluesselt der Keystore bereitwillig.
 * Ein Bildschirmschloss bleibt die erste Verteidigungslinie, diese Klasse ist
 * die zweite.
 *
 * **Keine Nutzerabfrage.** `setUserAuthenticationRequired` bleibt aus. Eine
 * Abfrage bei jedem Start waere ein Bildschirm, der Nachdenken erzwingt (G1) —
 * in einer App, deren Erfassung unter drei Sekunden bleiben soll. Ein
 * Biometrie-Gate ist eine eigene Entscheidung und steht im Backlog.
 */
object DatabaseKey {
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"
    private const val WRAP_ALIAS = "axiom_db_wrap"
    private const val PREFS = "axiom_secure"
    private const val KEY_WRAPPED = "db_key_wrapped"
    private const val KEY_IV = "db_key_iv"

    /** 256 Bit. Die Passphrase selbst, nicht ihre Ableitung. */
    private const val PASSPHRASE_BYTES = 32

    /** Von GCM vorgegeben. Den IV erzeugt die Chiffre selbst. */
    private const val GCM_TAG_BITS = 128

    /** Der Schluessel liegt vor. `key` traegt ihn. */
    const val STATE_READY = "ready"

    /**
     * Auf diesem Geraet wurde nie einer abgelegt. Eine vorhandene Datei kann
     * dann nur im Klartext liegen — unverschluesselt zu oeffnen ist hier
     * richtig und verliert nichts.
     */
    const val STATE_NONE = "none"

    /**
     * Es gab einen, er ist gerade nicht zu bekommen. Die Datei ist dann mit
     * hoher Wahrscheinlichkeit verschluesselt, und ohne Schluessel darf sie
     * niemand anfassen.
     */
    const val STATE_UNAVAILABLE = "unavailable"

    /**
     * Zustand und — wenn vorhanden — Passphrase fuer `PRAGMA key`, Base64.
     *
     * **Warum drei Zustaende und nicht zwei.** Vorher gab dieselbe Methode
     * `null` zurueck, sowohl wenn hier nie ein Schluessel angelegt wurde als
     * auch wenn der Keystore gerade nicht antwortete. Die Dart-Seite las
     * beides als „unverschluesselt oeffnen", legte eine Klartextdatei an,
     * traf beim naechsten Start mit dem inzwischen vorhandenen Schluessel auf
     * eine unlesbare Datei — und loeschte den gesamten append-only-Strom. Ein
     * voruebergehender Keystore-Fehler kostete damit alle Daten, ohne
     * Rueckfrage und ohne Backup.
     *
     * Der Unterschied, auf den es ankommt: „hier war nie einer" ist eine
     * Aussage ueber dieses Geraet und erlaubt den Klartextstart. „ich komme
     * gerade nicht heran" ist eine Aussage ueber diesen Moment und erlaubt
     * gar nichts.
     */
    fun passphrase(context: Context): Map<String, Any?> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val stored = prefs.getString(KEY_WRAPPED, null)
        val iv = prefs.getString(KEY_IV, null)

        if (stored != null && iv != null) {
            unwrap(stored, iv)?.let { return reply(STATE_READY, it) }
            // Ausgewickelt werden konnte es nicht. Das hat zwei sehr
            // verschiedene Ursachen — der Keystore-Schluessel ist endgueltig
            // weg (geloeschte App-Daten, zurueckgespieltes Backup,
            // Geraetewechsel), oder er antwortet gerade nicht (Keymaster kurz
            // nach dem Booten belegt) —, und von hier aus sind sie nicht zu
            // unterscheiden. Vorher wurde deshalb einfach ein neuer Schluessel
            // erzeugt und abgelegt; damit war die alte Datei endgueltig
            // unlesbar, auch im zweiten Fall. Jetzt wird nichts entschieden:
            // Der Zustand geht so, wie er ist, an die Dart-Seite.
            return reply(STATE_UNAVAILABLE)
        }

        // Ab hier steht fest, dass auf diesem Geraet nie ein Schluessel
        // abgelegt wurde — `commit()` unten ist die einzige Stelle, die das
        // tut, und sie schreibt erst, wenn das Einwickeln geklappt hat.
        val fresh = ByteArray(PASSPHRASE_BYTES).also { SecureRandom().nextBytes(it) }
        val encoded = Base64.encodeToString(fresh, Base64.NO_WRAP)
        val wrapped = wrap(encoded) ?: return reply(STATE_NONE)
        prefs.edit()
            .putString(KEY_WRAPPED, wrapped.first)
            .putString(KEY_IV, wrapped.second)
            .commit() // nicht apply(): Ohne den Eintrag ist die Datenbank verloren.
        return reply(STATE_READY, encoded)
    }

    private fun reply(state: String, key: String? = null): Map<String, Any?> =
        mapOf("state" to state, "key" to key)

    /** Paar aus eingewickelter Passphrase und IV, beide Base64. */
    private fun wrap(passphrase: String): Pair<String, String>? = try {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, wrapKey())
        val out = cipher.doFinal(passphrase.toByteArray(Charsets.UTF_8))
        Base64.encodeToString(out, Base64.NO_WRAP) to
            Base64.encodeToString(cipher.iv, Base64.NO_WRAP)
    } catch (_: Exception) {
        null
    }

    private fun unwrap(wrapped: String, iv: String): String? = try {
        val store = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        val key = store.getKey(WRAP_ALIAS, null) as? SecretKey
        if (key == null) {
            null
        } else {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE,
                key,
                GCMParameterSpec(GCM_TAG_BITS, Base64.decode(iv, Base64.NO_WRAP)),
            )
            String(
                cipher.doFinal(Base64.decode(wrapped, Base64.NO_WRAP)),
                Charsets.UTF_8,
            )
        }
    } catch (_: Exception) {
        null
    }

    /**
     * Der Schluessel, der die Passphrase einwickelt. Liegt im Keystore und
     * wird beim ersten Mal dort erzeugt.
     *
     * StrongBox — ein eigener Sicherheitschip — wenn das Geraet ihn hat, sonst
     * die TEE. Der Unterschied ist fuer diesen Zweck klein, aber wenn die
     * Hardware da ist, gibt es keinen Grund, sie nicht zu nehmen.
     */
    private fun wrapKey(): SecretKey {
        val store = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (store.getKey(WRAP_ALIAS, null) as? SecretKey)?.let { return it }

        fun build(strongBox: Boolean): SecretKey {
            val spec = KeyGenParameterSpec.Builder(
                WRAP_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .apply {
                    if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        setIsStrongBoxBacked(true)
                    }
                }
                .build()
            return KeyGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_AES,
                ANDROID_KEYSTORE,
            ).apply { init(spec) }.generateKey()
        }

        return try {
            build(strongBox = true)
        } catch (_: Exception) {
            // Kein StrongBox auf diesem Geraet. Kein Grund aufzugeben.
            build(strongBox = false)
        }
    }

    /**
     * Ob ueberhaupt schon ein Schluessel angelegt wurde.
     *
     * Fuer die Anzeige im Systeminspektor gedacht — nicht als Bedingung fuer
     * das Oeffnen. Die Wahrheit darueber, ob die Datei verschluesselt ist,
     * steht in der Datei, nicht hier.
     */
    fun exists(context: Context): Boolean = context
        .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        .contains(KEY_WRAPPED)
}
