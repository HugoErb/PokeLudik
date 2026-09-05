import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import ts from 'typescript';
import { PGlite } from '@electric-sql/pglite';

const root = fileURLToPath(new URL('../', import.meta.url));
const read = name => readFileSync(path.join(root, name), 'utf8');
const normalize = sql => sql.replaceAll('\r\n', '\n');
const schema = normalize(read('sql-schema/ddb-schema.sql'))
  .replace(/^\\.*$/gm, '')
  .replace('CREATE SCHEMA public;', 'CREATE SCHEMA IF NOT EXISTS public;');
const migration = normalize(read('sql-schema/functional-fixes.sql'));
const auction = normalize(read('sql-schema/pokemon-auction.sql'));
const pokemon = JSON.parse(read('src/assets/pokemon.json'));

// Exécuter les vraies fonctions TypeScript, sans recopier leur calcul dans le test.
function loadTs(relativePath) {
  const filename = path.resolve(root, relativePath);
  const exports = {};
  const code = ts.transpileModule(readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
  }).outputText;
  vm.runInNewContext(code, { exports, require: id => loadTs(path.resolve(path.dirname(filename), `${id}.ts`)) });
  return exports;
}
const { computeDuoCoverageScore, computeFinalScore, computeStatsScore, computeTotal } = loadTs('src/app/utils/draft-utils.ts');
const { TYPE_CHART } = loadTs('src/app/constants/type-chart.ts');
const totals = pokemon.map(computeTotal);
const range = { min: Math.min(...totals), max: Math.max(...totals) };
const team = ids => ids.map(id => pokemon.find(p => p.id === id));
const finalScore = (ids, opponents) => computeFinalScore(computeStatsScore(team(ids), range),
  computeDuoCoverageScore(team(ids), team(opponents)));

