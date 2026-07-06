export const MIN_FREQ = 200
export const MAX_FREQ = 30000
export const STEP_COUNT = 28

// Generates frequencies evenly spaced on a log scale, matching how humans
// perceive pitch (each step is an equal multiplicative jump, not additive).
export function generateFrequencySteps(min = MIN_FREQ, max = MAX_FREQ, count = STEP_COUNT) {
  const steps = []
  for (let i = 0; i < count; i++) {
    const t = i / (count - 1)
    const freq = min * Math.pow(max / min, t)
    steps.push(Math.round(freq))
  }
  return steps
}
