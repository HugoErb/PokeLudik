--
-- PostgreSQL database dump
--

\restrict ucbMrcVDrU10JUdFCr1xH6p4xZoFIfHZwOaoPWxC3Du0eFZyUfNTTCIsX4Zc72i

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
  v_value numeric;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_column NOT IN ('p1_picks','p2_picks') THEN RAISE EXCEPTION 'invalid_pick_column'; END IF;
  SELECT * INTO v_room FROM public.stat_duel_rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_room.status <> 'playing' THEN RAISE EXCEPTION 'room_not_playing'; END IF;
  IF p_column = 'p1_picks' AND v_user <> v_room.player1_id THEN RAISE EXCEPTION 'forbidden_p1_picks'; END IF;
  IF p_column = 'p2_picks' AND v_user IS DISTINCT FROM v_room.player2_id AND NOT (v_user = v_room.player1_id AND v_room.player2_id IS NULL) THEN RAISE EXCEPTION 'forbidden_p2_picks'; END IF;
  IF jsonb_typeof(p_pick) <> 'object' OR NOT (p_pick ? 'stat') OR NOT (p_pick ? 'value') THEN RAISE EXCEPTION 'invalid_pick'; END IF;
  -- Validation de la clé de stat
  v_stat := p_pick->>'stat';
  IF v_stat NOT IN ('pv','attaque','defense','atq_spe','def_spe','vitesse') THEN RAISE EXCEPTION 'invalid_stat_key'; END IF;
  -- Validation de la plage de valeur (base stats Pokémon : 1–999)
  v_value := (p_pick->>'value')::numeric;
  IF v_value IS NULL OR v_value < 1 OR v_value > 999 THEN RAISE EXCEPTION 'invalid_stat_value'; END IF;
  IF p_column = 'p1_picks' THEN
    IF jsonb_array_length(v_room.p1_picks) >= 6 THEN RAISE EXCEPTION 'too_many_picks'; END IF;
    UPDATE public.stat_duel_rooms SET p1_picks = v_room.p1_picks || jsonb_build_array(p_pick) WHERE id = p_room_id;
  ELSE
    IF jsonb_array_length(v_room.p2_picks) >= 6 THEN RAISE EXCEPTION 'too_many_picks'; END IF;
    UPDATE public.stat_duel_rooms SET p2_picks = v_room.p2_picks || jsonb_build_array(p_pick) WHERE id = p_room_id;
  END IF;
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
DECLARE v_balance integer; v_size integer; v_future integer; v_missing integer;
BEGIN
  v_balance:=CASE WHEN v_role='player1' THEN v_room.p1_balance ELSE v_room.p2_balance END;
  v_size:=CASE WHEN v_role='player1' THEN cardinality(v_room.p1_team) ELSE cardinality(v_room.p2_team) END;
  IF v_amount IS NULL OR v_amount<10 OR v_amount%10<>0 OR v_amount>v_balance-greatest(0,5-v_size)*10 THEN RAISE EXCEPTION 'invalid_bid'; END IF;
  IF v_size>=6 THEN
    SELECT count(*) INTO v_future FROM public.pokemon_catalog p WHERE NOT(p.id=ANY(v_room.used_pokemon_ids))
      AND (coalesce(jsonb_array_length(v_room.settings->'generations'),0)=0 OR p.generation IN (SELECT value::int FROM jsonb_array_elements_text(v_room.settings->'generations')))
      AND (coalesce(jsonb_array_length(v_room.settings->'categories'),0)=0 OR p.category IN (SELECT value FROM jsonb_array_elements_text(v_room.settings->'categories')));
    v_future:=v_future+coalesce(cardinality(v_room.requeue_pokemon_ids),0);
    v_missing:=(6-cardinality(v_room.p1_team))+(6-cardinality(v_room.p2_team));
    IF v_future<v_missing THEN RAISE EXCEPTION 'blocking_would_exhaust_pool'; END IF;
  END IF;
END; $$;


