type ScoreRingProps = {
  score: number;
};

export function ScoreRing({ score }: ScoreRingProps) {
  return (
    <div className="score-ring" style={{ "--score": score } as React.CSSProperties} role="img" aria-label={`Sleep score ${score} out of 100`}>
      <div><strong>{score}</strong><span>score</span></div>
    </div>
  );
}
