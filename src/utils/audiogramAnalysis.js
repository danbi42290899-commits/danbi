import { classifyLevel } from './hearingCategories'
import { AUDIOGRAM_FREQUENCIES } from './audiogramFrequencies'

const LOW_FREQS = [250, 500, 1000]
const HIGH_FREQS = [4000, 8000]
const PTA_FREQS = [500, 1000, 2000] // standard pure-tone average frequencies
const HIGH_FREQ_DROP_THRESHOLD_DB = 15

function average(thresholds, freqs) {
  const values = freqs.map((f) => thresholds[f]).filter((v) => typeof v === 'number')
  if (values.length === 0) return null
  return values.reduce((sum, v) => sum + v, 0) / values.length
}

// Pure-tone average: the standard clinical summary number for one ear,
// averaging thresholds at 500/1000/2000 Hz.
export function pureToneAverage(thresholds) {
  return average(thresholds, PTA_FREQS)
}

export function classifyEar(thresholds) {
  const pta = pureToneAverage(thresholds)
  return pta == null ? null : classifyLevel(pta)
}

// Flags a high-frequency drop-off pattern: high frequencies notably worse
// (higher threshold) than low frequencies.
export function detectHighFrequencyLoss(thresholds) {
  const lowAvg = average(thresholds, LOW_FREQS)
  const highAvg = average(thresholds, HIGH_FREQS)
  if (lowAvg == null || highAvg == null) return { detected: false, dropDb: 0 }
  const dropDb = highAvg - lowAvg
  return { detected: dropDb >= HIGH_FREQ_DROP_THRESHOLD_DB, dropDb }
}

// The tested frequency with the highest (worst) threshold for one ear —
// i.e. the frequency band where sensitivity drops off the most.
export function worstFrequency(thresholds) {
  let worstFreq = null
  let worstDb = -Infinity
  for (const freq of AUDIOGRAM_FREQUENCIES) {
    const value = thresholds[freq]
    if (typeof value === 'number' && value > worstDb) {
      worstDb = value
      worstFreq = freq
    }
  }
  return worstFreq
}

// Overall category uses the worse-performing ear's PTA (standard clinical
// convention when a single summary category is needed), while the result
// screen still shows each ear's own category individually.
export function overallCategory(rightThresholds, leftThresholds) {
  const rightPta = pureToneAverage(rightThresholds)
  const leftPta = pureToneAverage(leftThresholds)
  const worst = [rightPta, leftPta].filter((v) => v != null).sort((a, b) => b - a)[0]
  return worst == null ? null : classifyLevel(worst)
}
