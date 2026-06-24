import { shouldRevealStatDuelRound } from './stat-duel-sync';

describe('stat duel sync', () => {
  it("ne révèle pas la manche tant que le pick adverse n'est pas arrivé localement", () => {
    expect(shouldRevealStatDuelRound(1, 0, 0, -1)).toBeFalse();
  });

  it('révèle la manche quand les deux picks sont disponibles et pas encore révélés', () => {
    expect(shouldRevealStatDuelRound(1, 1, 0, -1)).toBeTrue();
  });

  it('ne révèle pas deux fois la même manche', () => {
    expect(shouldRevealStatDuelRound(1, 1, 0, 0)).toBeFalse();
  });
});
