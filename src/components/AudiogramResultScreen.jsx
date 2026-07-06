import AudiogramChart from './AudiogramChart'
import HearingProfileAvatar from './HearingProfileAvatar'
import { pureToneAverage, classifyEar, detectHighFrequencyLoss, worstFrequency, overallCategory } from '../utils/audiogramAnalysis'
import { matchHearingProfile } from '../utils/hearingPatterns'

function fmtDb(db) {
  return db == null ? '—' : `${Math.round(db)} dB`
}

function fmtHz(freq) {
  return freq == null ? '—' : `${freq.toLocaleString('en-US')} Hz`
}

function EarResultCard({ label, thresholds }) {
  const pta = pureToneAverage(thresholds)
  const category = classifyEar(thresholds)
  const hf = detectHighFrequencyLoss(thresholds)
  const worstFreq = worstFrequency(thresholds)

  return (
    <div className="result-card ear-result-card">
      <span className="result-label">{label}</span>
      <div className="ear-result-rows">
        <div className="ear-result-row">
          <span>PTA (avg. threshold)</span>
          <span>{fmtDb(pta)}</span>
        </div>
        <div className="ear-result-row">
          <span>Hearing category</span>
          <span>{category ? category.label : '—'}</span>
        </div>
        <div className="ear-result-row">
          <span>High-freq. drop-off</span>
          <span>{hf.detected ? `Yes (~${Math.round(hf.dropDb)} dB)` : 'No'}</span>
        </div>
        <div className="ear-result-row">
          <span>Most affected band</span>
          <span>{fmtHz(worstFreq)}</span>
        </div>
      </div>
    </div>
  )
}

export default function AudiogramResultScreen({ results, onRestart }) {
  const overall = overallCategory(results.right, results.left)
  const profile = matchHearingProfile(results.right, results.left)

  return (
    <div className="screen">
      <h2>Right/Left Ear Test Results</h2>

      {/* 1) Overall category + age-related profile pattern + percentile placeholder */}
      <div className="overall-card">
        <span className="result-label">OVERALL HEARING CATEGORY</span>
        <span className="overall-value">{overall ? overall.label : '—'}</span>

        {profile && (
          <div className="profile-inline">
            <HearingProfileAvatar patternId={profile.id} className="profile-avatar" />
            <div className="profile-text">
              <span className="result-label">HEARING PROFILE</span>
              <p className="profile-description">{profile.description}</p>
            </div>
          </div>
        )}

        <div className="percentile-row">
          <span className="result-label">PERCENTILE</span>
          <span className="result-summary">Requires normative dataset — future feature.</span>
        </div>
      </div>

      {/* 2) Left/Right ear results, left-on-screen-left */}
      <div className="result-grid">
        <EarResultCard label="LEFT EAR RESULT" thresholds={results.left} />
        <EarResultCard label="RIGHT EAR RESULT" thresholds={results.right} />
      </div>

      {/* 3) Audiogram graph */}
      <div className="scope-block">
        <p className="scope-label">AUDIOGRAM GRAPH</p>
        <AudiogramChart rightThresholds={results.right} leftThresholds={results.left} />
      </div>

      <p className="disclaimer">
        <strong>This is not a clinical diagnosis.</strong> Levels shown are relative and
        uncalibrated (not clinical dB HL) — they depend on your device volume and
        headphones. Category names, the high-frequency flag, and the hearing profile are
        rough pattern comparisons for education only. If you have concerns about your
        hearing, please consult an audiologist or ENT specialist.
      </p>

      <button className="primary-button" onClick={onRestart}>
        Test Again
      </button>
    </div>
  )
}
