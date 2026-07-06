// Standard octave audiometric test frequencies (ISO/ASHA pure-tone audiometry).
export const AUDIOGRAM_FREQUENCIES = [250, 500, 1000, 2000, 4000, 8000]

// Relative-level range used for the bracketing search at each frequency.
// Not calibrated dB SPL/HL — see useAudiogramEngine.js for why.
export const LEVEL_MIN_DB = -10
export const LEVEL_MAX_DB = 100
