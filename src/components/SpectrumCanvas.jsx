import { useEffect, useRef } from 'react'
import { MIN_FREQ, MAX_FREQ } from '../utils/frequencySteps'

const PEAK_THRESHOLD = 40 // ignore noise-floor "peaks" when nothing audible is playing

function freqToX(freq, width) {
  const t = Math.log(freq / MIN_FREQ) / Math.log(MAX_FREQ / MIN_FREQ)
  return t * width
}

export default function SpectrumCanvas({ getAnalyser }) {
  const canvasRef = useRef(null)
  const rafRef = useRef(null)

  useEffect(() => {
    const canvas = canvasRef.current
    const ctx = canvas.getContext('2d')
    const { width, height } = canvas
    const styles = getComputedStyle(document.documentElement)
    const bezelColor = styles.getPropertyValue('--scope-bezel').trim()
    const gridColor = styles.getPropertyValue('--scope-grid').trim()
    const lineColor = styles.getPropertyValue('--spectrum-line').trim()
    const labelColor = styles.getPropertyValue('--readout-fg').trim()

    function drawGrid() {
      ctx.strokeStyle = gridColor
      ctx.lineWidth = 1
      ctx.beginPath()
      ;[0.25, 0.5, 0.75].forEach((f) => {
        const y = Math.round(height * (1 - f)) + 0.5
        ctx.moveTo(0, y)
        ctx.lineTo(width, y)
      })
      ;[1000, 10000].forEach((freq) => {
        const x = Math.round(freqToX(freq, width)) + 0.5
        ctx.moveTo(x, 0)
        ctx.lineTo(x, height)
      })
      ctx.stroke()
    }

    function draw() {
      const analyser = getAnalyser()
      ctx.fillStyle = bezelColor
      ctx.fillRect(0, 0, width, height)
      drawGrid()

      if (analyser) {
        const bufferLength = analyser.frequencyBinCount
        const freqData = new Uint8Array(bufferLength)
        analyser.getByteFrequencyData(freqData)

        const sampleRate = analyser.context.sampleRate
        const binWidth = sampleRate / analyser.fftSize

        // Map each pixel column to a frequency on a log scale (matching the
        // sweep's log-spaced steps), then linearly interpolate between the
        // two nearest FFT bins so the trace reads as a smooth curve instead
        // of a bin-quantized staircase.
        const points = new Array(width)
        let peak = null
        for (let x = 0; x < width; x++) {
          const t = x / width
          const freq = MIN_FREQ * Math.pow(MAX_FREQ / MIN_FREQ, t)
          const binPos = freq / binWidth
          const binLow = Math.min(bufferLength - 1, Math.floor(binPos))
          const binHigh = Math.min(bufferLength - 1, binLow + 1)
          const frac = binPos - binLow
          const value = freqData[binLow] * (1 - frac) + freqData[binHigh] * frac
          const y = height - (value / 255) * height
          points[x] = y
          if (!peak || value > peak.value) peak = { x, y, value, freq }
        }

        // Gradient area fill under the curve.
        ctx.beginPath()
        ctx.moveTo(0, height)
        for (let x = 0; x < width; x++) ctx.lineTo(x, points[x])
        ctx.lineTo(width, height)
        ctx.closePath()
        const gradient = ctx.createLinearGradient(0, 0, 0, height)
        gradient.addColorStop(0, lineColor + '59') // ~35% alpha
        gradient.addColorStop(1, lineColor + '00')
        ctx.fillStyle = gradient
        ctx.fill()

        // Smooth line trace.
        ctx.beginPath()
        for (let x = 0; x < width; x++) {
          if (x === 0) ctx.moveTo(x, points[x])
          else ctx.lineTo(x, points[x])
        }
        ctx.lineWidth = 2
        ctx.strokeStyle = lineColor
        ctx.shadowColor = lineColor
        ctx.shadowBlur = 5
        ctx.stroke()
        ctx.shadowBlur = 0

        // Emphasized peak marker + direct label.
        if (peak && peak.value > PEAK_THRESHOLD) {
          ctx.beginPath()
          ctx.fillStyle = lineColor
          ctx.shadowColor = lineColor
          ctx.shadowBlur = 14
          ctx.arc(peak.x, peak.y, 4, 0, Math.PI * 2)
          ctx.fill()
          ctx.shadowBlur = 0

          // Anchor the label beside the dot, flipping side so it never
          // runs off the left/right edge of the canvas.
          const peakFreq = Math.round(peak.freq)
          const labelOnRight = peak.x < width / 2
          const labelY = Math.min(Math.max(peak.y - 8, 12), height - 12)
          ctx.font = "700 12px 'HRMono', ui-monospace, monospace"
          ctx.fillStyle = labelColor
          ctx.textBaseline = 'middle'
          ctx.textAlign = labelOnRight ? 'left' : 'right'
          ctx.fillText(
            `PEAK: ${peakFreq.toLocaleString('en-US')} Hz`,
            peak.x + (labelOnRight ? 10 : -10),
            labelY,
          )
        }
      }

      rafRef.current = requestAnimationFrame(draw)
    }

    draw()
    return () => cancelAnimationFrame(rafRef.current)
  }, [getAnalyser])

  return <canvas ref={canvasRef} width={640} height={200} className="scope-canvas" />
}