const db = new PGlite();
const p1 = '00000000-0000-4000-8000-000000000001';
const p2 = '00000000-0000-4000-8000-000000000002';
const outsider = '00000000-0000-4000-8000-000000000003';
const roomId = '10000000-0000-4000-8000-000000000001';
let checks = 0;
const check = (actual, expected, message) => { assert.deepEqual(actual, expected, message); checks++; };
async function asUser(user, action) {
  await db.query("SELECT set_config('request.jwt.claim.sub',$1,false)", [user]);
  await db.exec('SET ROLE authenticated');
  try { return await action(); } finally { await db.exec('RESET ROLE'); }
}
const replay = () => db.query('SELECT public.replay_guess_pokemon_room($1)', [roomId]);
const getRoom = async () => (await db.query('SELECT * FROM public.guess_pokemon_rooms WHERE id=$1', [roomId])).rows[0];

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
  await db.exec(schema);
  await db.exec('SET check_function_bodies = true; SET search_path = public; SET row_security = on;');

  const functions = ['replay_guess_pokemon_room(uuid)', 'update_draft_duo_room(uuid,jsonb)',
    'auction_type_multiplier(text,text)', 'auction_effective_multiplier(text[],text)',
    'auction_coverage_score(integer[],integer[])', 'draft_final_score(integer[],integer[])'];
  const definitions = async () => Promise.all(functions.map(async signature =>
    (await db.query('SELECT pg_get_functiondef($1::regprocedure) AS definition', [`public.${signature}`])).rows[0].definition));
  const freshDefinitions = await definitions();
  await db.exec(migration);
  check(await definitions(), freshDefinitions, 'Installation neuve et migration doivent définir les mêmes fonctions');
  await db.exec(migration);
  check(await definitions(), freshDefinitions, 'La migration doit être réexécutable');
  // Vérifier aussi une mise à niveau où les nouvelles fonctions n’existent pas encore.
  await db.exec('DROP FUNCTION public.replay_guess_pokemon_room(uuid); DROP FUNCTION public.draft_final_score(integer[],integer[]);');
  await db.exec(migration);
  check(await definitions(), freshDefinitions, 'La migration doit recréer les nouvelles fonctions');
  const auctionHelpers = auction.slice(auction.indexOf('CREATE OR REPLACE FUNCTION public.auction_type_multiplier('),
    auction.indexOf('DROP FUNCTION IF EXISTS public.save_pokemon_auction_result'));
  await db.exec(auctionHelpers);
  check(await definitions(), freshDefinitions, 'Réappliquer les enchères ne doit pas rétablir l’ancien calcul');

  for (const attack of Object.keys(TYPE_CHART)) {
    for (const defense of Object.keys(TYPE_CHART)) {
      const result = await db.query('SELECT public.auction_type_multiplier($1,$2) AS value', [attack, defense]);
      check(Number(result.rows[0].value), TYPE_CHART[attack][defense] ?? 1, `${attack} contre ${defense}`);
    }
  }
  const examples = [[[25], [195]], [[25], [130]], [[25], [230]], [[68], [493]], [[493], [68]],
    [[1, 2, 3, 4, 5, 6], [31, 32, 33, 34, 35, 36]], [[], [25]], [[25], []]];
  // Échantillonnage déterministe de véritables équipes du catalogue.
  for (let offset = 0; offset < 120; offset++) {
    examples.push([Array.from({ length: 6 }, (_, i) => 1 + (offset * 17 + i * 61) % 1025),
      Array.from({ length: 6 }, (_, i) => 1 + (offset * 31 + i * 73) % 1025)]);
  }
  for (const [own, opponent] of examples) {
    const result = await db.query(`SELECT public.auction_coverage_score($1,$2) AS coverage,
      public.draft_final_score($1,$2) AS final`, [own, opponent]);
    check(Number(result.rows[0].coverage), computeDuoCoverageScore(team(own), team(opponent)), 'Couverture client/SQL');
    check(Number(result.rows[0].final), finalScore(own, opponent), 'Score final client/SQL');
  }

  await db.query('INSERT INTO auth.users(id) VALUES ($1),($2),($3)', [p1, p2, outsider]);
  await db.query(`INSERT INTO public.guess_pokemon_rooms
    (id,player1_id,player2_id,status,pokemon_p1,pokemon_p2,p1_ready,p2_ready,winner_id,last_guess)
    VALUES ($1,$2,$3,'finished',25,4,true,false,$2,25)`, [roomId, p1, p2]);
  await assert.rejects(asUser(p1, replay), /replay_not_ready/); checks++;
  await assert.rejects(asUser(p2, replay), /only_player1_can_replay/); checks++;
  await assert.rejects(asUser(outsider, replay), /only_player1_can_replay/); checks++;
  await assert.rejects(asUser('', replay), /not_authenticated/); checks++;
  await asUser(p2, () => db.query("SELECT public.update_guess_pokemon_room($1,'{\"p2_ready\":true}'::jsonb)", [roomId]));
  await asUser(p1, replay);
  const manual = await getRoom();
  check([manual.status, manual.pokemon_p1, manual.pokemon_p2, manual.current_turn, manual.winner_id, manual.last_guess,
    manual.p1_ready, manual.p2_ready], ['selecting', null, null, null, null, null, false, false], 'Revanche manuelle');
  await asUser(p1, replay);
  check(await getRoom(), manual, 'Double appel sans effet sur une revanche déjà lancée');

  for (const firstPlayer of ['player1', 'player2', 'random']) {
    const settings = { randomPokemon: true, generations: [1], categories: ['starter'], firstPlayer };
    await db.query(`UPDATE public.guess_pokemon_rooms SET status='finished',p1_ready=true,p2_ready=true,settings=$2 WHERE id=$1`,
      [roomId, settings]);
    await asUser(p1, replay);
    const random = await getRoom();
    check(random.status, 'playing', 'Revanche aléatoire');
    check(random.pokemon_p1 !== random.pokemon_p2, true, 'Cibles distinctes');
    check(team([random.pokemon_p1, random.pokemon_p2]).every(p => p.generation === 1 && p.category === 'starter'), true, 'Filtres conservés');
    check(firstPlayer === 'random' ? [p1, p2].includes(random.current_turn) : random.current_turn === (firstPlayer === 'player1' ? p1 : p2), true, 'Premier joueur');
    await asUser(p1, replay);
    check(await getRoom(), random, 'Ne pas retirer les cibles au deuxième appel');
  }
  await db.query(`UPDATE public.guess_pokemon_rooms SET status='finished',p1_ready=true,p2_ready=true,
    settings='{"randomPokemon":true,"generations":[99]}'::jsonb WHERE id=$1`, [roomId]);
  await assert.rejects(asUser(p1, replay), /insufficient_pokemon_pool/); checks++;
  check((await getRoom()).status, 'finished', 'Échec atomique avec un pool vide');

  const own = [1, 2, 3, 4, 5, 6], opponent = [31, 32, 33, 34, 35, 36];
  await db.query(`INSERT INTO public.draft_duo_rooms(id,player1_id,player2_id,status,p1_team,p2_team)
    VALUES ($1,$2,$3,'playing',$4,$5)`, [roomId, p1, p2, own, opponent]);
  await asUser(p1, () => db.query(`SELECT public.update_draft_duo_room($1,'{"status":"finished","winner":"player1"}'::jsonb)`, [roomId]));
  const expected = finalScore(own, opponent) > finalScore(opponent, own) ? 'player1'
    : finalScore(own, opponent) < finalScore(opponent, own) ? 'player2' : 'draw';
  check((await db.query('SELECT winner FROM public.draft_duo_rooms WHERE id=$1', [roomId])).rows[0].winner, expected,
    'Le serveur détermine le gagnant avec la couverture même si le client propose un autre gagnant');
  console.log(`SQL fonctionnel vérifié : ${checks} contrôles PostgreSQL réussis.`);
} catch (error) {
  console.error(error.message);
  if (error.detail) console.error(error.detail);
  if (error.where) console.error(error.where);
  if (error.position && error.query) {
    const position = Number(error.position);
    console.error(error.query.slice(Math.max(0, position - 150), position + 150));
  }
  process.exitCode = 1;
} finally {
  await db.close();
}
