--
-- PostgreSQL database dump
--

\restrict 0ZZHKmD3Kfqu9HpsMDYEza8gCqeItCudjgb1D2hB5Ij2YRyl0iN0NGMB9CbPLa5

-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.3

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: room_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.room_status AS ENUM (
    'waiting',
    'ready',
    'selecting',
    'playing',
    'finished'
);


--
-- Name: append_stat_pick(uuid, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.append_stat_pick(p_room_id uuid, p_column text, p_pick jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_room public.stat_duel_rooms;
  v_stat text;
  v_picks jsonb;
  v_pokemon_id integer;
  v_value integer;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_column NOT IN ('p1_picks','p2_picks') THEN RAISE EXCEPTION 'invalid_pick_column'; END IF;
  SELECT * INTO v_room FROM public.stat_duel_rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_room.status <> 'playing' THEN RAISE EXCEPTION 'room_not_playing'; END IF;
  IF p_column = 'p1_picks' AND v_user <> v_room.player1_id THEN RAISE EXCEPTION 'forbidden_p1_picks'; END IF;
  IF p_column = 'p2_picks' AND v_user IS DISTINCT FROM v_room.player2_id AND NOT (v_user = v_room.player1_id AND v_room.player2_id IS NULL) THEN RAISE EXCEPTION 'forbidden_p2_picks'; END IF;
  IF jsonb_typeof(p_pick) <> 'object' OR NOT (p_pick ? 'stat') OR NOT (p_pick ? 'value') THEN RAISE EXCEPTION 'invalid_pick'; END IF;
  v_stat := p_pick->>'stat';
  IF v_stat NOT IN ('pv','attaque','defense','atq_spe','def_spe','vitesse') THEN RAISE EXCEPTION 'invalid_stat_key'; END IF;

  v_picks := coalesce(CASE WHEN p_column = 'p1_picks' THEN v_room.p1_picks ELSE v_room.p2_picks END, '[]'::jsonb);
  IF jsonb_array_length(v_picks) >= 6 THEN RAISE EXCEPTION 'too_many_picks'; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_picks) AS pick WHERE pick->>'stat' = v_stat) THEN RAISE EXCEPTION 'stat_already_used'; END IF;

  -- Le n-ième choix porte sur le n-ième Pokémon de la partie.
  v_pokemon_id := v_room.pokemon_ids[jsonb_array_length(v_picks) + 1];
  IF v_pokemon_id IS NULL THEN RAISE EXCEPTION 'invalid_round'; END IF;
  SELECT CASE v_stat
    WHEN 'pv' THEN p.pv WHEN 'attaque' THEN p.attaque WHEN 'defense' THEN p.defense
    WHEN 'atq_spe' THEN p.atq_spe WHEN 'def_spe' THEN p.def_spe WHEN 'vitesse' THEN p.vitesse
  END INTO v_value
  FROM public.pokemon_catalog p WHERE p.id = v_pokemon_id;
  IF v_value IS NULL THEN RAISE EXCEPTION 'invalid_pokemon'; END IF;

  IF p_column = 'p1_picks' THEN
    UPDATE public.stat_duel_rooms SET p1_picks = v_picks || jsonb_build_array(jsonb_build_object('stat', v_stat, 'value', v_value)) WHERE id = p_room_id;
  ELSE
    UPDATE public.stat_duel_rooms SET p2_picks = v_picks || jsonb_build_array(jsonb_build_object('stat', v_stat, 'value', v_value)) WHERE id = p_room_id;
  END IF;
END;
$$;


