import { useEffect, useState } from 'react'
import SafetyIntroScreen from './components/SafetyIntroScreen'
import HearingTestScreen from './components/HearingTestScreen'
import ConfirmationTestScreen from './components/ConfirmationTestScreen'
import ResultScreen from './components/ResultScreen'
import FilterLabScreen from './components/FilterLabScreen'
import AudiogramTab from './components/AudiogramTab'
import { useAudioEngine } from './hooks/useAudioEngine'
import './App.css'

function App() {
  const [activeTab, setActiveTab] = useState('hearingTest') // hearingTest | audiogramTest | filterLab
  const [phase, setPhase] = useState('intro') // intro | testing | confirming | result
  const [lastHeardFreq, setLastHeardFreq] = useState(null)
  const [firstNotHeardFreq, setFirstNotHeardFreq] = useState(null)
  const [confirmResult, setConfirmResult] = useState(null)

  const engine = useAudioEngine()

  // If the sweep reaches the end without the user clicking the button,
  // treat it as "heard everything" and move to the result screen.
  useEffect(() => {
    if (engine.isFinished && phase === 'testing') {
      setPhase('result')
    }
  }, [engine.isFinished, phase])

  // Navigating away to the Filter Lab mid-test would otherwise leave the
  // sweep's oscillator playing silently in the background.
  useEffect(() => {
    if (activeTab !== 'hearingTest' && (phase === 'testing' || phase === 'confirming')) {
      engine.stopAtCurrentStep()
      engine.stopTone()
      setPhase('intro')
      setLastHeardFreq(null)
      setFirstNotHeardFreq(null)
      setConfirmResult(null)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeTab])

  const handleStart = () => {
    setLastHeardFreq(null)
    setFirstNotHeardFreq(null)
    setConfirmResult(null)
    setPhase('testing')
    engine.start()
  }

  const handleCantHear = () => {
    const { steps, currentStepIndex } = engine
    engine.stopAtCurrentStep()
    const firstNotHeard = steps[currentStepIndex]
    const lastHeard = currentStepIndex > 0 ? steps[currentStepIndex - 1] : null
    setFirstNotHeardFreq(firstNotHeard)
    setLastHeardFreq(lastHeard)
    // Only run the bracketing confirmation test when there's an actual
    // heard/not-heard boundary to narrow down.
    setPhase(lastHeard != null ? 'confirming' : 'result')
  }

  const handleConfirmationComplete = (result) => {
    setConfirmResult(result)
    setPhase('result')
  }

  return (
    <div className="rack">
      <div className="nameplate">
        <span className="nameplate-model">MODEL HR&#8209;1</span>
        <h1>Frequency Hearing Test</h1>
        <div className="nameplate-sub-row">
          <p>Find the frequency where sound becomes hard to hear</p>
          <span className="credit">MADE BY DB</span>
        </div>
      </div>

      <div className="tab-row">
        <button
          className={`tab-button ${activeTab === 'hearingTest' ? 'active' : ''}`}
          onClick={() => setActiveTab('hearingTest')}
        >
          Hearing Test
        </button>
        <button
          className={`tab-button ${activeTab === 'audiogramTest' ? 'active' : ''}`}
          onClick={() => setActiveTab('audiogramTest')}
        >
          Right/Left Ear Test
        </button>
        <button
          className={`tab-button ${activeTab === 'filterLab' ? 'active' : ''}`}
          onClick={() => setActiveTab('filterLab')}
        >
          Filter Lab
        </button>
      </div>

      <main className="panel">
        {activeTab === 'hearingTest' && (
          <>
            {phase === 'intro' && <SafetyIntroScreen onStart={handleStart} />}
            {phase === 'testing' && (
              <HearingTestScreen engine={engine} onCantHear={handleCantHear} />
            )}
            {phase === 'confirming' && (
              <ConfirmationTestScreen
                engine={engine}
                initialLower={lastHeardFreq}
                initialUpper={firstNotHeardFreq}
                onComplete={handleConfirmationComplete}
              />
            )}
            {phase === 'result' && (
              <ResultScreen
                lastHeardFreq={lastHeardFreq}
                firstNotHeardFreq={firstNotHeardFreq}
                isFinished={engine.isFinished}
                confirmResult={confirmResult}
                onRestart={handleStart}
              />
            )}
          </>
        )}
        {activeTab === 'audiogramTest' && <AudiogramTab />}
        {activeTab === 'filterLab' && <FilterLabScreen />}
      </main>

      <div className="rack-footer">
        {activeTab === 'audiogramTest' ? (
          <>
            <span>250 Hz</span>
            <div className="line" aria-hidden="true"></div>
            <span>right/left ear test</span>
            <div className="line" aria-hidden="true"></div>
            <span>8,000 Hz</span>
          </>
        ) : (
          <>
            <span>200 Hz</span>
            <div className="line" aria-hidden="true"></div>
            <span>log sweep</span>
            <div className="line" aria-hidden="true"></div>
            <span>30,000 Hz</span>
          </>
        )}
      </div>
    </div>
  )
}

export default App
