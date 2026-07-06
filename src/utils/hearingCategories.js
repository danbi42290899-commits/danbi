// Commonly-cited ASHA-derived degree-of-hearing-loss scale (dB HL).
// https://www.asha.org/public/hearing/degree-of-hearing-loss/
// Some ASHA material further splits "Slight" (16-25) out of Normal; folded
// in here to keep the 6 categories the app surfaces to users.
export const HEARING_CATEGORIES = [
  { id: 'normal', label: 'Normal', min: -10, max: 25 },
  { id: 'mild', label: 'Mild', min: 26, max: 40 },
  { id: 'moderate', label: 'Moderate', min: 41, max: 55 },
  { id: 'moderatelySevere', label: 'Moderately Severe', min: 56, max: 70 },
  { id: 'severe', label: 'Severe', min: 71, max: 90 },
  { id: 'profound', label: 'Profound', min: 91, max: Infinity },
]

export function classifyLevel(db) {
  return (
    HEARING_CATEGORIES.find((c) => db >= c.min && db <= c.max) ??
    HEARING_CATEGORIES[HEARING_CATEGORIES.length - 1]
  )
}
