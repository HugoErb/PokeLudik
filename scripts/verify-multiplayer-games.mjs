import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';

const db = new PGlite();
const p1 = '00000000-0000-4000-8000-000000000001';
const p2 = '00000000-0000-4000-8000-000000000002';
const outsider = '00000000-0000-4000-8000-000000000003';
const guessId = '10000000-0000-4000-8000-000000000001';
const whoId = '10000000-0000-4000-8000-000000000002';
const cancelId = '10000000-0000-4000-8000-000000000003';

async function asUser(id, sql, params = []) {
  await db.query("SELECT set_config('request.jwt.claim.sub',$1,false)", [id]);
  await db.exec('SET ROLE authenticated');
  try { return await db.query(sql, params); }
  finally { await db.exec('RESET ROLE'); }
}

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
  const schema = readFileSync(new URL('../sql-schema/ddb-schema.sql', import.meta.url), 'utf8')
    .replace(/^\\.*$/gm, '')
    .replace('CREATE SCHEMA public;', 'CREATE SCHEMA IF NOT EXISTS public;');
  await db.exec(schema);
  await db.exec(`INSERT INTO auth.users(id) VALUES ('${p1}'),('${p2}'),('${outsider}');
    INSERT INTO public.pokemon_catalog(id,generation,category,pv,attaque,defense,atq_spe,def_spe,vitesse)
    VALUES (1,1,'normal',1,1,1,1,1,1),(2,1,'normal',2,2,2,2,2,2),(3,1,'normal',3,3,3,3,3,3);
    INSERT INTO public.guess_pokemon_rooms(id,player1_id,player2_id,pokemon_p1,pokemon_p2,current_turn,status)
    VALUES ('${guessId}','${p1}','${p2}',1,2,'${p1}','playing');
    INSERT INTO public.guess_pokemon_rooms(id,player1_id,player2_id,pokemon_p1,pokemon_p2,current_turn,status)
    VALUES ('${cancelId}','${p1}','${p2}',1,2,'${p1}','playing');
    INSERT INTO public.who_that_pokemon_rooms(id,player1_id,player2_id,status,settings,target_pokemon_id,used_pokemon_ids)
    VALUES ('${whoId}','${p1}','${p2}','playing','{}',1,ARRAY[1]);`);

  const guess = (id, pokemonId) => asUser(id,
    'SELECT public.submit_guess_pokemon_guess($1,$2) AS correct', [guessId, pokemonId]);
  assert.equal((await guess(p1, 3)).rows[0].correct, false);
  await assert.rejects(guess(p1, 2), /not_your_turn/);
  assert.equal((await guess(p2, 1)).rows[0].correct, true);
  const guessRoom = (await db.query('SELECT status,winner_id FROM public.guess_pokemon_rooms WHERE id=$1', [guessId])).rows[0];
  assert.equal(guessRoom.status, 'finished');
  assert.equal(guessRoom.winner_id, p2);

  const cancel = id => asUser(id, 'SELECT public.cancel_guess_pokemon_room($1)', [cancelId]);
  await assert.rejects(cancel(outsider), /not_room_player/);
  await cancel(p2);
  const canceled = (await db.query('SELECT status,winner_id,current_turn FROM public.guess_pokemon_rooms WHERE id=$1', [cancelId])).rows[0];
  assert.equal(canceled.status, 'finished');
  assert.equal(canceled.winner_id, null);
  assert.equal(canceled.current_turn, null);

  const whoGuess = (id, round, pokemonId) => asUser(id,
    'SELECT public.submit_who_that_pokemon_guess($1,$2,$3)', [whoId, round, pokemonId]);
  const skip = (id, round) => asUser(id,
    'SELECT public.skip_who_that_pokemon_round($1,$2)', [whoId, round]);
  await assert.rejects(whoGuess(outsider, 1, 1), /not_room_player/);
  await whoGuess(p1, 1, null);
  await whoGuess(p1, 1, 1);
  await assert.rejects(whoGuess(p1, 1, 1), /round_already_completed/);
  let whoRoom = (await db.query('SELECT * FROM public.who_that_pokemon_rooms WHERE id=$1', [whoId])).rows[0];
  assert.equal(whoRoom.round, 1);
  assert.equal(whoRoom.p1_score, 4);
  await skip(p2, 1);
  whoRoom = (await db.query('SELECT * FROM public.who_that_pokemon_rooms WHERE id=$1', [whoId])).rows[0];
  assert.equal(whoRoom.round, 2);
  assert.equal(whoRoom.p1_ready, false);
  assert.equal(whoRoom.p2_ready, false);
  assert.notEqual(whoRoom.target_pokemon_id, 1);
  await assert.rejects(skip(p1, 1), /stale_round/);
  for (let round = 2; round <= 10; round++) {
    await skip(p1, round);
    await skip(p2, round);
  }
  whoRoom = (await db.query('SELECT * FROM public.who_that_pokemon_rooms WHERE id=$1', [whoId])).rows[0];
  assert.equal(whoRoom.status, 'finished');
  assert.equal(whoRoom.winner, 'player1');
  assert.equal(whoRoom.p1_score, 4);
  console.log('RPC multijoueurs : vérifiées');
} finally {
  await db.close();
}
