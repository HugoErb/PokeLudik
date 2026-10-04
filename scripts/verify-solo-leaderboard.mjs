import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';

const read = name => readFileSync(new URL(`../${name}`, import.meta.url), 'utf8').replaceAll('\r\n', '\n');
const pokemon = JSON.parse(read('src/assets/pokemon.json'));
const db = new PGlite();
const p1 = '00000000-0000-4000-8000-000000000001';
const p2 = '00000000-0000-4000-8000-000000000002';
const runs = Array.from({ length: 12 }, (_, i) => `20000000-0000-4000-8000-${String(i + 1).padStart(12, '0')}`);
let checks = 0;
const check = (actual, expected, message) => { assert.deepEqual(actual, expected, message); checks++; };

async function asUser(id, sql, params = []) {
  await db.query("SELECT set_config('request.jwt.claim.sub',$1,false)", [id]);
  await db.exec('SET ROLE authenticated');
  try { return await db.query(sql, params); }
  finally { await db.exec('RESET ROLE'); }
}

const settings = value => JSON.stringify(value);
const statDuel = (user, run, value, picks) => asUser(user,
  'SELECT public.submit_stat_duel_score($1,$2::jsonb,$3::jsonb) AS r', [run, settings(value), JSON.stringify(picks)]);
const who = (user, run, value, score, found) => asUser(user,
  'SELECT public.submit_who_that_pokemon_score($1,$2::jsonb,$3,$4) AS r', [run, settings(value), score, found]);
const draft = (user, run, value, team) => asUser(user,
  'SELECT public.submit_draft_score($1,$2::jsonb,$3) AS r', [run, settings(value), team]);
const trainer = (user, run, index, team, opponent) => asUser(user,
  'SELECT public.submit_draft_trainer_score($1,$2,$3,$4) AS r', [run, index, team, opponent]);
const mine = async (user, mode, key, period = 'all') => (await asUser(user,
  'SELECT public.get_my_solo_scores($1,$2,$3) AS r', [mode, key, period])).rows[0].r;
const board = (user, mode, key, period = 'all') => asUser(user,
  'SELECT rank,user_id,score::float AS score,is_me,team FROM public.get_solo_leaderboard($1,$2,$3)', [mode, key, period]);

