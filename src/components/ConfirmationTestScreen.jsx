import { useEffect, useState } from 'react'
import WaveformCanvas from './WaveformCanvas'
import SpectrumCanvas from './SpectrumCanvas'

const MAX_ROUNDS = 4

export default function ConfirmationTestScreen({ engine, initialLower, initialUpper, onComplete }) {
  const [lower, setLower] = useState(initialLower)
  const [upper, setUpper] = useState(initialUpper)
  const [round, setRound] = useState(1)
  const [history, setHistory] = useState([])

  const candidate = Math.round((lower + upper) / 2)
  const done = round > MAX_ROUNDS || upper - lower <= 1 || candidate <= lower || candidate >= upper

  // Play the current candidate tone continuously until the user responds.
  useEffect(() => {
    if (done) return undefined
    engine.playTone(candidate)
    return () => engine.stopTone()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [candidate, done])

  useEffect(() => {
    if (done) {
      onComplete({ lower, upper, history })
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [done])

  if (done) return null

  const respond = (heard) => {
    setHistory((h) => [...h, { freq: candidate, heard }])
    if (heard) {
      setLower(candidate)
    } else {
      setUpper(candidate)
    }
    setRound((r) => r + 1)
  }

  return (
    <div className="screen">
      <h2>Confirmation Test</h2>
      <p className="hint">
        Step {round} of {MAX_ROUNDS} &mdash; narrowing in between {lower.toLocaleString('en-US')} Hz
        and {upper.toLocaleString('en-US')} Hz
      </p>

      <div className="readout">
        <span className="readout-value">{candidate.toLocaleString('en-US')}</span>
        <span className="readout-unit">Hz</span>
      </div>

      <div className="scope-block">
        <p className="scope-label">CH.1 — TIME DOMAIN (OSCILLOSCOPE)</p>
        <div className="scope-bezel">
          <WaveformCanvas getAnalyser={engine.getAnalyser} />
        </div>
      </div>

      <div className="scope-block">
        <p className="scope-label">CH.2 — FREQUENCY DOMAIN (FFT SPECTRUM)</p>
        <div className="scope-bezel">
          <SpectrumCanvas getAnalyser={engine.getAnalyser} />
        </div>
      </div>

      <div className="confirm-buttons">
        <button className="primary-button" onClick={() => respond(true)}>
          Heard
        </button>
        <button className="danger-button" onClick={() => respond(false)}>
          Not Heard
        </button>
      </div>
    </div>
  )
}
