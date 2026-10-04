export type RoomStatus = 'waiting' | 'ready' | 'selecting' | 'playing' | 'finished';

export type FirstPlayer = 'player1' | 'player2' | 'random';

export interface GameSettings {
  generations: number[];  // [] = toutes les générations
  categories: string[];   // [] = toutes les catégories
  noPokedex: boolean;     // cache tout sauf le nom
  noSearch: boolean;      // désactive les filtres avancés (garde la recherche par nom)
  firstPlayer: FirstPlayer; // qui joue en premier
  randomPokemon: boolean; // assigne un Pokémon aléatoire à chaque joueur
}

export const DEFAULT_SETTINGS: GameSettings = {
  generations: [],
  categories: [],
  noPokedex: false,
  noSearch: false,
  firstPlayer: 'random',
  randomPokemon: false,
};

export interface WhoGameSettings {
  generations: number[];
  categories: string[];
  initialHint: 'silhouette' | 'cry' | 'pokedex_number' | 'description' | 'random';
}

export const DEFAULT_WHO_SETTINGS: WhoGameSettings = {
  generations: [],
  categories: [],
  initialHint: 'silhouette',
};

export interface SizeUpGameSettings {
  generations: number[];
  categories: string[];
  /** Durée d'une manche en secondes, 0 = sans limite. */
  roundTimer: number;
}

export const DEFAULT_SIZE_UP_SETTINGS: SizeUpGameSettings = {
  generations: [],
  categories: [],
  roundTimer: 0,
};

export interface Room {
  id: string;
  player1_id: string;
  player2_id: string | null;
  pokemon_p1: number | null;
  pokemon_p2: number | null;
  p1_ready: boolean;
  p2_ready: boolean;
  current_turn: string | null;
  status: RoomStatus;
  winner_id: string | null;
  created_at: string;
  settings: GameSettings | null;
  last_guess: number | null;
  /** Incrémentée à chaque mise à jour : permet d'ignorer un état périmé. */
  version?: number;
}

export type RoomPatch = Partial<Omit<Room, 'id' | 'created_at' | 'player1_id'>>;

export interface Profile {
  id: string;
  username: string;
  avatar_url?: string;
  created_at: string;
}

export interface Friendship {
  id: string;
  requester_id: string;
  recipient_id: string;
  status: 'pending' | 'accepted';
  created_at: string;
}

export type GameMode = 'guess_my_pokemon' | 'stat_duel' | 'draft_duo' | 'who_that_pokemon' | 'pokemon_auction' | 'size_up';

export type AuctionFormat = 'live' | 'sealed' | 'turn_based';

export interface AuctionGameSettings {
  generations: number[];
  categories: string[];
  auctionFormat: AuctionFormat;
  startingBudget: number;
  randomAwardOnNoBid: boolean;
}

export interface AuctionResult {
  pokemonId: number;
  outcome: 'purchased' | 'free' | 'blocked' | 'tied' | 'unsold';
  winner: 'player1' | 'player2' | null;
  price: number;
  p1Bid?: number;
  p2Bid?: number;
  round: number;
  forced?: boolean;
}

export interface PokemonAuctionRoom {
  id: string;
  player1_id: string;
  player2_id: string | null;
  status: 'waiting' | 'playing' | 'finished';
  settings: AuctionGameSettings | null;
  p1_team: number[];
  p2_team: number[];
  p1_balance: number;
  p2_balance: number;
  current_pokemon_id: number | null;
  used_pokemon_ids: number[];
  requeue_pokemon_ids: number[];
  p1_passes_left: number;
  p2_passes_left: number;
  round: number;
  auction_start_at: string | null;
  auction_end_at: string | null;
  current_bid: number;
  current_bidder: 'player1' | 'player2' | null;
  current_turn: 'player1' | 'player2' | null;
  p1_passed: boolean;
  p2_passed: boolean;
  p1_bid_submitted: boolean;
  p2_bid_submitted: boolean;
  last_result: AuctionResult | null;
  p1_stats_score: number | null;
  p2_stats_score: number | null;
  p1_coverage_score: number | null;
  p2_coverage_score: number | null;
  p1_final_score: number | null;
  p2_final_score: number | null;
  winner: 'player1' | 'player2' | 'draw' | null;
  p1_ready: boolean;
  p2_ready: boolean;
  created_at: string;
  p1_pass_used?: boolean;
  p2_pass_used?: boolean;
  /** Incrémentée à chaque mise à jour : permet d'ignorer un état périmé. */
  version?: number;
}

