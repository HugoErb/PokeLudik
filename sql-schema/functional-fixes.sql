-- Correctifs fonctionnels : revanche Guess, score Draft Duo et immunités.
-- Base existante : appliquer pokemon-auction-catalog.sql avant ce fichier.
BEGIN;

CREATE OR REPLACE FUNCTION public.replay_guess_pokemon_room(p_room_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE
  v_user uuid := auth.uid();
  v_room public.guess_pokemon_rooms;
  v_random boolean;
  v_ids integer[];
  v_turn uuid;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_room FROM public.guess_pokemon_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_user <> v_room.player1_id THEN RAISE EXCEPTION 'only_player1_can_replay'; END IF;
  -- Deux appels concurrents ne doivent pas relancer une seconde fois la partie.
  IF v_room.status IN ('selecting','playing') THEN RETURN; END IF;
  IF v_room.status <> 'finished' OR NOT (v_room.p1_ready AND v_room.p2_ready) THEN
    RAISE EXCEPTION 'replay_not_ready';
  END IF;
  v_random := coalesce((v_room.settings->>'randomPokemon')::boolean,false);
  IF v_random THEN
    SELECT array_agg(id) INTO v_ids FROM (
      SELECT id FROM public.pokemon_catalog p
      WHERE (coalesce(jsonb_array_length(v_room.settings->'generations'),0)=0
        OR p.generation IN (SELECT value::integer FROM jsonb_array_elements_text(v_room.settings->'generations')))
        AND (coalesce(jsonb_array_length(v_room.settings->'categories'),0)=0
        OR p.category IN (SELECT value FROM jsonb_array_elements_text(v_room.settings->'categories')))
      ORDER BY random() LIMIT 2
    ) picked;
    IF coalesce(cardinality(v_ids),0) < 2 THEN RAISE EXCEPTION 'insufficient_pokemon_pool'; END IF;
    v_turn := CASE coalesce(v_room.settings->>'firstPlayer','random')
      WHEN 'player2' THEN coalesce(v_room.player2_id,v_room.player1_id)
      WHEN 'random' THEN CASE WHEN random()<0.5 THEN v_room.player1_id ELSE coalesce(v_room.player2_id,v_room.player1_id) END
      ELSE v_room.player1_id END;
  END IF;
  UPDATE public.guess_pokemon_rooms SET
    status=CASE WHEN v_random THEN 'playing'::public.room_status ELSE 'selecting'::public.room_status END,
    pokemon_p1=CASE WHEN v_random THEN v_ids[1] ELSE NULL END,
    pokemon_p2=CASE WHEN v_random THEN v_ids[2] ELSE NULL END,
    p1_ready=v_random,p2_ready=v_random,current_turn=v_turn,winner_id=NULL,last_guess=NULL
  WHERE id=p_room_id;
END; $$;

REVOKE ALL ON FUNCTION public.replay_guess_pokemon_room(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.replay_guess_pokemon_room(uuid) TO authenticated;

-- SCORE_FUNCTIONS_START
CREATE OR REPLACE FUNCTION public.auction_type_multiplier(p_attacker text,p_defender text) RETURNS numeric
LANGUAGE sql IMMUTABLE PARALLEL SAFE SET search_path=pg_catalog AS $$
  SELECT coalesce((('{
    "Normal":{"Roche":0.5,"Acier":0.5,"Spectre":0},
    "Feu":{"Feu":0.5,"Eau":0.5,"Plante":2,"Glace":2,"Insecte":2,"Roche":0.5,"Dragon":0.5,"Acier":2},
    "Eau":{"Feu":2,"Eau":0.5,"Plante":0.5,"Sol":2,"Roche":2,"Dragon":0.5},
    "Plante":{"Feu":0.5,"Eau":2,"Plante":0.5,"Poison":0.5,"Sol":2,"Vol":0.5,"Insecte":0.5,"Roche":2,"Dragon":0.5,"Acier":0.5},
    "Électrik":{"Eau":2,"Plante":0.5,"Électrik":0.5,"Sol":0,"Vol":2,"Dragon":0.5},
    "Glace":{"Feu":0.5,"Eau":0.5,"Plante":2,"Glace":0.5,"Sol":2,"Vol":2,"Dragon":2,"Acier":0.5},
    "Combat":{"Normal":2,"Glace":2,"Poison":0.5,"Vol":0.5,"Psy":0.5,"Insecte":0.5,"Roche":2,"Spectre":0,"Ténèbres":2,"Acier":2,"Fée":0.5},
    "Poison":{"Plante":2,"Poison":0.5,"Sol":0.5,"Roche":0.5,"Spectre":0.5,"Acier":0,"Fée":2},
    "Sol":{"Feu":2,"Plante":0.5,"Électrik":2,"Poison":2,"Vol":0,"Insecte":0.5,"Roche":2,"Acier":2},
    "Vol":{"Plante":2,"Électrik":0.5,"Combat":2,"Insecte":2,"Roche":0.5,"Acier":0.5},
    "Psy":{"Combat":2,"Poison":2,"Psy":0.5,"Ténèbres":0,"Acier":0.5},
    "Insecte":{"Feu":0.5,"Plante":2,"Combat":0.5,"Poison":0.5,"Vol":0.5,"Psy":2,"Spectre":0.5,"Ténèbres":2,"Acier":0.5,"Fée":0.5},
    "Roche":{"Feu":2,"Glace":2,"Combat":0.5,"Sol":0.5,"Vol":2,"Insecte":2,"Acier":0.5},
    "Spectre":{"Normal":0,"Psy":2,"Spectre":2,"Ténèbres":0.5},
    "Dragon":{"Dragon":2,"Acier":0.5,"Fée":0},
    "Ténèbres":{"Combat":0.5,"Psy":2,"Spectre":2,"Ténèbres":0.5,"Fée":0.5},
    "Acier":{"Feu":0.5,"Eau":0.5,"Électrik":0.5,"Glace":2,"Roche":2,"Acier":0.5,"Fée":2},
    "Fée":{"Feu":0.5,"Combat":2,"Poison":0.5,"Dragon":2,"Ténèbres":2,"Acier":0.5}
  }'::jsonb -> p_attacker ->> p_defender)::numeric),1);
$$;

CREATE OR REPLACE FUNCTION public.auction_effective_multiplier(p_defender_types text[],p_attacker text) RETURNS numeric
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE SET search_path=pg_catalog,public AS $$
DECLARE v_defender text; v_multiplier numeric:=1;
BEGIN
  FOREACH v_defender IN ARRAY p_defender_types LOOP
    v_multiplier:=v_multiplier*public.auction_type_multiplier(p_attacker,v_defender);
  END LOOP;
  RETURN v_multiplier;
END; $$;

CREATE OR REPLACE FUNCTION public.auction_coverage_score(p_team integer[],p_opponent integer[]) RETURNS numeric
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE
  v_my_types text[]; v_opponent_types text[]; v_my_type text; v_opponent_type text;
  v_my_pokemon public.pokemon_catalog%ROWTYPE; v_opponent_pokemon public.pokemon_catalog%ROWTYPE;
  v_hit boolean; v_covered integer:=0; v_exploited integer:=0; v_resisted integer:=0;
  v_offensive numeric:=0; v_pokemon numeric:=0; v_defensive numeric:=0;
BEGIN
  IF coalesce(cardinality(p_team),0)=0 OR coalesce(cardinality(p_opponent),0)=0 THEN RETURN 0; END IF;
  IF 493=ANY(p_team) THEN RETURN 10; END IF;

  SELECT coalesce(array_agg(DISTINCT item.type_name),ARRAY[]::text[]) INTO v_my_types
  FROM public.pokemon_catalog pokemon CROSS JOIN LATERAL unnest(pokemon.types) item(type_name)
  WHERE pokemon.id=ANY(p_team);
  SELECT coalesce(array_agg(DISTINCT item.type_name),ARRAY[]::text[]) INTO v_opponent_types
  FROM public.pokemon_catalog pokemon CROSS JOIN LATERAL unnest(pokemon.types) item(type_name)
  WHERE pokemon.id=ANY(p_opponent) AND pokemon.id<>493;

  FOREACH v_opponent_type IN ARRAY v_opponent_types LOOP
    v_hit:=false;
    FOREACH v_my_type IN ARRAY v_my_types LOOP
      IF public.auction_type_multiplier(v_my_type,v_opponent_type)>1 THEN v_hit:=true; EXIT; END IF;
    END LOOP;
    IF v_hit THEN v_covered:=v_covered+1; END IF;

    IF NOT (493=ANY(p_opponent)) THEN
      v_hit:=false;
      FOR v_my_pokemon IN SELECT * FROM public.pokemon_catalog WHERE id=ANY(p_team) LOOP
        IF public.auction_effective_multiplier(v_my_pokemon.types,v_opponent_type)<1 THEN v_hit:=true; EXIT; END IF;
      END LOOP;
      IF v_hit THEN v_resisted:=v_resisted+1; END IF;
    END IF;
  END LOOP;

  FOR v_opponent_pokemon IN SELECT * FROM public.pokemon_catalog WHERE id=ANY(p_opponent) AND id<>493 LOOP
    v_hit:=false;
    FOREACH v_my_type IN ARRAY v_my_types LOOP
      IF public.auction_effective_multiplier(v_opponent_pokemon.types,v_my_type)>1 THEN v_hit:=true; EXIT; END IF;
    END LOOP;
    IF v_hit THEN v_exploited:=v_exploited+1; END IF;
  END LOOP;

  IF cardinality(v_opponent_types)>0 THEN
    v_offensive:=v_covered::numeric/cardinality(v_opponent_types)*10;
    v_defensive:=v_resisted::numeric/cardinality(v_opponent_types)*10;
  END IF;
  v_pokemon:=v_exploited::numeric/cardinality(p_opponent)*10;
  RETURN round(0.5*v_offensive+0.3*v_pokemon+0.2*v_defensive,1);
END; $$;
REVOKE ALL ON FUNCTION public.auction_type_multiplier(text,text), public.auction_effective_multiplier(text[],text), public.auction_coverage_score(integer[],integer[]) FROM PUBLIC,anon,authenticated;

-- SCORE_FUNCTIONS_END

CREATE OR REPLACE FUNCTION public.draft_final_score(p_team integer[],p_opponent integer[]) RETURNS numeric
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE v_stats numeric;
BEGIN
  IF EXISTS (SELECT 1 FROM public.pokemon_catalog WHERE id=ANY(p_team||p_opponent)
    AND (rating<=0 OR cardinality(types)=0)) THEN RAISE EXCEPTION 'pokemon_catalog_incomplete'; END IF;
  SELECT round(avg(rating),1) INTO v_stats FROM public.pokemon_catalog WHERE id=ANY(p_team);
  RETURN round((coalesce(v_stats,0)+public.auction_coverage_score(p_team,p_opponent))/2,1);
END; $$;
REVOKE ALL ON FUNCTION public.draft_final_score(integer[],integer[]) FROM PUBLIC,anon,authenticated;

-- DRAFT_ROOM_FUNCTION_START
CREATE OR REPLACE FUNCTION public.update_draft_duo_room(p_room_id uuid, p_patch jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_room public.draft_duo_rooms;
  v_bad_keys text[];
  v_team integer[];
  v_settings jsonb;
  v_p1_total numeric;
  v_p2_total numeric;
  v_winner text;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_room FROM public.draft_duo_rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_user IS DISTINCT FROM v_room.player1_id AND v_user IS DISTINCT FROM v_room.player2_id THEN RAISE EXCEPTION 'not_room_player'; END IF;

  SELECT array_agg(key) INTO v_bad_keys
  FROM jsonb_object_keys(p_patch) AS key
  WHERE key <> ALL (ARRAY['status','settings','p1_team','p2_team','winner','p1_ready','p2_ready','player2_id']);
  IF v_bad_keys IS NOT NULL THEN RAISE EXCEPTION 'forbidden_fields: %', v_bad_keys; END IF;
  v_settings := coalesce(p_patch->'settings', v_room.settings, '{}'::jsonb);
  IF p_patch ? 'settings' AND (v_user <> v_room.player1_id OR v_room.status <> 'waiting') THEN RAISE EXCEPTION 'settings_locked'; END IF;

  IF p_patch ? 'p1_team' AND v_user <> v_room.player1_id THEN RAISE EXCEPTION 'forbidden_p1_team'; END IF;
  IF p_patch ? 'p2_team' AND v_user IS DISTINCT FROM v_room.player2_id
     AND NOT (v_user = v_room.player1_id AND p_patch->'p2_team' = '[]'::jsonb AND p_patch->>'status' = 'playing') THEN RAISE EXCEPTION 'forbidden_p2_team'; END IF;
  IF p_patch ? 'p1_ready' AND v_user <> v_room.player1_id
     AND NOT ((p_patch->>'p1_ready')::boolean = false AND p_patch->>'status' = 'finished') THEN RAISE EXCEPTION 'forbidden_p1_ready'; END IF;
  IF p_patch ? 'p2_ready' AND v_user IS DISTINCT FROM v_room.player2_id
     AND NOT (v_user = v_room.player1_id AND ((p_patch->>'p2_ready')::boolean = false OR v_room.player2_id IS NULL)
              OR ((p_patch->>'p2_ready')::boolean = false AND p_patch->>'status' = 'finished')) THEN RAISE EXCEPTION 'forbidden_p2_ready'; END IF;
  IF p_patch ? 'p1_ready' AND (p_patch->>'p1_ready')::boolean AND v_room.status <> 'finished' THEN RAISE EXCEPTION 'ready_not_allowed'; END IF;
  IF p_patch ? 'p2_ready' AND (p_patch->>'p2_ready')::boolean AND v_room.status <> 'finished' THEN RAISE EXCEPTION 'ready_not_allowed'; END IF;

  IF p_patch ? 'p1_team' OR p_patch ? 'p2_team' THEN
    v_team := ARRAY(SELECT jsonb_array_elements_text(CASE WHEN p_patch ? 'p1_team' THEN p_patch->'p1_team' ELSE p_patch->'p2_team' END)::integer);
    IF cardinality(v_team) > 6 OR (SELECT count(DISTINCT item.id) FROM unnest(v_team) AS item(id)) <> cardinality(v_team) THEN RAISE EXCEPTION 'invalid_team'; END IF;
    IF EXISTS (
      SELECT 1 FROM unnest(v_team) AS item(id) LEFT JOIN public.pokemon_catalog p ON p.id = item.id
      WHERE p.id IS NULL
         OR (coalesce(jsonb_array_length(v_settings->'generations'), 0) > 0 AND p.generation NOT IN (SELECT value::integer FROM jsonb_array_elements_text(v_settings->'generations')))
         OR (coalesce(jsonb_array_length(v_settings->'categories'), 0) > 0 AND p.category NOT IN (SELECT value FROM jsonb_array_elements_text(v_settings->'categories')))
    ) THEN RAISE EXCEPTION 'pokemon_outside_settings'; END IF;
  END IF;

  IF p_patch ? 'winner' AND NOT (p_patch ? 'status') THEN RAISE EXCEPTION 'winner_requires_status'; END IF;
  IF p_patch ? 'status' THEN
    IF p_patch->>'status' = 'playing' THEN
      IF v_user <> v_room.player1_id OR v_room.status NOT IN ('waiting','finished') THEN RAISE EXCEPTION 'invalid_launch'; END IF;
      IF v_room.status = 'finished' AND NOT (v_room.p1_ready AND v_room.p2_ready) THEN RAISE EXCEPTION 'replay_not_ready'; END IF;
      IF (SELECT count(*) FROM public.pokemon_catalog p
          WHERE (coalesce(jsonb_array_length(v_settings->'generations'), 0) = 0 OR p.generation IN (SELECT value::integer FROM jsonb_array_elements_text(v_settings->'generations')))
            AND (coalesce(jsonb_array_length(v_settings->'categories'), 0) = 0 OR p.category IN (SELECT value FROM jsonb_array_elements_text(v_settings->'categories')))) < 6 THEN RAISE EXCEPTION 'insufficient_pokemon_pool'; END IF;
    ELSIF p_patch->>'status' = 'finished' AND NULLIF(p_patch->>'winner','') IS NULL THEN
      v_winner := NULL;
    ELSIF p_patch->>'status' = 'finished' THEN
      IF cardinality(v_room.p1_team) <> 6 OR cardinality(v_room.p2_team) <> 6 THEN RAISE EXCEPTION 'game_not_complete'; END IF;
      v_p1_total := public.draft_final_score(v_room.p1_team,v_room.p2_team);
      v_p2_total := public.draft_final_score(v_room.p2_team,v_room.p1_team);
      v_winner := CASE WHEN v_p1_total > v_p2_total THEN 'player1' WHEN v_p2_total > v_p1_total THEN 'player2' ELSE 'draw' END;
    ELSE
      RAISE EXCEPTION 'invalid_status';
    END IF;
  END IF;

  UPDATE public.draft_duo_rooms
  SET
    status = CASE WHEN p_patch ? 'status' THEN p_patch->>'status' ELSE status END,
    settings = CASE WHEN p_patch ? 'settings' THEN p_patch->'settings' ELSE settings END,
    p1_team = CASE WHEN p_patch ? 'p1_team' THEN ARRAY(SELECT jsonb_array_elements_text(p_patch->'p1_team')::integer) ELSE p1_team END,
    p2_team = CASE WHEN p_patch ? 'p2_team' THEN ARRAY(SELECT jsonb_array_elements_text(p_patch->'p2_team')::integer) ELSE p2_team END,
    winner = CASE WHEN p_patch ? 'status' AND p_patch->>'status' = 'playing' THEN NULL WHEN p_patch ? 'status' AND p_patch->>'status' = 'finished' THEN v_winner ELSE winner END,
    p1_ready = CASE WHEN p_patch ? 'p1_ready' THEN (p_patch->>'p1_ready')::boolean ELSE p1_ready END,
    p2_ready = CASE WHEN p_patch ? 'p2_ready' THEN (p_patch->>'p2_ready')::boolean ELSE p2_ready END,
    player2_id = CASE WHEN p_patch ? 'player2_id' THEN NULLIF(p_patch->>'player2_id','')::uuid ELSE player2_id END
  WHERE id = p_room_id;
END;
$$;
-- DRAFT_ROOM_FUNCTION_END

NOTIFY pgrst, 'reload schema';
COMMIT;
