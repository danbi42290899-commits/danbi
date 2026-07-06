import { AUDIOGRAM_FREQUENCIES, LEVEL_MIN_DB, LEVEL_MAX_DB } from '../utils/audiogramFrequencies'
import { HEARING_CATEGORIES } from '../utils/hearingCategories'

const WIDTH = 640
const HEIGHT = 380
const MARGIN = { top: 46, right: 128, bottom: 40, left: 48 }
const PLOT_W = WIDTH - MARGIN.left - MARGIN.right
const PLOT_H = HEIGHT - MARGIN.top - MARGIN.bottom
const FREQ_MIN = 200
const FREQ_MAX = 9500
const Y_TICKS = [-10, 0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100]

function freqToX(freq) {
  const t = Math.log(freq / FREQ_MIN) / Math.log(FREQ_MAX / FREQ_MIN)
  return MARGIN.left + t * PLOT_W
}

function dbToY(db) {
  const clamped = Math.min(LEVEL_MAX_DB, Math.max(LEVEL_MIN_DB, db))
  const t = (clamped - LEVEL_MIN_DB) / (LEVEL_MAX_DB - LEVEL_MIN_DB)
  return MARGIN.top + t * PLOT_H
}

function freqLabel(freq) {
  return freq >= 1000 ? `${freq / 1000}k` : `${freq}`
}

function points(thresholds) {
  return AUDIOGRAM_FREQUENCIES.filter((f) => typeof thresholds?.[f] === 'number').map((f) => ({
    freq: f,
    x: freqToX(f),
    y: dbToY(thresholds[f]),
  }))
}

function polylinePoints(pts) {
  return pts.map((p) => `${p.x},${p.y}`).join(' ')
}

export default function AudiogramChart({ rightThresholds, leftThresholds }) {
  const rightPts = points(rightThresholds)
  const leftPts = points(leftThresholds)

  return (
    <svg
      className="audiogram-chart"
      viewBox={`0 0 ${WIDTH} ${HEIGHT}`}
      role="img"
      aria-label="Pure-tone audiogram chart"
    >
      <rect x={0} y={0} width={WIDTH} height={HEIGHT} className="audiogram-bg" />

      {HEARING_CATEGORIES.map((cat, i) => {
        const yTop = dbToY(cat.min)
        const yBottom = dbToY(Math.min(cat.max, LEVEL_MAX_DB))
        return (
          <g key={cat.id}>
            <rect
              x={MARGIN.left}
              y={yTop}
              width={PLOT_W}
              height={Math.max(0, yBottom - yTop)}
              className="audiogram-band"
              style={{ opacity: 0.06 + i * 0.055 }}
            />
            <text x={MARGIN.left + PLOT_W + 10} y={(yTop + yBottom) / 2 + 3} className="audiogram-band-label">
              {cat.label}
            </text>
          </g>
        )
      })}

      {Y_TICKS.map((db) => (
        <g key={db}>
          <line x1={MARGIN.left} x2={MARGIN.left + PLOT_W} y1={dbToY(db)} y2={dbToY(db)} className="audiogram-gridline" />
          <text x={MARGIN.left - 8} y={dbToY(db) + 3} textAnchor="end" className="audiogram-axis-label">
            {db}
          </text>
        </g>
      ))}

      {AUDIOGRAM_FREQUENCIES.map((freq) => (
        <g key={freq}>
          <line x1={freqToX(freq)} x2={freqToX(freq)} y1={MARGIN.top} y2={MARGIN.top + PLOT_H} className="audiogram-gridline" />
          <text x={freqToX(freq)} y={MARGIN.top + PLOT_H + 20} textAnchor="middle" className="audiogram-axis-label">
            {freqLabel(freq)}
          </text>
        </g>
      ))}

      <text x={MARGIN.left} y={14} className="audiogram-axis-title">
        Relative Hearing Level (dB, uncalibrated)
      </text>

      {rightPts.length > 1 && (
        <polyline points={polylinePoints(rightPts)} className="audiogram-line-right" />
      )}
      {leftPts.length > 1 && (
        <polyline points={polylinePoints(leftPts)} className="audiogram-line-left" />
      )}

      {rightPts.map((p) => (
        <circle key={`r-${p.freq}`} cx={p.x} cy={p.y} r={6} className="audiogram-marker-right" />
      ))}
      {leftPts.map((p) => (
        <g key={`l-${p.freq}`} className="audiogram-marker-left">
          <line x1={p.x - 5} y1={p.y - 5} x2={p.x + 5} y2={p.y + 5} />
          <line x1={p.x - 5} y1={p.y + 5} x2={p.x + 5} y2={p.y - 5} />
        </g>
      ))}

      <g className="audiogram-legend">
        <circle cx={MARGIN.left + 8} cy={32} r={5} className="audiogram-marker-right" />
        <text x={MARGIN.left + 20} y={35} className="audiogram-legend-label">
          Right Ear
        </text>
        <g className="audiogram-marker-left" transform={`translate(${MARGIN.left + 100}, 32)`}>
          <line x1={-5} y1={-5} x2={5} y2={5} />
          <line x1={-5} y1={5} x2={5} y2={-5} />
        </g>
        <text x={MARGIN.left + 114} y={35} className="audiogram-legend-label">
          Left Ear
        </text>
      </g>
    </svg>
  )
}