try {
  await db.exec(`CREATE ROLE anon; CREATE ROLE authenticated;
    CREATE SCHEMA extensions;
    CREATE FUNCTION extensions.uuid_generate_v4() RETURNS uuid LANGUAGE sql AS $$ SELECT gen_random_uuid() $$;
    CREATE SCHEMA auth;
    CREATE TABLE auth.users (id uuid PRIMARY KEY);
    CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
      SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
    $$;
    GRANT USAGE ON SCHEMA auth TO authenticated;`);
  // Le dump complet contient des extensions Supabase absentes de PGlite : ne reprendre que le nécessaire.
  const schema = read('sql-schema/ddb-schema.sql');
  const extract = pattern => {
    const match = schema.match(pattern);
    if (!match) throw new Error(`Bloc introuvable dans ddb-schema.sql : ${pattern}`);
    return match[0];
  };
  const fn = name => extract(new RegExp(`CREATE FUNCTION public\\.${name}\\([\\s\\S]*?\\$\\$;`));
  await db.exec([
    extract(/CREATE TABLE public\.pokemon_catalog \([\s\S]*?\);/),
    extract(/CREATE TABLE public\.profiles \([\s\S]*?\);/),
    'ALTER TABLE public.pokemon_catalog ADD PRIMARY KEY (id); ALTER TABLE public.profiles ADD PRIMARY KEY (id);',
    fn('auction_type_multiplier'), fn('auction_effective_multiplier'), fn('auction_coverage_score'), fn('draft_final_score'),
  ].join('\n'));
  const quote = value => `'${String(value).replaceAll("'", "''")}'`;
  await db.exec(`INSERT INTO public.pokemon_catalog VALUES ${pokemon.map(p => `(${p.id},${p.generation},${quote(p.category)},
    ARRAY[${p.types.map(quote).join(',')}]::text[],${Number(p.rating)},${p.stats.pv},${p.stats.attaque},${p.stats.defense},
    ${p.stats.atq_spe},${p.stats.def_spe},${p.stats.vitesse})`).join(',')};`);
  // La migration de base est supprimée du dépôt une fois appliquée : SOLO_LEADERBOARD_BASE permet d'en fournir une copie.
  await db.exec(process.env.SOLO_LEADERBOARD_BASE
    ? readFileSync(process.env.SOLO_LEADERBOARD_BASE, 'utf8')
    : read('sql-schema/migrations/solo-leaderboard.sql'));
  await db.exec(read('sql-schema/migrations/solo-leaderboard-update.sql'));
  await db.exec(`INSERT INTO auth.users(id) VALUES ('${p1}'),('${p2}');
    INSERT INTO public.profiles(id,username) VALUES ('${p1}','Sacha'),('${p2}','Ondine');
    SET check_function_bodies = true; SET row_security = on;`);

  // Permissions : seules les RPC publiques sont exécutables, la table reste fermée.
  for (const signature of [
    'public.submit_stat_duel_score(uuid,jsonb,jsonb)', 'public.submit_who_that_pokemon_score(uuid,jsonb,integer,integer)',
    'public.submit_draft_score(uuid,jsonb,integer[])', 'public.submit_draft_trainer_score(uuid,integer,integer[],integer[])',
    'public.get_solo_leaderboard(text,text,text,integer)', 'public.get_solo_leaderboard_categories(text,text)',
  ]) {
    const { rows } = await db.query(`SELECT has_function_privilege('anon',$1,'EXECUTE') AS anon,
      has_function_privilege('authenticated',$1,'EXECUTE') AS authenticated`, [signature]);
    check(rows[0], { anon: false, authenticated: true }, `Permissions de ${signature}`);
  }
  for (const signature of ['public.record_solo_score(uuid,text,jsonb,text,numeric,boolean,jsonb)', 'public.solo_pool_ok(integer[],jsonb)']) {
    const { rows } = await db.query("SELECT has_function_privilege('authenticated',$1,'EXECUTE') AS ok", [signature]);
    check(rows[0].ok, false, `Fonction interne ${signature}`);
  }
  await assert.rejects(asUser(p1, 'SELECT * FROM public.solo_scores'), /permission denied/); checks++;
  await assert.rejects(asUser(p1, "INSERT INTO public.solo_scores(run_id,user_id,mode,settings_key,score) VALUES (gen_random_uuid(),$1,'draft','x',10)", [p1]), /permission denied/); checks++;

  // Duel de Base Stats : score recalculé depuis le catalogue.
  const gen1 = pokemon.filter(p => p.generation === 1).slice(0, 6);
  const stats = ['pv', 'attaque', 'defense', 'atq_spe', 'def_spe', 'vitesse'];
  const picks = gen1.map((p, i) => ({ pokemon_id: p.id, stat: stats[i] }));
  const expected = gen1.reduce((sum, p, i) => sum + p.stats[stats[i]], 0);
  let result = (await statDuel(p1, runs[0], { generations: [1], categories: [] }, picks)).rows[0].r;
  check(Number(result.score), expected, 'Total Base Stats recalculé');
  check(result.settings_key, 'g=1;c=', 'Clé de catégorie Base Stats');
  check([result.is_record, result.rank_all_time, result.rank_week], [true, 1, 1], 'Premier record');
  result = (await statDuel(p1, runs[0], { generations: [1], categories: [] }, picks)).rows[0].r;
  check(Number((await db.query('SELECT count(*) FROM public.solo_scores')).rows[0].count), 1, 'run_id idempotent');
  await assert.rejects(statDuel(p2, runs[0], { generations: [1], categories: [] }, picks), /invalid_run/); checks++;
  await assert.rejects(statDuel(p1, runs[1], { generations: [2], categories: [] }, picks), /invalid_picks/); checks++;
  await assert.rejects(statDuel(p1, runs[1], {}, picks.map(p => ({ ...p, stat: 'pv' }))), /invalid_picks/); checks++;
  await assert.rejects(statDuel(p1, runs[1], { generations: [42] }, picks), /invalid_settings/); checks++;

  // Who's That : bornes du score.
  await assert.rejects(who(p1, runs[1], {}, 51, 10), /invalid_score/); checks++;
  await assert.rejects(who(p1, runs[1], {}, 30, 5), /invalid_score/); checks++;
  await assert.rejects(who(p1, runs[1], {}, 1, 1), /invalid_score/); checks++;
  result = (await who(p1, runs[1], { categories: ['starter', 'bébé'], initialHint: 'cry' }, 40, 10)).rows[0].r;
  check([result.settings_key, result.won], ['g=;c=bébé,starter;h=cry', true], 'Clé Who\'s That triée');
  result = (await who(p2, runs[2], { categories: ['bébé', 'starter', 'starter'], initialHint: 'cry' }, 45, 9)).rows[0].r;
  check([result.rank_all_time, result.won], [1, false], 'Meilleur score en tête');
  result = (await who(p1, runs[3], { categories: ['starter', 'bébé'], initialHint: 'cry' }, 20, 10)).rows[0].r;
  check([result.is_record, Number(result.previous_best), result.rank_all_time], [false, 40, 2], 'Pas de record, rang du meilleur score');
  let rows = (await board(p1, 'who_that_pokemon', 'g=;c=bébé,starter;h=cry')).rows;
  check(rows.map(r => [r.rank, r.user_id, r.score, r.is_me]), [[1, p2, 45, false], [2, p1, 40, true]], 'Classement Who\'s That');
  let personal = await mine(p1, 'who_that_pokemon', 'g=;c=bébé,starter;h=cry');
  check([personal.games, Number(personal.best), Number(personal.average), personal.rank], [2, 40, 30, 2], 'Résumé personnel');
  check(personal.entries.map(e => Number(e.score)), [40, 20], 'Parties personnelles triées');
  personal = await mine(p1, 'stat_duel', 'g=;c=');
  check([personal.games, personal.best, personal.rank, personal.entries], [0, null, null, []], 'Personnel sans partie');
  const categories = (await asUser(p1, "SELECT settings_key,players FROM public.get_solo_leaderboard_categories('who_that_pokemon','all')")).rows;
  check(categories, [{ settings_key: 'g=;c=bébé,starter;h=cry', players: 2 }], 'Catégories jouées');

  // Hebdomadaire : une partie ancienne ne compte que dans le tout temps.
  await db.query("UPDATE public.solo_scores SET created_at = now() - interval '30 days' WHERE run_id = $1", [runs[2]]);
  rows = (await board(p1, 'who_that_pokemon', 'g=;c=bébé,starter;h=cry', 'week')).rows;
  check(rows.map(r => [r.rank, r.user_id]), [[1, p1]], 'Classement de la semaine');

  // Team Builder : moyenne des ratings et pool filtré.
  const team = pokemon.filter(p => p.generation === 3).slice(0, 6);
  result = (await draft(p1, runs[4], { generations: [3] }, team.map(p => p.id))).rows[0].r;
  const avg = team.reduce((sum, p) => sum + Math.round(p.rating * 10), 0) / 6;
  check(Number(result.score), Math.round(avg) / 10, 'Note Team Builder recalculée');
  rows = (await asUser(p2, "SELECT user_id,team FROM public.get_solo_leaderboard('draft','g=3;c=','all')")).rows;
  check(rows.map(r => [r.user_id, r.team]), [[p1, team.map(p => p.id)]], 'Équipe renvoyée par le classement Team Builder');
  await assert.rejects(draft(p1, runs[5], { generations: [4] }, team.map(p => p.id)), /invalid_team/); checks++;
  await assert.rejects(draft(p1, runs[5], {}, [1, 1, 2, 3, 4, 5]), /invalid_team/); checks++;

  // Contre un dresseur : score final serveur + catégorie « dresseurs battus ».
  const strong = [150, 249, 250, 382, 383, 384];
  const weak = [10, 13, 129, 191, 298, 401];
  result = (await trainer(p1, runs[6], 0, strong, weak)).rows[0].r;
  check([result.won, result.settings_key], [true, 'trainer:0'], 'Victoire contre un dresseur');
  check(Number(result.score), Number((await db.query('SELECT public.draft_final_score($1,$2) AS s', [strong, weak])).rows[0].s), 'Score final dresseur');
  await trainer(p1, runs[7], 1, strong, weak);
  await trainer(p1, runs[8], 1, strong, weak);
  await trainer(p2, runs[9], 0, strong, weak);
  await trainer(p2, runs[10], 2, weak, strong);
  rows = (await board(p2, 'draft_trainer', 'trainers_defeated')).rows;
  check(rows.map(r => [r.rank, r.user_id, r.score, r.is_me]), [[1, p1, 2, false], [2, p2, 1, true]], 'Dresseurs battus distincts');
  check(rows.map(r => r.team), [null, null], 'Aucune équipe pour « Dresseurs battus »');
  personal = await mine(p1, 'draft_trainer', 'trainers_defeated');
  check([personal.games, Number(personal.best), personal.rank], [3, 2, 1], 'Résumé personnel dresseurs');
  check(personal.entries.map(e => [e.settings_key, e.team]), [['trainer:0', strong], ['trainer:1', strong]], 'Dresseurs battus personnels');

  console.log(`Classement solo : ${checks} vérifications OK.`);
} catch (error) {
  // Les erreurs PGlite embarquent toute la requête : n'afficher que l'essentiel.
  console.error(`Échec après ${checks} vérifications : ${error.message}${error.where ? `\n${error.where}` : ''}`);
  process.exitCode = 1;
} finally {
  await db.close();
}