--
-- Name: auction_begin_next(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auction_begin_next(p_room_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE v_room public.pokemon_auction_rooms; v_next integer; v_queue integer[];
BEGIN
  SELECT * INTO v_room FROM public.pokemon_auction_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_room.status<>'playing' THEN RETURN; END IF;
  v_queue:=v_room.requeue_pokemon_ids;
  IF coalesce(cardinality(v_queue),0)>0 AND coalesce(v_room.last_result->>'outcome','') NOT IN ('tied','unsold') THEN
    v_next:=v_queue[1]; v_queue:=v_queue[2:cardinality(v_queue)];
  ELSE
    SELECT p.id INTO v_next FROM public.pokemon_catalog p
    WHERE NOT (p.id=ANY(v_room.used_pokemon_ids))
      AND (coalesce(jsonb_array_length(v_room.settings->'generations'),0)=0 OR p.generation IN (SELECT value::int FROM jsonb_array_elements_text(v_room.settings->'generations')))
      AND (coalesce(jsonb_array_length(v_room.settings->'categories'),0)=0 OR p.category IN (SELECT value FROM jsonb_array_elements_text(v_room.settings->'categories')))
    ORDER BY random() LIMIT 1;
  END IF;
  IF v_next IS NULL AND coalesce(cardinality(v_queue),0)>0 THEN v_next:=v_queue[1]; v_queue:=v_queue[2:cardinality(v_queue)]; END IF;
  IF v_next IS NULL THEN RAISE EXCEPTION 'pokemon_pool_exhausted'; END IF;
  DELETE FROM public.pokemon_auction_bids WHERE room_id=p_room_id;
  UPDATE public.pokemon_auction_rooms SET current_pokemon_id=v_next,
    used_pokemon_ids=CASE WHEN v_next=ANY(used_pokemon_ids) THEN used_pokemon_ids ELSE array_append(used_pokemon_ids,v_next) END,
    requeue_pokemon_ids=coalesce(v_queue,'{}'), round=round+1,
    auction_start_at=clock_timestamp()+CASE WHEN round=0 THEN interval '5 seconds' ELSE interval '1 second' END,
    auction_end_at=clock_timestamp()+CASE WHEN round=0 THEN interval '35 seconds' ELSE interval '31 seconds' END,
    current_bid=0,current_bidder=NULL,current_turn=CASE WHEN settings->>'auctionFormat'='turn_based' THEN CASE WHEN random()<.5 THEN 'player1' ELSE 'player2' END END,
    p1_passed=false,p2_passed=false,p1_bid_submitted=false,p2_bid_submitted=false WHERE id=p_room_id;
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
    current_pokemon_id=NULL,used_pokemon_ids='{}',requeue_pokemon_ids='{}',round=0,current_bid=0,current_bidder=NULL,current_turn=NULL,last_result=NULL,
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
      current_pokemon_id=NULL,used_pokemon_ids='{}',requeue_pokemon_ids='{}',round=0,current_bid=0,current_bidder=NULL,current_turn=NULL,last_result=NULL,
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
BEGIN
  SELECT * INTO v_room FROM public.pokemon_auction_rooms WHERE id=p_room_id FOR UPDATE;
  IF auth.uid() IS DISTINCT FROM v_room.player1_id AND auth.uid() IS DISTINCT FROM v_room.player2_id THEN RAISE EXCEPTION 'not_room_player'; END IF;
  IF v_room.status<>'playing' OR v_room.current_pokemon_id IS NULL THEN RETURN; END IF;
  IF NOT p_force AND clock_timestamp()<v_room.auction_end_at THEN RAISE EXCEPTION 'auction_not_finished'; END IF;
  v_format:=v_room.settings->>'auctionFormat';
  IF v_format='sealed' THEN
    SELECT coalesce(max(amount) FILTER(WHERE player_id=v_room.player1_id),0),coalesce(max(amount) FILTER(WHERE player_id=v_room.player2_id),0) INTO v_p1,v_p2 FROM public.pokemon_auction_bids WHERE room_id=p_room_id AND round=v_room.round;
    IF v_p1>0 AND v_p1=v_p2 THEN v_outcome:='tied'; UPDATE public.pokemon_auction_rooms SET requeue_pokemon_ids=array_append(requeue_pokemon_ids,current_pokemon_id) WHERE id=p_room_id;
    ELSIF v_p1>v_p2 THEN v_winner:='player1';v_price:=v_p1; ELSIF v_p2>v_p1 THEN v_winner:='player2';v_price:=v_p2; END IF;
  ELSE v_winner:=v_room.current_bidder;v_price:=v_room.current_bid; IF v_winner='player1' THEN v_p1:=v_price; ELSIF v_winner='player2' THEN v_p2:=v_price; END IF; END IF;
  IF v_outcome IS NULL AND v_winner IS NULL THEN
    IF coalesce((v_room.settings->>'randomAwardOnNoBid')::boolean,true) THEN
      IF cardinality(v_room.p1_team)>=6 THEN v_winner:='player2'; ELSIF cardinality(v_room.p2_team)>=6 THEN v_winner:='player1'; ELSE v_winner:=CASE WHEN random()<.5 THEN 'player1' ELSE 'player2' END; END IF;
      v_outcome:='free';v_price:=0;
    ELSE
      v_outcome:='unsold';
      UPDATE public.pokemon_auction_rooms SET requeue_pokemon_ids=array_append(requeue_pokemon_ids,current_pokemon_id) WHERE id=p_room_id;
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
  UPDATE public.pokemon_auction_rooms SET last_result=jsonb_build_object('pokemonId',v_room.current_pokemon_id,'outcome',v_outcome,'winner',v_winner,'price',v_price,'p1Bid',v_p1,'p2Bid',v_p2,'round',v_room.round),current_pokemon_id=NULL WHERE id=p_room_id;
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
  IF p_amount>0 THEN PERFORM public.auction_assert_bid_allowed(v_room,v_role,p_amount); END IF;
  INSERT INTO public.pokemon_auction_bids(room_id,round,player_id,amount) VALUES(p_room_id,v_room.round,auth.uid(),p_amount);
  UPDATE public.pokemon_auction_rooms SET p1_bid_submitted=CASE WHEN v_role='player1' THEN true ELSE p1_bid_submitted END,p2_bid_submitted=CASE WHEN v_role='player2' THEN true ELSE p2_bid_submitted END WHERE id=p_room_id;
  SELECT * INTO v_room FROM public.pokemon_auction_rooms WHERE id=p_room_id;
  IF v_room.p1_bid_submitted AND v_room.p2_bid_submitted THEN PERFORM public.resolve_pokemon_auction(p_room_id,true); END IF;
END; $$;


--
-- Name: submit_who_that_pokemon_guess(uuid, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.submit_who_that_pokemon_guess(p_room_id uuid, p_pokemon_id integer, p_next_target_pokemon_id integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_user uuid := auth.uid();
  v_room public.who_that_pokemon_rooms;
  v_is_p1 boolean;
  v_p1_lives integer;
  v_p2_lives integer;
  v_p1_score integer;
  v_p2_score integer;
  v_round integer;
  v_status text := 'playing';
  v_winner text := null;
  v_target integer;
  v_used integer[];
begin
  if v_user is null then raise exception 'not_authenticated'; end if;

  select * into v_room from public.who_that_pokemon_rooms where id = p_room_id for update;
  if not found then raise exception 'room_not_found'; end if;
  if v_room.status <> 'playing' then raise exception 'room_not_playing'; end if;

  if v_user = v_room.player1_id then
    v_is_p1 := true;
  elsif v_user = v_room.player2_id then
    v_is_p1 := false;
  else
    raise exception 'not_room_player';
  end if;

  v_p1_lives := v_room.p1_lives;
  v_p2_lives := v_room.p2_lives;
  v_p1_score := v_room.p1_score;
  v_p2_score := v_room.p2_score;
  v_round := v_room.round;
  v_target := v_room.target_pokemon_id;
  v_used := v_room.used_pokemon_ids;

  if p_pokemon_id = v_room.target_pokemon_id then
    if v_is_p1 then
      v_p1_score := v_p1_score + greatest(0, 5 - v_p1_lives);
    else
      v_p2_score := v_p2_score + greatest(0, 5 - v_p2_lives);
    end if;
    v_round := v_round + 1;
  else
    if (v_is_p1 and v_p1_lives >= 3) or (not v_is_p1 and v_p2_lives >= 3) then
      v_round := v_round + 1;
    else
      if v_is_p1 then
        v_p1_lives := least(3, v_p1_lives + 1);
      else
        v_p2_lives := least(3, v_p2_lives + 1);
      end if;
    end if;
  end if;

  if v_round > 10 then
    v_status := 'finished';
    v_target := null;
    if v_p1_score > v_p2_score then v_winner := 'player1';
    elsif v_p2_score > v_p1_score then v_winner := 'player2';
    else v_winner := 'draw';
    end if;
  elsif v_round <> v_room.round then
    if p_next_target_pokemon_id is null then raise exception 'missing_next_target'; end if;
    v_target := p_next_target_pokemon_id;
    v_used := array_append(v_used, p_next_target_pokemon_id);
    v_p1_lives := 0;
    v_p2_lives := 0;
  end if;

  update public.who_that_pokemon_rooms
  set round = v_round,
      target_pokemon_id = v_target,
      used_pokemon_ids = v_used,
      p1_score = v_p1_score,
      p2_score = v_p2_score,
      p1_lives = v_p1_lives,
      p2_lives = v_p2_lives,
      status = v_status,
      winner = v_winner
  where id = p_room_id;
end;
$$;


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
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_room FROM public.guess_pokemon_rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_user IS DISTINCT FROM v_room.player1_id AND v_user IS DISTINCT FROM v_room.player2_id THEN RAISE EXCEPTION 'not_room_player'; END IF;

  SELECT array_agg(key) INTO v_bad_keys
  FROM jsonb_object_keys(p_patch) AS key
  WHERE key <> ALL (ARRAY['settings','pokemon_p1','pokemon_p2','p1_ready','p2_ready','current_turn','status','winner_id','last_guess','player2_id']);
  IF v_bad_keys IS NOT NULL THEN RAISE EXCEPTION 'forbidden_fields: %', v_bad_keys; END IF;

  IF p_patch ? 'settings' THEN
    IF v_user <> v_room.player1_id THEN RAISE EXCEPTION 'only_player1_can_change_settings'; END IF;
    IF v_room.status NOT IN ('waiting', 'ready', 'selecting') THEN RAISE EXCEPTION 'settings_locked_during_play'; END IF;
  END IF;

  IF p_patch ? 'winner_id' THEN
    IF NULLIF(p_patch->>'winner_id', '') IS NOT NULL THEN
      IF NULLIF(p_patch->>'winner_id', '')::uuid <> v_user THEN RAISE EXCEPTION 'forbidden_winner_id'; END IF;
      IF v_room.current_turn IS DISTINCT FROM v_user THEN RAISE EXCEPTION 'not_your_turn_to_win'; END IF;
      IF v_room.status <> 'playing' THEN RAISE EXCEPTION 'room_not_playing_for_win'; END IF;
    ELSE
      IF v_user <> v_room.player1_id THEN RAISE EXCEPTION 'only_player1_can_clear_winner'; END IF;
    END IF;
  END IF;

  IF p_patch ? 'status' AND p_patch->>'status' = 'finished' THEN
    IF NOT (p_patch ? 'winner_id') OR NULLIF(p_patch->>'winner_id', '') IS NULL THEN
      RAISE EXCEPTION 'finished_requires_winner';
    END IF;
  END IF;

  IF p_patch ? 'current_turn' AND NULLIF(p_patch->>'current_turn', '') IS NOT NULL THEN
    IF NOT (
      NULLIF(p_patch->>'current_turn', '')::uuid = v_room.player1_id OR
      (v_room.player2_id IS NOT NULL AND NULLIF(p_patch->>'current_turn', '')::uuid = v_room.player2_id)
    ) THEN
      RAISE EXCEPTION 'invalid_current_turn';
    END IF;
  END IF;

  IF p_patch ? 'player2_id' AND NOT (v_user = v_room.player1_id AND p_patch->>'player2_id' IS NULL AND v_room.status IN ('waiting','ready')) THEN RAISE EXCEPTION 'forbidden_player2_update'; END IF;

  IF p_patch ? 'pokemon_p1' AND v_user <> v_room.player1_id THEN RAISE EXCEPTION 'forbidden_player1_fields'; END IF;
  IF p_patch ? 'p1_ready' AND v_user <> v_room.player1_id THEN
    -- Exception : player2 peut remettre p1_ready à false quand il se déclare vainqueur dans le même appel
    IF NOT ((p_patch->>'p1_ready')::boolean = false AND p_patch ? 'winner_id' AND NULLIF(p_patch->>'winner_id','')::uuid = v_user) THEN
      RAISE EXCEPTION 'forbidden_player1_fields';
    END IF;
  END IF;

  IF (p_patch ? 'pokemon_p2' OR p_patch ? 'p2_ready') AND v_user IS DISTINCT FROM v_room.player2_id AND v_user IS DISTINCT FROM v_room.player1_id THEN RAISE EXCEPTION 'forbidden_player2_fields'; END IF;

  UPDATE public.guess_pokemon_rooms
  SET
    settings = CASE WHEN p_patch ? 'settings' THEN p_patch->'settings' ELSE settings END,
    pokemon_p1 = CASE WHEN p_patch ? 'pokemon_p1' THEN NULLIF(p_patch->>'pokemon_p1','')::integer ELSE pokemon_p1 END,
    pokemon_p2 = CASE WHEN p_patch ? 'pokemon_p2' THEN NULLIF(p_patch->>'pokemon_p2','')::integer ELSE pokemon_p2 END,
    p1_ready = CASE WHEN p_patch ? 'p1_ready' THEN (p_patch->>'p1_ready')::boolean ELSE p1_ready END,
    p2_ready = CASE WHEN p_patch ? 'p2_ready' THEN (p_patch->>'p2_ready')::boolean ELSE p2_ready END,
    current_turn = CASE WHEN p_patch ? 'current_turn' THEN NULLIF(p_patch->>'current_turn','')::uuid ELSE current_turn END,
    status = CASE WHEN p_patch ? 'status' THEN (p_patch->>'status')::public.room_status ELSE status END,
    winner_id = CASE WHEN p_patch ? 'winner_id' THEN NULLIF(p_patch->>'winner_id','')::uuid ELSE winner_id END,
    last_guess = CASE WHEN p_patch ? 'last_guess' THEN NULLIF(p_patch->>'last_guess','')::integer ELSE last_guess END,
    player2_id = CASE WHEN p_patch ? 'player2_id' THEN NULLIF(p_patch->>'player2_id','')::uuid ELSE player2_id END
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
  IF p_patch ? 'p1_ready' AND v_user <> v_room.player1_id THEN RAISE EXCEPTION 'forbidden_p1_ready'; END IF;
  IF p_patch ? 'p2_ready' AND v_user IS DISTINCT FROM v_room.player2_id AND NOT (v_user = v_room.player1_id AND ((p_patch->>'p2_ready')::boolean = false OR v_room.player2_id IS NULL)) THEN RAISE EXCEPTION 'forbidden_p2_ready'; END IF;
  IF p_patch ? 'player2_id' AND NOT (v_user = v_room.player1_id AND p_patch->>'player2_id' IS NULL AND v_room.status = 'waiting') THEN RAISE EXCEPTION 'forbidden_player2_update'; END IF;

  UPDATE public.stat_duel_rooms
  SET
    status = CASE WHEN p_patch ? 'status' THEN p_patch->>'status' ELSE status END,
    settings = CASE WHEN p_patch ? 'settings' THEN p_patch->'settings' ELSE settings END,
    pokemon_ids = CASE WHEN p_patch ? 'pokemon_ids' THEN ARRAY(SELECT jsonb_array_elements_text(p_patch->'pokemon_ids')::integer) ELSE pokemon_ids END,
    p1_picks = CASE WHEN p_patch ? 'p1_picks' THEN p_patch->'p1_picks' ELSE p1_picks END,
    p2_picks = CASE WHEN p_patch ? 'p2_picks' THEN p_patch->'p2_picks' ELSE p2_picks END,
    round_start_at = CASE WHEN p_patch ? 'round_start_at' THEN NULLIF(p_patch->>'round_start_at','')::timestamp with time zone ELSE round_start_at END,
    winner = CASE WHEN p_patch ? 'winner' THEN p_patch->>'winner' ELSE winner END,
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

  UPDATE public.who_that_pokemon_rooms
  SET
    status = CASE WHEN p_patch ? 'status' THEN p_patch->>'status' ELSE status END,
    settings = CASE WHEN p_patch ? 'settings' THEN p_patch->'settings' ELSE settings END,
    round = CASE WHEN p_patch ? 'round' THEN (p_patch->>'round')::integer ELSE round END,
    target_pokemon_id = CASE WHEN p_patch ? 'target_pokemon_id' THEN NULLIF(p_patch->>'target_pokemon_id','')::integer ELSE target_pokemon_id END,
    used_pokemon_ids = CASE WHEN p_patch ? 'used_pokemon_ids' THEN ARRAY(SELECT jsonb_array_elements_text(p_patch->'used_pokemon_ids')::integer) ELSE used_pokemon_ids END,
    p1_score = CASE WHEN p_patch ? 'p1_score' THEN (p_patch->>'p1_score')::integer ELSE p1_score END,
    p2_score = CASE WHEN p_patch ? 'p2_score' THEN (p_patch->>'p2_score')::integer ELSE p2_score END,
    p1_lives = CASE WHEN p_patch ? 'p1_lives' THEN (p_patch->>'p1_lives')::integer ELSE p1_lives END,
    p2_lives = CASE WHEN p_patch ? 'p2_lives' THEN (p_patch->>'p2_lives')::integer ELSE p2_lives END,
    winner = CASE WHEN p_patch ? 'winner' THEN NULLIF(p_patch->>'winner','') ELSE winner END,
    p1_ready = CASE WHEN p_patch ? 'p1_ready' THEN (p_patch->>'p1_ready')::boolean ELSE p1_ready END,
    p2_ready = CASE WHEN p_patch ? 'p2_ready' THEN (p_patch->>'p2_ready')::boolean ELSE p2_ready END,
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
    last_guess integer
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
    vitesse integer NOT NULL
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
-- Name: defeated_trainers set_defeated_trainer_username_before_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_defeated_trainer_username_before_write BEFORE INSERT OR UPDATE OF user_id ON public.defeated_trainers FOR EACH ROW EXECUTE FUNCTION public.set_defeated_trainer_username();


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

CREATE POLICY game_invites_insert ON public.game_invites FOR INSERT TO authenticated WITH CHECK (((auth.uid() = sender_id) AND (status = 'pending'::text) AND (sender_id <> recipient_id) AND (game_mode = ANY (ARRAY['guess_my_pokemon'::text, 'stat_duel'::text, 'draft_duo'::text, 'who_that_pokemon'::text, 'pokemon_auction'::text]))));


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

\unrestrict ucbMrcVDrU10JUdFCr1xH6p4xZoFIfHZwOaoPWxC3Du0eFZyUfNTTCIsX4Zc72i

