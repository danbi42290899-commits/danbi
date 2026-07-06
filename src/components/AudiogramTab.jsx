import { useState } from 'react'
import AudiogramIntroScreen from './AudiogramIntroScreen'
import AudiogramTrialScreen from './AudiogramTrialScreen'
import AudiogramResultScreen from './AudiogramResultScreen'
import { useAudiogramEngine } from '../hooks/useAudiogramEngine'
import { AUDIOGRAM_FREQUENCIES } from '../utils/audiogramFrequencies'

const EAR_ORDER = ['right', 'left']

export default function AudiogramTab() {
  const engine = useAudiogramEngine()
  const [phase, setPhase] = useState('intro') // intro | testing | result
  const [earIndex, setEarIndex] = useState(0)
  const [freqIndex, setFreqIndex] = useState(0)
  const [results, setResults] = useState({ right: {}, left: {} })

  const currentEar = EAR_ORDER[earIndex]
  const currentFreq = AUDIOGRAM_FREQUENCIES[freqIndex]

  // Ear is switched imperatively at each transition (not via an effect keyed
  // on currentEar) so the panner is guaranteed correct before the next
  // trial's first tone plays, instead of depending on effect-ordering
  // between this component and AudiogramTrialScreen.
  const handleStart = () => {
    engine.setEar(EAR_ORDER[0])
    setEarIndex(0)
    setFreqIndex(0)
    setResults({ right: {}, left: {} })
    setPhase('testing')
  }

  const handleTrialComplete = (thresholdDb) => {
    setResults((prev) => ({
      ...prev,
      [currentEar]: { ...prev[currentEar], [currentFreq]: thresholdDb },
    }))

    if (freqIndex + 1 < AUDIOGRAM_FREQUENCIES.length) {
      setFreqIndex(freqIndex + 1)
    } else if (earIndex + 1 < EAR_ORDER.length) {
      engine.setEar(EAR_ORDER[earIndex + 1])
      setEarIndex(earIndex + 1)
      setFreqIndex(0)
    } else {
      setPhase('result')
    }
  }

  return (
    <>
      {phase === 'intro' && <AudiogramIntroScreen engine={engine} onStart={handleStart} />}
      {phase === 'testing' && (
        <AudiogramTrialScreen
          key={`${currentEar}-${currentFreq}`}
          engine={engine}
          ear={currentEar}
          freq={currentFreq}
          onComplete={handleTrialComplete}
        />
      )}
      {phase === 'result' && <AudiogramResultScreen results={results} onRestart={handleStart} />}
    </>
  )
}
