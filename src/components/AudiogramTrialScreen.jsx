import { useEffect, useState } from 'react'
import WaveformCanvas from './WaveformCanvas'
import SpectrumCanvas from './SpectrumCanvas'
import { LEVEL_MIN_DB, LEVEL_MAX_DB } from '../utils/audiogramFrequencies'

const MAX_ROUNDS = 6

// Bisects the [LEVEL_MIN_DB, LEVEL_MAX_DB] relative-level range for a single
// fixed frequency, converging on the quietest level the user still reports
// hearing — the same bracketing shape as ConfirmationTestScreen, but over
// level instead of frequency.
export default function AudiogramTrialScreen({ engine, ear, freq, onComplete }) {
  const [lower, setLower] = useState(LEVEL_MIN_DB)
  const [upper, setUpper] = useState(LEVEL_MAX_DB)
  const [round, setRound] = useState(1)

  const candidate = Math.round((lower + upper) / 2)
  const done = round > MAX_ROUNDS || upper - lower <= 1

  useEffect(() => {
    if (done) return undefined
    engine.playToneAtLevel(freq, candidate)
    return () => engine.stopTone()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [candidate, freq, done])

  useEffect(() => {
    if (done) {
      onComplete(upper)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [done])

  if (done) return null

  const respond = (heard) => {
    if (heard) {
      setUpper(candidate)
    } else {
      setLower(candidate)
    }
    setRound((r) => r + 1)
  }

  return (
    <div className="screen">
      <p className="hint">
        {ear === 'right' ? 'RIGHT EAR' : 'LEFT EAR'} &mdash; {freq.toLocaleString('en-US')} Hz
        &mdash; step {round} of {MAX_ROUNDS}
      </p>

      <div className="readout">
        <span className="readout-value">{freq.toLocaleString('en-US')}</span>
        <span className="readout-unit">Hz</span>
      </div>

      <div className="scope-block">
        <p className="scope-label">CH.1 &mdash; TIME DOMAIN (OSCILLOSCOPE)</p>
        <div className="scope-bezel">
          <WaveformCanvas getAnalyser={engine.getAnalyser} />
        </div>
      </div>

      <div className="scope-block">
        <p className="scope-label">CH.2 &mdash; FREQUENCY DOMAIN (FFT SPECTRUM)</p>
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
