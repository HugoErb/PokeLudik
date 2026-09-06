import { AuctionGameSettings } from '../models/room.model';

export const AUCTION_TEAM_SIZE = 6;
export const AUCTION_MIN_BID = 10;
export const AUCTION_DURATION_SECONDS = 15;

export function normalizeAuctionBudget(value: number): number {
  if (!Number.isFinite(value)) return 1000;
  return Math.min(100_000, Math.max(60, Math.round(value / AUCTION_MIN_BID) * AUCTION_MIN_BID));
}

export function getMaximumAuctionBid(balance: number, teamSize: number): number {
  const placesAfterWin = Math.max(0, AUCTION_TEAM_SIZE - teamSize - 1);
  return Math.max(0, balance - placesAfterWin * AUCTION_MIN_BID);
}

export function auctionFormatLabel(format: AuctionGameSettings['auctionFormat']): string {
  if (format === 'sealed') return 'Offres secrètes';
  if (format === 'turn_based') return 'Tours alternés';
  return 'Enchère directe';
}
