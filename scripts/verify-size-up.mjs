import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';

// Vérifie la migration Size It Up (sql-schema/migrations/size-up.sql) dans une base PGlite.
// Les fonctions de classement existantes (solo_scores, record_solo_score, …) sont lues dans
// sql-schema/ddb-schema.sql, ou dans le fichier indiqué par SOLO_LEADERBOARD_BASE.

const read = name => readFileSync(new URL(`../${name}`, import.meta.url), 'utf8').replaceAll('\r\n', '\n');
const pokemon = JSON.parse(read('src/assets/pokemon.json'));
const db = new PGlite();
const p1 = '00000000-0000-4000-8000-000000000001';
const p2 = '00000000-0000-4000-8000-000000000002';
const outsider = '00000000-0000-4000-8000-000000000003';
const runs = Array.from({ length: 4 }, (_, i) => `30000000-0000-4000-8000-${String(i + 1).padStart(12, '0')}`);
let checks = 0;
const check = (actual, expected, message) => { assert.deepEqual(actual, expected, message); checks++; };
const rejects = async (promise, pattern) => { await assert.rejects(promise, pattern); checks++; };

async function asUser(id, sql, params = []) {
  await db.query("SELECT set_config('request.jwt.claim.sub',$1,false)", [id]);
  await db.exec('SET ROLE authenticated');
  try { return await db.query(sql, params); }
  finally { await db.exec('RESET ROLE'); }
}

const room = async id => (await db.query('SELECT * FROM public.size_up_rooms WHERE id=$1', [id])).rows[0];
const height = id => pokemon.find(p => p.id === id).height;
const points = (guess, actual) => guess === null ? 0 : Math.round(100 * Math.max(0, 1 - Math.abs(Math.log(guess / actual)) / Math.log(5)));
/** Recule les délais de la room pour simuler l'écoulement du temps. */
const expire = id => db.query(`UPDATE public.size_up_rooms SET
  round_deadline = CASE WHEN round_deadline IS NULL THEN NULL ELSE clock_timestamp() - interval '10 seconds' END,
  reveal_until = CASE WHEN reveal_until IS NULL THEN NULL ELSE clock_timestamp() - interval '1 second' END WHERE id=$1`, [id]);

