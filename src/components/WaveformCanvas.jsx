import { useEffect, useRef } from 'react'

export default function WaveformCanvas({ getAnalyser }) {
  const canvasRef = useRef(null)
  const rafRef = useRef(null)

  useEffect(() => {
    const canvas = canvasRef.current
    const ctx = canvas.getContext('2d')
    const { width, height } = canvas
    const styles = getComputedStyle(document.documentElement)
    const bezelColor = styles.getPropertyValue('--scope-bezel').trim()
    const traceColor = styles.getPropertyValue('--scope-green').trim()

    function draw() {
      const analyser = getAnalyser()
      ctx.fillStyle = bezelColor
      ctx.fillRect(0, 0, width, height)

      if (analyser) {
        const bufferLength = analyser.fftSize
        const dataArray = new Uint8Array(bufferLength)
        analyser.getByteTimeDomainData(dataArray)

        ctx.lineWidth = 2
        ctx.strokeStyle = traceColor
        ctx.beginPath()

        const sliceWidth = width / bufferLength
        let x = 0
        for (let i = 0; i < bufferLength; i++) {
          const v = dataArray[i] / 128.0
          const y = (v * height) / 2
          if (i === 0) {
            ctx.moveTo(x, y)
          } else {
            ctx.lineTo(x, y)
          }
          x += sliceWidth
        }
        ctx.stroke()
      }

      rafRef.current = requestAnimationFrame(draw)
    }

    draw()
    return () => cancelAnimationFrame(rafRef.current)
  }, [getAnalyser])

  return <canvas ref={canvasRef} width={640} height={200} className="scope-canvas" />
}
