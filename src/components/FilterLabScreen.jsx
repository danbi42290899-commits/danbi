import { useFilterLab } from '../hooks/useFilterLab'
import SpectrumCanvas from './SpectrumCanvas'
import { MIN_FREQ, MAX_FREQ } from '../utils/frequencySteps'

const FILTER_TYPES = [
  { id: 'lowpass', label: 'Low-Pass' },
  { id: 'highpass', label: 'High-Pass' },
  { id: 'bandpass', label: 'Band-Pass' },
]

function freqFromSlider(t) {
  return Math.round(MIN_FREQ * Math.pow(MAX_FREQ / MIN_FREQ, t))
}

function sliderFromFreq(freq) {
  return Math.log(freq / MIN_FREQ) / Math.log(MAX_FREQ / MIN_FREQ)
}

export default function FilterLabScreen() {
  const lab = useFilterLab()

  return (
    <div className="screen">
      <h2>Digital Filter Lab</h2>
      <p className="lede">
        A white-noise test signal (equal energy at every frequency) runs through a
        biquad filter. Compare the FFT spectrum before and after to see which
        frequencies the filter removes.
      </p>

      <div className="filter-type-row">
        {FILTER_TYPES.map((f) => (
          <button
            key={f.id}
            className={`filter-type-button ${lab.filterType === f.id ? 'active' : ''}`}
            onClick={() => lab.setFilterType(f.id)}
          >
            {f.label}
          </button>
        ))}
      </div>

      <div className="filter-slider-row">
        <label className="filter-slider-label" htmlFor="cutoff-slider">
          {lab.filterType === 'bandpass' ? 'Center Frequency' : 'Cutoff Frequency'}:{' '}
          {lab.cutoff.toLocaleString('en-US')} Hz
        </label>
        <input
          id="cutoff-slider"
          className="filter-slider"
          type="range"
          min="0"
          max="1"
          step="0.001"
          value={sliderFromFreq(lab.cutoff)}
          onChange={(e) => lab.setCutoff(freqFromSlider(Number(e.target.value)))}
        />
      </div>

      {lab.filterType === 'bandpass' && (
        <div className="filter-slider-row">
          <label className="filter-slider-label" htmlFor="q-slider">
            Bandwidth (Q): {lab.q.toFixed(1)}
          </label>
          <input
            id="q-slider"
            className="filter-slider"
            type="range"
            min="0.2"
            max="10"
            step="0.1"
            value={lab.q}
            onChange={(e) => lab.setQ(Number(e.target.value))}
          />
        </div>
      )}

      <button
        className={lab.isPlaying ? 'danger-button' : 'primary-button'}
        onClick={lab.isPlaying ? lab.stop : lab.play}
      >
        {lab.isPlaying ? 'Stop Test Signal' : 'Play Test Signal'}
      </button>

      <div className="scope-block">
        <p className="scope-label">BEFORE FILTER &mdash; WHITE NOISE</p>
        <div className="scope-bezel">
          <SpectrumCanvas getAnalyser={lab.getAnalyserPre} />
        </div>
        <div className="axis-ticks">
          <span>200</span>
          <span>1k</span>
          <span>10k</span>
          <span>30k Hz</span>
        </div>
      </div>

      <div className="scope-block">
        <p className="scope-label">AFTER FILTER</p>
        <div className="scope-bezel">
          <SpectrumCanvas getAnalyser={lab.getAnalyserPost} />
        </div>
        <div className="axis-ticks">
          <span>200</span>
          <span>1k</span>
          <span>10k</span>
          <span>30k Hz</span>
        </div>
      </div>
    </div>
  )
}
