package com.my_little_budget

internal data class NoteAlarmSystemPlaybackSettings(
    val soundAllowed: Boolean,
    val vibrationAllowed: Boolean,
)

internal data class NoteAlarmPlaybackDecision(
    val playSound: Boolean,
    val vibrate: Boolean,
    val showAlarmPresentation: Boolean = true,
)

internal object NoteAlarmPlaybackPolicy {
    const val CHANNEL_ID = "note_alarm_playback_v2"
    const val LEGACY_CHANNEL_ID = "note_alarm_playback_v1"

    // The channel exposes the user's sound/vibration choices. Actual playback is
    // performed below by MediaPlayer/Vibrator so custom clips can keep looping.
    // Every posted notification must therefore be silent to avoid double playback.
    const val NOTIFICATION_MUST_BE_SILENT = true

    fun systemSettings(
        notificationsAllowed: Boolean,
        channelEnabled: Boolean,
        channelSoundAllowed: Boolean,
        channelVibrationAllowed: Boolean,
    ): NoteAlarmSystemPlaybackSettings {
        val presentationAllowed = notificationsAllowed && channelEnabled
        return NoteAlarmSystemPlaybackSettings(
            soundAllowed = presentationAllowed && channelSoundAllowed,
            vibrationAllowed = presentationAllowed && channelVibrationAllowed,
        )
    }

    fun shouldPlaySound(systemAllowed: Boolean, noteAllowed: Boolean): Boolean =
        systemAllowed && noteAllowed

    fun shouldVibrate(systemAllowed: Boolean, noteAllowed: Boolean): Boolean =
        systemAllowed && noteAllowed

    fun resolve(
        systemSoundAllowed: Boolean,
        systemVibrationAllowed: Boolean,
        noteSoundAllowed: Boolean,
        noteVibrationAllowed: Boolean,
    ) = NoteAlarmPlaybackDecision(
        playSound = shouldPlaySound(systemSoundAllowed, noteSoundAllowed),
        vibrate = shouldVibrate(systemVibrationAllowed, noteVibrationAllowed),
    )
}
