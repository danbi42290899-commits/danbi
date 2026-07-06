import WaveformCanvas from './WaveformCanvas'
import SpectrumCanvas from './SpectrumCanvas'

export default function HearingTestScreen({ engine, onCantHear }) {
  const { currentFrequency, getAnalyser } = engine

  return (
    <div className="screen">
      <h2>Listening Test in Progress</h2>

      <div className="readout">
        <span className="readout-value">
          {currentFrequency ? currentFrequency.toLocaleString('en-US') : '—'}
        </span>
        <span className="readout-unit">Hz</span>
      </div>
      <p className="hint">Frequency is sweeping from low to high on a logarithmic scale.</p>

      <div className="scope-block">
        <p className="scope-label">CH.1 — TIME DOMAIN (OSCILLOSCOPE)</p>
        <div className="scope-bezel">
          <WaveformCanvas getAnalyser={getAnalyser} />
        </div>
      </div>

      <div className="scope-block">
        <p className="scope-label">CH.2 — FREQUENCY DOMAIN (FFT SPECTRUM)</p>
        <div className="scope-bezel">
          <SpectrumCanvas getAnalyser={getAnalyser} />
        </div>
        <div className="axis-ticks">
          <span>200</span>
          <span>1k</span>
          <span>10k</span>
          <span>30k Hz</span>
        </div>
      </div>

      <button className="danger-button" onClick={onCantHear}>
        Can&apos;t hear from here
      </button>
    </div>
  )
}
