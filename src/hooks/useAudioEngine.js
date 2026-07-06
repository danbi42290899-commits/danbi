import { useCallback, useEffect, useRef, useState } from 'react'
import { generateFrequencySteps } from '../utils/frequencySteps'

const STEP_DURATION_MS = 1200
const FADE_SECONDS = 0.05
const PLAY_GAIN = 0.25

export function useAudioEngine() {
  const stepsRef = useRef(generateFrequencySteps())
  const audioCtxRef = useRef(null)
  const gainRef = useRef(null)
  const analyserRef = useRef(null)
  const oscillatorRef = useRef(null)
  const timeoutRef = useRef(null)
  const advanceRef = useRef(null)

  const [currentStepIndex, setCurrentStepIndex] = useState(-1)
  const [isRunning, setIsRunning] = useState(false)
  const [isFinished, setIsFinished] = useState(false)

  const ensureAudioContext = useCallback(() => {
    if (!audioCtxRef.current) {
      const AudioContextCtor = window.AudioContext || window.webkitAudioContext
      // A 96kHz sample rate keeps the Nyquist limit (48kHz) safely above
      // MAX_FREQ so 30kHz tones aren't aliased or silently clamped.
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
      gain.connect(analyser)
      analyser.connect(ctx.destination)
      audioCtxRef.current = ctx
      gainRef.current = gain
      analyserRef.current = analyser
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

  const playFrequency = useCallback(
    (freq) => {
      const ctx = ensureAudioContext()
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
      gainRef.current.gain.linearRampToValueAtTime(PLAY_GAIN, now + FADE_SECONDS)

      osc.start(now)
      oscillatorRef.current = osc
    },
    [ensureAudioContext],
  )

  // Stored in a ref (not useCallback) so the recursive setTimeout chain
  // always calls the latest version without stale-closure issues.
  advanceRef.current = (index) => {
    const steps = stepsRef.current
    if (index >= steps.length) {
      stopSound()
      setIsRunning(false)
      setIsFinished(true)
      return
    }
    setCurrentStepIndex(index)
    playFrequency(steps[index])
    timeoutRef.current = setTimeout(() => advanceRef.current(index + 1), STEP_DURATION_MS)
  }

  const start = useCallback(() => {
    const ctx = ensureAudioContext()
    if (ctx.state === 'suspended') {
      ctx.resume()
    }
    setIsFinished(false)
    setIsRunning(true)
    advanceRef.current(0)
  }, [ensureAudioContext])

  const stopAtCurrentStep = useCallback(() => {
    clearTimeout(timeoutRef.current)
    stopSound()
    setIsRunning(false)
  }, [stopSound])

  // Sustained single-tone playback for the confirmation test: unlike the
  // sweep, the tone keeps playing until the user responds.
  const playTone = useCallback(
    (freq) => {
      ensureAudioContext()
      playFrequency(freq)
    },
    [ensureAudioContext, playFrequency],
  )

  const stopTone = useCallback(() => {
    stopSound()
  }, [stopSound])

  useEffect(() => {
    return () => {
      clearTimeout(timeoutRef.current)
      stopSound()
      if (audioCtxRef.current) {
        audioCtxRef.current.close()
      }
    }
  }, [stopSound])

  return {
    steps: stepsRef.current,
    currentStepIndex,
    currentFrequency:
      currentStepIndex >= 0 && currentStepIndex < stepsRef.current.length
        ? stepsRef.current[currentStepIndex]
        : null,
    isRunning,
    isFinished,
    start,
    stopAtCurrentStep,
    playTone,
    stopTone,
    getAnalyser: () => analyserRef.current,
  }
}