export interface GameInvite {
  id: string;
  sender_id: string;
  recipient_id: string;
  room_id: string;
  game_mode: GameMode;
  status: 'pending' | 'accepted' | 'declined';
  created_at: string;
  sender_profile?: { username: string };
}

export interface StatPick {
  stat: string;
  value: number;
}

export interface StatDuelRoom {
  id: string;
  player1_id: string;
  player2_id: string | null;
  status: 'waiting' | 'playing' | 'finished';
  pokemon_ids: number[];
  p1_picks: StatPick[];
  p2_picks: StatPick[];
  round_start_at: string | null;
  winner: 'player1' | 'player2' | 'draw' | null;
  p1_ready: boolean;
  p2_ready: boolean;
  settings: GameSettings | null;
  created_at: string;
}

export interface DraftDuoRoom {
  id: string;
  player1_id: string;
  player2_id: string | null;
  status: 'waiting' | 'playing' | 'finished';
  p1_team: number[];
  p2_team: number[];
  winner: 'player1' | 'player2' | 'draw' | null;
  p1_ready: boolean;
  p2_ready: boolean;
  settings: GameSettings | null;
  created_at: string;
}

export interface WhoPokemonRoom {
  id: string;
  player1_id: string;
  player2_id: string | null;
  status: 'waiting' | 'playing' | 'finished';
  settings: WhoGameSettings | null;
  round: number;
  target_pokemon_id: number | null;
  used_pokemon_ids: number[];
  p1_score: number;
  p2_score: number;
  p1_lives: number;
  p2_lives: number;
  winner: 'player1' | 'player2' | 'draw' | null;
  p1_ready: boolean;
  p2_ready: boolean;
  created_at: string;
}

/** Manche jouée en duo Size Up, telle que stockée dans `size_up_rooms.history`. */
export interface SizeUpHistoryEntry {
  round: number;
  reference_id: number;
  target_id: number;
  p1_guess: number | null;
  p2_guess: number | null;
  p1_points: number;
  p2_points: number;
}

export interface SizeUpRoom {
  id: string;
  player1_id: string;
  player2_id: string | null;
  status: 'waiting' | 'playing' | 'finished';
  settings: SizeUpGameSettings | null;
  round: number;
  round_phase: 'guessing' | 'reveal';
  reference_pokemon_id: number | null;
  target_pokemon_id: number | null;
  used_pokemon_ids: number[];
  round_deadline: string | null;
  reveal_until: string | null;
  /** Les estimations restent secrètes côté serveur jusqu'à la révélation. */
  p1_submitted: boolean;
  p2_submitted: boolean;
  p1_score: number;
  p2_score: number;
  history: SizeUpHistoryEntry[];
  winner: 'player1' | 'player2' | 'draw' | null;
  p1_ready: boolean;
  p2_ready: boolean;
  created_at: string;
  /** Incrémentée à chaque mise à jour : permet d'ignorer un état périmé. */
  version?: number;
}

export type FriendStatus = 'online' | 'in_game' | 'offline';

export interface FriendWithStatus {
  id: string;
  friendId: string;
  username: string;
  avatarUrl?: string;
  status: FriendStatus;
}

export interface FriendRequest {
  id: string;
  requesterId: string;
  username: string;
  avatarUrl?: string;
}
