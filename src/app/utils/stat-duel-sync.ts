export function shouldRevealStatDuelRound(
  myPickCount: number,
  opponentPickCount: number,
  round: number,
  revealedRound: number,
): boolean {
  return myPickCount > round && opponentPickCount > round && revealedRound < round;
}
