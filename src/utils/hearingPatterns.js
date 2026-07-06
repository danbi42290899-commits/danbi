import { pureToneAverage, detectHighFrequencyLoss } from './audiogramAnalysis'
import { classifyLevel } from './hearingCategories'

const ASYMMETRY_THRESHOLD_DB = 15

// Rule-based, deliberately simple pattern matching. This is NOT a diagnosis —
// every description is phrased as "pattern resembles / similar to" so it
// reads as a rough shape comparison, not a clinical finding.
export function matchHearingProfile(rightThresholds, leftThresholds) {
  const rightPta = pureToneAverage(rightThresholds)
  const leftPta = pureToneAverage(leftThresholds)
  if (rightPta == null && leftPta == null) return null

  if (rightPta != null && leftPta != null && Math.abs(rightPta - leftPta) >= ASYMMETRY_THRESHOLD_DB) {
    return {
      id: 'asymmetric',
      label: 'Asymmetric Pattern',
      description:
        'Your two ears show a noticeably different pattern from each other. A side-to-side ' +
        'difference like this is generally worth mentioning to an audiologist, regardless of ' +
        'the overall category.',
    }
  }

  const worsePta = Math.max(rightPta ?? -Infinity, leftPta ?? -Infinity)
  const worseThresholds = (rightPta ?? -Infinity) >= (leftPta ?? -Infinity) ? rightThresholds : leftThresholds
  const worseCategory = classifyLevel(worsePta)

  if (worseCategory.id === 'normal') {
    return {
      id: 'normal',
      label: 'Normal Pattern',
      description:
        'Your hearing profile falls within the typical range at every frequency tested here — ' +
        'no notable pattern of concern shows up in this demo.',
    }
  }

  const hf = detectHighFrequencyLoss(worseThresholds)
  if (hf.detected) {
    return {
      id: 'highFrequencySloping',
      label: 'High-Frequency Sloping Pattern',
      description:
        'Your hearing profile shows a high-frequency drop-off pattern similar to age-related ' +
        'hearing decline, most noticeable around 4,000–8,000 Hz.',
    }
  }

  return {
    id: 'flatLoss',
    label: 'Flat Pattern',
    description:
      'Your hearing profile shows a relatively even reduction across most frequencies, rather ' +
      'than the sloping, high-frequency-only pattern typical of age-related decline.',
  }
}