--
-- Name: apply_who_that_pokemon_action(uuid, integer, integer, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apply_who_that_pokemon_action(p_room_id uuid, p_round integer, p_pokemon_id integer, p_skip boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_room public.who_that_pokemon_rooms;
  v_is_p1 boolean;
  v_p1_ready boolean;
  v_p2_ready boolean;
  v_p1_lives integer;
  v_p2_lives integer;
  v_p1_score integer;
  v_p2_score integer;
  v_next integer;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_room FROM public.who_that_pokemon_rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_room.status <> 'playing' THEN RAISE EXCEPTION 'room_not_playing'; END IF;
  IF v_room.round <> p_round THEN RAISE EXCEPTION 'stale_round'; END IF;
  IF v_user = v_room.player1_id THEN
    v_is_p1 := true;
    IF v_room.p1_ready THEN RAISE EXCEPTION 'round_already_completed'; END IF;
  ELSIF v_user = v_room.player2_id THEN
    v_is_p1 := false;
    IF v_room.p2_ready THEN RAISE EXCEPTION 'round_already_completed'; END IF;
  ELSE
    RAISE EXCEPTION 'not_room_player';
  END IF;

  v_p1_ready := v_room.p1_ready;
  v_p2_ready := v_room.p2_ready;
  v_p1_lives := v_room.p1_lives;
  v_p2_lives := v_room.p2_lives;
  v_p1_score := v_room.p1_score;
  v_p2_score := v_room.p2_score;

  IF p_skip THEN
    IF v_is_p1 THEN v_p1_ready := true; ELSE v_p2_ready := true; END IF;
  ELSIF p_pokemon_id IS NULL THEN
    IF v_is_p1 THEN
      v_p1_lives := least(3, v_p1_lives + 1);
    ELSE
      v_p2_lives := least(3, v_p2_lives + 1);
    END IF;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM public.pokemon_catalog WHERE id = p_pokemon_id) THEN
      RAISE EXCEPTION 'invalid_pokemon';
    END IF;
    IF p_pokemon_id = v_room.target_pokemon_id THEN
      IF v_is_p1 THEN
        v_p1_score := v_p1_score + greatest(0, 5 - v_p1_lives);
        v_p1_ready := true;
      ELSE
        v_p2_score := v_p2_score + greatest(0, 5 - v_p2_lives);
        v_p2_ready := true;
      END IF;
    ELSE
      IF v_is_p1 THEN
        v_p1_lives := least(3, v_p1_lives + 1);
      ELSE
        v_p2_lives := least(3, v_p2_lives + 1);
      END IF;
    END IF;
  END IF;

  IF v_p1_ready AND v_p2_ready THEN
    IF v_room.round >= 10 THEN
      UPDATE public.who_that_pokemon_rooms SET status = 'finished', target_pokemon_id = NULL,
        p1_score = v_p1_score, p2_score = v_p2_score,
        p1_lives = v_p1_lives, p2_lives = v_p2_lives,
        winner = CASE WHEN v_p1_score > v_p2_score THEN 'player1'
          WHEN v_p2_score > v_p1_score THEN 'player2' ELSE 'draw' END,
        p1_ready = false, p2_ready = false
      WHERE id = p_room_id;
      RETURN;
    END IF;

    SELECT p.id INTO v_next FROM public.pokemon_catalog p
    WHERE (coalesce(jsonb_array_length(v_room.settings->'generations'), 0) = 0
      OR p.generation IN (SELECT value::integer FROM jsonb_array_elements_text(v_room.settings->'generations')))
      AND (coalesce(jsonb_array_length(v_room.settings->'categories'), 0) = 0
      OR p.category IN (SELECT value FROM jsonb_array_elements_text(v_room.settings->'categories')))
      AND NOT (p.id = ANY(v_room.used_pokemon_ids))
    ORDER BY random() LIMIT 1;
    IF v_next IS NULL THEN
      SELECT p.id INTO v_next FROM public.pokemon_catalog p
      WHERE (coalesce(jsonb_array_length(v_room.settings->'generations'), 0) = 0
        OR p.generation IN (SELECT value::integer FROM jsonb_array_elements_text(v_room.settings->'generations')))
        AND (coalesce(jsonb_array_length(v_room.settings->'categories'), 0) = 0
        OR p.category IN (SELECT value FROM jsonb_array_elements_text(v_room.settings->'categories')))
      ORDER BY random() LIMIT 1;
    END IF;
    IF v_next IS NULL THEN RAISE EXCEPTION 'empty_pokemon_pool'; END IF;
    UPDATE public.who_that_pokemon_rooms SET round = v_room.round + 1,
      target_pokemon_id = v_next, used_pokemon_ids = array_append(v_room.used_pokemon_ids, v_next),
      p1_score = v_p1_score, p2_score = v_p2_score,
      p1_lives = 0, p2_lives = 0, p1_ready = false, p2_ready = false
    WHERE id = p_room_id;
    RETURN;
  END IF;

  UPDATE public.who_that_pokemon_rooms SET p1_score = v_p1_score, p2_score = v_p2_score,
    p1_lives = v_p1_lives, p2_lives = v_p2_lives,
    p1_ready = v_p1_ready, p2_ready = v_p2_ready
  WHERE id = p_room_id;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: pokemon_auction_rooms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pokemon_auction_rooms (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    player1_id uuid NOT NULL,
    player2_id uuid,
    status text DEFAULT 'waiting'::text NOT NULL,
    settings jsonb,
    p1_team integer[] DEFAULT '{}'::integer[] NOT NULL,
    p2_team integer[] DEFAULT '{}'::integer[] NOT NULL,
    p1_balance integer DEFAULT 0 NOT NULL,
    p2_balance integer DEFAULT 0 NOT NULL,
    current_pokemon_id integer,
    used_pokemon_ids integer[] DEFAULT '{}'::integer[] NOT NULL,
    requeue_pokemon_ids integer[] DEFAULT '{}'::integer[] NOT NULL,
    round integer DEFAULT 0 NOT NULL,
    auction_start_at timestamp with time zone,
    auction_end_at timestamp with time zone,
    current_bid integer DEFAULT 0 NOT NULL,
    current_bidder text,
    current_turn text,
    p1_passed boolean DEFAULT false NOT NULL,
    p2_passed boolean DEFAULT false NOT NULL,
    p1_bid_submitted boolean DEFAULT false NOT NULL,
    p2_bid_submitted boolean DEFAULT false NOT NULL,
    last_result jsonb,
    p1_stats_score numeric(3,1),
    p2_stats_score numeric(3,1),
    p1_coverage_score numeric(3,1),
    p2_coverage_score numeric(3,1),
    p1_final_score numeric(3,1),
    p2_final_score numeric(3,1),
    winner text,
    p1_ready boolean DEFAULT false NOT NULL,
    p2_ready boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    p1_passes_left integer DEFAULT 3 NOT NULL,
    p2_passes_left integer DEFAULT 3 NOT NULL,
    version bigint DEFAULT 0 NOT NULL,
    p1_pass_used boolean DEFAULT false NOT NULL,
    p2_pass_used boolean DEFAULT false NOT NULL,
    CONSTRAINT pokemon_auction_rooms_current_bidder_check CHECK ((current_bidder = ANY (ARRAY['player1'::text, 'player2'::text]))),
    CONSTRAINT pokemon_auction_rooms_current_turn_check CHECK ((current_turn = ANY (ARRAY['player1'::text, 'player2'::text]))),
    CONSTRAINT pokemon_auction_rooms_status_check CHECK ((status = ANY (ARRAY['waiting'::text, 'playing'::text, 'finished'::text]))),
    CONSTRAINT pokemon_auction_rooms_winner_check CHECK ((winner = ANY (ARRAY['player1'::text, 'player2'::text, 'draw'::text])))
);


--
-- Name: auction_assert_bid_allowed(public.pokemon_auction_rooms, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auction_assert_bid_allowed(v_room public.pokemon_auction_rooms, v_role text, v_amount integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_balance integer; v_size integer; v_missing integer;
BEGIN
  v_balance:=CASE WHEN v_role='player1' THEN v_room.p1_balance ELSE v_room.p2_balance END;
  v_size:=CASE WHEN v_role='player1' THEN cardinality(v_room.p1_team) ELSE cardinality(v_room.p2_team) END;
  IF v_amount IS NULL OR v_amount<10 OR v_amount%10<>0 OR v_amount>v_balance-greatest(0,5-v_size)*10 THEN RAISE EXCEPTION 'invalid_bid'; END IF;
  IF v_size>=6 THEN
    v_missing:=(6-cardinality(v_room.p1_team))+(6-cardinality(v_room.p2_team));
    IF public.auction_remaining_pool(v_room)<v_missing THEN RAISE EXCEPTION 'blocking_would_exhaust_pool'; END IF;
  END IF;
END; $$;


--
-- Name: auction_begin_next(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auction_begin_next(p_room_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_room public.pokemon_auction_rooms; v_next integer;
BEGIN
  SELECT * INTO v_room FROM public.pokemon_auction_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_room.status<>'playing' THEN RETURN; END IF;
  SELECT p.id INTO v_next FROM public.pokemon_catalog p
  WHERE NOT (p.id=ANY(v_room.used_pokemon_ids))
    AND (coalesce(jsonb_array_length(v_room.settings->'generations'),0)=0 OR p.generation IN (SELECT value::int FROM jsonb_array_elements_text(v_room.settings->'generations')))
    AND (coalesce(jsonb_array_length(v_room.settings->'categories'),0)=0 OR p.category IN (SELECT value FROM jsonb_array_elements_text(v_room.settings->'categories')))
  ORDER BY random() LIMIT 1;
  IF v_next IS NULL THEN RAISE EXCEPTION 'pokemon_pool_exhausted'; END IF;
  DELETE FROM public.pokemon_auction_bids WHERE room_id=p_room_id;
  UPDATE public.pokemon_auction_rooms SET current_pokemon_id=v_next,
    used_pokemon_ids=array_append(used_pokemon_ids,v_next),
    requeue_pokemon_ids='{}', round=round+1,
    auction_start_at=clock_timestamp()+CASE WHEN round=0 THEN interval '5 seconds' ELSE interval '1 second' END,
    auction_end_at=clock_timestamp()+CASE WHEN round=0 THEN interval '20 seconds' ELSE interval '16 seconds' END,
    current_bid=0,current_bidder=NULL,current_turn=CASE WHEN settings->>'auctionFormat'='turn_based' THEN CASE WHEN random()<.5 THEN 'player1' ELSE 'player2' END END,
    p1_passed=false,p2_passed=false,p1_bid_submitted=false,p2_bid_submitted=false,p1_pass_used=false,p2_pass_used=false WHERE id=p_room_id;
END; $$;


--
-- Name: auction_consume_pass(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auction_consume_pass(p_room_id uuid, p_role text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_room public.pokemon_auction_rooms; v_left integer; v_size integer; v_used boolean;
BEGIN
  SELECT * INTO v_room FROM public.pokemon_auction_rooms WHERE id=p_room_id FOR UPDATE;
  IF coalesce((v_room.settings->>'randomAwardOnNoBid')::boolean,true) THEN RETURN; END IF;
  v_size:=CASE WHEN p_role='player1' THEN cardinality(v_room.p1_team) ELSE cardinality(v_room.p2_team) END;
  IF v_size>=6 THEN RETURN; END IF;
  v_used:=CASE WHEN p_role='player1' THEN v_room.p1_pass_used ELSE v_room.p2_pass_used END;
  IF v_used THEN RETURN; END IF;
  v_left:=CASE WHEN p_role='player1' THEN v_room.p1_passes_left ELSE v_room.p2_passes_left END;
  IF v_left<=0 THEN RAISE EXCEPTION 'no_pass_left'; END IF;
  UPDATE public.pokemon_auction_rooms SET
    p1_passes_left=CASE WHEN p_role='player1' THEN p1_passes_left-1 ELSE p1_passes_left END,
    p2_passes_left=CASE WHEN p_role='player2' THEN p2_passes_left-1 ELSE p2_passes_left END,
    p1_pass_used=CASE WHEN p_role='player1' THEN true ELSE p1_pass_used END,
    p2_pass_used=CASE WHEN p_role='player2' THEN true ELSE p2_pass_used END
  WHERE id=p_room_id;
END; $$;


--
-- Name: auction_coverage_score(integer[], integer[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auction_coverage_score(p_team integer[], p_opponent integer[]) RETURNS numeric
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
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


--
-- Name: auction_effective_multiplier(text[], text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auction_effective_multiplier(p_defender_types text[], p_attacker text) RETURNS numeric
    LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_defender text; v_multiplier numeric:=1;
BEGIN
  FOREACH v_defender IN ARRAY p_defender_types LOOP
    v_multiplier:=v_multiplier*public.auction_type_multiplier(p_attacker,v_defender);
  END LOOP;
  RETURN v_multiplier;
END; $$;


--
-- Name: auction_remaining_pool(public.pokemon_auction_rooms); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auction_remaining_pool(v_room public.pokemon_auction_rooms) RETURNS integer
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
  SELECT count(*)::integer FROM public.pokemon_catalog p WHERE NOT(p.id=ANY(v_room.used_pokemon_ids))
    AND (coalesce(jsonb_array_length(v_room.settings->'generations'),0)=0 OR p.generation IN (SELECT value::int FROM jsonb_array_elements_text(v_room.settings->'generations')))
    AND (coalesce(jsonb_array_length(v_room.settings->'categories'),0)=0 OR p.category IN (SELECT value FROM jsonb_array_elements_text(v_room.settings->'categories')));
$$;


--
-- Name: auction_type_multiplier(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auction_type_multiplier(p_attacker text, p_defender text) RETURNS numeric
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    SET search_path TO 'pg_catalog'
    AS $$
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


--
-- Name: bump_row_version(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.bump_row_version() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog'
    AS $$
BEGIN
  NEW.version := OLD.version + 1;
  RETURN NEW;
END; $$;


--
-- Name: cancel_guess_pokemon_room(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cancel_guess_pokemon_room(p_room_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_room public.guess_pokemon_rooms;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_room FROM public.guess_pokemon_rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_user IS DISTINCT FROM v_room.player1_id AND v_user IS DISTINCT FROM v_room.player2_id THEN
    RAISE EXCEPTION 'not_room_player';
  END IF;
  IF v_room.status = 'finished' THEN RETURN; END IF;

  UPDATE public.guess_pokemon_rooms
  SET status = 'finished', winner_id = NULL, current_turn = NULL,
      p1_ready = false, p2_ready = false, last_guess = NULL
  WHERE id = p_room_id;
END;
$$;


--
-- Name: cancel_pokemon_auction_room(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cancel_pokemon_auction_room(p_room_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.pokemon_auction_rooms WHERE id=p_room_id AND (auth.uid()=player1_id OR auth.uid()=player2_id)) THEN RAISE EXCEPTION 'not_room_player'; END IF;
  UPDATE public.pokemon_auction_rooms SET status='finished',winner=NULL,p1_ready=false,p2_ready=false,current_pokemon_id=NULL WHERE id=p_room_id;
END $$;


--
-- Name: delete_old_draft_duo_rooms(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_old_draft_duo_rooms() RETURNS void
    LANGUAGE sql
    AS $$
  DELETE FROM public.draft_duo_rooms
  WHERE created_at <= now() - interval '3 hours';
$$;


--
-- Name: delete_old_game_invites(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_old_game_invites() RETURNS void
    LANGUAGE sql
    AS $$
  DELETE FROM public.game_invites
  WHERE created_at <= now() - interval '24 hours';
$$;


--
-- Name: delete_old_rooms(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_old_rooms() RETURNS void
    LANGUAGE sql
    AS $$
  DELETE FROM public.guess_pokemon_rooms
  WHERE created_at <= now() - interval '3 hours';
$$;


--
-- Name: delete_old_size_up_rooms(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_old_size_up_rooms() RETURNS void
    LANGUAGE sql
    AS $$
  DELETE FROM public.size_up_rooms
  WHERE created_at <= now() - interval '3 hours';
$$;


--
-- Name: delete_old_stat_duel_rooms(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_old_stat_duel_rooms() RETURNS void
    LANGUAGE sql
    AS $$
  DELETE FROM public.stat_duel_rooms
  WHERE created_at <= now() - interval '3 hours';
$$;


--
-- Name: delete_old_who_that_pokemon_rooms(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_old_who_that_pokemon_rooms() RETURNS void
    LANGUAGE sql
    AS $$
  DELETE FROM public.who_that_pokemon_rooms
  WHERE created_at <= now() - interval '3 hours';
$$;


--
-- Name: draft_final_score(integer[], integer[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.draft_final_score(p_team integer[], p_opponent integer[]) RETURNS numeric
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_stats numeric;
BEGIN
  IF EXISTS (SELECT 1 FROM public.pokemon_catalog WHERE id=ANY(p_team||p_opponent)
    AND (rating<=0 OR cardinality(types)=0)) THEN RAISE EXCEPTION 'pokemon_catalog_incomplete'; END IF;
  SELECT round(avg(rating),1) INTO v_stats FROM public.pokemon_catalog WHERE id=ANY(p_team);
  RETURN round((coalesce(v_stats,0)+public.auction_coverage_score(p_team,p_opponent))/2,1);
END; $$;


--
-- Name: finalize_pokemon_auction(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.finalize_pokemon_auction(p_room_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_room public.pokemon_auction_rooms; v_first_pass boolean;
BEGIN
  SELECT * INTO v_room FROM public.pokemon_auction_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND OR (auth.uid() IS DISTINCT FROM v_room.player1_id AND auth.uid() IS DISTINCT FROM v_room.player2_id) THEN RAISE EXCEPTION 'not_room_player'; END IF;
  IF v_room.status<>'playing' OR v_room.current_pokemon_id IS NULL OR clock_timestamp()<v_room.auction_end_at THEN RETURN; END IF;
  IF v_room.settings->>'auctionFormat'='turn_based' THEN
    v_first_pass:=v_room.p1_passed OR v_room.p2_passed;
    IF v_room.current_turn='player1' THEN UPDATE public.pokemon_auction_rooms SET p1_passed=true WHERE id=p_room_id; ELSE UPDATE public.pokemon_auction_rooms SET p2_passed=true WHERE id=p_room_id; END IF;
    IF v_room.current_bid=0 AND NOT v_first_pass THEN UPDATE public.pokemon_auction_rooms SET current_turn=CASE WHEN v_room.current_turn='player1' THEN 'player2' ELSE 'player1' END,auction_end_at=clock_timestamp()+interval '15 seconds' WHERE id=p_room_id; RETURN; END IF;
  END IF;
  PERFORM public.resolve_pokemon_auction(p_room_id,true);
END; $$;


--
-- Name: finalize_size_up_round(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.finalize_size_up_round(p_room_id uuid, p_round integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_room public.size_up_rooms;
  v_pair integer[];
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_room FROM public.size_up_rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_user IS DISTINCT FROM v_room.player1_id AND v_user IS DISTINCT FROM v_room.player2_id THEN RAISE EXCEPTION 'not_room_player'; END IF;
  IF v_room.status <> 'playing' OR v_room.round <> p_round THEN RETURN; END IF;

  IF v_room.round_phase = 'guessing' THEN
    IF v_room.round_deadline IS NOT NULL AND clock_timestamp() >= v_room.round_deadline + interval '2 seconds' THEN
      PERFORM public.size_up_reveal_round(p_room_id);
    END IF;
    RETURN;
  END IF;

  IF v_room.reveal_until IS NULL OR clock_timestamp() < v_room.reveal_until THEN RETURN; END IF;

  IF v_room.round >= 5 THEN
    UPDATE public.size_up_rooms SET
      status = 'finished', round_deadline = NULL, reveal_until = NULL,
      winner = CASE WHEN p1_score > p2_score THEN 'player1' WHEN p2_score > p1_score THEN 'player2' ELSE 'draw' END,
      p1_ready = false, p2_ready = false
    WHERE id = p_room_id;
    DELETE FROM public.size_up_guesses WHERE room_id = p_room_id;
    RETURN;
  END IF;

  v_pair := public.size_up_pick_pair(v_room.settings, v_room.used_pokemon_ids);
  IF coalesce(array_length(v_pair, 1), 0) < 2 THEN RAISE EXCEPTION 'empty_pokemon_pool'; END IF;
  UPDATE public.size_up_rooms SET
    round = round + 1, round_phase = 'guessing',
    reference_pokemon_id = v_pair[1], target_pokemon_id = v_pair[2],
    used_pokemon_ids = used_pokemon_ids || v_pair,
    round_deadline = public.size_up_deadline(settings), reveal_until = NULL,
    p1_submitted = false, p2_submitted = false
  WHERE id = p_room_id;
END;
$$;


--
-- Name: get_my_solo_scores(text, text, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_my_solo_scores(p_mode text, p_settings_key text, p_period text DEFAULT 'all'::text, p_limit integer DEFAULT 20) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_since timestamptz := CASE WHEN p_period = 'week' THEN public.solo_week_start() ELSE '-infinity'::timestamptz END;
  v_limit int := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_trainers boolean := p_mode = 'draft_trainer' AND p_settings_key = 'trainers_defeated';
  v_games int;
  v_best numeric;
  v_average numeric;
  v_rank int;
  v_entries jsonb;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_period NOT IN ('all','week') THEN RAISE EXCEPTION 'invalid_period'; END IF;

  IF v_trainers THEN
    SELECT count(*)::int, count(DISTINCT settings_key) FILTER (WHERE won), NULL
      INTO v_games, v_best, v_average
      FROM public.solo_scores
     WHERE user_id = v_user AND mode = 'draft_trainer' AND created_at >= v_since;
    SELECT 1 + count(*) INTO v_rank FROM (
      SELECT user_id FROM public.solo_scores
       WHERE mode = 'draft_trainer' AND won AND created_at >= v_since AND user_id <> v_user
       GROUP BY user_id HAVING count(DISTINCT settings_key) > coalesce(v_best, 0)
    ) s;
    SELECT coalesce(jsonb_agg(e ORDER BY e->>'settings_key'), '[]'::jsonb) INTO v_entries FROM (
      SELECT DISTINCT ON (settings_key) jsonb_build_object(
        'score', score, 'achieved_at', created_at, 'won', won, 'team', details->'team', 'settings_key', settings_key) AS e
        FROM public.solo_scores
       WHERE user_id = v_user AND mode = 'draft_trainer' AND won AND created_at >= v_since
       ORDER BY settings_key, score DESC, created_at ASC
    ) t;
  ELSE
    SELECT count(*)::int, max(score), round(avg(score), 1)
      INTO v_games, v_best, v_average
      FROM public.solo_scores
     WHERE user_id = v_user AND mode = p_mode AND settings_key = p_settings_key AND created_at >= v_since;
    SELECT 1 + count(*) INTO v_rank FROM (
      SELECT user_id FROM public.solo_scores
       WHERE mode = p_mode AND settings_key = p_settings_key AND created_at >= v_since AND user_id <> v_user
       GROUP BY user_id HAVING max(score) > v_best
    ) s;
    SELECT coalesce(jsonb_agg(e ORDER BY (e->>'score')::numeric DESC, e->>'achieved_at'), '[]'::jsonb) INTO v_entries FROM (
      SELECT jsonb_build_object(
        'score', score, 'achieved_at', created_at, 'won', won, 'team', details->'team', 'settings_key', settings_key) AS e
        FROM public.solo_scores
       WHERE user_id = v_user AND mode = p_mode AND settings_key = p_settings_key AND created_at >= v_since
       ORDER BY score DESC, created_at ASC
       LIMIT v_limit
    ) t;
  END IF;

  RETURN jsonb_build_object(
    'games', v_games,
    'best', v_best,
    'average', v_average,
    'rank', CASE WHEN v_best IS NOT NULL AND (NOT v_trainers OR v_best > 0) THEN v_rank END,
    'entries', v_entries
  );
END; $$;


--
-- Name: get_server_time(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_server_time() RETURNS timestamp with time zone
    LANGUAGE sql
    SET search_path TO 'pg_catalog'
    AS $$ SELECT clock_timestamp(); $$;


--
-- Name: get_solo_leaderboard(text, text, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_solo_leaderboard(p_mode text, p_settings_key text, p_period text DEFAULT 'all'::text, p_limit integer DEFAULT 50) RETURNS TABLE(rank integer, user_id uuid, username text, avatar_url text, score numeric, achieved_at timestamp with time zone, is_me boolean, team jsonb)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
#variable_conflict use_column
DECLARE
  v_user uuid := auth.uid();
  v_since timestamptz := CASE WHEN p_period = 'week' THEN public.solo_week_start() ELSE '-infinity'::timestamptz END;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_period NOT IN ('all','week') THEN RAISE EXCEPTION 'invalid_period'; END IF;

  RETURN QUERY
  WITH best AS (
    -- Dresseurs battus : date de la première victoire contre chaque dresseur.
    SELECT t.user_id, count(*)::numeric AS score, max(t.first_win) AS achieved_at, NULL::jsonb AS team
      FROM (
        SELECT s.user_id, s.settings_key, min(s.created_at) AS first_win
          FROM public.solo_scores s
         WHERE p_mode = 'draft_trainer' AND p_settings_key = 'trainers_defeated'
           AND s.mode = 'draft_trainer' AND s.won AND s.created_at >= v_since
         GROUP BY s.user_id, s.settings_key
      ) t
     GROUP BY t.user_id
    UNION ALL
    (SELECT DISTINCT ON (s.user_id) s.user_id, s.score, s.created_at, s.details->'team'
       FROM public.solo_scores s
      WHERE p_settings_key <> 'trainers_defeated'
        AND s.mode = p_mode AND s.settings_key = p_settings_key AND s.created_at >= v_since
      ORDER BY s.user_id, s.score DESC, s.created_at ASC)
  ), ranked AS (
    SELECT b.*, (rank() OVER (ORDER BY b.score DESC))::int AS rnk,
           row_number() OVER (ORDER BY b.score DESC, b.achieved_at ASC) AS pos
      FROM best b
  )
  SELECT r.rnk, r.user_id, p.username, p.avatar_url, r.score, r.achieved_at, r.user_id = v_user, r.team
    FROM ranked r
    JOIN public.profiles p ON p.id = r.user_id
   WHERE r.pos <= least(greatest(coalesce(p_limit, 50), 1), 100) OR r.user_id = v_user
   ORDER BY r.pos;
END; $$;


--
-- Name: get_solo_leaderboard_categories(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_solo_leaderboard_categories(p_mode text, p_period text DEFAULT 'all'::text) RETURNS TABLE(settings_key text, settings jsonb, players integer)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
#variable_conflict use_column
DECLARE
  v_since timestamptz := CASE WHEN p_period = 'week' THEN public.solo_week_start() ELSE '-infinity'::timestamptz END;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  RETURN QUERY
  SELECT s.settings_key, (array_agg(s.settings))[1], count(DISTINCT s.user_id)::int
    FROM public.solo_scores s
   WHERE s.mode = p_mode AND s.created_at >= v_since
   GROUP BY s.settings_key
   ORDER BY count(DISTINCT s.user_id) DESC, s.settings_key;
END; $$;


--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  INSERT INTO public.profiles (id, username)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'username', split_part(NEW.email, '@', 1))
  );
  RETURN NEW;
END;
$$;


--
-- Name: join_draft_duo_room(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.join_draft_duo_room(p_room_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_room public.draft_duo_rooms;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_room FROM public.draft_duo_rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_room.player1_id = v_user THEN RAISE EXCEPTION 'creator_cannot_join'; END IF;
  IF v_room.player2_id IS NOT NULL OR v_room.status <> 'waiting' THEN RAISE EXCEPTION 'room_not_joinable'; END IF;
  UPDATE public.draft_duo_rooms SET player2_id = v_user WHERE id = p_room_id;
END;
$$;


--
-- Name: join_guess_pokemon_room(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.join_guess_pokemon_room(p_room_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_room public.guess_pokemon_rooms;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_room FROM public.guess_pokemon_rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_room.player1_id = v_user THEN RAISE EXCEPTION 'creator_cannot_join'; END IF;
  IF v_room.player2_id IS NOT NULL OR v_room.status <> 'waiting' THEN RAISE EXCEPTION 'room_not_joinable'; END IF;
  UPDATE public.guess_pokemon_rooms SET player2_id = v_user, status = 'ready' WHERE id = p_room_id;
END;
$$;


--
-- Name: join_pokemon_auction_room(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.join_pokemon_auction_room(p_room_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_room public.pokemon_auction_rooms; v_user uuid:=auth.uid();
BEGIN
  SELECT * INTO v_room FROM public.pokemon_auction_rooms WHERE id=p_room_id FOR UPDATE;
  IF v_user IS NULL OR NOT FOUND OR v_room.status<>'waiting' OR v_room.player2_id IS NOT NULL OR v_room.player1_id=v_user THEN RAISE EXCEPTION 'room_not_joinable'; END IF;
  UPDATE public.pokemon_auction_rooms SET player2_id=v_user WHERE id=p_room_id;
END; $$;


--
-- Name: join_size_up_room(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.join_size_up_room(p_room_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_room public.size_up_rooms;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_room FROM public.size_up_rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_room.player1_id = v_user THEN RAISE EXCEPTION 'creator_cannot_join'; END IF;
  IF v_room.player2_id IS NOT NULL OR v_room.status <> 'waiting' THEN RAISE EXCEPTION 'room_not_joinable'; END IF;
  UPDATE public.size_up_rooms SET player2_id = v_user WHERE id = p_room_id;
END;
$$;


--
-- Name: join_stat_duel_room(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.join_stat_duel_room(p_room_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_room public.stat_duel_rooms;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_room FROM public.stat_duel_rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_room.player1_id = v_user THEN RAISE EXCEPTION 'creator_cannot_join'; END IF;
  IF v_room.player2_id IS NOT NULL OR v_room.status <> 'waiting' THEN RAISE EXCEPTION 'room_not_joinable'; END IF;
  UPDATE public.stat_duel_rooms SET player2_id = v_user WHERE id = p_room_id;
END;
$$;


--
-- Name: join_who_that_pokemon_room(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.join_who_that_pokemon_room(p_room_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_room public.who_that_pokemon_rooms;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_room FROM public.who_that_pokemon_rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_room.player1_id = v_user THEN RAISE EXCEPTION 'creator_cannot_join'; END IF;
  IF v_room.player2_id IS NOT NULL OR v_room.status <> 'waiting' THEN RAISE EXCEPTION 'room_not_joinable'; END IF;
  UPDATE public.who_that_pokemon_rooms SET player2_id = v_user WHERE id = p_room_id;
END;
$$;


--
-- Name: launch_pokemon_auction_room(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.launch_pokemon_auction_room(p_room_id uuid, p_settings jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_room public.pokemon_auction_rooms; v_budget integer; v_count integer;
BEGIN
  SELECT * INTO v_room FROM public.pokemon_auction_rooms WHERE id=p_room_id FOR UPDATE;
  v_budget:=(p_settings->>'startingBudget')::integer;
  IF auth.uid() IS DISTINCT FROM v_room.player1_id OR v_room.player2_id IS NULL OR v_room.status NOT IN ('waiting','finished') THEN RAISE EXCEPTION 'invalid_launch'; END IF;
  IF v_room.status='finished' AND NOT(v_room.p1_ready AND v_room.p2_ready) THEN RAISE EXCEPTION 'replay_not_ready'; END IF;
  IF p_settings->>'auctionFormat' IS NULL OR p_settings->>'auctionFormat' NOT IN ('live','sealed','turn_based') OR v_budget IS NULL OR v_budget<60 OR v_budget>100000 OR v_budget%10<>0 THEN RAISE EXCEPTION 'invalid_settings'; END IF;
  SELECT count(*) INTO v_count FROM public.pokemon_catalog p WHERE
    (coalesce(jsonb_array_length(p_settings->'generations'),0)=0 OR p.generation IN (SELECT value::int FROM jsonb_array_elements_text(p_settings->'generations')))
    AND (coalesce(jsonb_array_length(p_settings->'categories'),0)=0 OR p.category IN (SELECT value FROM jsonb_array_elements_text(p_settings->'categories')));
  IF v_count<12 THEN RAISE EXCEPTION 'insufficient_pokemon_pool'; END IF;
  IF EXISTS (SELECT 1 FROM public.pokemon_catalog p WHERE
    (coalesce(jsonb_array_length(p_settings->'generations'),0)=0 OR p.generation IN (SELECT value::int FROM jsonb_array_elements_text(p_settings->'generations')))
    AND (coalesce(jsonb_array_length(p_settings->'categories'),0)=0 OR p.category IN (SELECT value FROM jsonb_array_elements_text(p_settings->'categories')))
    AND (p.rating<=0 OR cardinality(p.types)=0)) THEN RAISE EXCEPTION 'pokemon_catalog_incomplete'; END IF;
  DELETE FROM public.pokemon_auction_bids WHERE room_id=p_room_id;
  UPDATE public.pokemon_auction_rooms SET status='playing',settings=p_settings,p1_team='{}',p2_team='{}',p1_balance=v_budget,p2_balance=v_budget,
    current_pokemon_id=NULL,used_pokemon_ids='{}',requeue_pokemon_ids='{}',p1_passes_left=3,p2_passes_left=3,round=0,current_bid=0,current_bidder=NULL,current_turn=NULL,last_result=NULL,
    winner=NULL,p1_stats_score=NULL,p2_stats_score=NULL,p1_coverage_score=NULL,p2_coverage_score=NULL,p1_final_score=NULL,p2_final_score=NULL,p1_ready=false,p2_ready=false WHERE id=p_room_id;
  PERFORM public.auction_begin_next(p_room_id);
END; $$;


--
-- Name: pass_pokemon_auction_turn(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pass_pokemon_auction_turn(p_room_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_room public.pokemon_auction_rooms; v_role text; v_other boolean;
BEGIN
  SELECT * INTO v_room FROM public.pokemon_auction_rooms WHERE id=p_room_id FOR UPDATE;
  v_role:=CASE WHEN auth.uid()=v_room.player1_id THEN 'player1' WHEN auth.uid()=v_room.player2_id THEN 'player2' END;
  IF v_role IS NULL OR v_room.status<>'playing' OR v_room.current_pokemon_id IS NULL OR v_room.settings->>'auctionFormat'<>'turn_based' OR v_room.current_turn<>v_role OR clock_timestamp() NOT BETWEEN v_room.auction_start_at AND v_room.auction_end_at THEN RAISE EXCEPTION 'pass_not_allowed'; END IF;
  PERFORM public.auction_consume_pass(p_room_id,v_role);
  v_other:=CASE WHEN v_role='player1' THEN v_room.p2_passed ELSE v_room.p1_passed END;
  UPDATE public.pokemon_auction_rooms SET p1_passed=CASE WHEN v_role='player1' THEN true ELSE p1_passed END,p2_passed=CASE WHEN v_role='player2' THEN true ELSE p2_passed END,current_turn=CASE WHEN v_role='player1' THEN 'player2' ELSE 'player1' END,auction_end_at=clock_timestamp()+interval '15 seconds' WHERE id=p_room_id;
  IF v_room.current_bid>0 OR v_other THEN PERFORM public.resolve_pokemon_auction(p_room_id,true); END IF;
END; $$;


--
-- Name: place_pokemon_auction_bid(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.place_pokemon_auction_bid(p_room_id uuid, p_amount integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_room public.pokemon_auction_rooms; v_role text; v_other_passed boolean;
BEGIN
  SELECT * INTO v_room FROM public.pokemon_auction_rooms WHERE id=p_room_id FOR UPDATE;
  v_role:=CASE WHEN auth.uid()=v_room.player1_id THEN 'player1' WHEN auth.uid()=v_room.player2_id THEN 'player2' END;
  IF v_role IS NULL OR v_room.status<>'playing' OR v_room.settings->>'auctionFormat' NOT IN ('live','turn_based') OR clock_timestamp() NOT BETWEEN v_room.auction_start_at AND v_room.auction_end_at THEN RAISE EXCEPTION 'bid_not_allowed'; END IF;
  IF p_amount<=v_room.current_bid OR v_room.current_bidder=v_role THEN RAISE EXCEPTION 'bid_too_low'; END IF;
  IF v_room.settings->>'auctionFormat'='turn_based' AND v_room.current_turn<>v_role THEN RAISE EXCEPTION 'not_your_turn'; END IF;
  PERFORM public.auction_assert_bid_allowed(v_room,v_role,p_amount);
  v_other_passed:=CASE WHEN v_role='player1' THEN v_room.p2_passed ELSE v_room.p1_passed END;
  UPDATE public.pokemon_auction_rooms SET current_bid=p_amount,current_bidder=v_role,
    auction_end_at=CASE WHEN auction_end_at-clock_timestamp()<interval '10 seconds' THEN clock_timestamp()+interval '10 seconds' ELSE auction_end_at END,
    current_turn=CASE WHEN settings->>'auctionFormat'='turn_based' THEN CASE WHEN v_role='player1' THEN 'player2' ELSE 'player1' END ELSE current_turn END WHERE id=p_room_id;
  IF v_other_passed THEN PERFORM public.resolve_pokemon_auction(p_room_id,true); END IF;
END; $$;


--
-- Name: record_solo_score(uuid, text, jsonb, text, numeric, boolean, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.record_solo_score(p_run_id uuid, p_mode text, p_settings jsonb, p_settings_key text, p_score numeric, p_won boolean, p_details jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_row public.solo_scores;
  v_previous_best numeric;
  v_week_start timestamptz := public.solo_week_start();
  v_rank_all int;
  v_rank_week int;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_run_id IS NULL THEN RAISE EXCEPTION 'invalid_run'; END IF;

  SELECT * INTO v_row FROM public.solo_scores WHERE run_id = p_run_id;
  IF FOUND AND v_row.user_id <> v_user THEN RAISE EXCEPTION 'invalid_run'; END IF;
  IF NOT FOUND THEN
    INSERT INTO public.solo_scores (run_id, user_id, mode, settings, settings_key, score, won, details)
    VALUES (p_run_id, v_user, p_mode, p_settings, p_settings_key, p_score, p_won, coalesce(p_details, '{}'::jsonb))
    ON CONFLICT (run_id) DO NOTHING;
    SELECT * INTO v_row FROM public.solo_scores WHERE run_id = p_run_id;
  END IF;

  SELECT max(score) INTO v_previous_best FROM public.solo_scores
   WHERE user_id = v_user AND mode = v_row.mode AND settings_key = v_row.settings_key
     AND (created_at, id) < (v_row.created_at, v_row.id);

  -- Rang = 1 + nombre de joueurs dont le meilleur score est strictement supérieur.
  SELECT 1 + count(*) INTO v_rank_all FROM (
    SELECT user_id FROM public.solo_scores
     WHERE mode = v_row.mode AND settings_key = v_row.settings_key AND user_id <> v_user
     GROUP BY user_id HAVING max(score) > greatest(v_row.score, coalesce(v_previous_best, v_row.score))
  ) s;
  SELECT 1 + count(*) INTO v_rank_week FROM (
    SELECT user_id FROM public.solo_scores
     WHERE mode = v_row.mode AND settings_key = v_row.settings_key AND user_id <> v_user AND created_at >= v_week_start
     GROUP BY user_id HAVING max(score) > (
       SELECT max(score) FROM public.solo_scores
        WHERE user_id = v_user AND mode = v_row.mode AND settings_key = v_row.settings_key AND created_at >= v_week_start
     )
  ) s;

  RETURN jsonb_build_object(
    'score', v_row.score,
    'won', v_row.won,
    'settings_key', v_row.settings_key,
    'previous_best', v_previous_best,
    'is_record', v_previous_best IS NULL OR v_row.score > v_previous_best,
    'rank_all_time', v_rank_all,
    'rank_week', v_rank_week
  );
END; $$;


--
-- Name: replay_guess_pokemon_room(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.replay_guess_pokemon_room(p_room_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
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


--
-- Name: request_pokemon_auction_replay(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.request_pokemon_auction_replay(p_room_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_room public.pokemon_auction_rooms; v_role text; v_both_ready boolean; v_budget integer;
BEGIN
  SELECT * INTO v_room FROM public.pokemon_auction_rooms WHERE id=p_room_id FOR UPDATE;
  v_role:=CASE WHEN auth.uid()=v_room.player1_id THEN 'player1' WHEN auth.uid()=v_room.player2_id THEN 'player2' END;
  IF v_role IS NULL OR v_room.status<>'finished' OR v_room.winner IS NULL OR cardinality(v_room.p1_team)<>6 OR cardinality(v_room.p2_team)<>6 THEN RAISE EXCEPTION 'replay_not_allowed'; END IF;
  UPDATE public.pokemon_auction_rooms SET p1_ready=CASE WHEN v_role='player1' THEN true ELSE p1_ready END,p2_ready=CASE WHEN v_role='player2' THEN true ELSE p2_ready END WHERE id=p_room_id;
  v_both_ready:=(v_role='player1' OR v_room.p1_ready) AND (v_role='player2' OR v_room.p2_ready);
  IF v_both_ready THEN
    v_budget:=(v_room.settings->>'startingBudget')::integer;
    DELETE FROM public.pokemon_auction_bids WHERE room_id=p_room_id;
    UPDATE public.pokemon_auction_rooms SET status='playing',p1_team='{}',p2_team='{}',p1_balance=v_budget,p2_balance=v_budget,
      current_pokemon_id=NULL,used_pokemon_ids='{}',requeue_pokemon_ids='{}',p1_passes_left=3,p2_passes_left=3,round=0,current_bid=0,current_bidder=NULL,current_turn=NULL,last_result=NULL,
      winner=NULL,p1_stats_score=NULL,p2_stats_score=NULL,p1_coverage_score=NULL,p2_coverage_score=NULL,p1_final_score=NULL,p2_final_score=NULL,p1_ready=false,p2_ready=false WHERE id=p_room_id;
    PERFORM public.auction_begin_next(p_room_id);
  END IF;
END $$;


--
-- Name: resolve_pokemon_auction(uuid, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.resolve_pokemon_auction(p_room_id uuid, p_force boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_room public.pokemon_auction_rooms; v_format text; v_p1 integer:=0; v_p2 integer:=0; v_winner text; v_price integer:=0; v_outcome text; v_team integer[]; v_balance integer;
  v_p1_open boolean; v_p2_open boolean; v_p1_out boolean; v_p2_out boolean; v_forced boolean:=false; v_missing integer;
BEGIN
  SELECT * INTO v_room FROM public.pokemon_auction_rooms WHERE id=p_room_id FOR UPDATE;
  IF auth.uid() IS DISTINCT FROM v_room.player1_id AND auth.uid() IS DISTINCT FROM v_room.player2_id THEN RAISE EXCEPTION 'not_room_player'; END IF;
  IF v_room.status<>'playing' OR v_room.current_pokemon_id IS NULL THEN RETURN; END IF;
  IF NOT p_force AND clock_timestamp()<v_room.auction_end_at THEN RAISE EXCEPTION 'auction_not_finished'; END IF;
  v_format:=v_room.settings->>'auctionFormat';
  IF v_format='sealed' THEN
    SELECT coalesce(max(amount) FILTER(WHERE player_id=v_room.player1_id),0),coalesce(max(amount) FILTER(WHERE player_id=v_room.player2_id),0) INTO v_p1,v_p2 FROM public.pokemon_auction_bids WHERE room_id=p_room_id AND round=v_room.round;
    -- Égalité d'offres secrètes : tirage au sort, le Pokémon ne revient pas plus tard.
    IF v_p1>0 AND v_p1=v_p2 THEN v_winner:=CASE WHEN random()<.5 THEN 'player1' ELSE 'player2' END; v_price:=v_p1;
    ELSIF v_p1>v_p2 THEN v_winner:='player1';v_price:=v_p1; ELSIF v_p2>v_p1 THEN v_winner:='player2';v_price:=v_p2; END IF;
  ELSE v_winner:=v_room.current_bidder;v_price:=v_room.current_bid; IF v_winner='player1' THEN v_p1:=v_price; ELSIF v_winner='player2' THEN v_p2:=v_price; END IF; END IF;
  IF v_winner IS NULL THEN
    v_p1_open:=cardinality(v_room.p1_team)<6; v_p2_open:=cardinality(v_room.p2_team)<6;
    v_missing:=(6-cardinality(v_room.p1_team))+(6-cardinality(v_room.p2_team));
    IF coalesce((v_room.settings->>'randomAwardOnNoBid')::boolean,true) THEN
      IF NOT v_p1_open THEN v_winner:='player2'; ELSIF NOT v_p2_open THEN v_winner:='player1'; ELSE v_winner:=CASE WHEN random()<.5 THEN 'player1' ELSE 'player2' END; END IF;
      v_outcome:='free';v_price:=0;
    ELSE
      -- Jetons de passe : un joueur incomplet qui n'a pas passé et n'a plus de jeton récupère le Pokémon.
      v_p1_out:=v_p1_open AND NOT v_room.p1_pass_used AND v_room.p1_passes_left<=0;
      v_p2_out:=v_p2_open AND NOT v_room.p2_pass_used AND v_room.p2_passes_left<=0;
      -- Le pool restant (ce Pokémon exclu) ne suffit plus : le Pokémon doit être attribué.
      IF NOT (v_p1_out OR v_p2_out) AND public.auction_remaining_pool(v_room)<v_missing THEN
        v_p1_out:=v_p1_open; v_p2_out:=v_p2_open;
      END IF;
      IF v_p1_out OR v_p2_out THEN
        v_winner:=CASE WHEN v_p1_out AND v_p2_out THEN CASE WHEN random()<.5 THEN 'player1' ELSE 'player2' END WHEN v_p1_out THEN 'player1' ELSE 'player2' END;
        v_outcome:='free';v_price:=0;v_forced:=true;
      ELSE
        -- Personne n'a enchéri : un joueur qui n'a pas cliqué sur « Passer » perd aussi un jeton.
        v_outcome:='unsold';
        UPDATE public.pokemon_auction_rooms SET
          p1_passes_left=CASE WHEN v_p1_open AND NOT p1_pass_used THEN greatest(0,p1_passes_left-1) ELSE p1_passes_left END,
          p2_passes_left=CASE WHEN v_p2_open AND NOT p2_pass_used THEN greatest(0,p2_passes_left-1) ELSE p2_passes_left END
        WHERE id=p_room_id;
      END IF;
    END IF;
  END IF;
  IF v_outcome IS NULL THEN
    v_team:=CASE WHEN v_winner='player1' THEN v_room.p1_team ELSE v_room.p2_team END;
    v_balance:=CASE WHEN v_winner='player1' THEN v_room.p1_balance ELSE v_room.p2_balance END;
    IF cardinality(v_team)>=6 THEN v_outcome:='blocked'; ELSE v_outcome:='purchased';v_team:=array_append(v_team,v_room.current_pokemon_id); END IF;
    IF v_winner='player1' THEN UPDATE public.pokemon_auction_rooms SET p1_team=v_team,p1_balance=v_balance-v_price WHERE id=p_room_id; ELSE UPDATE public.pokemon_auction_rooms SET p2_team=v_team,p2_balance=v_balance-v_price WHERE id=p_room_id; END IF;
  ELSIF v_outcome='free' THEN
    IF v_winner='player1' THEN UPDATE public.pokemon_auction_rooms SET p1_team=array_append(p1_team,current_pokemon_id) WHERE id=p_room_id; ELSE UPDATE public.pokemon_auction_rooms SET p2_team=array_append(p2_team,current_pokemon_id) WHERE id=p_room_id; END IF;
  END IF;
  UPDATE public.pokemon_auction_rooms SET last_result=jsonb_build_object('pokemonId',v_room.current_pokemon_id,'outcome',v_outcome,'winner',v_winner,'price',v_price,'p1Bid',v_p1,'p2Bid',v_p2,'round',v_room.round,'forced',v_forced),current_pokemon_id=NULL WHERE id=p_room_id;
  SELECT * INTO v_room FROM public.pokemon_auction_rooms WHERE id=p_room_id;
  IF cardinality(v_room.p1_team)=6 AND cardinality(v_room.p2_team)=6 THEN UPDATE public.pokemon_auction_rooms SET status='finished' WHERE id=p_room_id; ELSE PERFORM public.auction_begin_next(p_room_id); END IF;
END; $$;


--
-- Name: rls_auto_enable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rls_auto_enable() RETURNS event_trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


--
-- Name: save_pokemon_auction_result(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.save_pokemon_auction_result(p_room_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_room public.pokemon_auction_rooms; v_p1_stats numeric; v_p2_stats numeric; v_p1_coverage numeric; v_p2_coverage numeric; v_p1 numeric; v_p2 numeric;
BEGIN
  SELECT * INTO v_room FROM public.pokemon_auction_rooms WHERE id=p_room_id FOR UPDATE;
  IF (auth.uid() IS DISTINCT FROM v_room.player1_id AND auth.uid() IS DISTINCT FROM v_room.player2_id) OR v_room.status<>'finished' OR cardinality(v_room.p1_team)<>6 OR cardinality(v_room.p2_team)<>6 THEN RAISE EXCEPTION 'result_not_allowed'; END IF;
  IF v_room.winner IS NOT NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM public.pokemon_catalog WHERE id=ANY(v_room.p1_team||v_room.p2_team) AND (rating<=0 OR cardinality(types)=0)) THEN RAISE EXCEPTION 'pokemon_catalog_incomplete'; END IF;
  SELECT round(avg(rating),1) INTO v_p1_stats FROM public.pokemon_catalog WHERE id=ANY(v_room.p1_team);
  SELECT round(avg(rating),1) INTO v_p2_stats FROM public.pokemon_catalog WHERE id=ANY(v_room.p2_team);
  v_p1_coverage:=public.auction_coverage_score(v_room.p1_team,v_room.p2_team);
  v_p2_coverage:=public.auction_coverage_score(v_room.p2_team,v_room.p1_team);
  v_p1:=round((v_p1_stats+v_p1_coverage)/2,1);v_p2:=round((v_p2_stats+v_p2_coverage)/2,1);
  UPDATE public.pokemon_auction_rooms SET p1_stats_score=v_p1_stats,p2_stats_score=v_p2_stats,p1_coverage_score=v_p1_coverage,p2_coverage_score=v_p2_coverage,p1_final_score=v_p1,p2_final_score=v_p2,winner=CASE WHEN v_p1>v_p2 THEN 'player1' WHEN v_p2>v_p1 THEN 'player2' ELSE 'draw' END WHERE id=p_room_id;
END; $$;


--
-- Name: set_defeated_trainer_username(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_defeated_trainer_username() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  select p.username
  into new.username
  from public.profiles p
  where p.id = new.user_id;

  return new;
end;
$$;


--
-- Name: set_pokemon_auction_settings(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_pokemon_auction_settings(p_room_id uuid, p_settings jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_room public.pokemon_auction_rooms; v_budget integer;
BEGIN
  SELECT * INTO v_room FROM public.pokemon_auction_rooms WHERE id=p_room_id FOR UPDATE;
  v_budget:=(p_settings->>'startingBudget')::integer;
  IF auth.uid() IS DISTINCT FROM v_room.player1_id OR v_room.status<>'waiting' THEN RAISE EXCEPTION 'settings_locked'; END IF;
  IF p_settings->>'auctionFormat' IS NULL OR p_settings->>'auctionFormat' NOT IN ('live','sealed','turn_based') OR v_budget IS NULL OR v_budget<60 OR v_budget>100000 OR v_budget%10<>0 THEN RAISE EXCEPTION 'invalid_settings'; END IF;
  UPDATE public.pokemon_auction_rooms SET settings=p_settings WHERE id=p_room_id;
END; $$;


--
-- Name: size_up_deadline(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.size_up_deadline(p_settings jsonb) RETURNS timestamp with time zone
    LANGUAGE sql
    SET search_path TO 'pg_catalog'
    AS $$
  SELECT CASE WHEN coalesce((p_settings->>'roundTimer')::int, 0) > 0
    THEN clock_timestamp() + make_interval(secs => (p_settings->>'roundTimer')::int + 1)
    ELSE NULL END;
$$;


--
-- Name: size_up_pick_pair(jsonb, integer[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.size_up_pick_pair(p_settings jsonb, p_used integer[]) RETURNS integer[]
    LANGUAGE sql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
  WITH pool AS (
    SELECT pc.id FROM public.pokemon_catalog pc
    WHERE pc.height > 0
      AND (coalesce(jsonb_array_length(p_settings->'generations'), 0) = 0 OR p_settings->'generations' @> to_jsonb(pc.generation))
      AND (coalesce(jsonb_array_length(p_settings->'categories'), 0) = 0 OR p_settings->'categories' @> to_jsonb(pc.category))
  ), fresh AS (
    SELECT id FROM pool WHERE NOT (id = ANY (coalesce(p_used, '{}'::integer[])))
  )
  SELECT CASE WHEN (SELECT count(*) FROM fresh) >= 2
    THEN ARRAY(SELECT id FROM fresh ORDER BY random() LIMIT 2)
    ELSE ARRAY(SELECT id FROM pool ORDER BY random() LIMIT 2)
  END;
$$;


--
-- Name: size_up_points(numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.size_up_points(p_guess numeric, p_actual numeric) RETURNS integer
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $$
  SELECT CASE
    WHEN p_guess IS NULL OR p_guess <= 0 OR p_actual IS NULL OR p_actual <= 0 THEN 0
    ELSE round((100 * greatest(0, 1 - abs(ln(p_guess::float8 / p_actual::float8)) / ln(5::float8)))::numeric)::integer
  END;
$$;


--
-- Name: size_up_reveal_round(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.size_up_reveal_round(p_room_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_room public.size_up_rooms;
  v_actual numeric;
  v_p1_guess numeric;
  v_p2_guess numeric;
  v_p1_points integer;
  v_p2_points integer;
BEGIN
  SELECT * INTO v_room FROM public.size_up_rooms WHERE id = p_room_id;
  SELECT height INTO v_actual FROM public.pokemon_catalog WHERE id = v_room.target_pokemon_id;
  SELECT guess INTO v_p1_guess FROM public.size_up_guesses WHERE room_id = p_room_id AND round = v_room.round AND player_id = v_room.player1_id;
  SELECT guess INTO v_p2_guess FROM public.size_up_guesses WHERE room_id = p_room_id AND round = v_room.round AND player_id = v_room.player2_id;
  v_p1_points := public.size_up_points(v_p1_guess, v_actual);
  v_p2_points := public.size_up_points(v_p2_guess, v_actual);

  UPDATE public.size_up_rooms SET
    round_phase = 'reveal',
    round_deadline = NULL,
    reveal_until = clock_timestamp() + interval '6 seconds',
    p1_score = p1_score + v_p1_points,
    p2_score = p2_score + v_p2_points,
    history = history || jsonb_build_array(jsonb_build_object(
      'round', v_room.round,
      'reference_id', v_room.reference_pokemon_id,
      'target_id', v_room.target_pokemon_id,
      'p1_guess', v_p1_guess,
      'p2_guess', v_p2_guess,
      'p1_points', v_p1_points,
      'p2_points', v_p2_points
    ))
  WHERE id = p_room_id;
END;
$$;


--
-- Name: skip_who_that_pokemon_round(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.skip_who_that_pokemon_round(p_room_id uuid, p_round integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM public.apply_who_that_pokemon_action(p_room_id, p_round, NULL, true);
END;
$$;


--
-- Name: solo_normalize_settings(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.solo_normalize_settings(p_mode text, p_settings jsonb) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE
  v_gens int[];
  v_cats text[];
  v_hint text;
  v_timer int;
  v_result jsonb;
BEGIN
  SELECT coalesce(array_agg(DISTINCT g::int ORDER BY g::int), '{}')
    INTO v_gens
    FROM jsonb_array_elements_text(coalesce(p_settings->'generations', '[]'::jsonb)) AS g;
  SELECT coalesce(array_agg(DISTINCT c COLLATE "C" ORDER BY c COLLATE "C"), '{}')
    INTO v_cats
    FROM jsonb_array_elements_text(coalesce(p_settings->'categories', '[]'::jsonb)) AS c;
  IF EXISTS (SELECT 1 FROM unnest(v_gens) g WHERE g < 1 OR g > 9) THEN RAISE EXCEPTION 'invalid_settings'; END IF;
  IF EXISTS (SELECT 1 FROM unnest(v_cats) c WHERE c NOT IN (
    'classique','starter','légendaire','fabuleux','fossile','ultra-chimère','pseudo-légendaire','bébé','paradoxe'
  )) THEN RAISE EXCEPTION 'invalid_settings'; END IF;

  v_result := jsonb_build_object('generations', to_jsonb(v_gens), 'categories', to_jsonb(v_cats));
  IF p_mode = 'who_that_pokemon' THEN
    v_hint := coalesce(p_settings->>'initialHint', 'silhouette');
    IF v_hint NOT IN ('silhouette','cry','pokedex_number','description','random') THEN RAISE EXCEPTION 'invalid_settings'; END IF;
    v_result := v_result || jsonb_build_object('initialHint', v_hint);
  END IF;
  IF p_mode = 'size_up' THEN
    v_timer := coalesce((p_settings->>'roundTimer')::int, 0);
    IF v_timer NOT IN (0, 15, 30, 60) THEN RAISE EXCEPTION 'invalid_settings'; END IF;
    IF p_settings ? 'showMeters' AND jsonb_typeof(p_settings->'showMeters') <> 'boolean' THEN RAISE EXCEPTION 'invalid_settings'; END IF;
    v_result := v_result || jsonb_build_object(
      'roundTimer', v_timer,
      'showMeters', coalesce((p_settings->>'showMeters')::boolean, true)
    );
  END IF;
  RETURN v_result;
END; $$;


--
-- Name: solo_pool_ok(integer[], jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.solo_pool_ok(p_ids integer[], p_settings jsonb) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
  SELECT (SELECT count(*) FROM public.pokemon_catalog pc
           WHERE pc.id = ANY(p_ids)
             AND (jsonb_array_length(p_settings->'generations') = 0 OR p_settings->'generations' @> to_jsonb(pc.generation))
             AND (jsonb_array_length(p_settings->'categories') = 0 OR p_settings->'categories' @> to_jsonb(pc.category)))
         = (SELECT count(DISTINCT x) FROM unnest(p_ids) x);
$$;


--
-- Name: solo_settings_key(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.solo_settings_key(p_mode text, p_settings jsonb) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
  SELECT 'g=' || coalesce((SELECT string_agg(g, ',' ORDER BY g::int) FROM jsonb_array_elements_text(p_settings->'generations') g), '')
      || ';c=' || coalesce((SELECT string_agg(c, ',' ORDER BY c COLLATE "C") FROM jsonb_array_elements_text(p_settings->'categories') c), '')
      || CASE WHEN p_mode = 'who_that_pokemon' THEN ';h=' || coalesce(p_settings->>'initialHint', 'silhouette') ELSE '' END
      || CASE WHEN p_mode = 'size_up' THEN ';t=' || coalesce(p_settings->>'roundTimer', '0') ELSE '' END
      || CASE WHEN p_mode = 'size_up' AND p_settings->>'showMeters' = 'false' THEN ';m=0' ELSE '' END;
$$;


--
-- Name: solo_week_start(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.solo_week_start() RETURNS timestamp with time zone
    LANGUAGE sql STABLE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
  SELECT date_trunc('week', now() AT TIME ZONE 'Europe/Paris') AT TIME ZONE 'Europe/Paris';
$$;


--
-- Name: start_size_up_game(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.start_size_up_game(p_room_id uuid, p_settings jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_room public.size_up_rooms;
  v_settings jsonb;
  v_pair integer[];
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_room FROM public.size_up_rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_user <> v_room.player1_id THEN RAISE EXCEPTION 'not_host'; END IF;
  IF v_room.player2_id IS NULL THEN RAISE EXCEPTION 'missing_opponent'; END IF;
  IF NOT (v_room.status = 'waiting' OR (v_room.status = 'finished' AND v_room.p1_ready AND v_room.p2_ready)) THEN
    RAISE EXCEPTION 'room_not_startable';
  END IF;

  -- Revanche : on garde les paramètres de la partie précédente.
  v_settings := public.solo_normalize_settings('size_up',
    CASE WHEN v_room.status = 'finished' AND v_room.settings IS NOT NULL THEN v_room.settings ELSE p_settings END);
  v_pair := public.size_up_pick_pair(v_settings, '{}'::integer[]);
  IF coalesce(array_length(v_pair, 1), 0) < 2 THEN RAISE EXCEPTION 'empty_pokemon_pool'; END IF;

  DELETE FROM public.size_up_guesses WHERE room_id = p_room_id;
  UPDATE public.size_up_rooms SET
    status = 'playing', settings = v_settings, round = 1, round_phase = 'guessing',
    reference_pokemon_id = v_pair[1], target_pokemon_id = v_pair[2], used_pokemon_ids = v_pair,
    round_deadline = public.size_up_deadline(v_settings), reveal_until = NULL,
    p1_submitted = false, p2_submitted = false, p1_score = 0, p2_score = 0, history = '[]'::jsonb,
    winner = NULL, p1_ready = false, p2_ready = false
  WHERE id = p_room_id;
END;
$$;


--
-- Name: submit_draft_score(uuid, jsonb, integer[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.submit_draft_score(p_run_id uuid, p_settings jsonb, p_team integer[]) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE
  v_settings jsonb := public.solo_normalize_settings('draft', p_settings);
  v_score numeric;
BEGIN
  IF cardinality(p_team) <> 6 OR (SELECT count(DISTINCT x) FROM unnest(p_team) x) <> 6 THEN RAISE EXCEPTION 'invalid_team'; END IF;
  IF NOT public.solo_pool_ok(p_team, v_settings) THEN RAISE EXCEPTION 'invalid_team'; END IF;
  SELECT round(avg(rating), 1) INTO v_score FROM public.pokemon_catalog WHERE id = ANY(p_team);
  RETURN public.record_solo_score(p_run_id, 'draft', v_settings, public.solo_settings_key('draft', v_settings),
    v_score, true, jsonb_build_object('team', to_jsonb(p_team)));
END; $$;


--
-- Name: submit_draft_trainer_score(uuid, integer, integer[], integer[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.submit_draft_trainer_score(p_run_id uuid, p_trainer_index integer, p_team integer[], p_opponent integer[]) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE
  v_score numeric;
  v_opponent_score numeric;
BEGIN
  IF p_trainer_index IS NULL OR p_trainer_index < 0 OR p_trainer_index > 200 THEN RAISE EXCEPTION 'invalid_trainer'; END IF;
  IF cardinality(p_team) <> 6 OR (SELECT count(DISTINCT x) FROM unnest(p_team) x) <> 6
     OR cardinality(p_opponent) < 1 OR cardinality(p_opponent) > 6
     OR NOT public.solo_pool_ok(p_team || p_opponent, '{"generations":[],"categories":[]}'::jsonb)
  THEN RAISE EXCEPTION 'invalid_team'; END IF;
  v_score := public.draft_final_score(p_team, p_opponent);
  v_opponent_score := public.draft_final_score(p_opponent, p_team);
  RETURN public.record_solo_score(p_run_id, 'draft_trainer', jsonb_build_object('trainer', p_trainer_index),
    'trainer:' || p_trainer_index, v_score, v_score > v_opponent_score,
    jsonb_build_object('team', to_jsonb(p_team), 'opponent', to_jsonb(p_opponent), 'opponent_score', v_opponent_score));
END; $$;


--
-- Name: submit_guess_pokemon_guess(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.submit_guess_pokemon_guess(p_room_id uuid, p_pokemon_id integer) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_room public.guess_pokemon_rooms;
  v_target integer;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_room FROM public.guess_pokemon_rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_room.status <> 'playing' THEN RAISE EXCEPTION 'room_not_playing'; END IF;
  IF v_room.current_turn IS DISTINCT FROM v_user THEN RAISE EXCEPTION 'not_your_turn'; END IF;
  IF v_user = v_room.player1_id THEN
    v_target := v_room.pokemon_p2;
  ELSIF v_user = v_room.player2_id THEN
    v_target := v_room.pokemon_p1;
  ELSE
    RAISE EXCEPTION 'not_room_player';
  END IF;
  IF v_target IS NULL THEN RAISE EXCEPTION 'missing_target'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.pokemon_catalog WHERE id = p_pokemon_id) THEN
    RAISE EXCEPTION 'invalid_pokemon';
  END IF;

  IF p_pokemon_id = v_target THEN
    UPDATE public.guess_pokemon_rooms SET status = 'finished', winner_id = v_user,
      p1_ready = false, p2_ready = false, last_guess = NULL
    WHERE id = p_room_id;
    RETURN true;
  END IF;

  UPDATE public.guess_pokemon_rooms SET
    current_turn = CASE WHEN v_user = player1_id THEN player2_id ELSE player1_id END,
    last_guess = p_pokemon_id
  WHERE id = p_room_id;
  RETURN false;
END;
$$;


--
-- Name: submit_pokemon_auction_sealed_bid(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.submit_pokemon_auction_sealed_bid(p_room_id uuid, p_amount integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_room public.pokemon_auction_rooms; v_role text;
BEGIN
  SELECT * INTO v_room FROM public.pokemon_auction_rooms WHERE id=p_room_id FOR UPDATE;
  v_role:=CASE WHEN auth.uid()=v_room.player1_id THEN 'player1' WHEN auth.uid()=v_room.player2_id THEN 'player2' END;
  IF p_amount IS NULL OR p_amount<0 OR p_amount%10<>0 OR v_role IS NULL OR v_room.status<>'playing' OR v_room.current_pokemon_id IS NULL OR v_room.settings->>'auctionFormat'<>'sealed' OR clock_timestamp() NOT BETWEEN v_room.auction_start_at AND v_room.auction_end_at OR (v_role='player1' AND v_room.p1_bid_submitted) OR (v_role='player2' AND v_room.p2_bid_submitted) THEN RAISE EXCEPTION 'sealed_bid_not_allowed'; END IF;
  IF p_amount>0 THEN PERFORM public.auction_assert_bid_allowed(v_room,v_role,p_amount); ELSE PERFORM public.auction_consume_pass(p_room_id,v_role); END IF;
  INSERT INTO public.pokemon_auction_bids(room_id,round,player_id,amount) VALUES(p_room_id,v_room.round,auth.uid(),p_amount);
  UPDATE public.pokemon_auction_rooms SET p1_bid_submitted=CASE WHEN v_role='player1' THEN true ELSE p1_bid_submitted END,p2_bid_submitted=CASE WHEN v_role='player2' THEN true ELSE p2_bid_submitted END WHERE id=p_room_id;
  SELECT * INTO v_room FROM public.pokemon_auction_rooms WHERE id=p_room_id;
  IF v_room.p1_bid_submitted AND v_room.p2_bid_submitted THEN PERFORM public.resolve_pokemon_auction(p_room_id,true); END IF;
END; $$;


--
-- Name: submit_size_up_guess(uuid, integer, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.submit_size_up_guess(p_room_id uuid, p_round integer, p_guess numeric) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_room public.size_up_rooms;
  v_is_p1 boolean;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_guess IS NULL OR p_guess < 0.05 OR p_guess > 30 THEN RAISE EXCEPTION 'invalid_guess'; END IF;
  SELECT * INTO v_room FROM public.size_up_rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_room.status <> 'playing' THEN RAISE EXCEPTION 'room_not_playing'; END IF;
  IF v_room.round <> p_round THEN RAISE EXCEPTION 'stale_round'; END IF;
  IF v_room.round_phase <> 'guessing'
     OR (v_room.round_deadline IS NOT NULL AND clock_timestamp() > v_room.round_deadline + interval '2 seconds') THEN
    RAISE EXCEPTION 'round_closed';
  END IF;

  IF v_user = v_room.player1_id THEN
    v_is_p1 := true;
    IF v_room.p1_submitted THEN RAISE EXCEPTION 'already_submitted'; END IF;
  ELSIF v_user = v_room.player2_id THEN
    v_is_p1 := false;
    IF v_room.p2_submitted THEN RAISE EXCEPTION 'already_submitted'; END IF;
  ELSE
    RAISE EXCEPTION 'not_room_player';
  END IF;

  INSERT INTO public.size_up_guesses (room_id, round, player_id, guess) VALUES (p_room_id, p_round, v_user, round(p_guess, 3));
  UPDATE public.size_up_rooms SET
    p1_submitted = p1_submitted OR v_is_p1,
    p2_submitted = p2_submitted OR NOT v_is_p1
  WHERE id = p_room_id
  RETURNING * INTO v_room;

  IF v_room.p1_submitted AND v_room.p2_submitted THEN
    PERFORM public.size_up_reveal_round(p_room_id);
  END IF;
END;
$$;


--
-- Name: submit_size_up_score(uuid, jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.submit_size_up_score(p_run_id uuid, p_settings jsonb, p_rounds jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE
  v_settings jsonb := public.solo_normalize_settings('size_up', p_settings);
  v_ids int[];
  v_score numeric;
BEGIN
  IF jsonb_typeof(p_rounds) <> 'array' OR jsonb_array_length(p_rounds) <> 5 THEN RAISE EXCEPTION 'invalid_rounds'; END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_rounds) r
    WHERE (r->>'reference_id') IS NULL OR (r->>'target_id') IS NULL
       OR (r->>'reference_id')::int = (r->>'target_id')::int
       OR (jsonb_typeof(r->'guess') <> 'null' AND ((r->>'guess')::numeric < 0.05 OR (r->>'guess')::numeric > 30))
  ) THEN RAISE EXCEPTION 'invalid_rounds'; END IF;

  SELECT array_agg(id) INTO v_ids FROM (
    SELECT (r->>'reference_id')::int AS id FROM jsonb_array_elements(p_rounds) r
    UNION ALL
    SELECT (r->>'target_id')::int FROM jsonb_array_elements(p_rounds) r
  ) ids;
  IF NOT public.solo_pool_ok(v_ids, v_settings) THEN RAISE EXCEPTION 'invalid_rounds'; END IF;

  SELECT sum(public.size_up_points(nullif(r->>'guess', '')::numeric, pc.height))
    INTO v_score
    FROM jsonb_array_elements(p_rounds) r
    JOIN public.pokemon_catalog pc ON pc.id = (r->>'target_id')::int;

  RETURN public.record_solo_score(p_run_id, 'size_up', v_settings, public.solo_settings_key('size_up', v_settings),
    coalesce(v_score, 0), true, jsonb_build_object('rounds', p_rounds));
END; $$;


--
-- Name: submit_stat_duel_score(uuid, jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.submit_stat_duel_score(p_run_id uuid, p_settings jsonb, p_picks jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE
  v_settings jsonb := public.solo_normalize_settings('stat_duel', p_settings);
  v_ids int[];
  v_stats text[];
  v_score numeric;
BEGIN
  IF jsonb_typeof(p_picks) <> 'array' OR jsonb_array_length(p_picks) <> 6 THEN RAISE EXCEPTION 'invalid_picks'; END IF;
  SELECT array_agg((p->>'pokemon_id')::int), array_agg(p->>'stat') INTO v_ids, v_stats FROM jsonb_array_elements(p_picks) p;
  IF (SELECT count(DISTINCT x) FROM unnest(v_ids) x) <> 6
     OR (SELECT count(DISTINCT s) FROM unnest(v_stats) s WHERE s IN ('pv','attaque','defense','atq_spe','def_spe','vitesse')) <> 6
  THEN RAISE EXCEPTION 'invalid_picks'; END IF;
  IF NOT public.solo_pool_ok(v_ids, v_settings) THEN RAISE EXCEPTION 'invalid_picks'; END IF;

  SELECT sum(CASE p->>'stat'
      WHEN 'pv' THEN pc.pv WHEN 'attaque' THEN pc.attaque WHEN 'defense' THEN pc.defense
      WHEN 'atq_spe' THEN pc.atq_spe WHEN 'def_spe' THEN pc.def_spe ELSE pc.vitesse END)
    INTO v_score
    FROM jsonb_array_elements(p_picks) p
    JOIN public.pokemon_catalog pc ON pc.id = (p->>'pokemon_id')::int;

  RETURN public.record_solo_score(p_run_id, 'stat_duel', v_settings, public.solo_settings_key('stat_duel', v_settings),
    v_score, true, jsonb_build_object('picks', p_picks));
END; $$;


--
-- Name: submit_who_that_pokemon_guess(uuid, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.submit_who_that_pokemon_guess(p_room_id uuid, p_round integer, p_pokemon_id integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM public.apply_who_that_pokemon_action(p_room_id, p_round, p_pokemon_id, false);
END;
$$;


--
-- Name: submit_who_that_pokemon_score(uuid, jsonb, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.submit_who_that_pokemon_score(p_run_id uuid, p_settings jsonb, p_score integer, p_found integer) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE
  v_settings jsonb := public.solo_normalize_settings('who_that_pokemon', p_settings);
BEGIN
  IF p_found IS NULL OR p_score IS NULL OR p_found < 0 OR p_found > 10 OR p_score < 0 OR p_score > 5 * p_found
     OR p_score < 2 * p_found
  THEN RAISE EXCEPTION 'invalid_score'; END IF;
  RETURN public.record_solo_score(p_run_id, 'who_that_pokemon', v_settings, public.solo_settings_key('who_that_pokemon', v_settings),
    p_score, p_found = 10, jsonb_build_object('found', p_found));
END; $$;


--
-- Name: update_draft_duo_room(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_draft_duo_room(p_room_id uuid, p_patch jsonb) RETURNS void
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
  IF p_patch ? 'player2_id' AND NOT (v_user = v_room.player1_id AND p_patch->>'player2_id' IS NULL AND v_room.status = 'waiting') THEN RAISE EXCEPTION 'forbidden_player2_update'; END IF;

  IF p_patch ? 'p1_team' AND v_user <> v_room.player1_id THEN RAISE EXCEPTION 'forbidden_p1_team'; END IF;
  IF p_patch ? 'p2_team' AND v_user IS DISTINCT FROM v_room.player2_id
     AND NOT (v_user = v_room.player1_id AND p_patch->'p2_team' = '[]'::jsonb AND p_patch->>'status' = 'playing') THEN RAISE EXCEPTION 'forbidden_p2_team'; END IF;
  IF p_patch ? 'p1_ready' AND v_user <> v_room.player1_id
     AND NOT coalesce((p_patch->>'p1_ready')::boolean = false AND p_patch->>'status' = 'finished', false) THEN RAISE EXCEPTION 'forbidden_p1_ready'; END IF;
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


--
-- Name: update_guess_pokemon_room(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_guess_pokemon_room(p_room_id uuid, p_patch jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_room public.guess_pokemon_rooms;
  v_bad_keys text[];
  v_status text := p_patch->>'status';
  v_is_p1 boolean;
  v_dev_room boolean;
  v_launch boolean;
  v_random_launch boolean;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_room FROM public.guess_pokemon_rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_user IS DISTINCT FROM v_room.player1_id AND v_user IS DISTINCT FROM v_room.player2_id THEN RAISE EXCEPTION 'not_room_player'; END IF;

  SELECT array_agg(key) INTO v_bad_keys
  FROM jsonb_object_keys(p_patch) AS key
  WHERE key <> ALL (ARRAY['settings','pokemon_p1','pokemon_p2','p1_ready','p2_ready','current_turn','status','winner_id','last_guess','player2_id']);
  IF v_bad_keys IS NOT NULL THEN RAISE EXCEPTION 'forbidden_fields: %', v_bad_keys; END IF;

  v_is_p1 := v_user = v_room.player1_id;
  -- Room de développement : adversaire simulé, sans compte (player2_id NULL).
  v_dev_room := v_room.player2_id IS NULL;

  IF p_patch ? 'settings' THEN
    IF NOT v_is_p1 THEN RAISE EXCEPTION 'only_player1_can_change_settings'; END IF;
    IF v_room.status NOT IN ('waiting', 'ready', 'selecting') THEN RAISE EXCEPTION 'settings_locked_during_play'; END IF;
  END IF;

  -- Le vainqueur n'est désigné que par submit_guess_pokemon_guess.
  IF p_patch ? 'winner_id' THEN
    IF NULLIF(p_patch->>'winner_id', '') IS NOT NULL THEN RAISE EXCEPTION 'forbidden_winner_id'; END IF;
    IF NOT v_is_p1 THEN RAISE EXCEPTION 'only_player1_can_clear_winner'; END IF;
  END IF;

  IF p_patch ? 'status' THEN
    IF v_status = 'playing' THEN
      -- Les deux joueurs peuvent lancer en même temps : le second appel ne change rien.
      IF v_room.status = 'playing' THEN RETURN; END IF;
      IF v_room.status IN ('waiting', 'ready') THEN
        IF NOT v_is_p1 THEN RAISE EXCEPTION 'only_player1_can_launch'; END IF;
      ELSIF v_room.status <> 'selecting' THEN
        RAISE EXCEPTION 'invalid_status_transition';
      END IF;
    ELSIF v_status IN ('selecting', 'ready') THEN
      IF NOT v_is_p1 OR v_room.status NOT IN ('waiting', 'ready', 'selecting') THEN RAISE EXCEPTION 'invalid_status_transition'; END IF;
    ELSIF v_status = 'finished' THEN
      -- L'abandon passe par cancel_guess_pokemon_room, la victoire par submit_guess_pokemon_guess.
      RAISE EXCEPTION 'finished_requires_winner';
    ELSE
      RAISE EXCEPTION 'invalid_status_transition';
    END IF;
  END IF;

  v_launch := coalesce(v_status = 'playing', false);
  -- Mode Pokémon aléatoire : player1 attribue les deux Pokémon et lance directement.
  v_random_launch := v_launch AND v_is_p1 AND v_room.status IN ('waiting', 'ready');

  IF v_launch AND NOT (
    coalesce((p_patch->>'p1_ready')::boolean, v_room.p1_ready)
    AND coalesce((p_patch->>'p2_ready')::boolean, v_room.p2_ready)
    AND (CASE WHEN p_patch ? 'pokemon_p1' THEN NULLIF(p_patch->>'pokemon_p1','')::integer ELSE v_room.pokemon_p1 END) IS NOT NULL
    AND (CASE WHEN p_patch ? 'pokemon_p2' THEN NULLIF(p_patch->>'pokemon_p2','')::integer ELSE v_room.pokemon_p2 END) IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'players_not_ready';
  END IF;

  IF p_patch ? 'current_turn' THEN
    IF NOT (v_launch OR v_dev_room) THEN RAISE EXCEPTION 'forbidden_current_turn'; END IF;
    IF NULLIF(p_patch->>'current_turn', '') IS NOT NULL AND NOT (
      NULLIF(p_patch->>'current_turn', '')::uuid = v_room.player1_id OR
      (v_room.player2_id IS NOT NULL AND NULLIF(p_patch->>'current_turn', '')::uuid = v_room.player2_id)
    ) THEN
      RAISE EXCEPTION 'invalid_current_turn';
    END IF;
  END IF;

  IF p_patch ? 'last_guess' AND NOT v_dev_room THEN RAISE EXCEPTION 'forbidden_last_guess'; END IF;

  IF p_patch ? 'player2_id' AND NOT (v_is_p1 AND p_patch->>'player2_id' IS NULL AND v_room.status IN ('waiting','ready')) THEN RAISE EXCEPTION 'forbidden_player2_update'; END IF;

  -- Pokémon secrets : modifiables uniquement avant le début de la partie.
  IF (p_patch ? 'pokemon_p1' OR p_patch ? 'pokemon_p2') AND v_room.status NOT IN ('waiting', 'ready', 'selecting') THEN
    RAISE EXCEPTION 'pokemon_locked';
  END IF;
  IF p_patch ? 'pokemon_p1' AND NOT v_is_p1 THEN RAISE EXCEPTION 'forbidden_player1_fields'; END IF;
  IF p_patch ? 'pokemon_p2' AND v_user IS DISTINCT FROM v_room.player2_id AND NOT (v_is_p1 AND (v_random_launch OR v_dev_room)) THEN
    RAISE EXCEPTION 'forbidden_player2_fields';
  END IF;

  IF p_patch ? 'p1_ready' AND NOT v_is_p1 THEN RAISE EXCEPTION 'forbidden_player1_fields'; END IF;
  IF p_patch ? 'p2_ready' AND v_user IS DISTINCT FROM v_room.player2_id AND NOT (v_is_p1 AND (v_random_launch OR v_dev_room)) THEN
    RAISE EXCEPTION 'forbidden_player2_fields';
  END IF;
  -- « Prêt » : pendant la sélection, pour une revanche, ou au lancement.
  IF ((p_patch->>'p1_ready')::boolean OR (p_patch->>'p2_ready')::boolean)
     AND v_room.status NOT IN ('selecting', 'finished') AND NOT v_launch THEN
    RAISE EXCEPTION 'ready_not_allowed';
  END IF;

  UPDATE public.guess_pokemon_rooms
  SET
    settings = CASE WHEN p_patch ? 'settings' THEN p_patch->'settings' ELSE settings END,
    pokemon_p1 = CASE WHEN p_patch ? 'pokemon_p1' THEN NULLIF(p_patch->>'pokemon_p1','')::integer ELSE pokemon_p1 END,
    pokemon_p2 = CASE WHEN p_patch ? 'pokemon_p2' THEN NULLIF(p_patch->>'pokemon_p2','')::integer ELSE pokemon_p2 END,
    p1_ready = CASE WHEN p_patch ? 'p1_ready' THEN (p_patch->>'p1_ready')::boolean ELSE p1_ready END,
    p2_ready = CASE WHEN p_patch ? 'p2_ready' THEN (p_patch->>'p2_ready')::boolean ELSE p2_ready END,
    current_turn = CASE WHEN p_patch ? 'current_turn' THEN NULLIF(p_patch->>'current_turn','')::uuid ELSE current_turn END,
    status = CASE WHEN p_patch ? 'status' THEN (p_patch->>'status')::public.room_status ELSE status END,
    winner_id = CASE WHEN p_patch ? 'winner_id' THEN NULL ELSE winner_id END,
    last_guess = CASE WHEN p_patch ? 'last_guess' THEN NULLIF(p_patch->>'last_guess','')::integer ELSE last_guess END,
    player2_id = CASE WHEN p_patch ? 'player2_id' THEN NULLIF(p_patch->>'player2_id','')::uuid ELSE player2_id END
  WHERE id = p_room_id;
END;
$$;


--
-- Name: update_size_up_room(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_size_up_room(p_room_id uuid, p_patch jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_room public.size_up_rooms;
  v_bad_keys text[];
  v_abandon boolean;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_room FROM public.size_up_rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_user IS DISTINCT FROM v_room.player1_id AND v_user IS DISTINCT FROM v_room.player2_id THEN RAISE EXCEPTION 'not_room_player'; END IF;

  SELECT array_agg(key) INTO v_bad_keys
  FROM jsonb_object_keys(p_patch) AS key
  WHERE key <> ALL (ARRAY['status','settings','winner','p1_ready','p2_ready']);
  IF v_bad_keys IS NOT NULL THEN RAISE EXCEPTION 'forbidden_fields: %', v_bad_keys; END IF;

  IF p_patch ? 'settings' AND (v_user <> v_room.player1_id OR v_room.status <> 'waiting') THEN RAISE EXCEPTION 'settings_locked'; END IF;
  IF p_patch ? 'status' AND p_patch->>'status' IS DISTINCT FROM 'finished' THEN RAISE EXCEPTION 'forbidden_status'; END IF;
  IF p_patch ? 'winner' AND jsonb_typeof(p_patch->'winner') <> 'null' THEN RAISE EXCEPTION 'forbidden_winner'; END IF;
  IF p_patch ? 'p1_ready' AND (p_patch->>'p1_ready')::boolean AND (v_user <> v_room.player1_id OR v_room.status <> 'finished') THEN RAISE EXCEPTION 'forbidden_ready'; END IF;
  IF p_patch ? 'p2_ready' AND (p_patch->>'p2_ready')::boolean AND (v_user IS DISTINCT FROM v_room.player2_id OR v_room.status <> 'finished') THEN RAISE EXCEPTION 'forbidden_ready'; END IF;

  -- Abandon : la room est close sans vainqueur.
  v_abandon := p_patch ? 'status';

  UPDATE public.size_up_rooms
  SET
    status = CASE WHEN v_abandon THEN 'finished' ELSE status END,
    winner = CASE WHEN v_abandon THEN NULL ELSE winner END,
    round_deadline = CASE WHEN v_abandon THEN NULL ELSE round_deadline END,
    reveal_until = CASE WHEN v_abandon THEN NULL ELSE reveal_until END,
    settings = CASE WHEN p_patch ? 'settings' THEN public.solo_normalize_settings('size_up', p_patch->'settings') ELSE settings END,
    p1_ready = CASE WHEN v_abandon THEN false WHEN p_patch ? 'p1_ready' THEN (p_patch->>'p1_ready')::boolean ELSE p1_ready END,
    p2_ready = CASE WHEN v_abandon THEN false WHEN p_patch ? 'p2_ready' THEN (p_patch->>'p2_ready')::boolean ELSE p2_ready END
  WHERE id = p_room_id;
END;
$$;


--
-- Name: update_stat_duel_room(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_stat_duel_room(p_room_id uuid, p_patch jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_room public.stat_duel_rooms;
  v_bad_keys text[];
  v_winner text;
  v_p1_total numeric;
  v_p2_total numeric;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_room FROM public.stat_duel_rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_user IS DISTINCT FROM v_room.player1_id AND v_user IS DISTINCT FROM v_room.player2_id THEN RAISE EXCEPTION 'not_room_player'; END IF;

  SELECT array_agg(key) INTO v_bad_keys
  FROM jsonb_object_keys(p_patch) AS key
  WHERE key <> ALL (ARRAY['status','settings','pokemon_ids','p1_picks','p2_picks','round_start_at','winner','p1_ready','p2_ready','player2_id']);
  IF v_bad_keys IS NOT NULL THEN RAISE EXCEPTION 'forbidden_fields: %', v_bad_keys; END IF;
  IF p_patch ? 'settings' AND (v_user <> v_room.player1_id OR v_room.status <> 'waiting') THEN RAISE EXCEPTION 'settings_locked'; END IF;
  IF (p_patch ? 'pokemon_ids' OR p_patch ? 'round_start_at') AND v_user <> v_room.player1_id THEN RAISE EXCEPTION 'only_player1_can_launch'; END IF;

  IF p_patch ? 'p1_picks' AND (v_user <> v_room.player1_id OR p_patch->'p1_picks' <> '[]'::jsonb) THEN RAISE EXCEPTION 'forbidden_p1_picks'; END IF;
  IF p_patch ? 'p2_picks' AND (v_user <> v_room.player1_id OR p_patch->'p2_picks' <> '[]'::jsonb) THEN RAISE EXCEPTION 'forbidden_p2_picks'; END IF;
  -- player2 peut remettre p1_ready à false en abandonnant (même règle que update_draft_duo_room) :
  -- sans cela, l'abandon de player2 était refusé et la room restait ouverte.
  IF p_patch ? 'p1_ready' AND v_user <> v_room.player1_id
     AND NOT coalesce((p_patch->>'p1_ready')::boolean = false AND p_patch->>'status' = 'finished', false) THEN RAISE EXCEPTION 'forbidden_p1_ready'; END IF;
  IF p_patch ? 'p2_ready' AND v_user IS DISTINCT FROM v_room.player2_id AND NOT (v_user = v_room.player1_id AND ((p_patch->>'p2_ready')::boolean = false OR v_room.player2_id IS NULL)) THEN RAISE EXCEPTION 'forbidden_p2_ready'; END IF;
  IF p_patch ? 'player2_id' AND NOT (v_user = v_room.player1_id AND p_patch->>'player2_id' IS NULL AND v_room.status = 'waiting') THEN RAISE EXCEPTION 'forbidden_player2_update'; END IF;

  -- Le client envoie winner: null au lancement et à l'abandon ; un vainqueur n'est accepté qu'en fin de partie.
  IF NULLIF(p_patch->>'winner', '') IS NOT NULL AND p_patch->>'status' IS DISTINCT FROM 'finished' THEN RAISE EXCEPTION 'winner_requires_status'; END IF;
  IF p_patch->>'status' = 'finished' AND NULLIF(p_patch->>'winner', '') IS NOT NULL THEN
    IF jsonb_array_length(coalesce(v_room.p1_picks, '[]'::jsonb)) <> 6 OR jsonb_array_length(coalesce(v_room.p2_picks, '[]'::jsonb)) <> 6 THEN
      RAISE EXCEPTION 'game_not_complete';
    END IF;
    SELECT coalesce(sum((pick->>'value')::numeric), 0) INTO v_p1_total FROM jsonb_array_elements(v_room.p1_picks) AS pick;
    SELECT coalesce(sum((pick->>'value')::numeric), 0) INTO v_p2_total FROM jsonb_array_elements(v_room.p2_picks) AS pick;
    v_winner := CASE WHEN v_p1_total > v_p2_total THEN 'player1' WHEN v_p2_total > v_p1_total THEN 'player2' ELSE 'draw' END;
  ELSE
    -- Lancement ou abandon : pas de vainqueur.
    v_winner := NULL;
  END IF;

  UPDATE public.stat_duel_rooms
  SET
    status = CASE WHEN p_patch ? 'status' THEN p_patch->>'status' ELSE status END,
    settings = CASE WHEN p_patch ? 'settings' THEN p_patch->'settings' ELSE settings END,
    pokemon_ids = CASE WHEN p_patch ? 'pokemon_ids' THEN ARRAY(SELECT jsonb_array_elements_text(p_patch->'pokemon_ids')::integer) ELSE pokemon_ids END,
    p1_picks = CASE WHEN p_patch ? 'p1_picks' THEN p_patch->'p1_picks' ELSE p1_picks END,
    p2_picks = CASE WHEN p_patch ? 'p2_picks' THEN p_patch->'p2_picks' ELSE p2_picks END,
    round_start_at = CASE WHEN p_patch ? 'round_start_at' THEN NULLIF(p_patch->>'round_start_at','')::timestamp with time zone ELSE round_start_at END,
    winner = CASE WHEN p_patch ? 'winner' THEN v_winner ELSE winner END,
    p1_ready = CASE WHEN p_patch ? 'p1_ready' THEN (p_patch->>'p1_ready')::boolean ELSE p1_ready END,
    p2_ready = CASE WHEN p_patch ? 'p2_ready' THEN (p_patch->>'p2_ready')::boolean ELSE p2_ready END,
    player2_id = CASE WHEN p_patch ? 'player2_id' THEN NULLIF(p_patch->>'player2_id','')::uuid ELSE player2_id END
  WHERE id = p_room_id;
END;
$$;


--
-- Name: update_who_that_pokemon_room(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_who_that_pokemon_room(p_room_id uuid, p_patch jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_room public.who_that_pokemon_rooms;
  v_bad_keys text[];
  v_status text := p_patch->>'status';
  v_launch boolean;
  v_target integer;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_room FROM public.who_that_pokemon_rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_user IS DISTINCT FROM v_room.player1_id AND v_user IS DISTINCT FROM v_room.player2_id THEN RAISE EXCEPTION 'not_room_player'; END IF;

  SELECT array_agg(key) INTO v_bad_keys
  FROM jsonb_object_keys(p_patch) AS key
  WHERE key <> ALL (ARRAY['status','settings','round','target_pokemon_id','used_pokemon_ids','p1_score','p2_score','p1_lives','p2_lives','winner','p1_ready','p2_ready','player2_id']);
  IF v_bad_keys IS NOT NULL THEN RAISE EXCEPTION 'forbidden_fields: %', v_bad_keys; END IF;
  IF p_patch ? 'settings' AND (v_user <> v_room.player1_id OR v_room.status <> 'waiting') THEN RAISE EXCEPTION 'settings_locked'; END IF;

  IF p_patch ? 'status' THEN
    IF v_status = 'playing' THEN
      IF v_user <> v_room.player1_id THEN RAISE EXCEPTION 'only_player1_can_launch'; END IF;
      -- Relance déjà appliquée (realtime + polling) : ne pas tirer une nouvelle cible.
      IF v_room.status = 'playing' THEN RETURN; END IF;
      IF v_room.status = 'finished' AND NOT (v_room.p1_ready AND v_room.p2_ready) THEN RAISE EXCEPTION 'replay_not_ready'; END IF;
    ELSIF v_status = 'finished' THEN
      IF NULLIF(p_patch->>'winner', '') IS NOT NULL THEN RAISE EXCEPTION 'forbidden_winner'; END IF;
    ELSE
      RAISE EXCEPTION 'invalid_status';
    END IF;
  END IF;
  v_launch := coalesce(v_status = 'playing', false);

  IF p_patch ? 'winner' AND NULLIF(p_patch->>'winner', '') IS NOT NULL THEN RAISE EXCEPTION 'forbidden_winner'; END IF;
  IF NOT v_launch AND p_patch ?| ARRAY['round','target_pokemon_id','used_pokemon_ids','p1_score','p2_score','p1_lives','p2_lives'] THEN
    RAISE EXCEPTION 'forbidden_game_fields';
  END IF;

  IF v_launch THEN
    v_target := NULLIF(p_patch->>'target_pokemon_id', '')::integer;
    IF v_target IS NULL OR NOT EXISTS (SELECT 1 FROM public.pokemon_catalog WHERE id = v_target) THEN RAISE EXCEPTION 'invalid_target'; END IF;
  END IF;

  -- « Prêt » (demande de revanche) : uniquement pour soi, en fin de partie.
  IF (p_patch->>'p1_ready')::boolean AND (v_user <> v_room.player1_id OR v_room.status <> 'finished' OR v_launch) THEN RAISE EXCEPTION 'forbidden_p1_ready'; END IF;
  IF (p_patch->>'p2_ready')::boolean AND (v_user IS DISTINCT FROM v_room.player2_id OR v_room.status <> 'finished' OR v_launch) THEN RAISE EXCEPTION 'forbidden_p2_ready'; END IF;
  -- Remise à false : seulement avec un changement de statut (lancement ou abandon).
  IF (p_patch ? 'p1_ready' OR p_patch ? 'p2_ready') AND NOT (p_patch ? 'status')
     AND NOT (coalesce((p_patch->>'p1_ready')::boolean, true) AND coalesce((p_patch->>'p2_ready')::boolean, true)) THEN
    RAISE EXCEPTION 'forbidden_ready_reset';
  END IF;

  IF p_patch ? 'player2_id' AND NOT (v_user = v_room.player1_id AND p_patch->>'player2_id' IS NULL AND v_room.status = 'waiting') THEN RAISE EXCEPTION 'forbidden_player2_update'; END IF;

  UPDATE public.who_that_pokemon_rooms
  SET
    status = CASE WHEN p_patch ? 'status' THEN p_patch->>'status' ELSE status END,
    settings = CASE WHEN p_patch ? 'settings' THEN p_patch->'settings' ELSE settings END,
    round = CASE WHEN v_launch THEN 1 ELSE round END,
    target_pokemon_id = CASE WHEN v_launch THEN v_target ELSE target_pokemon_id END,
    used_pokemon_ids = CASE WHEN v_launch THEN ARRAY[v_target] ELSE used_pokemon_ids END,
    p1_score = CASE WHEN v_launch THEN 0 ELSE p1_score END,
    p2_score = CASE WHEN v_launch THEN 0 ELSE p2_score END,
    p1_lives = CASE WHEN v_launch THEN 0 ELSE p1_lives END,
    p2_lives = CASE WHEN v_launch THEN 0 ELSE p2_lives END,
    winner = CASE WHEN v_launch OR p_patch ? 'winner' THEN NULL ELSE winner END,
    p1_ready = CASE WHEN v_launch THEN false WHEN p_patch ? 'p1_ready' THEN (p_patch->>'p1_ready')::boolean ELSE p1_ready END,
    p2_ready = CASE WHEN v_launch THEN false WHEN p_patch ? 'p2_ready' THEN (p_patch->>'p2_ready')::boolean ELSE p2_ready END,
    player2_id = CASE WHEN p_patch ? 'player2_id' THEN NULLIF(p_patch->>'player2_id','')::uuid ELSE player2_id END
  WHERE id = p_room_id;
END;
$$;


--
-- Name: defeated_trainers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.defeated_trainers (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    user_id uuid NOT NULL,
    trainer_index integer NOT NULL,
    defeated_at timestamp with time zone DEFAULT now(),
    username text
);


--
-- Name: draft_duo_rooms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.draft_duo_rooms (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    player1_id uuid NOT NULL,
    player2_id uuid,
    status text DEFAULT 'waiting'::text NOT NULL,
    p1_team integer[] DEFAULT '{}'::integer[] NOT NULL,
    p2_team integer[] DEFAULT '{}'::integer[] NOT NULL,
    winner text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    p1_ready boolean DEFAULT false NOT NULL,
    p2_ready boolean DEFAULT false NOT NULL,
    settings jsonb,
    CONSTRAINT draft_duo_rooms_status_check CHECK ((status = ANY (ARRAY['waiting'::text, 'playing'::text, 'finished'::text])))
);


--
-- Name: friendships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.friendships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    requester_id uuid NOT NULL,
    recipient_id uuid NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT friendships_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text])))
);


--
-- Name: game_invites; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.game_invites (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    sender_id uuid NOT NULL,
    recipient_id uuid NOT NULL,
    room_id uuid NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    game_mode text DEFAULT 'guess_my_pokemon'::text NOT NULL,
    CONSTRAINT game_invites_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'declined'::text])))
);


--
-- Name: guess_pokemon_rooms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.guess_pokemon_rooms (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    player1_id uuid NOT NULL,
    player2_id uuid,
    pokemon_p1 integer,
    pokemon_p2 integer,
    p1_ready boolean DEFAULT false NOT NULL,
    p2_ready boolean DEFAULT false NOT NULL,
    current_turn uuid,
    status public.room_status DEFAULT 'waiting'::public.room_status NOT NULL,
    winner_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    settings jsonb,
    last_guess integer,
    version bigint DEFAULT 0 NOT NULL
);


--
-- Name: pokemon_auction_bids; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pokemon_auction_bids (
    room_id uuid NOT NULL,
    round integer NOT NULL,
    player_id uuid NOT NULL,
    amount integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT pokemon_auction_bids_amount_check CHECK (((amount >= 0) AND ((amount % 10) = 0)))
);


--
-- Name: pokemon_catalog; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pokemon_catalog (
    id integer NOT NULL,
    generation integer NOT NULL,
    category text NOT NULL,
    types text[] DEFAULT '{}'::text[] NOT NULL,
    rating numeric(3,1) DEFAULT 0 NOT NULL,
    pv integer NOT NULL,
    attaque integer NOT NULL,
    defense integer NOT NULL,
    atq_spe integer NOT NULL,
    def_spe integer NOT NULL,
    vitesse integer NOT NULL,
    height numeric(5,2)
);


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    username text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    avatar_url text
);


--
-- Name: size_up_guesses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.size_up_guesses (
    room_id uuid NOT NULL,
    round integer NOT NULL,
    player_id uuid NOT NULL,
    guess numeric(7,3) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: size_up_rooms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.size_up_rooms (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    player1_id uuid NOT NULL,
    player2_id uuid,
    status text DEFAULT 'waiting'::text NOT NULL,
    settings jsonb,
    round integer DEFAULT 1 NOT NULL,
    round_phase text DEFAULT 'guessing'::text NOT NULL,
    reference_pokemon_id integer,
    target_pokemon_id integer,
    used_pokemon_ids integer[] DEFAULT '{}'::integer[] NOT NULL,
    round_deadline timestamp with time zone,
    reveal_until timestamp with time zone,
    p1_submitted boolean DEFAULT false NOT NULL,
    p2_submitted boolean DEFAULT false NOT NULL,
    p1_score integer DEFAULT 0 NOT NULL,
    p2_score integer DEFAULT 0 NOT NULL,
    history jsonb DEFAULT '[]'::jsonb NOT NULL,
    winner text,
    p1_ready boolean DEFAULT false NOT NULL,
    p2_ready boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    version bigint DEFAULT 0 NOT NULL,
    CONSTRAINT size_up_rooms_round_phase_check CHECK ((round_phase = ANY (ARRAY['guessing'::text, 'reveal'::text]))),
    CONSTRAINT size_up_rooms_status_check CHECK ((status = ANY (ARRAY['waiting'::text, 'playing'::text, 'finished'::text]))),
    CONSTRAINT size_up_rooms_winner_check CHECK (((winner IS NULL) OR (winner = ANY (ARRAY['player1'::text, 'player2'::text, 'draw'::text]))))
);


--
-- Name: solo_scores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solo_scores (
    id bigint NOT NULL,
    run_id uuid NOT NULL,
    user_id uuid NOT NULL,
    mode text NOT NULL,
    settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    settings_key text NOT NULL,
    score numeric(6,1) NOT NULL,
    won boolean DEFAULT false NOT NULL,
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT solo_scores_mode_check CHECK ((mode = ANY (ARRAY['stat_duel'::text, 'who_that_pokemon'::text, 'draft'::text, 'draft_trainer'::text, 'size_up'::text])))
);


--
-- Name: solo_scores_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solo_scores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solo_scores_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solo_scores_id_seq OWNED BY public.solo_scores.id;


--
-- Name: stat_duel_rooms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stat_duel_rooms (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    player1_id uuid NOT NULL,
    player2_id uuid,
    status text DEFAULT 'waiting'::text,
    pokemon_ids integer[] DEFAULT '{}'::integer[],
    p1_picks jsonb DEFAULT '[]'::jsonb,
    p2_picks jsonb DEFAULT '[]'::jsonb,
    round_start_at timestamp with time zone,
    winner text,
    created_at timestamp with time zone DEFAULT now(),
    p1_ready boolean DEFAULT false NOT NULL,
    p2_ready boolean DEFAULT false NOT NULL,
    settings jsonb,
    CONSTRAINT stat_duel_rooms_status_check CHECK ((status = ANY (ARRAY['waiting'::text, 'playing'::text, 'finished'::text])))
);


--
-- Name: who_that_pokemon_rooms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.who_that_pokemon_rooms (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    player1_id uuid NOT NULL,
    player2_id uuid,
    status text DEFAULT 'waiting'::text NOT NULL,
    settings jsonb,
    round integer DEFAULT 1 NOT NULL,
    target_pokemon_id integer,
    used_pokemon_ids integer[] DEFAULT '{}'::integer[] NOT NULL,
    p1_score integer DEFAULT 0 NOT NULL,
    p2_score integer DEFAULT 0 NOT NULL,
    p1_lives integer DEFAULT 0 NOT NULL,
    p2_lives integer DEFAULT 0 NOT NULL,
    winner text,
    p1_ready boolean DEFAULT false NOT NULL,
    p2_ready boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT who_that_pokemon_rooms_status_check CHECK ((status = ANY (ARRAY['waiting'::text, 'playing'::text, 'finished'::text]))),
    CONSTRAINT who_that_pokemon_rooms_winner_check CHECK (((winner IS NULL) OR (winner = ANY (ARRAY['player1'::text, 'player2'::text, 'draw'::text]))))
);


--
-- Name: solo_scores id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solo_scores ALTER COLUMN id SET DEFAULT nextval('public.solo_scores_id_seq'::regclass);


--
-- Name: defeated_trainers defeated_trainers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.defeated_trainers
    ADD CONSTRAINT defeated_trainers_pkey PRIMARY KEY (id);


--
-- Name: defeated_trainers defeated_trainers_user_id_trainer_index_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.defeated_trainers
    ADD CONSTRAINT defeated_trainers_user_id_trainer_index_key UNIQUE (user_id, trainer_index);


--
-- Name: draft_duo_rooms draft_duo_rooms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.draft_duo_rooms
    ADD CONSTRAINT draft_duo_rooms_pkey PRIMARY KEY (id);


--
-- Name: friendships friendships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.friendships
    ADD CONSTRAINT friendships_pkey PRIMARY KEY (id);


--
-- Name: friendships friendships_requester_id_recipient_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.friendships
    ADD CONSTRAINT friendships_requester_id_recipient_id_key UNIQUE (requester_id, recipient_id);


--
-- Name: game_invites game_invites_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_invites
    ADD CONSTRAINT game_invites_pkey PRIMARY KEY (id);


--
-- Name: pokemon_auction_bids pokemon_auction_bids_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pokemon_auction_bids
    ADD CONSTRAINT pokemon_auction_bids_pkey PRIMARY KEY (room_id, round, player_id);


--
-- Name: pokemon_auction_rooms pokemon_auction_rooms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pokemon_auction_rooms
    ADD CONSTRAINT pokemon_auction_rooms_pkey PRIMARY KEY (id);


--
-- Name: pokemon_catalog pokemon_catalog_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pokemon_catalog
    ADD CONSTRAINT pokemon_catalog_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_username_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_username_unique UNIQUE (username);


--
-- Name: guess_pokemon_rooms rooms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.guess_pokemon_rooms
    ADD CONSTRAINT rooms_pkey PRIMARY KEY (id);


--
-- Name: size_up_guesses size_up_guesses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.size_up_guesses
    ADD CONSTRAINT size_up_guesses_pkey PRIMARY KEY (room_id, round, player_id);


--
-- Name: size_up_rooms size_up_rooms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.size_up_rooms
    ADD CONSTRAINT size_up_rooms_pkey PRIMARY KEY (id);


--
-- Name: solo_scores solo_scores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solo_scores
    ADD CONSTRAINT solo_scores_pkey PRIMARY KEY (id);


--
-- Name: solo_scores solo_scores_run_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solo_scores
    ADD CONSTRAINT solo_scores_run_id_key UNIQUE (run_id);


--
-- Name: stat_duel_rooms stat_duel_rooms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stat_duel_rooms
    ADD CONSTRAINT stat_duel_rooms_pkey PRIMARY KEY (id);


--
-- Name: who_that_pokemon_rooms who_that_pokemon_rooms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.who_that_pokemon_rooms
    ADD CONSTRAINT who_that_pokemon_rooms_pkey PRIMARY KEY (id);


--
-- Name: idx_draft_duo_rooms_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_draft_duo_rooms_created_at ON public.draft_duo_rooms USING btree (created_at);


--
-- Name: idx_draft_duo_rooms_player1_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_draft_duo_rooms_player1_id ON public.draft_duo_rooms USING btree (player1_id);


--
-- Name: idx_draft_duo_rooms_player2_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_draft_duo_rooms_player2_id ON public.draft_duo_rooms USING btree (player2_id);


--
-- Name: idx_draft_duo_rooms_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_draft_duo_rooms_status ON public.draft_duo_rooms USING btree (status);


--
-- Name: idx_friendships_pair_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_friendships_pair_unique ON public.friendships USING btree (LEAST(requester_id, recipient_id), GREATEST(requester_id, recipient_id));


--
-- Name: idx_friendships_recipient_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_friendships_recipient_status ON public.friendships USING btree (recipient_id, status);


--
-- Name: idx_friendships_requester_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_friendships_requester_status ON public.friendships USING btree (requester_id, status);


--
-- Name: idx_game_invites_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_game_invites_created_at ON public.game_invites USING btree (created_at);


--
-- Name: idx_game_invites_recipient_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_game_invites_recipient_status ON public.game_invites USING btree (recipient_id, status);


--
-- Name: idx_game_invites_room_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_game_invites_room_id ON public.game_invites USING btree (room_id);


--
-- Name: idx_game_invites_sender_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_game_invites_sender_status ON public.game_invites USING btree (sender_id, status);


--
-- Name: idx_guess_pokemon_rooms_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_guess_pokemon_rooms_created_at ON public.guess_pokemon_rooms USING btree (created_at);


--
-- Name: idx_pokemon_auction_rooms_players; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pokemon_auction_rooms_players ON public.pokemon_auction_rooms USING btree (player1_id, player2_id);


--
-- Name: idx_profiles_lower_username; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profiles_lower_username ON public.profiles USING btree (lower(username));


--
-- Name: idx_rooms_player1_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rooms_player1_id ON public.guess_pokemon_rooms USING btree (player1_id);


--
-- Name: idx_rooms_player2_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rooms_player2_id ON public.guess_pokemon_rooms USING btree (player2_id);


--
-- Name: idx_rooms_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rooms_status ON public.guess_pokemon_rooms USING btree (status);


--
-- Name: idx_size_up_rooms_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_size_up_rooms_created_at ON public.size_up_rooms USING btree (created_at);


--
-- Name: idx_stat_duel_rooms_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stat_duel_rooms_created_at ON public.stat_duel_rooms USING btree (created_at);


--
-- Name: idx_stat_duel_rooms_player1_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stat_duel_rooms_player1_id ON public.stat_duel_rooms USING btree (player1_id);


--
-- Name: idx_stat_duel_rooms_player2_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stat_duel_rooms_player2_id ON public.stat_duel_rooms USING btree (player2_id);


--
-- Name: idx_stat_duel_rooms_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stat_duel_rooms_status ON public.stat_duel_rooms USING btree (status);


--
-- Name: idx_who_that_pokemon_rooms_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_who_that_pokemon_rooms_created_at ON public.who_that_pokemon_rooms USING btree (created_at);


--
-- Name: solo_scores_ranking_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX solo_scores_ranking_idx ON public.solo_scores USING btree (mode, settings_key, score DESC, created_at);


--
-- Name: solo_scores_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX solo_scores_user_idx ON public.solo_scores USING btree (user_id);


--
-- Name: guess_pokemon_rooms guess_pokemon_rooms_bump_version; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER guess_pokemon_rooms_bump_version BEFORE UPDATE ON public.guess_pokemon_rooms FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: pokemon_auction_rooms pokemon_auction_rooms_bump_version; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pokemon_auction_rooms_bump_version BEFORE UPDATE ON public.pokemon_auction_rooms FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: defeated_trainers set_defeated_trainer_username_before_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_defeated_trainer_username_before_write BEFORE INSERT OR UPDATE OF user_id ON public.defeated_trainers FOR EACH ROW EXECUTE FUNCTION public.set_defeated_trainer_username();


--
-- Name: size_up_rooms size_up_rooms_bump_version; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER size_up_rooms_bump_version BEFORE UPDATE ON public.size_up_rooms FOR EACH ROW EXECUTE FUNCTION public.bump_row_version();


--
-- Name: defeated_trainers defeated_trainers_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.defeated_trainers
    ADD CONSTRAINT defeated_trainers_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: draft_duo_rooms draft_duo_rooms_player1_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.draft_duo_rooms
    ADD CONSTRAINT draft_duo_rooms_player1_id_fkey FOREIGN KEY (player1_id) REFERENCES auth.users(id);


--
-- Name: draft_duo_rooms draft_duo_rooms_player2_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.draft_duo_rooms
    ADD CONSTRAINT draft_duo_rooms_player2_id_fkey FOREIGN KEY (player2_id) REFERENCES auth.users(id);


--
-- Name: friendships friendships_recipient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.friendships
    ADD CONSTRAINT friendships_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: friendships friendships_requester_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.friendships
    ADD CONSTRAINT friendships_requester_id_fkey FOREIGN KEY (requester_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: game_invites game_invites_recipient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_invites
    ADD CONSTRAINT game_invites_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: game_invites game_invites_sender_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_invites
    ADD CONSTRAINT game_invites_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: pokemon_auction_bids pokemon_auction_bids_player_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pokemon_auction_bids
    ADD CONSTRAINT pokemon_auction_bids_player_id_fkey FOREIGN KEY (player_id) REFERENCES auth.users(id);


--
-- Name: pokemon_auction_bids pokemon_auction_bids_room_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pokemon_auction_bids
    ADD CONSTRAINT pokemon_auction_bids_room_id_fkey FOREIGN KEY (room_id) REFERENCES public.pokemon_auction_rooms(id) ON DELETE CASCADE;


--
-- Name: pokemon_auction_rooms pokemon_auction_rooms_player1_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pokemon_auction_rooms
    ADD CONSTRAINT pokemon_auction_rooms_player1_id_fkey FOREIGN KEY (player1_id) REFERENCES auth.users(id);


--
-- Name: pokemon_auction_rooms pokemon_auction_rooms_player2_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pokemon_auction_rooms
    ADD CONSTRAINT pokemon_auction_rooms_player2_id_fkey FOREIGN KEY (player2_id) REFERENCES auth.users(id);


--
-- Name: profiles profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: guess_pokemon_rooms rooms_current_turn_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.guess_pokemon_rooms
    ADD CONSTRAINT rooms_current_turn_fkey FOREIGN KEY (current_turn) REFERENCES auth.users(id);


--
-- Name: guess_pokemon_rooms rooms_player1_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.guess_pokemon_rooms
    ADD CONSTRAINT rooms_player1_id_fkey FOREIGN KEY (player1_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: guess_pokemon_rooms rooms_player2_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.guess_pokemon_rooms
    ADD CONSTRAINT rooms_player2_id_fkey FOREIGN KEY (player2_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: guess_pokemon_rooms rooms_winner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.guess_pokemon_rooms
    ADD CONSTRAINT rooms_winner_id_fkey FOREIGN KEY (winner_id) REFERENCES auth.users(id);


--
-- Name: size_up_guesses size_up_guesses_room_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.size_up_guesses
    ADD CONSTRAINT size_up_guesses_room_id_fkey FOREIGN KEY (room_id) REFERENCES public.size_up_rooms(id) ON DELETE CASCADE;


--
-- Name: size_up_rooms size_up_rooms_player1_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.size_up_rooms
    ADD CONSTRAINT size_up_rooms_player1_id_fkey FOREIGN KEY (player1_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: size_up_rooms size_up_rooms_player2_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.size_up_rooms
    ADD CONSTRAINT size_up_rooms_player2_id_fkey FOREIGN KEY (player2_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: solo_scores solo_scores_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solo_scores
    ADD CONSTRAINT solo_scores_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: who_that_pokemon_rooms who_that_pokemon_rooms_player1_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.who_that_pokemon_rooms
    ADD CONSTRAINT who_that_pokemon_rooms_player1_id_fkey FOREIGN KEY (player1_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: who_that_pokemon_rooms who_that_pokemon_rooms_player2_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.who_that_pokemon_rooms
    ADD CONSTRAINT who_that_pokemon_rooms_player2_id_fkey FOREIGN KEY (player2_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: guess_pokemon_rooms Création de room autorisée; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Création de room autorisée" ON public.guess_pokemon_rooms FOR INSERT TO authenticated WITH CHECK ((auth.uid() = player1_id));


--
-- Name: defeated_trainers Les utilisateurs peuvent enregistrer leurs propres victoires; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Les utilisateurs peuvent enregistrer leurs propres victoires" ON public.defeated_trainers FOR INSERT WITH CHECK ((auth.uid() = user_id));


--
-- Name: defeated_trainers Les utilisateurs peuvent supprimer leurs propres victoires; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Les utilisateurs peuvent supprimer leurs propres victoires" ON public.defeated_trainers FOR DELETE USING ((auth.uid() = user_id));


--
-- Name: defeated_trainers Les utilisateurs peuvent voir leurs propres victoires; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Les utilisateurs peuvent voir leurs propres victoires" ON public.defeated_trainers FOR SELECT USING ((auth.uid() = user_id));


--
-- Name: profiles Profil modifiable par son propriétaire; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Profil modifiable par son propriétaire" ON public.profiles FOR UPDATE TO authenticated USING ((auth.uid() = id)) WITH CHECK ((auth.uid() = id));


--
-- Name: profiles Profiles lisibles par tous les authentifiés; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Profiles lisibles par tous les authentifiés" ON public.profiles FOR SELECT TO authenticated USING (true);


--
-- Name: guess_pokemon_rooms Room visible par ses joueurs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Room visible par ses joueurs" ON public.guess_pokemon_rooms FOR SELECT TO authenticated USING (((auth.uid() = player1_id) OR (auth.uid() = player2_id) OR (status = 'waiting'::public.room_status)));


--
-- Name: defeated_trainers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.defeated_trainers ENABLE ROW LEVEL SECURITY;

--
-- Name: draft_duo_rooms; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.draft_duo_rooms ENABLE ROW LEVEL SECURITY;

--
-- Name: draft_duo_rooms draft_duo_rooms_delete_owner; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY draft_duo_rooms_delete_owner ON public.draft_duo_rooms FOR DELETE TO authenticated USING ((auth.uid() = player1_id));


--
-- Name: draft_duo_rooms draft_duo_rooms_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY draft_duo_rooms_insert ON public.draft_duo_rooms FOR INSERT WITH CHECK ((auth.uid() = player1_id));


--
-- Name: draft_duo_rooms draft_duo_rooms_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY draft_duo_rooms_select ON public.draft_duo_rooms FOR SELECT USING (((auth.uid() = player1_id) OR (auth.uid() = player2_id) OR (status = 'waiting'::text)));


--
-- Name: friendships; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;

--
-- Name: friendships friendships_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY friendships_delete_own ON public.friendships FOR DELETE TO authenticated USING (((auth.uid() = requester_id) OR (auth.uid() = recipient_id)));


--
-- Name: friendships friendships_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY friendships_insert ON public.friendships FOR INSERT TO authenticated WITH CHECK (((auth.uid() = requester_id) AND (status = 'pending'::text) AND (requester_id <> recipient_id)));


--
-- Name: friendships friendships_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY friendships_select ON public.friendships FOR SELECT TO authenticated USING (((auth.uid() = requester_id) OR (auth.uid() = recipient_id)));


--
-- Name: friendships friendships_update_accept; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY friendships_update_accept ON public.friendships FOR UPDATE TO authenticated USING (((auth.uid() = recipient_id) AND (status = 'pending'::text))) WITH CHECK (((auth.uid() = recipient_id) AND (status = 'accepted'::text)));


--
-- Name: game_invites; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.game_invites ENABLE ROW LEVEL SECURITY;

--
-- Name: game_invites game_invites_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY game_invites_insert ON public.game_invites FOR INSERT TO authenticated WITH CHECK (((auth.uid() = sender_id) AND (status = 'pending'::text) AND (sender_id <> recipient_id) AND (game_mode = ANY (ARRAY['guess_my_pokemon'::text, 'stat_duel'::text, 'draft_duo'::text, 'who_that_pokemon'::text, 'pokemon_auction'::text, 'size_up'::text]))));


--
-- Name: game_invites game_invites_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY game_invites_select ON public.game_invites FOR SELECT TO authenticated USING (((auth.uid() = sender_id) OR (auth.uid() = recipient_id)));


--
-- Name: game_invites game_invites_update_recipient; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY game_invites_update_recipient ON public.game_invites FOR UPDATE TO authenticated USING (((auth.uid() = recipient_id) AND (status = 'pending'::text))) WITH CHECK (((auth.uid() = recipient_id) AND (status = ANY (ARRAY['accepted'::text, 'declined'::text]))));


--
-- Name: game_invites game_invites_update_sender; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY game_invites_update_sender ON public.game_invites FOR UPDATE TO authenticated USING (((auth.uid() = sender_id) AND (status = 'pending'::text))) WITH CHECK (((auth.uid() = sender_id) AND (status = ANY (ARRAY['pending'::text, 'declined'::text]))));


--
-- Name: guess_pokemon_rooms; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.guess_pokemon_rooms ENABLE ROW LEVEL SECURITY;

--
-- Name: guess_pokemon_rooms guess_pokemon_rooms_delete_owner; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY guess_pokemon_rooms_delete_owner ON public.guess_pokemon_rooms FOR DELETE TO authenticated USING ((auth.uid() = player1_id));


--
-- Name: pokemon_auction_bids; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pokemon_auction_bids ENABLE ROW LEVEL SECURITY;

--
-- Name: pokemon_auction_bids pokemon_auction_bids_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pokemon_auction_bids_select_own ON public.pokemon_auction_bids FOR SELECT TO authenticated USING ((auth.uid() = player_id));


--
-- Name: pokemon_auction_rooms; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pokemon_auction_rooms ENABLE ROW LEVEL SECURITY;

--
-- Name: pokemon_auction_rooms pokemon_auction_rooms_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pokemon_auction_rooms_delete ON public.pokemon_auction_rooms FOR DELETE TO authenticated USING ((auth.uid() = player1_id));


--
-- Name: pokemon_auction_rooms pokemon_auction_rooms_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pokemon_auction_rooms_insert ON public.pokemon_auction_rooms FOR INSERT TO authenticated WITH CHECK ((auth.uid() = player1_id));


--
-- Name: pokemon_auction_rooms pokemon_auction_rooms_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pokemon_auction_rooms_select ON public.pokemon_auction_rooms FOR SELECT TO authenticated USING (((auth.uid() = player1_id) OR (auth.uid() = player2_id) OR (EXISTS ( SELECT 1
   FROM public.game_invites invite
  WHERE ((invite.room_id = pokemon_auction_rooms.id) AND (invite.recipient_id = auth.uid()) AND (invite.game_mode = 'pokemon_auction'::text) AND (invite.status = 'pending'::text))))));


--
-- Name: pokemon_catalog; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pokemon_catalog ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles profiles_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_insert_own ON public.profiles FOR INSERT TO authenticated WITH CHECK ((auth.uid() = id));


--
-- Name: size_up_guesses; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.size_up_guesses ENABLE ROW LEVEL SECURITY;

--
-- Name: size_up_rooms; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.size_up_rooms ENABLE ROW LEVEL SECURITY;

--
-- Name: size_up_rooms size_up_rooms_delete_owner; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY size_up_rooms_delete_owner ON public.size_up_rooms FOR DELETE TO authenticated USING ((auth.uid() = player1_id));


--
-- Name: size_up_rooms size_up_rooms_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY size_up_rooms_insert ON public.size_up_rooms FOR INSERT TO authenticated WITH CHECK (((auth.uid() = player1_id) AND (status = 'waiting'::text) AND (player2_id IS NULL)));


--
-- Name: size_up_rooms size_up_rooms_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY size_up_rooms_select ON public.size_up_rooms FOR SELECT TO authenticated USING (((auth.uid() = player1_id) OR (auth.uid() = player2_id) OR (status = 'waiting'::text)));


--
-- Name: solo_scores; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.solo_scores ENABLE ROW LEVEL SECURITY;

--
-- Name: stat_duel_rooms; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stat_duel_rooms ENABLE ROW LEVEL SECURITY;

--
-- Name: stat_duel_rooms stat_duel_rooms_delete_owner; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY stat_duel_rooms_delete_owner ON public.stat_duel_rooms FOR DELETE TO authenticated USING ((auth.uid() = player1_id));


--
-- Name: stat_duel_rooms stat_duel_rooms_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY stat_duel_rooms_insert ON public.stat_duel_rooms FOR INSERT TO authenticated WITH CHECK ((auth.uid() = player1_id));


--
-- Name: stat_duel_rooms stat_duel_rooms_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY stat_duel_rooms_select ON public.stat_duel_rooms FOR SELECT TO authenticated USING (((auth.uid() = player1_id) OR (auth.uid() = player2_id) OR (status = 'waiting'::text)));


--
-- Name: who_that_pokemon_rooms; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.who_that_pokemon_rooms ENABLE ROW LEVEL SECURITY;

--
-- Name: who_that_pokemon_rooms who_that_pokemon_rooms_delete_owner; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY who_that_pokemon_rooms_delete_owner ON public.who_that_pokemon_rooms FOR DELETE TO authenticated USING ((auth.uid() = player1_id));


--
-- Name: who_that_pokemon_rooms who_that_pokemon_rooms_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY who_that_pokemon_rooms_insert ON public.who_that_pokemon_rooms FOR INSERT TO authenticated WITH CHECK ((auth.uid() = player1_id));


--
-- Name: who_that_pokemon_rooms who_that_pokemon_rooms_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY who_that_pokemon_rooms_select ON public.who_that_pokemon_rooms FOR SELECT TO authenticated USING (((auth.uid() = player1_id) OR (auth.uid() = player2_id) OR (status = 'waiting'::text)));


--
-- PostgreSQL database dump complete
--

\unrestrict 0ZZHKmD3Kfqu9HpsMDYEza8gCqeItCudjgb1D2hB5Ij2YRyl0iN0NGMB9CbPLa5

