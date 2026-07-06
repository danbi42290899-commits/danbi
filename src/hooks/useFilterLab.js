import { useEffect, useRef, useState } from 'react'

const NOISE_DURATION_SECONDS = 4
const DEFAULT_CUTOFF = 2000
const DEFAULT_Q = 1
const NOISE_GAIN = 0.2

export function useFilterLab() {
  const audioCtxRef = useRef(null)
  const noiseBufferRef = useRef(null)
  const noiseSourceRef = useRef(null)
  const filterRef = useRef(null)
  const analyserPreRef = useRef(null)
  const analyserPostRef = useRef(null)
  const gainRef = useRef(null)

  const [isPlaying, setIsPlaying] = useState(false)
  const [filterType, setFilterTypeState] = useState('lowpass')
  const [cutoff, setCutoffState] = useState(DEFAULT_CUTOFF)
  const [q, setQState] = useState(DEFAULT_Q)

  // Plain function (not useCallback) so it always closes over the latest
  // filterType/cutoff/q state when first invoked from play().
  function ensureContext() {
    if (!audioCtxRef.current) {
      const AudioContextCtor = window.AudioContext || window.webkitAudioContext
      let ctx
      try {
        ctx = new AudioContextCtor({ sampleRate: 96000 })
      } catch {
        ctx = new AudioContextCtor()
      }

      const analyserPre = ctx.createAnalyser()
      analyserPre.fftSize = 2048

      const filter = ctx.createBiquadFilter()
      filter.type = filterType
      filter.frequency.value = cutoff
      filter.Q.value = q

      const analyserPost = ctx.createAnalyser()
      analyserPost.fftSize = 2048

      const gain = ctx.createGain()
      gain.gain.value = NOISE_GAIN

      // source -> analyserPre -> filter -> analyserPost -> gain -> destination
      analyserPre.connect(filter)
      filter.connect(analyserPost)
      analyserPost.connect(gain)
      gain.connect(ctx.destination)

      audioCtxRef.current = ctx
      filterRef.current = filter
      analyserPreRef.current = analyserPre
      analyserPostRef.current = analyserPost
      gainRef.current = gain
    }
    return audioCtxRef.current
  }

  function ensureNoiseBuffer(ctx) {
    if (!noiseBufferRef.current) {
      const length = Math.round(ctx.sampleRate * NOISE_DURATION_SECONDS)
      const buffer = ctx.createBuffer(1, length, ctx.sampleRate)
      const data = buffer.getChannelData(0)
      for (let i = 0; i < length; i++) {
        data[i] = Math.random() * 2 - 1
      }
      noiseBufferRef.current = buffer
    }
    return noiseBufferRef.current
  }

  function play() {
    const ctx = ensureContext()
    if (ctx.state === 'suspended') ctx.resume()
    const buffer = ensureNoiseBuffer(ctx)

    if (noiseSourceRef.current) {
      try {
        noiseSourceRef.current.stop()
      } catch {
        // already stopped
      }
      noiseSourceRef.current.disconnect()
    }
    const source = ctx.createBufferSource()
    source.buffer = buffer
    source.loop = true
    source.connect(analyserPreRef.current)
    source.start()
    noiseSourceRef.current = source
    setIsPlaying(true)
  }

  function stop() {
    if (noiseSourceRef.current) {
      const src = noiseSourceRef.current
      noiseSourceRef.current = null
      try {
        src.stop()
      } catch {
        // already stopped
      }
      src.disconnect()
    }
    setIsPlaying(false)
  }

  function setFilterType(type) {
    setFilterTypeState(type)
    if (filterRef.current) filterRef.current.type = type
  }

  function setCutoff(freq) {
    setCutoffState(freq)
    if (filterRef.current) filterRef.current.frequency.value = freq
  }

  function setQ(value) {
    setQState(value)
    if (filterRef.current) filterRef.current.Q.value = value
  }

  useEffect(() => {
    return () => {
      stop()
      if (audioCtxRef.current) {
        audioCtxRef.current.close()
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return {
    isPlaying,
    filterType,
    cutoff,
    q,
    play,
    stop,
    setFilterType,
    setCutoff,
    setQ,
    getAnalyserPre: () => analyserPreRef.current,
    getAnalyserPost: () => analyserPostRef.current,
  }
}
