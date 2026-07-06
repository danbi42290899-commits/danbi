function fmt(freq) {
  return freq != null ? `${freq.toLocaleString('en-US')} Hz` : '—'
}

export default function ResultScreen({
  lastHeardFreq,
  firstNotHeardFreq,
  isFinished,
  confirmResult,
  onRestart,
}) {
  const thresholdLower = confirmResult ? confirmResult.lower : lastHeardFreq
  const thresholdUpper = confirmResult ? confirmResult.upper : firstNotHeardFreq

  return (
    <div className="screen">
      <h2>Your Results</h2>

      {isFinished ? (
        <p className="result-summary">
          You heard the entire tested range (200 Hz – 30,000 Hz). No drop-off point was
          detected.
        </p>
      ) : (
        <>
          <div className="result-grid">
            <div className="result-card">
              <span className="result-label">MAIN SWEEP — FIRST NOT HEARD</span>
              <span className="result-value">{fmt(firstNotHeardFreq)}</span>
            </div>
            <div className="result-card">
              <span className="result-label">MAIN SWEEP — LAST HEARD</span>
              <span className="result-value">{fmt(lastHeardFreq)}</span>
            </div>
          </div>

          {confirmResult && confirmResult.history.length > 0 && (
            <div className="confirm-history">
              <p className="scope-label confirm-history-title">CONFIRMATION TEST RESULTS</p>
              <div className="confirm-history-list">
                {confirmResult.history.map((h, i) => (
                  <span
                    key={i}
                    className={`confirm-chip ${h.heard ? 'chip-heard' : 'chip-not-heard'}`}
                  >
                    {fmt(h.freq)} &middot; {h.heard ? 'Heard' : 'Not Heard'}
                  </span>
                ))}
              </div>
            </div>
          )}

          <div className="result-card result-card-wide">
            <span className="result-label">ESTIMATED HEARING THRESHOLD RANGE</span>
            <span className="result-value">
              {fmt(thresholdLower)} &ndash; {fmt(thresholdUpper)}
            </span>
          </div>

          <p className="result-summary">
            Your hearing sensitivity appears to drop off somewhere in this narrowed
            range.
          </p>
        </>
      )}

      <p className="disclaimer">
        <strong>This is not a clinical diagnosis.</strong> This is a rough self-check
        demo, not a clinical measurement. Results can be affected by your
        speakers/headphones, volume level, and background noise.
      </p>

      <button className="primary-button" onClick={onRestart}>
        Test Again
      </button>
    </div>
  )
}
