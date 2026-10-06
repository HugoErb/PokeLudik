import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';

// Vérifie sql-schema/migrations/2026-10-06-securite-rpc.sql dans une base PGlite minimale :
// chaque flux envoyé par le client Angular doit passer, chaque tentative de triche doit échouer.
// Les tables reprennent les définitions de sql-schema/ddb-schema.sql.

const db = new PGlite();
const p1 = '00000000-0000-4000-8000-000000000001';
const p2 = '00000000-0000-4000-8000-000000000002';
const outsider = '00000000-0000-4000-8000-000000000003';
let roomCounter = 0;
const newRoomId = () => `10000000-0000-4000-8000-${String(++roomCounter).padStart(12, '0')}`;

async function asUser(id, sql, params = []) {
  await db.query("SELECT set_config('request.jwt.claim.sub',$1,false)", [id]);
  await db.exec('SET ROLE authenticated');
  try { return await db.query(sql, params); }
  finally { await db.exec('RESET ROLE'); }
}

const rpc = (fn, user, roomId, patch) => asUser(user, `SELECT public.${fn}($1,$2::jsonb)`, [roomId, JSON.stringify(patch)]);
const guessUpdate = (user, roomId, patch) => rpc('update_guess_pokemon_room', user, roomId, patch);
const whoUpdate = (user, roomId, patch) => rpc('update_who_that_pokemon_room', user, roomId, patch);
const statUpdate = (user, roomId, patch) => rpc('update_stat_duel_room', user, roomId, patch);
const draftUpdate = (user, roomId, patch) => rpc('update_draft_duo_room', user, roomId, patch);
const appendPick = (user, roomId, column, pick) => asUser(user, 'SELECT public.append_stat_pick($1,$2,$3::jsonb)', [roomId, column, JSON.stringify(pick)]);
const row = async (table, id) => (await db.query(`SELECT * FROM public.${table} WHERE id=$1`, [id])).rows[0];

