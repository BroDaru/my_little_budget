package com.my_little_budget

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NoteAlarmPlaybackPolicyTest {
    @Test
    fun `sound requires both system channel and note permission`() {
        assertTrue(NoteAlarmPlaybackPolicy.shouldPlaySound(systemAllowed = true, noteAllowed = true))
        assertFalse(NoteAlarmPlaybackPolicy.shouldPlaySound(systemAllowed = false, noteAllowed = true))
        assertFalse(NoteAlarmPlaybackPolicy.shouldPlaySound(systemAllowed = true, noteAllowed = false))
    }

    @Test
    fun `vibration requires both system channel and note permission`() {
        assertTrue(NoteAlarmPlaybackPolicy.shouldVibrate(systemAllowed = true, noteAllowed = true))
        assertFalse(NoteAlarmPlaybackPolicy.shouldVibrate(systemAllowed = false, noteAllowed = true))
        assertFalse(NoteAlarmPlaybackPolicy.shouldVibrate(systemAllowed = true, noteAllowed = false))
    }

    @Test
    fun `alarm presentation remains enabled when playback is disabled`() {
        val decision = NoteAlarmPlaybackPolicy.resolve(
            systemSoundAllowed = false,
            systemVibrationAllowed = false,
            noteSoundAllowed = true,
            noteVibrationAllowed = true,
        )

        assertFalse(decision.playSound)
        assertFalse(decision.vibrate)
        assertTrue(decision.showAlarmPresentation)
    }

    @Test
    fun `blocking all notifications disables direct playback without disabling presentation code`() {
        val system = NoteAlarmPlaybackPolicy.systemSettings(
            notificationsAllowed = false,
            channelEnabled = true,
            channelSoundAllowed = true,
            channelVibrationAllowed = true,
        )
        val decision = NoteAlarmPlaybackPolicy.resolve(
            systemSoundAllowed = system.soundAllowed,
            systemVibrationAllowed = system.vibrationAllowed,
            noteSoundAllowed = true,
            noteVibrationAllowed = true,
        )

        assertFalse(decision.playSound)
        assertFalse(decision.vibrate)
        assertTrue(decision.showAlarmPresentation)
    }

    @Test
    fun `foreground notification is always silent to prevent duplicate playback`() {
        assertTrue(NoteAlarmPlaybackPolicy.NOTIFICATION_MUST_BE_SILENT)
        assertTrue(NoteAlarmPlaybackPolicy.CHANNEL_ID.endsWith("_v2"))
    }
}
