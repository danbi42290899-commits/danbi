import { useCallback, useEffect, useRef, useState } from 'react'
import { LEVEL_MAX_DB } from '../utils/audiogramFrequencies'

const FADE_SECONDS = 0.05
const MAX_GAIN = 0.25 // same headroom as PLAY_GAIN in useAudioEngine.js
const REFERENCE_FREQ = 1000
const REFERENCE_LEVEL_DB = LEVEL_MAX_DB - 40 // moderate, comfortable calibration tone

// Converts a relative, uncalibrated "level" in dB into a linear gain using
// the physically-correct dB-amplitude relationship (20*log10(ratio)), so
// equal dB steps are equal perceptual loudness steps. This is NOT calibrated
// to dB SPL/HL — real loudness at the ear still depends on device volume and
// headphones, which we can't know. It only guarantees internally-consistent
// relative comparisons (ear vs ear, frequency vs frequency) as long as the
// device volume knob isn't touched between trials.
function levelToGain(db) {
  return MAX_GAIN * Math.pow(10, (db - LEVEL_MAX_DB) / 20)
}

export function useAudiogramEngine() {
  const audioCtxRef = useRef(null)
  const gainRef = useRef(null)
  const analyserRef = useRef(null)
  const pannerRef = useRef(null)
  const oscillatorRef = useRef(null)
  const earRef = useRef('right')

  const [ear, setEarState] = useState('right')

  const ensureAudioContext = useCallback(() => {
    if (!audioCtxRef.current) {
      const AudioContextCtor = window.AudioContext || window.webkitAudioContext
      let ctx
      try {
        ctx = new AudioContextCtor({ sampleRate: 96000 })
      } catch {
        ctx = new AudioContextCtor()
      }
      const gain = ctx.createGain()
      gain.gain.value = 0
      const analyser = ctx.createAnalyser()
      analyser.fftSize = 2048
      const panner = ctx.createStereoPanner()
      panner.pan.value = earRef.current === 'right' ? 1 : -1

      gain.connect(analyser)
      analyser.connect(panner)
      panner.connect(ctx.destination)

      audioCtxRef.current = ctx
      gainRef.current = gain
      analyserRef.current = analyser
      pannerRef.current = panner
    }
    return audioCtxRef.current
  }, [])

  const stopSound = useCallback(() => {
    const ctx = audioCtxRef.current
    const gain = gainRef.current
    if (ctx && gain) {
      const now = ctx.currentTime
      gain.gain.cancelScheduledValues(now)
      gain.gain.setValueAtTime(gain.gain.value, now)
      gain.gain.linearRampToValueAtTime(0, now + FADE_SECONDS)
    }
    if (oscillatorRef.current) {
      const osc = oscillatorRef.current
      oscillatorRef.current = null
      setTimeout(() => {
        try {
          osc.stop()
          osc.disconnect()
        } catch {
          // already stopped
        }
      }, FADE_SECONDS * 1000 + 20)
    }
  }, [])

  const playAt = useCallback(
    (freq, gainValue) => {
      const ctx = ensureAudioContext()
      if (ctx.state === 'suspended') ctx.resume()
      if (oscillatorRef.current) {
        const oldOsc = oscillatorRef.current
        try {
          oldOsc.stop()
        } catch {
          // already stopped
        }
        oldOsc.disconnect()
      }
      const osc = ctx.createOscillator()
      osc.type = 'sine'
      osc.frequency.value = freq
      osc.connect(gainRef.current)

      const now = ctx.currentTime
      gainRef.current.gain.cancelScheduledValues(now)
      gainRef.current.gain.setValueAtTime(0.0001, now)
      gainRef.current.gain.linearRampToValueAtTime(Math.max(gainValue, 0.0001), now + FADE_SECONDS)

      osc.start(now)
      oscillatorRef.current = osc
    },
    [ensureAudioContext],
  )

  // Sustained playback (like the confirmation test's playTone): keeps
  // playing at a given frequency/level until the caller stops it.
  const playToneAtLevel = useCallback(
    (freq, db) => {
      playAt(freq, levelToGain(db))
    },
    [playAt],
  )

  // Fixed-level, center-panned tone for the volume-calibration step. Ear
  // panning is restored automatically the next time playToneAtLevel runs.
  const playReferenceTone = useCallback(() => {
    const ctx = ensureAudioContext()
    if (pannerRef.current) pannerRef.current.pan.value = 0
    playAt(REFERENCE_FREQ, levelToGain(REFERENCE_LEVEL_DB))
    return ctx
  }, [ensureAudioContext, playAt])

  const stopTone = useCallback(() => {
    stopSound()
    if (pannerRef.current) {
      pannerRef.current.pan.value = earRef.current === 'right' ? 1 : -1
    }
  }, [stopSound])

  const setEar = useCallback((nextEar) => {
    earRef.current = nextEar
    setEarState(nextEar)
    if (pannerRef.current) {
      pannerRef.current.pan.value = nextEar === 'right' ? 1 : -1
    }
  }, [])

  useEffect(() => {
    return () => {
      stopSound()
      if (audioCtxRef.current) {
        audioCtxRef.current.close()
      }
    }
  }, [stopSound])

  return {
    ear,
    setEar,
    playToneAtLevel,
    playReferenceTone,
    stopTone,
    getAnalyser: () => analyserRef.current,
  }
}
