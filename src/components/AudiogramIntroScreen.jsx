import { useState } from 'react'

export default function AudiogramIntroScreen({ engine, onStart }) {
  const [referencePlaying, setReferencePlaying] = useState(false)

  const toggleReference = () => {
    if (referencePlaying) {
      engine.stopTone()
      setReferencePlaying(false)
    } else {
      engine.playReferenceTone()
      setReferencePlaying(true)
    }
  }

  const handleStart = () => {
    if (referencePlaying) {
      engine.stopTone()
      setReferencePlaying(false)
    }
    onStart()
  }

  return (
    <div className="screen">
      <h2>Right/Left Ear Test</h2>
      <p className="lede">
        Each ear is tested separately using stereo panning &mdash; the right-ear test
        plays only in your right channel, the left-ear test only in your left. At six
        standard frequencies (250 Hz&ndash;8,000 Hz) the tone gets quieter or louder
        until we find the level where it&apos;s just barely audible.
      </p>

      <div className="hazard-box">
        <div className="hazard-stripe" />
        <div className="hazard-body">
          <h3>CAUTION &mdash; READ BEFORE TESTING</h3>
          <ul>
            <li>
              <strong>Headphones are required</strong>, not optional &mdash; without
              them the left/right separation won&apos;t work and results are
              meaningless.
            </li>
            <li>
              This app is <strong>not a medical diagnostic tool</strong>. If you have
              concerns about your hearing, please consult an audiologist or ENT
              specialist.
            </li>
            <li>
              Use the reference tone below to set a comfortable, moderate volume, then{' '}
              <strong>do not change it</strong> for the rest of the test.
            </li>
            <li>Stop immediately if any sound feels uncomfortable or painful.</li>
          </ul>
        </div>
      </div>

      <button className={referencePlaying ? 'danger-button' : 'secondary-button'} onClick={toggleReference}>
        {referencePlaying ? 'Stop Reference Tone' : 'Play Reference Tone'}
      </button>

      <button className="primary-button" onClick={handleStart}>
        Start Right Ear Test
      </button>
    </div>
  )
}
