// Minimalist line-art glyphs (not cartoon avatars) matching the instrument
// panel's technical style, one per hearingPatterns.js pattern id.
const PATHS = {
  normal: (
    <path d="M4 32 h10 l4 -14 l6 24 l6 -18 l6 12 l6 -8 l22 4" />
  ),
  highFrequencySloping: (
    <>
      <path d="M4 12 v44 M4 56 h56" opacity="0.35" />
      <rect x="9" y="18" width="7" height="38" />
      <rect x="20" y="24" width="7" height="32" />
      <rect x="31" y="32" width="7" height="24" />
      <rect x="42" y="42" width="7" height="14" />
      <rect x="53" y="48" width="7" height="8" />
    </>
  ),
  flatLoss: (
    <>
      <path d="M4 12 v44 M4 56 h56" opacity="0.35" />
      <path d="M4 22 h56" strokeDasharray="3 3" opacity="0.5" />
      <rect x="9" y="34" width="7" height="22" />
      <rect x="20" y="34" width="7" height="22" />
      <rect x="31" y="34" width="7" height="22" />
      <rect x="42" y="34" width="7" height="22" />
      <rect x="53" y="34" width="7" height="22" />
    </>
  ),
  asymmetric: (
    <>
      <path d="M16 8 v48 M48 8 v48" opacity="0.35" />
      <rect x="8" y="18" width="16" height="38" />
      <rect x="40" y="38" width="16" height="18" />
      <text x="16" y="14" fontSize="9" textAnchor="middle" stroke="none" fill="currentColor">
        L
      </text>
      <text x="48" y="14" fontSize="9" textAnchor="middle" stroke="none" fill="currentColor">
        R
      </text>
    </>
  ),
}

export default function HearingProfileAvatar({ patternId, className }) {
  const content = PATHS[patternId] ?? PATHS.normal
  return (
    <svg
      className={className}
      viewBox="0 0 64 64"
      width="56"
      height="56"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {content}
    </svg>
  )
}