try {
  await db.exec(`CREATE ROLE anon; CREATE ROLE authenticated;
    CREATE SCHEMA auth;
    CREATE TABLE auth.users (id uuid PRIMARY KEY);
    CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
      SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
    $$;
    GRANT USAGE ON SCHEMA auth TO authenticated;
    GRANT USAGE ON SCHEMA public TO authenticated, anon;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO authenticated, anon;
    CREATE PUBLICATION supabase_realtime;
    CREATE TABLE public.game_invites (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), sender_id uuid, recipient_id uuid, room_id uuid, game_mode text, status text);
    ALTER TABLE public.game_invites ENABLE ROW LEVEL SECURITY;
    CREATE FUNCTION public.bump_row_version() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN NEW.version := OLD.version + 1; RETURN NEW; END; $$;`);

  const schema = read('sql-schema/ddb-schema.sql');
  const extract = pattern => {
    const match = schema.match(pattern);
    if (!match) throw new Error(`Bloc introuvable dans ddb-schema.sql : ${pattern}`);
    return match[0];
  };
  await db.exec(`${extract(/CREATE TABLE public\.pokemon_catalog \([\s\S]*?\);/)}
    ALTER TABLE public.pokemon_catalog ADD PRIMARY KEY (id);
    CREATE TABLE public.profiles (id uuid PRIMARY KEY, username text, avatar_url text);`);
  const quote = value => `'${String(value).replaceAll("'", "''")}'`;
  await db.exec(`INSERT INTO public.pokemon_catalog (id, generation, category, types, rating, pv, attaque, defense, atq_spe, def_spe, vitesse)
    VALUES ${pokemon.map(p => `(${p.id},${p.generation},${quote(p.category)},
    ARRAY[${p.types.map(quote).join(',')}]::text[],${Number(p.rating ?? 0)},${p.stats.pv},${p.stats.attaque},${p.stats.defense},
    ${p.stats.atq_spe},${p.stats.def_spe},${p.stats.vitesse})`).join(',')};`);

  const leaderboardBase = process.env.SOLO_LEADERBOARD_BASE
    ? readFileSync(process.env.SOLO_LEADERBOARD_BASE, 'utf8')
    : ['solo_week_start', 'solo_pool_ok', 'record_solo_score']
      .map(name => extract(new RegExp(`CREATE FUNCTION public\\.${name}\\([\\s\\S]*?\\$\\$;`)))
      .concat(extract(/CREATE TABLE public\.solo_scores \([\s\S]*?\);/))
      .join('\n');
  await db.exec(leaderboardBase);
  await db.exec(`CREATE SEQUENCE IF NOT EXISTS public.solo_scores_id_seq;
    ALTER TABLE public.solo_scores ALTER COLUMN id SET DEFAULT nextval('public.solo_scores_id_seq');
    ALTER TABLE public.solo_scores ADD PRIMARY KEY (id);
    CREATE UNIQUE INDEX IF NOT EXISTS solo_scores_run_id_key ON public.solo_scores (run_id);
    REVOKE ALL ON public.solo_scores FROM anon, authenticated;`);

  await db.exec(read('sql-schema/migrations/size-up.sql'));
  await db.exec(read('sql-schema/migrations/size-up.sql')); // idempotente
  await db.exec(`INSERT INTO auth.users(id) VALUES ('${p1}'),('${p2}'),('${outsider}');
    INSERT INTO public.profiles(id,username) VALUES ('${p1}','Sacha'),('${p2}','Ondine');
    SET row_security = on;`);

  // Catalogue et formule de score.
  check(Number((await db.query('SELECT count(*) FROM public.pokemon_catalog WHERE height > 0')).rows[0].count), pokemon.length, 'Tailles importées');
  for (const [guess, actual] of [[1.2, 1.2], [1.1, 1], [2, 1], [0.5, 1], [3, 1], [5, 1], [14.5, 0.3]]) {
    const { rows } = await db.query('SELECT public.size_up_points($1,$2) AS p', [guess, actual]);
    check(rows[0].p, points(guess, actual), `Points ${guess} / ${actual}`);
  }
  check((await db.query('SELECT public.size_up_points(NULL,1) AS p')).rows[0].p, 0, 'Aucune estimation');

  // Permissions.
  for (const signature of ['public.size_up_reveal_round(uuid)']) {
    const { rows } = await db.query("SELECT has_function_privilege('authenticated',$1,'EXECUTE') AS ok", [signature]);
    check(rows[0].ok, false, `Fonction interne ${signature}`);
  }
  await rejects(asUser(p1, 'SELECT * FROM public.size_up_guesses'), /permission denied/);

  // Duo : création, réglages, lancement.
  const roomId = (await asUser(p1, `INSERT INTO public.size_up_rooms(player1_id, settings) VALUES ($1, '{"generations":[1],"categories":[],"roundTimer":15}') RETURNING id`, [p1])).rows[0].id;
  await rejects(asUser(p1, 'SELECT public.start_size_up_game($1,$2::jsonb)', [roomId, '{}']), /missing_opponent/);
  await rejects(asUser(p1, 'SELECT public.join_size_up_room($1)', [roomId]), /creator_cannot_join/);
  await asUser(p2, 'SELECT public.join_size_up_room($1)', [roomId]);
  await rejects(asUser(p2, `SELECT public.update_size_up_room($1,'{"settings":{}}'::jsonb)`, [roomId]), /settings_locked/);
  await rejects(asUser(p1, `SELECT public.update_size_up_room($1,'{"settings":{"roundTimer":7}}'::jsonb)`, [roomId]), /invalid_settings/);
  await rejects(asUser(p1, `SELECT public.update_size_up_room($1,'{"p1_score":500}'::jsonb)`, [roomId]), /forbidden_fields/);
  await asUser(p1, `SELECT public.update_size_up_room($1,'{"settings":{"generations":[1],"categories":[],"roundTimer":15}}'::jsonb)`, [roomId]);
  await rejects(asUser(p2, 'SELECT public.start_size_up_game($1,$2::jsonb)', [roomId, '{}']), /not_host/);
  await asUser(p1, 'SELECT public.start_size_up_game($1,$2::jsonb)', [roomId, JSON.stringify({ generations: [1], categories: [], roundTimer: 15 })]);
  let state = await room(roomId);
  check([state.status, state.round, state.round_phase, state.version > 0], ['playing', 1, 'guessing', true], 'Partie lancée');
  check(state.reference_pokemon_id !== state.target_pokemon_id, true, 'Paire de Pokémon distincts');
  check([height(state.reference_pokemon_id) > 0, pokemon.find(p => p.id === state.target_pokemon_id).generation], [true, 1], 'Pool filtré');
  check(state.round_deadline !== null, true, 'Chrono fixé');

  // Manche 1 : les deux répondent, l'estimation adverse reste secrète jusqu'à la révélation.
  await rejects(asUser(outsider, 'SELECT public.submit_size_up_guess($1,1,1)', [roomId]), /not_room_player/);
  await rejects(asUser(p1, 'SELECT public.submit_size_up_guess($1,1,100)', [roomId]), /invalid_guess/);
  await rejects(asUser(p1, 'SELECT public.submit_size_up_guess($1,2,1)', [roomId]), /stale_round/);
  await asUser(p1, 'SELECT public.submit_size_up_guess($1,1,1.5)', [roomId]);
  await rejects(asUser(p1, 'SELECT public.submit_size_up_guess($1,1,1.5)', [roomId]), /already_submitted/);
  state = (await asUser(p2, 'SELECT * FROM public.size_up_rooms WHERE id=$1', [roomId])).rows[0];
  check([state.p1_submitted, state.p2_submitted, state.history], [true, false, []], 'Estimation secrète avant révélation');
  await asUser(p2, 'SELECT public.submit_size_up_guess($1,1,0.4)', [roomId]);
  state = await room(roomId);
  const actual1 = height(state.target_pokemon_id);
  check([state.round_phase, state.p1_score, state.p2_score], ['reveal', points(1.5, actual1), points(0.4, actual1)], 'Révélation et scores');
  check(state.history.map(h => [h.round, Number(h.p1_guess), Number(h.p2_guess)]), [[1, 1.5, 0.4]], 'Historique de la manche');

  // Révélation non écoulée : pas d'avancée. Puis manche suivante.
  await asUser(p1, 'SELECT public.finalize_size_up_round($1,1)', [roomId]);
  check((await room(roomId)).round, 1, 'Pas d’avancée pendant la révélation');
  const usedBefore = state.used_pokemon_ids;
  await expire(roomId);
  await asUser(p2, 'SELECT public.finalize_size_up_round($1,1)', [roomId]);
  await asUser(p1, 'SELECT public.finalize_size_up_round($1,1)', [roomId]); // second appel sans effet
  state = await room(roomId);
  check([state.round, state.round_phase, state.p1_submitted, state.p2_submitted], [2, 'guessing', false, false], 'Manche 2');
  check(usedBefore.some(id => [state.reference_pokemon_id, state.target_pokemon_id].includes(id)), false, 'Pas de Pokémon déjà joué');

  // Manche 2 : chrono écoulé, seul p1 a répondu → 0 point pour p2.
  await asUser(p1, 'SELECT public.submit_size_up_guess($1,2,1)', [roomId]);
  await asUser(p2, 'SELECT public.finalize_size_up_round($1,2)', [roomId]);
  check((await room(roomId)).round_phase, 'guessing', 'Pas de clôture avant la fin du chrono');
  await expire(roomId);
  await rejects(asUser(p2, 'SELECT public.submit_size_up_guess($1,2,1)', [roomId]), /round_closed/);
  await asUser(p2, 'SELECT public.finalize_size_up_round($1,2)', [roomId]);
  state = await room(roomId);
  check([state.round_phase, state.history[1].p2_guess, state.history[1].p2_points], ['reveal', null, 0], 'Absence de réponse');

  // Manches 3 à 5 puis fin de partie.
  for (let round = 3; round <= 5; round++) {
    await expire(roomId);
    await asUser(p1, 'SELECT public.finalize_size_up_round($1,$2)', [roomId, round - 1]);
    await asUser(p1, 'SELECT public.submit_size_up_guess($1,$2,2)', [roomId, round]);
    await asUser(p2, 'SELECT public.submit_size_up_guess($1,$2,2)', [roomId, round]);
  }
  await expire(roomId);
  await asUser(p1, 'SELECT public.finalize_size_up_round($1,5)', [roomId]);
  state = await room(roomId);
  const winner = state.p1_score > state.p2_score ? 'player1' : state.p2_score > state.p1_score ? 'player2' : 'draw';
  check([state.status, state.winner, state.history.length], ['finished', winner, 5], 'Fin de partie');
  check(state.p1_score, state.history.reduce((sum, h) => sum + h.p1_points, 0), 'Score total cohérent');

  // Revanche.
  await rejects(asUser(p2, `SELECT public.update_size_up_room($1,'{"p1_ready":true}'::jsonb)`, [roomId]), /forbidden_ready/);
  await asUser(p1, `SELECT public.update_size_up_room($1,'{"p1_ready":true}'::jsonb)`, [roomId]);
  await rejects(asUser(p1, 'SELECT public.start_size_up_game($1,$2::jsonb)', [roomId, '{}']), /room_not_startable/);
  await asUser(p2, `SELECT public.update_size_up_room($1,'{"p2_ready":true}'::jsonb)`, [roomId]);
  await asUser(p1, 'SELECT public.start_size_up_game($1,$2::jsonb)', [roomId, '{}']);
  state = await room(roomId);
  check([state.status, state.round, state.p1_score, state.history, state.settings.roundTimer], ['playing', 1, 0, [], 15], 'Revanche avec les mêmes paramètres');

  // Abandon.
  await rejects(asUser(p2, `SELECT public.update_size_up_room($1,'{"status":"playing"}'::jsonb)`, [roomId]), /forbidden_status/);
  await asUser(p2, `SELECT public.update_size_up_room($1,'{"status":"finished","winner":null,"p1_ready":false,"p2_ready":false}'::jsonb)`, [roomId]);
  state = await room(roomId);
  check([state.status, state.winner], ['finished', null], 'Abandon');

  // Classement solo : score recalculé côté serveur.
  const gen1 = pokemon.filter(p => p.generation === 1);
  const rounds = Array.from({ length: 5 }, (_, i) => ({ reference_id: gen1[2 * i].id, target_id: gen1[2 * i + 1].id, guess: i === 4 ? null : 1 }));
  const expected = rounds.reduce((sum, r) => sum + points(r.guess, height(r.target_id)), 0);
  const submit = (user, run, settings, value) => asUser(user, 'SELECT public.submit_size_up_score($1,$2::jsonb,$3::jsonb) AS r',
    [run, JSON.stringify(settings), JSON.stringify(value)]);
  let result = (await submit(p1, runs[0], { generations: [1], categories: [], roundTimer: 30 }, rounds)).rows[0].r;
  check([Number(result.score), result.settings_key, result.is_record], [expected, 'g=1;c=;t=30', true], 'Score solo recalculé');
  await rejects(submit(p1, runs[1], { generations: [2], categories: [], roundTimer: 0 }, rounds), /invalid_rounds/);
  await rejects(submit(p1, runs[1], {}, rounds.slice(0, 4)), /invalid_rounds/);
  await rejects(submit(p1, runs[1], {}, rounds.map(r => ({ ...r, target_id: r.reference_id }))), /invalid_rounds/);
  await rejects(submit(p1, runs[1], {}, rounds.map(r => ({ ...r, guess: 99 }))), /invalid_rounds/);
  await rejects(submit(p1, runs[1], { roundTimer: 20 }, rounds), /invalid_settings/);

  console.log(`Size It Up : ${checks} vérifications OK`);
} finally {
  await db.close();
}
