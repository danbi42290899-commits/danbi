export default function SafetyIntroScreen({ onStart }) {
  return (
    <div className="screen">
      <h2>Before You Start</h2>
      <p className="lede">
        This demo plays sine wave tones from low to high frequency so you can find the
        range of frequencies you can hear, while visualizing the sound as a waveform
        and a frequency spectrum (FFT).
      </p>

      <div className="hazard-box">
        <div className="hazard-stripe" />
        <div className="hazard-body">
          <h3>CAUTION — READ BEFORE TESTING</h3>
          <ul>
            <li>
              This app is <strong>not a medical diagnostic tool</strong>. If you have
              concerns about your hearing, please consult an audiologist or ENT
              specialist.
            </li>
            <li>
              Set your device volume to a comfortable, moderate level{' '}
              <strong>before</strong> starting, and do not change it during the test.
            </li>
            <li>Stop immediately if any sound feels uncomfortable or painful.</li>
            <li>Headphones are recommended for the most accurate results.</li>
          </ul>
        </div>
      </div>

      <button className="primary-button" onClick={onStart}>
        Start Test
      </button>
    </div>
  )
}