try {
  await db.exec(`
    CREATE ROLE anon; CREATE ROLE authenticated;
    CREATE SCHEMA auth;
    CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
      SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
    $$;
    GRANT USAGE ON SCHEMA auth TO authenticated, anon;
    GRANT USAGE ON SCHEMA public TO authenticated, anon;

    CREATE TYPE public.room_status AS ENUM ('waiting','ready','selecting','playing','finished');
    CREATE TABLE public.pokemon_catalog (
      id integer PRIMARY KEY, generation integer NOT NULL, category text NOT NULL,
      types text[] DEFAULT '{}' NOT NULL, rating numeric(3,1) DEFAULT 0 NOT NULL,
      pv integer NOT NULL, attaque integer NOT NULL, defense integer NOT NULL,
      atq_spe integer NOT NULL, def_spe integer NOT NULL, vitesse integer NOT NULL);
    CREATE TABLE public.guess_pokemon_rooms (
      id uuid PRIMARY KEY, player1_id uuid NOT NULL, player2_id uuid, pokemon_p1 integer, pokemon_p2 integer,
      p1_ready boolean DEFAULT false NOT NULL, p2_ready boolean DEFAULT false NOT NULL, current_turn uuid,
      status public.room_status DEFAULT 'waiting' NOT NULL, winner_id uuid, created_at timestamptz DEFAULT now() NOT NULL,
      settings jsonb, last_guess integer);
    CREATE TABLE public.who_that_pokemon_rooms (
      id uuid PRIMARY KEY, player1_id uuid NOT NULL, player2_id uuid, status text DEFAULT 'waiting' NOT NULL,
      settings jsonb, round integer DEFAULT 1 NOT NULL, target_pokemon_id integer,
      used_pokemon_ids integer[] DEFAULT '{}' NOT NULL, p1_score integer DEFAULT 0 NOT NULL, p2_score integer DEFAULT 0 NOT NULL,
      p1_lives integer DEFAULT 0 NOT NULL, p2_lives integer DEFAULT 0 NOT NULL, winner text,
      p1_ready boolean DEFAULT false NOT NULL, p2_ready boolean DEFAULT false NOT NULL, created_at timestamptz DEFAULT now() NOT NULL,
      CHECK (status IN ('waiting','playing','finished')), CHECK (winner IS NULL OR winner IN ('player1','player2','draw')));
    CREATE TABLE public.stat_duel_rooms (
      id uuid PRIMARY KEY, player1_id uuid NOT NULL, player2_id uuid, status text DEFAULT 'waiting',
      pokemon_ids integer[] DEFAULT '{}', p1_picks jsonb DEFAULT '[]', p2_picks jsonb DEFAULT '[]',
      round_start_at timestamptz, winner text, created_at timestamptz DEFAULT now(),
      p1_ready boolean DEFAULT false NOT NULL, p2_ready boolean DEFAULT false NOT NULL, settings jsonb,
      CHECK (status IN ('waiting','playing','finished')));
    CREATE TABLE public.draft_duo_rooms (
      id uuid PRIMARY KEY, player1_id uuid NOT NULL, player2_id uuid, status text DEFAULT 'waiting' NOT NULL,
      p1_team integer[] DEFAULT '{}' NOT NULL, p2_team integer[] DEFAULT '{}' NOT NULL, winner text,
      created_at timestamptz DEFAULT now() NOT NULL, p1_ready boolean DEFAULT false NOT NULL,
      p2_ready boolean DEFAULT false NOT NULL, settings jsonb, CHECK (status IN ('waiting','playing','finished')));
    CREATE FUNCTION public.draft_final_score(team integer[], opponent integer[]) RETURNS numeric
      LANGUAGE sql AS $$ SELECT coalesce(sum(t), 0)::numeric FROM unnest(team) AS t $$;

    CREATE TABLE public.friendships (
      id uuid DEFAULT gen_random_uuid() PRIMARY KEY, requester_id uuid NOT NULL, recipient_id uuid NOT NULL,
      status text DEFAULT 'pending' NOT NULL, created_at timestamptz DEFAULT now() NOT NULL,
      CHECK (status IN ('pending','accepted')));
    CREATE TABLE public.game_invites (
      id uuid DEFAULT gen_random_uuid() PRIMARY KEY, sender_id uuid NOT NULL, recipient_id uuid NOT NULL,
      room_id uuid NOT NULL, status text DEFAULT 'pending' NOT NULL, created_at timestamptz DEFAULT now() NOT NULL,
      game_mode text DEFAULT 'guess_my_pokemon' NOT NULL, CHECK (status IN ('pending','accepted','declined')));
    ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;
    ALTER TABLE public.game_invites ENABLE ROW LEVEL SECURITY;
    CREATE POLICY friendships_select ON public.friendships FOR SELECT TO authenticated USING ((auth.uid() = requester_id) OR (auth.uid() = recipient_id));
    CREATE POLICY friendships_update_accept ON public.friendships FOR UPDATE TO authenticated
      USING ((auth.uid() = recipient_id) AND (status = 'pending')) WITH CHECK ((auth.uid() = recipient_id) AND (status = 'accepted'));
    CREATE POLICY game_invites_select ON public.game_invites FOR SELECT TO authenticated USING ((auth.uid() = sender_id) OR (auth.uid() = recipient_id));
    CREATE POLICY game_invites_update_recipient ON public.game_invites FOR UPDATE TO authenticated
      USING ((auth.uid() = recipient_id) AND (status = 'pending')) WITH CHECK ((auth.uid() = recipient_id) AND (status IN ('accepted','declined')));
    GRANT ALL ON TABLE public.friendships TO anon, authenticated;
    GRANT ALL ON TABLE public.game_invites TO anon, authenticated;

    INSERT INTO public.pokemon_catalog(id,generation,category,pv,attaque,defense,atq_spe,def_spe,vitesse) VALUES
      (1,1,'normal',10,20,30,40,50,60),(2,1,'normal',61,51,41,31,21,11),(3,1,'normal',5,5,5,5,5,5),
      (4,1,'normal',7,7,7,7,7,7),(5,1,'normal',9,9,9,9,9,9),(6,1,'normal',3,3,3,3,3,3);
  `);
  const migration = readFileSync(new URL('../sql-schema/migrations/2026-10-06-securite-rpc.sql', import.meta.url), 'utf8');
  await db.exec(migration);
  await db.exec(migration); // idempotente
  await db.exec(`GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;`);

  // ─── Guess my Pokémon ─────────────────────────────────────────────────────
  const newGuessRoom = async (fields) => {
    const id = newRoomId();
    const cols = { id, player1_id: p1, player2_id: p2, status: 'ready', ...fields };
    const keys = Object.keys(cols);
    await db.query(`INSERT INTO public.guess_pokemon_rooms(${keys.join(',')}) VALUES (${keys.map((_, i) => `$${i + 1}`).join(',')})`, Object.values(cols));
    return id;
  };

  // Flux normal : lancement → sélection → prêt → partie (les deux joueurs envoient le passage en jeu).
  let guess = await newGuessRoom({});
  await guessUpdate(p1, guess, { status: 'selecting', settings: { firstPlayer: 'player1' } });
  await guessUpdate(p1, guess, { settings: { firstPlayer: 'player2' } });
  await guessUpdate(p1, guess, { pokemon_p1: 1 });
  await guessUpdate(p2, guess, { pokemon_p2: 2 });
  await guessUpdate(p2, guess, { pokemon_p2: 3 }); // changement d'avis pendant la sélection
  await guessUpdate(p1, guess, { p1_ready: true });
  await assert.rejects(guessUpdate(p1, guess, { status: 'playing', current_turn: p1 }), /players_not_ready/);
  await guessUpdate(p2, guess, { p2_ready: true });
  await guessUpdate(p2, guess, { status: 'playing', current_turn: p2 });
  await guessUpdate(p1, guess, { status: 'playing', current_turn: p1 }); // second lancement concurrent : sans effet
  let g = await row('guess_pokemon_rooms', guess);
  assert.equal(g.status, 'playing');
  assert.equal(g.current_turn, p2);
  assert.equal(g.pokemon_p2, 3);

  // Triches pendant la partie.
  await assert.rejects(guessUpdate(p2, guess, { status: 'finished', winner_id: p2 }), /forbidden_winner_id/);
  await assert.rejects(guessUpdate(p2, guess, { winner_id: p2 }), /forbidden_winner_id/);
  await assert.rejects(guessUpdate(p2, guess, { status: 'finished' }), /finished_requires_winner/);
  await assert.rejects(guessUpdate(p1, guess, { current_turn: p1 }), /forbidden_current_turn/);
  await assert.rejects(guessUpdate(p2, guess, { pokemon_p2: 4 }), /pokemon_locked/);
  await assert.rejects(guessUpdate(p1, guess, { pokemon_p2: 4 }), /pokemon_locked/);
  await assert.rejects(guessUpdate(p1, guess, { last_guess: 5 }), /forbidden_last_guess/);
  await assert.rejects(guessUpdate(outsider, guess, { p1_ready: true }), /not_room_player/);

  // Sélection : player1 ne choisit pas le Pokémon de player2, player2 ne lance pas seul.
  guess = await newGuessRoom({ status: 'selecting' });
  await assert.rejects(guessUpdate(p1, guess, { pokemon_p2: 4 }), /forbidden_player2_fields/);
  await assert.rejects(guessUpdate(p1, guess, { p2_ready: true }), /forbidden_player2_fields/);
  await assert.rejects(guessUpdate(p2, guess, { pokemon_p1: 4 }), /forbidden_player1_fields/);
  await assert.rejects(guessUpdate(p2, guess, { status: 'selecting' }), /invalid_status_transition/);
  await assert.rejects(guessUpdate(p1, guess, { pokemon_p1: 1, pokemon_p2: 2, p1_ready: true, p2_ready: true, status: 'playing', current_turn: p1 }), /forbidden_player2_fields/);

  // Mode Pokémon aléatoire : player1 attribue les deux Pokémon et lance.
  guess = await newGuessRoom({});
  await assert.rejects(guessUpdate(p2, guess, { settings: {}, pokemon_p1: 1, pokemon_p2: 2, p1_ready: true, p2_ready: true, status: 'playing', current_turn: p2 }), /only_player1_can_change_settings|only_player1_can_launch/);
  await guessUpdate(p1, guess, { settings: { randomPokemon: true }, pokemon_p1: 1, pokemon_p2: 2, p1_ready: true, p2_ready: true, status: 'playing', current_turn: p1 });
  g = await row('guess_pokemon_rooms', guess);
  assert.equal(g.status, 'playing');
  assert.equal(g.pokemon_p2, 2);

  // Revanche : chaque joueur se déclare prêt sur une partie terminée.
  guess = await newGuessRoom({ status: 'finished', winner_id: p1, pokemon_p1: 1, pokemon_p2: 2 });
  await guessUpdate(p1, guess, { p1_ready: true });
  await guessUpdate(p2, guess, { p2_ready: true });
  await assert.rejects(guessUpdate(p2, guess, { p1_ready: true }), /forbidden_player1_fields/);
  g = await row('guess_pokemon_rooms', guess);
  assert.equal(g.p1_ready && g.p2_ready, true);

  // Room de développement (adversaire simulé sans compte).
  guess = await newGuessRoom({ player2_id: null, status: 'waiting' });
  await guessUpdate(p1, guess, { player2_id: null, status: 'ready' });
  await guessUpdate(p1, guess, { status: 'selecting', settings: {} });
  await guessUpdate(p1, guess, { pokemon_p1: 1 });
  await guessUpdate(p1, guess, { p1_ready: true });
  await guessUpdate(p1, guess, { pokemon_p2: 2, p2_ready: true, status: 'playing', current_turn: p1 });
  await guessUpdate(p1, guess, { current_turn: p1, last_guess: 3 });
  g = await row('guess_pokemon_rooms', guess);
  assert.equal(g.status, 'playing');
  assert.equal(g.last_guess, 3);

  // ─── Who's That Pokémon ──────────────────────────────────────────────────
  const whoLaunch = { status: 'playing', round: 1, target_pokemon_id: 1, used_pokemon_ids: [1], p1_score: 0, p2_score: 0, p1_lives: 0, p2_lives: 0, winner: null, p1_ready: false, p2_ready: false };
  const who = newRoomId();
  await db.query("INSERT INTO public.who_that_pokemon_rooms(id,player1_id,player2_id,status) VALUES ($1,$2,$3,'waiting')", [who, p1, p2]);
  await whoUpdate(p1, who, { settings: { generations: [] } });
  await assert.rejects(whoUpdate(p2, who, whoLaunch), /only_player1_can_launch/);
  await assert.rejects(whoUpdate(p1, who, { ...whoLaunch, target_pokemon_id: 999, used_pokemon_ids: [999] }), /invalid_target/);
  await whoUpdate(p1, who, { ...whoLaunch, settings: { generations: [] }, p1_score: 40, p1_lives: 9 });
  let w = await row('who_that_pokemon_rooms', who);
  assert.equal(w.status, 'playing');
  assert.equal(w.p1_score, 0, 'les scores sont remis à zéro par le serveur');
  assert.equal(w.p1_lives, 0);
  assert.deepEqual(w.used_pokemon_ids, [1]);
  await whoUpdate(p1, who, { ...whoLaunch, target_pokemon_id: 2 }); // relance concurrente : sans effet
  assert.equal((await row('who_that_pokemon_rooms', who)).target_pokemon_id, 1);

  await assert.rejects(whoUpdate(p2, who, { p2_score: 50 }), /forbidden_game_fields/);
  await assert.rejects(whoUpdate(p2, who, { status: 'finished', winner: 'player2' }), /forbidden_winner/);
  await assert.rejects(whoUpdate(p2, who, { winner: 'player2' }), /forbidden_winner/);
  await assert.rejects(whoUpdate(p2, who, { round: 10, target_pokemon_id: 3 }), /forbidden_game_fields/);
  await assert.rejects(whoUpdate(p2, who, { player2_id: outsider }), /forbidden_player2_update/);
  await assert.rejects(whoUpdate(p2, who, { p2_ready: true }), /forbidden_p2_ready/);

  // Fin de partie (posée ici directement, comme le ferait apply_who_that_pokemon_action) puis revanche.
  await db.query("UPDATE public.who_that_pokemon_rooms SET status='finished', winner='player1', p1_score=8 WHERE id=$1", [who]);
  await assert.rejects(whoUpdate(p1, who, whoLaunch), /replay_not_ready/);
  await assert.rejects(whoUpdate(p2, who, { p1_ready: true }), /forbidden_p1_ready/);
  await whoUpdate(p1, who, { p1_ready: true });
  await whoUpdate(p2, who, { p2_ready: true });
  await whoUpdate(p1, who, { ...whoLaunch, target_pokemon_id: 3, used_pokemon_ids: [3] });
  w = await row('who_that_pokemon_rooms', who);
  assert.equal(w.status, 'playing');
  assert.equal(w.winner, null);
  assert.equal(w.p1_score, 0);
  assert.equal(w.target_pokemon_id, 3);

  // Abandon par player2 (page de jeu) puis par player1 (lobby).
  await whoUpdate(p2, who, { status: 'finished', winner: null, p1_ready: false, p2_ready: false });
  w = await row('who_that_pokemon_rooms', who);
  assert.equal(w.status, 'finished');
  assert.equal(w.winner, null);
  await whoUpdate(p1, who, { status: 'finished', winner: null });

  // ─── Duel de base stats ──────────────────────────────────────────────────
  const stat = newRoomId();
  await db.query("INSERT INTO public.stat_duel_rooms(id,player1_id,player2_id,status) VALUES ($1,$2,$3,'waiting')", [stat, p1, p2]);
  await statUpdate(p1, stat, { settings: { generations: [] } });
  await assert.rejects(statUpdate(p2, stat, { status: 'playing', pokemon_ids: [1, 2, 3, 4, 5, 6] }), /only_player1_can_launch/);
  // Patch exact du lobby (lancement).
  await statUpdate(p1, stat, { status: 'playing', settings: {}, pokemon_ids: [1, 2, 3, 4, 5, 6], round_start_at: new Date().toISOString(), p1_picks: [], p2_picks: [], winner: null, p1_ready: false, p2_ready: false });

  await assert.rejects(appendPick(p2, stat, 'p1_picks', { stat: 'pv', value: 10 }), /forbidden_p1_picks/);
  await appendPick(p1, stat, 'p1_picks', { stat: 'vitesse', value: 999 }); // valeur client ignorée
  await assert.rejects(appendPick(p1, stat, 'p1_picks', { stat: 'vitesse', value: 1 }), /stat_already_used/);
  let s = await row('stat_duel_rooms', stat);
  assert.deepEqual(s.p1_picks, [{ stat: 'vitesse', value: 60 }], 'valeur lue dans pokemon_catalog (Pokémon 1)');

  await assert.rejects(statUpdate(p2, stat, { status: 'finished', winner: 'player2' }), /game_not_complete/);
  await assert.rejects(statUpdate(p2, stat, { winner: 'player2' }), /winner_requires_status/);
  await assert.rejects(statUpdate(p2, stat, { status: 'playing', winner: 'player2' }), /winner_requires_status/);

  const order = ['pv', 'attaque', 'defense', 'atq_spe', 'def_spe'];
  for (const key of order) await appendPick(p1, stat, 'p1_picks', { stat: key, value: 1 });
  for (const key of [...order, 'vitesse']) await appendPick(p2, stat, 'p2_picks', { stat: key, value: 999 });
  await assert.rejects(appendPick(p2, stat, 'p2_picks', { stat: 'pv', value: 1 }), /too_many_picks/);
  s = await row('stat_duel_rooms', stat);
  const total = picks => picks.reduce((sum, pick) => sum + pick.value, 0);
  const expected = total(s.p1_picks) > total(s.p2_picks) ? 'player1' : total(s.p2_picks) > total(s.p1_picks) ? 'player2' : 'draw';
  const lie = expected === 'player2' ? 'player1' : 'player2';
  await statUpdate(p2, stat, { status: 'finished', winner: lie });
  s = await row('stat_duel_rooms', stat);
  assert.equal(s.status, 'finished');
  assert.equal(s.winner, expected, 'le vainqueur est recalculé côté serveur');

  await assert.rejects(statUpdate(p2, stat, { p1_ready: false }), /forbidden_p1_ready/);

  // Revanche (choix vidés par player1) puis abandon par player2.
  await statUpdate(p1, stat, { p1_ready: true });
  await statUpdate(p2, stat, { p2_ready: true });
  // Patch exact de la revanche (stat-duel.component.ts).
  await statUpdate(p1, stat, { status: 'playing', pokemon_ids: [6, 5, 4, 3, 2, 1], p1_picks: [], p2_picks: [], winner: null, round_start_at: new Date().toISOString(), p1_ready: false, p2_ready: false });
  s = await row('stat_duel_rooms', stat);
  assert.equal(s.status, 'playing');
  assert.equal(s.winner, null);
  await statUpdate(p2, stat, { status: 'finished', winner: null, p1_ready: false, p2_ready: false });
  s = await row('stat_duel_rooms', stat);
  assert.equal(s.status, 'finished');
  assert.equal(s.winner, null);

  // ─── Team Builder duo ────────────────────────────────────────────────────
  const draft = newRoomId();
  await db.query("INSERT INTO public.draft_duo_rooms(id,player1_id,player2_id,status) VALUES ($1,$2,$3,'waiting')", [draft, p1, p2]);
  await assert.rejects(draftUpdate(p2, draft, { player2_id: outsider }), /forbidden_player2_update/);
  await assert.rejects(draftUpdate(p1, draft, { player2_id: outsider }), /forbidden_player2_update/);
  await draftUpdate(p1, draft, { settings: {} });
  await draftUpdate(p1, draft, { player2_id: null });
  assert.equal((await row('draft_duo_rooms', draft)).player2_id, null);
  await db.query('UPDATE public.draft_duo_rooms SET player2_id=$2 WHERE id=$1', [draft, p2]);
  await draftUpdate(p1, draft, { status: 'playing', p1_team: [], p2_team: [] });
  await assert.rejects(draftUpdate(p1, draft, { player2_id: null }), /forbidden_player2_update/);
  await assert.rejects(draftUpdate(p2, draft, { p1_ready: false }), /forbidden_p1_ready/);
  await draftUpdate(p1, draft, { p1_team: [1, 2, 3, 4, 5, 6] });
  await draftUpdate(p2, draft, { p2_team: [1, 2, 3, 4, 5, 6] });
  await draftUpdate(p2, draft, { status: 'finished', winner: 'player2' });
  assert.equal((await row('draft_duo_rooms', draft)).winner, 'draw', 'vainqueur recalculé (fonction existante)');
  // Revanche puis abandon de player2 (patchs exacts du client).
  await draftUpdate(p1, draft, { p1_ready: true });
  await draftUpdate(p2, draft, { p2_ready: true });
  await draftUpdate(p1, draft, { status: 'playing', p1_team: [], p2_team: [], winner: null, p1_ready: false, p2_ready: false });
  await draftUpdate(p2, draft, { status: 'finished', winner: null, p1_ready: false, p2_ready: false });
  const d = await row('draft_duo_rooms', draft);
  assert.equal(d.status, 'finished');
  assert.equal(d.winner, null);

  // ─── Relations : seule la colonne status est modifiable ─────────────────
  const friendship = (await db.query('INSERT INTO public.friendships(requester_id,recipient_id) VALUES ($1,$2) RETURNING id', [outsider, p1])).rows[0].id;
  await assert.rejects(asUser(p1, 'UPDATE public.friendships SET status=$2, requester_id=$3 WHERE id=$1', [friendship, 'accepted', p2]), /permission denied/);
  await asUser(p1, 'UPDATE public.friendships SET status=$2 WHERE id=$1', [friendship, 'accepted']);
  assert.equal((await row('friendships', friendship)).status, 'accepted');

  const invite = (await db.query('INSERT INTO public.game_invites(sender_id,recipient_id,room_id) VALUES ($1,$2,$3) RETURNING id', [p1, p2, guess])).rows[0].id;
  await assert.rejects(asUser(p2, 'UPDATE public.game_invites SET status=$2, sender_id=$3 WHERE id=$1', [invite, 'accepted', outsider]), /permission denied/);
  await asUser(p2, 'UPDATE public.game_invites SET status=$2 WHERE id=$1', [invite, 'declined']);
  assert.equal((await row('game_invites', invite)).status, 'declined');

  console.log('Migration sécurité RPC : vérifiée');
} finally {
  await db.close();
}
