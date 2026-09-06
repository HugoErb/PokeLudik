import { auctionFormatLabel, getMaximumAuctionBid, normalizeAuctionBudget } from './auction-utils';

describe('auction-utils', () => {
  it('normalise le budget dans les bornes et au pas de dix', () => {
    expect(normalizeAuctionBudget(57)).toBe(60);
    expect(normalizeAuctionBudget(1004)).toBe(1000);
    expect(normalizeAuctionBudget(100_500)).toBe(100_000);
  });

  it('réserve dix Pokédollars par place restante après un achat', () => {
    expect(getMaximumAuctionBid(1000, 0)).toBe(950);
    expect(getMaximumAuctionBid(60, 0)).toBe(10);
    expect(getMaximumAuctionBid(100, 5)).toBe(100);
  });

  it('nomme les trois formats', () => {
    expect(auctionFormatLabel('live')).toBe('Enchère directe');
    expect(auctionFormatLabel('sealed')).toBe('Offres secrètes');
    expect(auctionFormatLabel('turn_based')).toBe('Tours alternés');
  });
});
