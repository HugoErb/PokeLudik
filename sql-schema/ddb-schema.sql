--
-- PostgreSQL database dump
--


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

CREATE SCHEMA IF NOT EXISTS public;


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
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_room public.stat_duel_rooms;
  v_stat text;
  v_value integer;
  v_pick_count integer;
  v_pokemon_id integer;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_column NOT IN ('p1_picks','p2_picks') THEN RAISE EXCEPTION 'invalid_pick_column'; END IF;
  SELECT * INTO v_room FROM public.stat_duel_rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_room.status <> 'playing' THEN RAISE EXCEPTION 'room_not_playing'; END IF;
  IF p_column = 'p1_picks' AND v_user <> v_room.player1_id THEN RAISE EXCEPTION 'forbidden_p1_picks'; END IF;
  IF p_column = 'p2_picks' AND v_user IS DISTINCT FROM v_room.player2_id AND NOT (v_user = v_room.player1_id AND v_room.player2_id IS NULL) THEN RAISE EXCEPTION 'forbidden_p2_picks'; END IF;
  IF jsonb_typeof(p_pick) <> 'object' OR NOT (p_pick ? 'stat') THEN RAISE EXCEPTION 'invalid_pick'; END IF;
  v_stat := p_pick->>'stat';
  IF v_stat NOT IN ('pv','attaque','defense','atq_spe','def_spe','vitesse') THEN RAISE EXCEPTION 'invalid_stat_key'; END IF;

  IF cardinality(v_room.pokemon_ids) <> 6 THEN RAISE EXCEPTION 'invalid_pokemon_sequence'; END IF;
  IF p_column = 'p1_picks' THEN
    v_pick_count := jsonb_array_length(v_room.p1_picks);
    IF v_pick_count >= 6 THEN RAISE EXCEPTION 'too_many_picks'; END IF;
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_room.p1_picks) pick WHERE pick->>'stat' = v_stat) THEN RAISE EXCEPTION 'stat_already_used'; END IF;
  ELSE
    v_pick_count := jsonb_array_length(v_room.p2_picks);
    IF v_pick_count >= 6 THEN RAISE EXCEPTION 'too_many_picks'; END IF;
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_room.p2_picks) pick WHERE pick->>'stat' = v_stat) THEN RAISE EXCEPTION 'stat_already_used'; END IF;
  END IF;

  v_pokemon_id := v_room.pokemon_ids[v_pick_count + 1];
  SELECT CASE v_stat
    WHEN 'pv' THEN pv WHEN 'attaque' THEN attaque WHEN 'defense' THEN defense
    WHEN 'atq_spe' THEN atq_spe WHEN 'def_spe' THEN def_spe WHEN 'vitesse' THEN vitesse
  END INTO v_value FROM public.pokemon_catalog WHERE id = v_pokemon_id;
  IF v_value IS NULL THEN RAISE EXCEPTION 'pokemon_not_found'; END IF;

  IF p_column = 'p1_picks' THEN
    UPDATE public.stat_duel_rooms SET p1_picks = v_room.p1_picks || jsonb_build_array(jsonb_build_object('stat', v_stat, 'value', v_value)) WHERE id = p_room_id;
  ELSE
    UPDATE public.stat_duel_rooms SET p2_picks = v_room.p2_picks || jsonb_build_array(jsonb_build_object('stat', v_stat, 'value', v_value)) WHERE id = p_room_id;
  END IF;
END;
$$;


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
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
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
    SET search_path TO 'pg_catalog', 'public'
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
    SET search_path TO 'pg_catalog', 'public'
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
-- Name: join_stat_duel_room(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.join_stat_duel_room(p_room_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
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
    SET search_path TO 'pg_catalog', 'public'
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
-- Name: set_defeated_trainer_username(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_defeated_trainer_username() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
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
-- Name: submit_guess_pokemon_guess(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.submit_guess_pokemon_guess(p_room_id uuid, p_pokemon_id integer) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_room public.guess_pokemon_rooms;
  v_target integer;
  v_opponent uuid;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_room FROM public.guess_pokemon_rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_room.status <> 'playing' THEN RAISE EXCEPTION 'room_not_playing'; END IF;
  IF v_room.current_turn IS DISTINCT FROM v_user THEN RAISE EXCEPTION 'not_your_turn'; END IF;

  IF v_user = v_room.player1_id THEN
    v_target := v_room.pokemon_p2;
    v_opponent := v_room.player2_id;
  ELSIF v_user = v_room.player2_id THEN
    v_target := v_room.pokemon_p1;
    v_opponent := v_room.player1_id;
  ELSE
    RAISE EXCEPTION 'not_room_player';
  END IF;
  IF v_target IS NULL OR v_opponent IS NULL THEN RAISE EXCEPTION 'incomplete_room'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.pokemon_catalog WHERE id = p_pokemon_id) THEN RAISE EXCEPTION 'pokemon_not_found'; END IF;

  IF p_pokemon_id = v_target THEN
    UPDATE public.guess_pokemon_rooms
    SET winner_id = v_user, status = 'finished', p1_ready = false, p2_ready = false, last_guess = NULL
    WHERE id = p_room_id;
    RETURN true;
  END IF;

  UPDATE public.guess_pokemon_rooms SET current_turn = v_opponent, last_guess = p_pokemon_id WHERE id = p_room_id;
  RETURN false;
END;
$$;


--
-- Name: submit_who_that_pokemon_guess(uuid, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.submit_who_that_pokemon_guess(p_room_id uuid, p_round integer, p_pokemon_id integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
declare
  v_user uuid := auth.uid();
  v_room public.who_that_pokemon_rooms;
  v_is_p1 boolean;
  v_p1_lives integer;
  v_p2_lives integer;
  v_p1_score integer;
  v_p2_score integer;
  v_p1_ready boolean;
  v_p2_ready boolean;
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
  if p_round <> v_room.round then raise exception 'stale_round'; end if;

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
  v_p1_ready := v_room.p1_ready;
  v_p2_ready := v_room.p2_ready;
  v_round := v_room.round;
  v_target := v_room.target_pokemon_id;
  v_used := v_room.used_pokemon_ids;

  if (v_is_p1 and v_p1_ready) or (not v_is_p1 and v_p2_ready) then
    raise exception 'round_already_completed';
  end if;

  if p_pokemon_id = 0 then
    if v_is_p1 then
      v_p1_ready := true;
    else
      v_p2_ready := true;
    end if;
  elsif p_pokemon_id is null then
    if (v_is_p1 and v_p1_lives >= 3) or (not v_is_p1 and v_p2_lives >= 3) then
      raise exception 'all_hints_revealed';
    end if;
    if v_is_p1 then
      v_p1_lives := least(3, v_p1_lives + 1);
    else
      v_p2_lives := least(3, v_p2_lives + 1);
    end if;
  elsif p_pokemon_id = v_room.target_pokemon_id then
    if v_is_p1 then
      v_p1_score := v_p1_score + greatest(0, 5 - v_p1_lives);
      v_p1_ready := true;
    else
      v_p2_score := v_p2_score + greatest(0, 5 - v_p2_lives);
      v_p2_ready := true;
    end if;
  else
    if v_is_p1 then
      v_p1_lives := least(3, v_p1_lives + 1);
    else
      v_p2_lives := least(3, v_p2_lives + 1);
    end if;
  end if;

  if v_p1_ready and v_p2_ready then
    v_round := v_round + 1;
  end if;

  if v_round > 10 then
    v_status := 'finished';
    v_target := null;
    v_p1_ready := false;
    v_p2_ready := false;
    if v_p1_score > v_p2_score then v_winner := 'player1';
    elsif v_p2_score > v_p1_score then v_winner := 'player2';
    else v_winner := 'draw';
    end if;
  elsif v_round <> v_room.round then
    select p.id into v_target
    from public.pokemon_catalog p
    where (coalesce(jsonb_array_length(v_room.settings->'generations'), 0) = 0
           or p.generation in (select value::integer from jsonb_array_elements_text(v_room.settings->'generations')))
      and (coalesce(jsonb_array_length(v_room.settings->'categories'), 0) = 0
           or p.category in (select value from jsonb_array_elements_text(v_room.settings->'categories')))
      and not (p.id = any(v_used))
    order by random()
    limit 1;
    if v_target is null then
      select p.id into v_target
      from public.pokemon_catalog p
      where (coalesce(jsonb_array_length(v_room.settings->'generations'), 0) = 0
             or p.generation in (select value::integer from jsonb_array_elements_text(v_room.settings->'generations')))
        and (coalesce(jsonb_array_length(v_room.settings->'categories'), 0) = 0
             or p.category in (select value from jsonb_array_elements_text(v_room.settings->'categories')))
      order by random()
      limit 1;
    end if;
    if v_target is null then raise exception 'empty_pokemon_pool'; end if;
    v_used := array_append(v_used, v_target);
    v_p1_lives := 0;
    v_p2_lives := 0;
    v_p1_ready := false;
    v_p2_ready := false;
  end if;

  update public.who_that_pokemon_rooms
  set round = v_round,
      target_pokemon_id = v_target,
      used_pokemon_ids = v_used,
      p1_score = v_p1_score,
      p2_score = v_p2_score,
      p1_lives = v_p1_lives,
      p2_lives = v_p2_lives,
      p1_ready = v_p1_ready,
      p2_ready = v_p2_ready,
      status = v_status,
      winner = v_winner
  where id = p_room_id;
end;
$$;


--
-- Name: skip_who_that_pokemon_round(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.skip_who_that_pokemon_round(p_room_id uuid, p_round integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
BEGIN
  -- L'identifiant 0 représente un abandon volontaire et ne peut correspondre à aucun Pokémon.
  PERFORM public.submit_who_that_pokemon_guess(p_room_id, p_round, 0);
END;
$$;


--
-- Name: update_draft_duo_room(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_draft_duo_room(p_room_id uuid, p_patch jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
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
    SET search_path TO 'pg_catalog', 'public'
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

  IF p_patch ? 'settings' AND (v_user <> v_room.player1_id OR v_room.status = 'playing') THEN RAISE EXCEPTION 'settings_locked'; END IF;

  -- En multijoueur, les guesses et leur résultat passent exclusivement par
  -- submit_guess_pokemon_guess, qui compare avec la cible côté serveur.
  IF (p_patch ? 'winner_id' OR p_patch ? 'last_guess') AND v_room.player2_id IS NOT NULL THEN
    IF NOT (p_patch ? 'status' AND p_patch->>'status' = 'finished' AND NULLIF(p_patch->>'winner_id','') IS NULL) THEN
      RAISE EXCEPTION 'use_submit_guess';
    END IF;
  END IF;

  IF p_patch ? 'status' THEN
    IF p_patch->>'status' = 'finished' AND NULLIF(p_patch->>'winner_id','') IS NULL THEN
      NULL; -- abandon volontaire : autorisé aux deux participants
    ELSIF v_user <> v_room.player1_id THEN
      RAISE EXCEPTION 'only_player1_can_change_status';
    ELSIF p_patch->>'status' = 'playing' AND v_room.status NOT IN ('ready','selecting','finished') THEN
      RAISE EXCEPTION 'invalid_status_transition';
    ELSIF p_patch->>'status' = 'playing' AND NOT (
      (v_room.p1_ready AND v_room.p2_ready OR
       coalesce((p_patch->>'p1_ready')::boolean, false) AND coalesce((p_patch->>'p2_ready')::boolean, false))
      AND coalesce(NULLIF(p_patch->>'pokemon_p1','')::integer, v_room.pokemon_p1) IS NOT NULL
      AND coalesce(NULLIF(p_patch->>'pokemon_p2','')::integer, v_room.pokemon_p2) IS NOT NULL
    ) THEN RAISE EXCEPTION 'players_not_ready';
    ELSIF p_patch->>'status' = 'selecting' AND v_room.status NOT IN ('ready','finished') THEN
      RAISE EXCEPTION 'invalid_status_transition';
    ELSIF p_patch->>'status' = 'finished' AND v_room.player2_id IS NOT NULL THEN
      RAISE EXCEPTION 'use_submit_guess';
    ELSIF p_patch->>'status' = 'ready' AND NOT (v_user = v_room.player1_id AND v_room.player2_id IS NULL AND v_room.status IN ('waiting','ready')) THEN
      RAISE EXCEPTION 'invalid_status_transition';
    ELSIF p_patch->>'status' NOT IN ('ready','selecting','playing','finished') THEN
      RAISE EXCEPTION 'invalid_status_transition';
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

  IF p_patch ? 'pokemon_p1' AND (v_user <> v_room.player1_id OR (v_room.status <> 'selecting' AND p_patch->>'status' <> 'playing')) THEN RAISE EXCEPTION 'forbidden_p1_pokemon'; END IF;
  IF p_patch ? 'pokemon_p2' AND v_user IS DISTINCT FROM v_room.player2_id
     AND NOT (v_user = v_room.player1_id AND (v_room.player2_id IS NULL OR p_patch->>'status' = 'playing')) THEN RAISE EXCEPTION 'forbidden_p2_pokemon'; END IF;
  IF p_patch ? 'pokemon_p2' AND v_room.status <> 'selecting' AND p_patch->>'status' <> 'playing' THEN RAISE EXCEPTION 'pokemon_selection_closed'; END IF;
  IF p_patch ? 'p1_ready' AND v_user <> v_room.player1_id
     AND NOT ((p_patch->>'p1_ready')::boolean = false AND p_patch->>'status' = 'finished') THEN RAISE EXCEPTION 'forbidden_p1_ready'; END IF;
  IF p_patch ? 'p2_ready' AND v_user IS DISTINCT FROM v_room.player2_id
     AND NOT (v_user = v_room.player1_id AND ((p_patch->>'p2_ready')::boolean = false OR v_room.player2_id IS NULL
              OR (p_patch->>'status' = 'playing' AND coalesce((p_patch->'settings'->>'randomPokemon')::boolean, (v_room.settings->>'randomPokemon')::boolean, false)))) THEN RAISE EXCEPTION 'forbidden_p2_ready'; END IF;
  IF p_patch ? 'p1_ready' AND (p_patch->>'p1_ready')::boolean AND v_room.status NOT IN ('selecting','finished') AND p_patch->>'status' <> 'playing' THEN RAISE EXCEPTION 'ready_not_allowed'; END IF;
  IF p_patch ? 'p2_ready' AND (p_patch->>'p2_ready')::boolean AND v_room.status NOT IN ('selecting','finished') AND p_patch->>'status' <> 'playing' THEN RAISE EXCEPTION 'ready_not_allowed'; END IF;

  IF p_patch ? 'pokemon_p1' AND NULLIF(p_patch->>'pokemon_p1','') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.pokemon_catalog WHERE id = (p_patch->>'pokemon_p1')::integer) THEN RAISE EXCEPTION 'pokemon_not_found'; END IF;
  IF p_patch ? 'pokemon_p2' AND NULLIF(p_patch->>'pokemon_p2','') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.pokemon_catalog WHERE id = (p_patch->>'pokemon_p2')::integer) THEN RAISE EXCEPTION 'pokemon_not_found'; END IF;

  IF p_patch ? 'current_turn' AND v_room.status = 'playing' AND v_room.player2_id IS NOT NULL THEN RAISE EXCEPTION 'use_submit_guess'; END IF;

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
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_room public.stat_duel_rooms;
  v_bad_keys text[];
  v_ids integer[];
  v_settings jsonb;
  v_p1_total numeric;
  v_p2_total numeric;
  v_winner text;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_room FROM public.stat_duel_rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_user IS DISTINCT FROM v_room.player1_id AND v_user IS DISTINCT FROM v_room.player2_id THEN RAISE EXCEPTION 'not_room_player'; END IF;

  SELECT array_agg(key) INTO v_bad_keys
  FROM jsonb_object_keys(p_patch) AS key
  WHERE key <> ALL (ARRAY['status','settings','pokemon_ids','p1_picks','p2_picks','round_start_at','winner','p1_ready','p2_ready','player2_id']);
  IF v_bad_keys IS NOT NULL THEN RAISE EXCEPTION 'forbidden_fields: %', v_bad_keys; END IF;
  v_settings := coalesce(p_patch->'settings', v_room.settings, '{}'::jsonb);
  IF p_patch ? 'settings' AND (v_user <> v_room.player1_id OR v_room.status <> 'waiting') THEN RAISE EXCEPTION 'settings_locked'; END IF;
  IF (p_patch ? 'pokemon_ids' OR p_patch ? 'round_start_at') AND v_user <> v_room.player1_id THEN RAISE EXCEPTION 'only_player1_can_launch'; END IF;

  IF p_patch ? 'pokemon_ids' THEN
    v_ids := ARRAY(SELECT jsonb_array_elements_text(p_patch->'pokemon_ids')::integer);
    IF cardinality(v_ids) <> 6 OR (SELECT count(DISTINCT item.id) FROM unnest(v_ids) AS item(id)) <> 6 THEN RAISE EXCEPTION 'six_distinct_pokemon_required'; END IF;
    IF EXISTS (
      SELECT 1 FROM unnest(v_ids) AS item(id) LEFT JOIN public.pokemon_catalog p ON p.id = item.id
      WHERE p.id IS NULL
         OR (coalesce(jsonb_array_length(v_settings->'generations'), 0) > 0 AND p.generation NOT IN (SELECT value::integer FROM jsonb_array_elements_text(v_settings->'generations')))
         OR (coalesce(jsonb_array_length(v_settings->'categories'), 0) > 0 AND p.category NOT IN (SELECT value FROM jsonb_array_elements_text(v_settings->'categories')))
    ) THEN RAISE EXCEPTION 'pokemon_outside_settings'; END IF;
  END IF;

  IF p_patch ? 'p1_picks' AND NOT (v_user = v_room.player1_id AND p_patch->'p1_picks' = '[]'::jsonb AND p_patch->>'status' = 'playing') THEN RAISE EXCEPTION 'forbidden_p1_picks'; END IF;
  IF p_patch ? 'p2_picks' AND NOT (v_user = v_room.player1_id AND p_patch->'p2_picks' = '[]'::jsonb AND p_patch->>'status' = 'playing') THEN RAISE EXCEPTION 'forbidden_p2_picks'; END IF;
  IF p_patch ? 'p1_ready' AND v_user <> v_room.player1_id
     AND NOT ((p_patch->>'p1_ready')::boolean = false AND p_patch->>'status' = 'finished') THEN RAISE EXCEPTION 'forbidden_p1_ready'; END IF;
  IF p_patch ? 'p2_ready' AND v_user IS DISTINCT FROM v_room.player2_id
     AND NOT (v_user = v_room.player1_id AND ((p_patch->>'p2_ready')::boolean = false OR v_room.player2_id IS NULL)
              OR ((p_patch->>'p2_ready')::boolean = false AND p_patch->>'status' = 'finished')) THEN RAISE EXCEPTION 'forbidden_p2_ready'; END IF;
  IF p_patch ? 'p1_ready' AND (p_patch->>'p1_ready')::boolean AND v_room.status <> 'finished' THEN RAISE EXCEPTION 'ready_not_allowed'; END IF;
  IF p_patch ? 'p2_ready' AND (p_patch->>'p2_ready')::boolean AND v_room.status <> 'finished' THEN RAISE EXCEPTION 'ready_not_allowed'; END IF;
  IF p_patch ? 'player2_id' AND NOT (v_user = v_room.player1_id AND p_patch->>'player2_id' IS NULL AND v_room.status = 'waiting') THEN RAISE EXCEPTION 'forbidden_player2_update'; END IF;

  IF p_patch ? 'winner' AND NOT (p_patch ? 'status') THEN RAISE EXCEPTION 'winner_requires_status'; END IF;
  IF p_patch ? 'status' THEN
    IF p_patch->>'status' = 'playing' THEN
      IF v_user <> v_room.player1_id OR v_room.status NOT IN ('waiting','finished') THEN RAISE EXCEPTION 'invalid_launch'; END IF;
      IF v_room.status = 'finished' AND NOT (v_room.p1_ready AND v_room.p2_ready) THEN RAISE EXCEPTION 'replay_not_ready'; END IF;
      IF NOT (p_patch ? 'pokemon_ids') OR NOT (p_patch ? 'round_start_at') THEN RAISE EXCEPTION 'incomplete_launch'; END IF;
    ELSIF p_patch->>'status' = 'finished' AND NULLIF(p_patch->>'winner','') IS NULL THEN
      v_winner := NULL; -- abandon
    ELSIF p_patch->>'status' = 'finished' THEN
      IF jsonb_array_length(v_room.p1_picks) <> 6 OR jsonb_array_length(v_room.p2_picks) <> 6 THEN RAISE EXCEPTION 'game_not_complete'; END IF;
      SELECT coalesce(sum((pick->>'value')::numeric), 0) INTO v_p1_total FROM jsonb_array_elements(v_room.p1_picks) pick;
      SELECT coalesce(sum((pick->>'value')::numeric), 0) INTO v_p2_total FROM jsonb_array_elements(v_room.p2_picks) pick;
      v_winner := CASE WHEN v_p1_total > v_p2_total THEN 'player1' WHEN v_p2_total > v_p1_total THEN 'player2' ELSE 'draw' END;
    ELSE
      RAISE EXCEPTION 'invalid_status';
    END IF;
  END IF;

  UPDATE public.stat_duel_rooms
  SET
    status = CASE WHEN p_patch ? 'status' THEN p_patch->>'status' ELSE status END,
    settings = CASE WHEN p_patch ? 'settings' THEN p_patch->'settings' ELSE settings END,
    pokemon_ids = CASE WHEN p_patch ? 'pokemon_ids' THEN ARRAY(SELECT jsonb_array_elements_text(p_patch->'pokemon_ids')::integer) ELSE pokemon_ids END,
    p1_picks = CASE WHEN p_patch ? 'p1_picks' THEN p_patch->'p1_picks' ELSE p1_picks END,
    p2_picks = CASE WHEN p_patch ? 'p2_picks' THEN p_patch->'p2_picks' ELSE p2_picks END,
    round_start_at = CASE WHEN p_patch ? 'round_start_at' THEN NULLIF(p_patch->>'round_start_at','')::timestamp with time zone ELSE round_start_at END,
    winner = CASE WHEN p_patch ? 'status' AND p_patch->>'status' = 'playing' THEN NULL WHEN p_patch ? 'status' AND p_patch->>'status' = 'finished' THEN v_winner ELSE winner END,
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
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_room public.who_that_pokemon_rooms;
  v_bad_keys text[];
  v_settings jsonb;
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
  v_settings := coalesce(p_patch->'settings', v_room.settings, '{}'::jsonb);
  IF p_patch ? 'settings' AND (v_user <> v_room.player1_id OR v_room.status <> 'waiting') THEN RAISE EXCEPTION 'settings_locked'; END IF;
  IF p_patch ? 'player2_id' AND NOT (v_user = v_room.player1_id AND p_patch->>'player2_id' IS NULL AND v_room.status = 'waiting') THEN RAISE EXCEPTION 'forbidden_player2_update'; END IF;
  IF p_patch ? 'p1_ready' AND v_user <> v_room.player1_id
     AND NOT ((p_patch->>'p1_ready')::boolean = false AND p_patch->>'status' = 'finished') THEN RAISE EXCEPTION 'forbidden_p1_ready'; END IF;
  IF p_patch ? 'p2_ready' AND v_user IS DISTINCT FROM v_room.player2_id
     AND NOT (v_user = v_room.player1_id AND (p_patch->>'p2_ready')::boolean = false
              OR ((p_patch->>'p2_ready')::boolean = false AND p_patch->>'status' = 'finished')) THEN RAISE EXCEPTION 'forbidden_p2_ready'; END IF;
  IF p_patch ? 'p1_ready' AND (p_patch->>'p1_ready')::boolean AND v_room.status <> 'finished' THEN RAISE EXCEPTION 'ready_not_allowed'; END IF;
  IF p_patch ? 'p2_ready' AND (p_patch->>'p2_ready')::boolean AND v_room.status <> 'finished' THEN RAISE EXCEPTION 'ready_not_allowed'; END IF;

  IF p_patch ? 'status' AND p_patch->>'status' = 'playing' THEN
    IF v_user <> v_room.player1_id OR v_room.status NOT IN ('waiting','finished') THEN RAISE EXCEPTION 'invalid_launch'; END IF;
    IF v_room.status = 'finished' AND NOT (v_room.p1_ready AND v_room.p2_ready) THEN RAISE EXCEPTION 'replay_not_ready'; END IF;
    IF NOT (p_patch ? 'round' AND p_patch ? 'target_pokemon_id' AND p_patch ? 'used_pokemon_ids'
            AND p_patch ? 'p1_score' AND p_patch ? 'p2_score' AND p_patch ? 'p1_lives' AND p_patch ? 'p2_lives'
            AND p_patch ? 'winner' AND p_patch ? 'p1_ready' AND p_patch ? 'p2_ready') THEN RAISE EXCEPTION 'incomplete_launch'; END IF;
    IF (p_patch->>'round')::integer <> 1 OR (p_patch->>'p1_score')::integer <> 0 OR (p_patch->>'p2_score')::integer <> 0
       OR (p_patch->>'p1_lives')::integer <> 0 OR (p_patch->>'p2_lives')::integer <> 0
       OR NULLIF(p_patch->>'winner','') IS NOT NULL OR (p_patch->>'p1_ready')::boolean OR (p_patch->>'p2_ready')::boolean THEN RAISE EXCEPTION 'invalid_launch_state'; END IF;
    v_target := (p_patch->>'target_pokemon_id')::integer;
    IF ARRAY(SELECT jsonb_array_elements_text(p_patch->'used_pokemon_ids')::integer) <> ARRAY[v_target] THEN RAISE EXCEPTION 'invalid_used_pokemon'; END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.pokemon_catalog p WHERE p.id = v_target
        AND (coalesce(jsonb_array_length(v_settings->'generations'), 0) = 0 OR p.generation IN (SELECT value::integer FROM jsonb_array_elements_text(v_settings->'generations')))
        AND (coalesce(jsonb_array_length(v_settings->'categories'), 0) = 0 OR p.category IN (SELECT value FROM jsonb_array_elements_text(v_settings->'categories')))
    ) THEN RAISE EXCEPTION 'pokemon_outside_settings'; END IF;
  ELSIF p_patch ? 'status' AND p_patch->>'status' = 'finished' AND NULLIF(p_patch->>'winner','') IS NULL THEN
    NULL; -- abandon
  ELSIF p_patch ? 'status' THEN
    RAISE EXCEPTION 'invalid_status_transition';
  ELSIF p_patch ? 'round' OR p_patch ? 'target_pokemon_id' OR p_patch ? 'used_pokemon_ids'
     OR p_patch ? 'p1_score' OR p_patch ? 'p2_score' OR p_patch ? 'p1_lives' OR p_patch ? 'p2_lives' OR p_patch ? 'winner' THEN
    RAISE EXCEPTION 'game_state_is_server_managed';
  END IF;

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


SET default_tablespace = '';

SET default_table_access_method = heap;

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
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    username text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    avatar_url text
);


-- Catalogue minimal utilise par les fonctions de jeu pour valider les filtres,
-- les identifiants et les valeurs de statistiques sans faire confiance au client.
CREATE TABLE public.pokemon_catalog (
    id integer PRIMARY KEY,
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

-- POKEMON_CATALOG_DATA_START
INSERT INTO public.pokemon_catalog (id, generation, category, types, rating, pv, attaque, defense, atq_spe, def_spe, vitesse) VALUES
(1,1,'starter',ARRAY['Plante','Poison']::text[],5.6,45,49,49,65,65,45),
(2,1,'starter',ARRAY['Plante','Poison']::text[],6.8,60,62,63,80,80,60),
(3,1,'starter',ARRAY['Plante','Poison']::text[],8.2,80,82,83,100,100,80),
(4,1,'starter',ARRAY['Feu']::text[],5.5,39,52,43,60,50,65),
(5,1,'starter',ARRAY['Feu']::text[],6.8,58,64,58,80,65,80),
(6,1,'starter',ARRAY['Feu','Vol']::text[],8.3,78,84,78,109,85,100),
(7,1,'starter',ARRAY['Eau']::text[],5.5,44,48,65,50,64,43),
(8,1,'starter',ARRAY['Eau']::text[],6.8,59,63,80,65,80,58),
(9,1,'starter',ARRAY['Eau']::text[],8.3,79,83,100,85,105,78),
(10,1,'classique',ARRAY['Insecte']::text[],2.7,45,30,35,20,20,45),
(11,1,'classique',ARRAY['Insecte']::text[],3.1,50,20,55,25,25,30),
(12,1,'classique',ARRAY['Insecte','Vol']::text[],6.7,60,45,50,90,80,70),
(13,1,'classique',ARRAY['Insecte','Poison']::text[],2.7,40,35,30,20,20,50),
(14,1,'classique',ARRAY['Insecte','Poison']::text[],3.1,45,25,50,25,25,35),
(15,1,'classique',ARRAY['Insecte','Poison']::text[],6.7,65,90,40,45,80,75),
(16,1,'classique',ARRAY['Normal','Vol']::text[],4.4,40,45,40,35,35,56),
(17,1,'classique',ARRAY['Normal','Vol']::text[],6.1,63,60,55,50,50,71),
(18,1,'classique',ARRAY['Normal','Vol']::text[],7.7,83,80,75,70,70,101),
(19,1,'classique',ARRAY['Normal']::text[],4.4,30,56,35,25,35,72),
(20,1,'classique',ARRAY['Normal']::text[],6.9,55,81,60,50,70,97),
(21,1,'classique',ARRAY['Normal','Vol']::text[],4.6,40,60,30,31,31,70),
(22,1,'classique',ARRAY['Normal','Vol']::text[],7.3,65,90,65,61,61,100),
(23,1,'classique',ARRAY['Poison']::text[],5.1,35,60,44,40,54,55),
(24,1,'classique',ARRAY['Poison']::text[],7.4,60,95,69,65,79,80),
(25,1,'classique',ARRAY['Électrik']::text[],5.6,35,55,40,50,50,90),
(26,1,'classique',ARRAY['Électrik']::text[],7.8,60,90,55,90,80,110),
(27,1,'classique',ARRAY['Sol']::text[],5.3,50,75,85,20,30,40),
(28,1,'classique',ARRAY['Sol']::text[],7.4,75,100,110,45,55,65),
(29,1,'classique',ARRAY['Poison']::text[],4.9,55,47,52,40,40,41),
(30,1,'classique',ARRAY['Poison']::text[],6.3,70,62,67,55,55,56),
(31,1,'classique',ARRAY['Poison','Sol']::text[],8,90,92,87,75,85,76),
(32,1,'classique',ARRAY['Poison']::text[],4.8,46,57,40,40,40,50),
(33,1,'classique',ARRAY['Poison']::text[],6.3,61,72,57,55,55,65),
(34,1,'classique',ARRAY['Poison','Sol']::text[],8,81,102,77,85,75,85),
(35,1,'classique',ARRAY['Fée']::text[],5.7,70,45,48,60,65,35),
(36,1,'classique',ARRAY['Fée']::text[],7.8,95,70,73,95,90,60),
(37,1,'classique',ARRAY['Feu']::text[],5.3,38,41,40,50,65,65),
(38,1,'classique',ARRAY['Feu']::text[],8,73,76,75,81,100,100),
(39,1,'classique',ARRAY['Normal','Fée']::text[],4.8,115,45,20,45,25,20),
(40,1,'classique',ARRAY['Normal','Fée']::text[],7.2,140,70,45,85,50,45),
(41,1,'classique',ARRAY['Poison','Vol']::text[],4.2,40,45,35,30,40,55),
(42,1,'classique',ARRAY['Poison','Vol']::text[],7.5,75,80,70,65,75,90),
(43,1,'classique',ARRAY['Plante','Poison']::text[],5.6,45,50,55,75,65,30),
(44,1,'classique',ARRAY['Plante','Poison']::text[],6.7,60,65,70,85,75,40),
(45,1,'classique',ARRAY['Plante','Poison']::text[],7.8,75,80,85,110,90,50),
(46,1,'classique',ARRAY['Insecte','Plante']::text[],5,35,70,55,45,55,25),
(47,1,'classique',ARRAY['Insecte','Plante']::text[],6.8,60,95,80,60,80,30),
(48,1,'classique',ARRAY['Insecte','Poison']::text[],5.4,60,55,50,40,55,45),
(49,1,'classique',ARRAY['Insecte','Poison']::text[],7.4,70,65,60,90,75,90),
(50,1,'classique',ARRAY['Sol']::text[],4.7,10,55,25,35,45,95),
(51,1,'classique',ARRAY['Sol']::text[],7.1,35,100,50,50,70,120),
(52,1,'classique',ARRAY['Normal']::text[],5.1,40,45,35,40,40,90),
(53,1,'classique',ARRAY['Normal']::text[],7.3,65,70,60,65,65,115),
(54,1,'classique',ARRAY['Eau']::text[],5.6,50,52,48,65,50,55),
(55,1,'classique',ARRAY['Eau']::text[],8,80,82,78,95,80,85),
(56,1,'classique',ARRAY['Combat']::text[],5.4,40,80,35,35,45,70),
(57,1,'classique',ARRAY['Combat']::text[],7.5,65,105,60,60,70,95),
(58,1,'classique',ARRAY['Feu']::text[],6.1,55,70,45,70,50,60),
(59,1,'classique',ARRAY['Feu']::text[],8.5,90,110,80,100,80,95),
(60,1,'classique',ARRAY['Eau']::text[],5.3,40,50,40,40,40,90),
(61,1,'classique',ARRAY['Eau']::text[],6.6,65,65,65,50,50,90),
(62,1,'classique',ARRAY['Eau','Combat']::text[],8.1,90,95,95,70,90,70),
(63,1,'classique',ARRAY['Psy']::text[],5.5,25,20,15,105,55,90),
(64,1,'classique',ARRAY['Psy']::text[],6.8,40,35,30,120,70,105),
(65,1,'classique',ARRAY['Psy']::text[],8,55,50,45,135,95,120),
(66,1,'classique',ARRAY['Combat']::text[],5.4,70,80,50,35,35,35),
(67,1,'classique',ARRAY['Combat']::text[],6.8,80,100,70,50,60,45),
(68,1,'classique',ARRAY['Combat']::text[],8,90,130,80,65,85,55),
(69,1,'classique',ARRAY['Plante','Poison']::text[],5.3,50,75,35,70,30,40),
(70,1,'classique',ARRAY['Plante','Poison']::text[],6.7,65,90,50,85,45,55),
(71,1,'classique',ARRAY['Plante','Poison']::text[],7.8,80,105,65,100,70,70),
(72,1,'classique',ARRAY['Eau','Poison']::text[],5.9,40,40,35,50,100,70),
(73,1,'classique',ARRAY['Eau','Poison']::text[],8.1,80,70,65,80,120,100),
(74,1,'classique',ARRAY['Roche','Sol']::text[],5.3,40,80,100,30,30,20),
(75,1,'classique',ARRAY['Roche','Sol']::text[],6.7,55,95,115,45,45,35),
(76,1,'classique',ARRAY['Roche','Sol']::text[],7.9,80,120,130,55,65,45),
(77,1,'classique',ARRAY['Feu']::text[],6.9,50,85,55,65,65,90),
(78,1,'classique',ARRAY['Feu']::text[],8,65,100,70,80,80,105),
(79,1,'classique',ARRAY['Eau','Psy']::text[],5.6,90,65,65,40,40,15),
(80,1,'classique',ARRAY['Eau','Psy']::text[],7.8,95,75,110,100,80,30),
(81,1,'classique',ARRAY['Électrik','Acier']::text[],5.7,25,35,70,95,55,45),
(82,1,'classique',ARRAY['Électrik','Acier']::text[],7.6,50,60,95,120,70,70),
(83,1,'classique',ARRAY['Normal','Vol']::text[],6.5,52,90,55,58,62,60),
(84,1,'classique',ARRAY['Normal','Vol']::text[],5.5,35,85,45,35,35,75),
(85,1,'classique',ARRAY['Normal','Vol']::text[],7.6,60,110,70,60,60,110),
(86,1,'classique',ARRAY['Eau']::text[],5.7,65,45,55,45,70,45),
(87,1,'classique',ARRAY['Eau','Glace']::text[],7.7,90,70,80,70,95,70),
(88,1,'classique',ARRAY['Poison']::text[],5.7,80,80,50,40,50,25),
(89,1,'classique',ARRAY['Poison']::text[],8,105,105,75,65,100,50),
(90,1,'classique',ARRAY['Eau']::text[],5.4,30,65,100,45,25,40),
(91,1,'classique',ARRAY['Eau','Glace']::text[],8.2,50,95,180,85,45,70),
(92,1,'classique',ARRAY['Spectre','Poison']::text[],5.5,30,35,30,100,35,80),
(93,1,'classique',ARRAY['Spectre','Poison']::text[],6.8,45,50,45,115,55,95),
(94,1,'classique',ARRAY['Spectre','Poison']::text[],8,60,65,60,130,75,110),
(95,1,'classique',ARRAY['Roche','Sol']::text[],6.6,35,45,160,30,45,70),
(96,1,'classique',ARRAY['Psy']::text[],5.8,60,48,45,43,90,42),
(97,1,'classique',ARRAY['Psy']::text[],7.8,85,73,70,73,115,67),
(98,1,'classique',ARRAY['Eau']::text[],5.7,30,105,90,25,25,50),
(99,1,'classique',ARRAY['Eau']::text[],7.7,55,130,115,50,50,75),
(100,1,'classique',ARRAY['Électrik']::text[],5.8,40,30,50,55,55,100),
(101,1,'classique',ARRAY['Électrik']::text[],7.8,60,50,70,80,80,150),
(102,1,'classique',ARRAY['Plante','Psy']::text[],5.7,60,40,80,60,45,40),
(103,1,'classique',ARRAY['Plante','Psy']::text[],8.3,95,95,85,125,75,55),
(104,1,'classique',ARRAY['Sol']::text[],5.6,50,50,95,40,50,35),
(105,1,'classique',ARRAY['Sol']::text[],7.1,60,80,110,50,80,45),
(106,1,'classique',ARRAY['Combat']::text[],7.5,50,120,53,35,110,87),
(107,1,'classique',ARRAY['Combat']::text[],7.5,50,105,79,35,110,76),
(108,1,'classique',ARRAY['Normal']::text[],6.6,90,55,75,60,75,30),
(109,1,'classique',ARRAY['Poison']::text[],6,40,65,95,60,45,35),
(110,1,'classique',ARRAY['Poison']::text[],7.8,65,90,120,85,70,60),
(111,1,'classique',ARRAY['Sol','Roche']::text[],6,80,85,95,30,30,25),
(112,1,'classique',ARRAY['Sol','Roche']::text[],7.8,105,130,120,45,45,40),
(113,1,'classique',ARRAY['Normal']::text[],7.4,250,5,5,35,105,50),
(114,1,'classique',ARRAY['Plante']::text[],7.2,65,55,115,100,40,60),
(115,1,'classique',ARRAY['Normal']::text[],7.8,105,95,80,40,80,90),
(116,1,'classique',ARRAY['Eau']::text[],5.2,30,40,70,70,25,60),
(117,1,'classique',ARRAY['Eau']::text[],7.3,55,65,95,95,45,85),
(118,1,'classique',ARRAY['Eau']::text[],5.6,45,67,60,35,50,63),
(119,1,'classique',ARRAY['Eau']::text[],7.4,80,92,65,65,80,68),
(120,1,'classique',ARRAY['Eau']::text[],6,30,45,55,70,55,85),
(121,1,'classique',ARRAY['Eau','Psy']::text[],8.2,60,75,85,100,85,115),
(122,1,'classique',ARRAY['Psy','Fée']::text[],7.5,40,45,65,100,120,90),
(123,1,'classique',ARRAY['Insecte','Vol']::text[],8,70,110,80,55,80,105),
(124,1,'classique',ARRAY['Glace','Psy']::text[],7.5,65,50,35,115,95,95),
(125,1,'classique',ARRAY['Électrik']::text[],7.8,65,83,57,95,85,105),
(126,1,'classique',ARRAY['Feu']::text[],7.9,65,95,57,100,85,93),
(127,1,'classique',ARRAY['Insecte']::text[],8,65,125,100,55,70,85),
(128,1,'classique',ARRAY['Normal']::text[],7.8,75,100,95,40,70,110),
(129,1,'classique',ARRAY['Eau']::text[],2.9,20,10,55,15,20,80),
(130,1,'classique',ARRAY['Eau','Vol']::text[],8.4,95,125,79,60,100,81),
(131,1,'classique',ARRAY['Eau','Glace']::text[],8.3,130,85,80,85,95,60),
(132,1,'classique',ARRAY['Normal']::text[],5.1,48,48,48,48,48,48),
(133,1,'classique',ARRAY['Normal']::text[],5.7,55,55,50,45,65,55),
(134,1,'classique',ARRAY['Eau']::text[],8.2,130,65,60,110,95,65),
(135,1,'classique',ARRAY['Électrik']::text[],8.2,65,65,60,110,95,130),
(136,1,'classique',ARRAY['Feu']::text[],8.2,65,130,60,95,110,65),
(137,1,'classique',ARRAY['Normal']::text[],6.7,65,60,70,85,75,40),
(138,1,'fossile',ARRAY['Roche','Eau']::text[],6.2,35,40,100,90,55,35),
(139,1,'fossile',ARRAY['Roche','Eau']::text[],7.9,70,60,125,115,70,55),
(140,1,'fossile',ARRAY['Roche','Eau']::text[],6.2,30,80,90,55,45,55),
(141,1,'fossile',ARRAY['Roche','Eau']::text[],7.9,60,115,105,65,70,80),
(142,1,'fossile',ARRAY['Roche','Vol']::text[],8.1,80,105,65,60,75,130),
(143,1,'classique',ARRAY['Normal']::text[],8.4,160,110,65,65,110,30),
(144,1,'légendaire',ARRAY['Glace','Vol']::text[],8.8,90,85,100,95,125,85),
(145,1,'légendaire',ARRAY['Électrik','Vol']::text[],8.8,90,90,85,125,90,100),
(146,1,'légendaire',ARRAY['Feu','Vol']::text[],8.8,90,100,90,125,85,90),
(147,1,'classique',ARRAY['Dragon']::text[],5.3,41,64,45,50,50,50),
(148,1,'classique',ARRAY['Dragon']::text[],7,61,84,65,70,70,70),
(149,1,'pseudo-légendaire',ARRAY['Dragon','Vol']::text[],8.9,91,134,95,100,100,80),
(150,1,'légendaire',ARRAY['Psy']::text[],9.7,106,110,90,154,90,130),
(151,1,'fabuleux',ARRAY['Psy']::text[],8.9,100,100,100,100,100,100),
(152,2,'starter',ARRAY['Plante']::text[],5.6,45,49,65,49,65,45),
(153,2,'starter',ARRAY['Plante']::text[],6.8,60,62,80,63,80,60),
(154,2,'starter',ARRAY['Plante']::text[],8.2,80,82,100,83,100,80),
(155,2,'starter',ARRAY['Feu']::text[],5.5,39,52,43,60,50,65),
(156,2,'starter',ARRAY['Feu']::text[],6.8,58,64,58,80,65,80),
(157,2,'starter',ARRAY['Feu']::text[],8.3,78,84,78,109,85,100),
(158,2,'starter',ARRAY['Eau']::text[],5.5,50,65,64,44,48,43),
(159,2,'starter',ARRAY['Eau']::text[],6.8,65,80,80,59,63,58),
(160,2,'starter',ARRAY['Eau']::text[],8.3,85,105,100,79,83,78),
(161,2,'classique',ARRAY['Normal']::text[],3.4,35,46,34,35,45,20),
(162,2,'classique',ARRAY['Normal']::text[],7,85,76,64,45,55,90),
(163,2,'classique',ARRAY['Normal','Vol']::text[],4.6,60,30,30,36,56,50),
(164,2,'classique',ARRAY['Normal','Vol']::text[],7.4,100,50,50,86,96,70),
(165,2,'classique',ARRAY['Insecte','Vol']::text[],4.7,40,20,30,40,80,55),
(166,2,'classique',ARRAY['Insecte','Vol']::text[],6.7,55,35,50,55,110,85),
(167,2,'classique',ARRAY['Insecte','Poison']::text[],4.3,40,60,40,40,40,30),
(168,2,'classique',ARRAY['Insecte','Poison']::text[],6.8,70,90,70,60,70,40),
(169,2,'classique',ARRAY['Poison','Vol']::text[],8.3,85,90,80,70,80,130),
(170,2,'classique',ARRAY['Eau','Électrik']::text[],5.8,75,38,38,56,56,67),
(171,2,'classique',ARRAY['Eau','Électrik']::text[],7.5,125,58,58,76,76,67),
(172,2,'bébé',ARRAY['Électrik']::text[],3.1,20,40,15,35,35,60),
(173,2,'bébé',ARRAY['Fée']::text[],3.5,50,25,28,45,55,15),
(174,2,'bébé',ARRAY['Normal','Fée']::text[],3.3,90,30,15,40,20,15),
(175,2,'bébé',ARRAY['Fée']::text[],4.2,35,20,65,40,65,20),
(176,2,'classique',ARRAY['Fée','Vol']::text[],6.8,55,40,85,80,105,40),
(177,2,'classique',ARRAY['Psy','Vol']::text[],5.6,40,50,45,70,45,70),
(178,2,'classique',ARRAY['Psy','Vol']::text[],7.6,65,75,70,95,70,95),
(179,2,'classique',ARRAY['Électrik']::text[],5,55,40,40,65,45,35),
(180,2,'classique',ARRAY['Électrik']::text[],6.3,70,55,55,80,60,45),
(181,2,'classique',ARRAY['Électrik']::text[],8.1,90,75,85,115,90,55),
(182,2,'classique',ARRAY['Plante']::text[],7.8,75,80,95,90,100,50),
(183,2,'classique',ARRAY['Eau','Fée']::text[],4.3,70,20,50,20,50,40),
(184,2,'classique',ARRAY['Eau','Fée']::text[],7,100,50,80,60,80,50),
(185,2,'classique',ARRAY['Roche']::text[],6.9,70,100,115,30,65,30),
(186,2,'classique',ARRAY['Eau']::text[],8,90,75,75,90,100,70),
(187,2,'classique',ARRAY['Plante','Vol']::text[],4.3,35,35,40,35,55,50),
(188,2,'classique',ARRAY['Plante','Vol']::text[],6,55,45,50,45,65,80),
(189,2,'classique',ARRAY['Plante','Vol']::text[],7.5,75,55,70,55,95,110),
(190,2,'classique',ARRAY['Normal']::text[],6.2,55,70,55,40,55,85),
(191,2,'classique',ARRAY['Plante']::text[],1.9,30,30,30,30,30,30),
(192,2,'classique',ARRAY['Plante']::text[],7.1,75,75,55,105,85,30),
(193,2,'classique',ARRAY['Insecte','Vol']::text[],6.7,65,65,45,75,45,95),
(194,2,'classique',ARRAY['Eau','Sol']::text[],3.3,55,45,45,25,25,15),
(195,2,'classique',ARRAY['Eau','Sol']::text[],7.2,95,85,85,65,65,35),
(196,2,'classique',ARRAY['Psy']::text[],8.2,65,65,60,130,95,110),
(197,2,'classique',ARRAY['Ténèbres']::text[],8.2,95,65,110,60,130,65),
(198,2,'classique',ARRAY['Ténèbres','Vol']::text[],6.8,60,85,42,85,42,91),
(199,2,'classique',ARRAY['Eau','Psy']::text[],7.8,95,75,80,100,110,30),
(200,2,'classique',ARRAY['Spectre']::text[],7.2,60,60,60,85,85,85),
(201,2,'classique',ARRAY['Psy']::text[],5.9,48,72,48,72,48,48),
(202,2,'classique',ARRAY['Psy']::text[],6.8,190,33,58,33,58,33),
(203,2,'classique',ARRAY['Normal','Psy']::text[],7.5,70,80,65,90,65,85),
(204,2,'classique',ARRAY['Insecte']::text[],5.1,50,65,90,35,35,15),
(205,2,'classique',ARRAY['Insecte','Acier']::text[],7.6,75,90,140,60,60,40),
(206,2,'classique',ARRAY['Normal']::text[],7,100,70,70,65,65,45),
(207,2,'classique',ARRAY['Sol','Vol']::text[],7.2,65,75,105,35,65,85),
(208,2,'classique',ARRAY['Acier','Sol']::text[],8.1,75,85,200,55,65,30),
(209,2,'classique',ARRAY['Fée']::text[],5.3,60,80,50,40,40,30),
(210,2,'classique',ARRAY['Fée']::text[],7.4,90,120,75,60,60,45),
(211,2,'classique',ARRAY['Eau','Poison']::text[],7.3,65,95,85,55,55,85),
(212,2,'classique',ARRAY['Insecte','Acier']::text[],8,70,130,100,55,80,65),
(213,2,'classique',ARRAY['Insecte','Roche']::text[],8,20,10,230,10,230,5),
(214,2,'classique',ARRAY['Insecte','Combat']::text[],8,80,125,75,40,95,85),
(215,2,'classique',ARRAY['Ténèbres','Glace']::text[],7.2,55,95,55,35,75,115),
(216,2,'classique',ARRAY['Normal']::text[],5.8,60,80,50,50,50,40),
(217,2,'classique',ARRAY['Normal']::text[],8,90,130,75,75,75,55),
(218,2,'classique',ARRAY['Feu']::text[],4.3,40,40,40,70,40,20),
(219,2,'classique',ARRAY['Feu','Roche']::text[],7.2,60,50,120,90,80,30),
(220,2,'classique',ARRAY['Glace','Sol']::text[],4.3,50,50,40,30,30,50),
(221,2,'classique',ARRAY['Glace','Sol']::text[],7.4,100,100,80,60,60,50),
(222,2,'classique',ARRAY['Eau','Roche']::text[],6.9,65,55,95,65,95,35),
(223,2,'classique',ARRAY['Eau']::text[],5.3,35,65,35,65,35,65),
(224,2,'classique',ARRAY['Eau']::text[],7.7,75,105,75,105,75,45),
(225,2,'classique',ARRAY['Glace','Vol']::text[],5.8,45,55,45,65,45,75),
(226,2,'classique',ARRAY['Eau','Vol']::text[],7.8,85,40,70,80,140,70),
(227,2,'classique',ARRAY['Acier','Vol']::text[],7.6,65,80,140,40,70,70),
(228,2,'classique',ARRAY['Ténèbres','Feu']::text[],5.8,45,60,30,80,50,65),
(229,2,'classique',ARRAY['Ténèbres','Feu']::text[],8,75,90,50,110,80,95),
(230,2,'classique',ARRAY['Eau','Dragon']::text[],8.4,75,95,95,95,95,85),
(231,2,'classique',ARRAY['Sol']::text[],5.8,90,60,60,40,40,40),
(232,2,'classique',ARRAY['Sol']::text[],8,90,120,120,60,60,50),
(233,2,'classique',ARRAY['Normal']::text[],8.1,85,80,90,105,95,60),
(234,2,'classique',ARRAY['Normal']::text[],7.6,73,95,62,85,65,85),
(235,2,'classique',ARRAY['Normal']::text[],4.3,55,20,35,20,45,75),
(236,2,'bébé',ARRAY['Combat']::text[],3.3,35,35,35,35,35,35),
(237,2,'classique',ARRAY['Combat']::text[],7.5,50,95,95,35,110,70),
(238,2,'bébé',ARRAY['Glace','Psy']::text[],5.4,45,30,15,85,65,65),
(239,2,'bébé',ARRAY['Électrik']::text[],6.2,45,63,37,65,55,95),
(240,2,'bébé',ARRAY['Feu']::text[],6.3,45,75,37,70,55,83),
(241,2,'classique',ARRAY['Normal']::text[],7.8,95,80,105,40,70,100),
(242,2,'classique',ARRAY['Normal']::text[],8.4,255,10,10,75,135,55),
(243,2,'légendaire',ARRAY['Électrik']::text[],8.8,90,85,75,115,100,115),
(244,2,'légendaire',ARRAY['Feu']::text[],8.8,115,115,85,90,75,100),
(245,2,'légendaire',ARRAY['Eau']::text[],8.8,100,75,115,90,115,85),
(246,2,'classique',ARRAY['Roche','Sol']::text[],5.3,50,64,50,45,50,41),
(247,2,'classique',ARRAY['Roche','Sol']::text[],6.9,70,84,70,65,70,51),
(248,2,'pseudo-légendaire',ARRAY['Roche','Ténèbres']::text[],8.9,100,134,110,95,100,61),
(249,2,'légendaire',ARRAY['Psy','Vol']::text[],9.7,106,90,130,90,154,110),
(250,2,'légendaire',ARRAY['Feu','Vol']::text[],9.7,106,130,90,110,154,90),
(251,2,'fabuleux',ARRAY['Psy','Plante']::text[],8.9,100,100,100,100,100,100),
(252,3,'starter',ARRAY['Plante']::text[],5.5,40,45,35,65,55,70),
(253,3,'starter',ARRAY['Plante']::text[],6.8,50,65,45,85,65,95),
(254,3,'starter',ARRAY['Plante']::text[],8.3,70,85,65,105,85,120),
(255,3,'starter',ARRAY['Feu']::text[],5.5,45,60,40,70,50,45),
(256,3,'starter',ARRAY['Feu','Combat']::text[],6.8,60,85,60,85,60,55),
(257,3,'starter',ARRAY['Feu','Combat']::text[],8.3,80,120,70,110,70,80),
(258,3,'starter',ARRAY['Eau']::text[],5.5,50,70,50,50,50,40),
(259,3,'starter',ARRAY['Eau','Sol']::text[],6.8,70,85,70,60,70,50),
(260,3,'starter',ARRAY['Eau','Sol']::text[],8.3,100,110,90,85,90,60),
(261,3,'classique',ARRAY['Ténèbres']::text[],3.6,35,55,35,30,30,35),
(262,3,'classique',ARRAY['Ténèbres']::text[],7,70,90,70,60,60,70),
(263,3,'classique',ARRAY['Normal']::text[],4.1,38,30,41,30,41,60),
(264,3,'classique',ARRAY['Normal']::text[],7,78,70,61,50,61,100),
(265,3,'classique',ARRAY['Insecte']::text[],2.7,45,45,35,20,30,20),
(266,3,'classique',ARRAY['Insecte']::text[],3.1,50,35,55,25,25,15),
(267,3,'classique',ARRAY['Insecte','Vol']::text[],6.7,60,70,50,100,50,65),
(268,3,'classique',ARRAY['Insecte']::text[],3.1,50,35,55,25,25,15),
(269,3,'classique',ARRAY['Insecte','Poison']::text[],6.6,60,50,70,50,90,65),
(270,3,'classique',ARRAY['Eau','Plante']::text[],3.6,40,30,30,40,50,30),
(271,3,'classique',ARRAY['Eau','Plante']::text[],6,60,50,50,60,70,50),
(272,3,'classique',ARRAY['Eau','Plante']::text[],7.7,80,70,70,90,100,70),
(273,3,'classique',ARRAY['Plante']::text[],3.6,40,40,50,30,30,30),
(274,3,'classique',ARRAY['Plante','Ténèbres']::text[],6,70,70,40,60,40,60),
(275,3,'classique',ARRAY['Plante','Ténèbres']::text[],7.7,90,100,60,90,60,80),
(276,3,'classique',ARRAY['Normal','Vol']::text[],4.8,40,55,30,30,30,85),
(277,3,'classique',ARRAY['Normal','Vol']::text[],7.5,60,85,60,75,50,125),
(278,3,'classique',ARRAY['Eau','Vol']::text[],4.8,40,30,30,55,30,85),
(279,3,'classique',ARRAY['Eau','Vol']::text[],7.3,60,50,100,95,70,65),
(280,3,'classique',ARRAY['Psy','Fée']::text[],2.8,28,25,25,45,35,40),
(281,3,'classique',ARRAY['Psy','Fée']::text[],4.9,38,35,35,65,55,50),
(282,3,'classique',ARRAY['Psy','Fée']::text[],8.1,68,65,65,125,115,80),
(283,3,'classique',ARRAY['Insecte','Eau']::text[],4.7,40,30,32,50,52,65),
(284,3,'classique',ARRAY['Insecte','Vol']::text[],7.4,70,60,62,100,82,80),
(285,3,'classique',ARRAY['Plante']::text[],5.2,60,40,60,40,60,35),
(286,3,'classique',ARRAY['Plante','Combat']::text[],7.5,60,130,80,60,60,70),
(287,3,'classique',ARRAY['Normal']::text[],5,60,60,60,35,35,30),
(288,3,'classique',ARRAY['Normal']::text[],7.3,80,80,80,55,55,90),
(289,3,'classique',ARRAY['Normal']::text[],9.6,150,160,100,95,65,100),
(290,3,'classique',ARRAY['Insecte','Sol']::text[],4.7,31,45,90,30,30,40),
(291,3,'classique',ARRAY['Insecte','Vol']::text[],7.5,61,90,45,50,50,160),
(292,3,'classique',ARRAY['Insecte','Spectre']::text[],4,1,90,45,30,30,40),
(293,3,'classique',ARRAY['Normal']::text[],4.1,64,51,23,51,23,28),
(294,3,'classique',ARRAY['Normal']::text[],6.2,84,71,43,71,43,48),
(295,3,'classique',ARRAY['Normal']::text[],7.8,104,91,63,91,73,68),
(296,3,'classique',ARRAY['Combat']::text[],4,72,60,30,20,30,25),
(297,3,'classique',ARRAY['Combat']::text[],7.7,144,120,60,40,60,50),
(298,3,'bébé',ARRAY['Normal','Fée']::text[],2.5,50,20,40,20,40,20),
(299,3,'classique',ARRAY['Roche']::text[],6.5,30,45,135,45,90,30),
(300,3,'classique',ARRAY['Normal']::text[],4.6,50,45,45,35,35,50),
(301,3,'classique',ARRAY['Normal']::text[],6.8,70,65,65,55,55,90),
(302,3,'classique',ARRAY['Ténèbres','Spectre']::text[],6.5,50,75,75,65,65,50),
(303,3,'classique',ARRAY['Acier','Fée']::text[],6.5,50,85,85,55,55,50),
(304,3,'classique',ARRAY['Acier','Roche']::text[],5.8,50,70,100,40,40,30),
(305,3,'classique',ARRAY['Acier','Roche']::text[],7.2,60,90,140,50,50,40),
(306,3,'classique',ARRAY['Acier','Roche']::text[],8.3,70,110,180,60,60,50),
(307,3,'classique',ARRAY['Combat','Psy']::text[],5,30,40,55,40,55,60),
(308,3,'classique',ARRAY['Combat','Psy']::text[],6.9,60,60,75,60,75,80),
(309,3,'classique',ARRAY['Électrik']::text[],5.2,40,45,40,65,40,65),
(310,3,'classique',ARRAY['Électrik']::text[],7.7,70,75,60,105,60,105),
(311,3,'classique',ARRAY['Électrik']::text[],6.8,60,50,40,85,75,95),
(312,3,'classique',ARRAY['Électrik']::text[],6.8,60,40,50,75,85,95),
(313,3,'classique',ARRAY['Insecte']::text[],7.2,65,73,75,47,85,85),
(314,3,'classique',ARRAY['Insecte']::text[],7.2,65,47,75,73,85,85),
(315,3,'classique',ARRAY['Plante','Poison']::text[],6.8,50,60,45,100,80,65),
(316,3,'classique',ARRAY['Poison']::text[],5.3,70,43,53,43,53,40),
(317,3,'classique',ARRAY['Poison']::text[],7.6,100,73,83,73,83,55),
(318,3,'classique',ARRAY['Eau','Ténèbres']::text[],5.4,45,90,20,65,20,65),
(319,3,'classique',ARRAY['Eau','Ténèbres']::text[],7.5,70,120,40,95,40,95),
(320,3,'classique',ARRAY['Eau']::text[],6.8,130,70,35,70,35,60),
(321,3,'classique',ARRAY['Eau']::text[],8,170,90,45,90,45,60),
(322,3,'classique',ARRAY['Feu','Sol']::text[],5.4,60,60,40,65,45,35),
(323,3,'classique',ARRAY['Feu','Sol']::text[],7.5,70,100,70,105,75,40),
(324,3,'classique',ARRAY['Feu']::text[],7.6,70,85,140,85,70,20),
(325,3,'classique',ARRAY['Psy']::text[],5.8,60,25,35,70,80,60),
(326,3,'classique',ARRAY['Psy']::text[],7.6,80,45,65,90,110,80),
(327,3,'classique',ARRAY['Normal']::text[],6.2,60,60,60,60,60,60),
(328,3,'classique',ARRAY['Sol']::text[],5.1,45,100,45,45,45,10),
(329,3,'classique',ARRAY['Sol','Dragon']::text[],6,50,70,50,50,50,70),
(330,3,'classique',ARRAY['Sol','Dragon']::text[],8.2,80,100,80,80,80,100),
(331,3,'classique',ARRAY['Plante']::text[],5.9,50,85,40,85,40,35),
(332,3,'classique',ARRAY['Plante','Ténèbres']::text[],7.7,70,115,60,115,60,55),
(333,3,'classique',ARRAY['Normal','Vol']::text[],5.5,45,40,60,40,75,50),
(334,3,'classique',ARRAY['Dragon','Vol']::text[],7.8,75,70,90,70,105,80),
(335,3,'classique',ARRAY['Normal']::text[],7.5,73,115,60,60,60,90),
(336,3,'classique',ARRAY['Poison']::text[],7.5,73,100,60,100,60,65),
(337,3,'classique',ARRAY['Roche','Psy']::text[],7.5,90,55,65,95,85,70),
(338,3,'classique',ARRAY['Roche','Psy']::text[],7.5,90,95,85,55,65,70),
(339,3,'classique',ARRAY['Eau','Sol']::text[],5.1,50,48,43,46,41,60),
(340,3,'classique',ARRAY['Eau','Sol']::text[],7.6,110,78,73,76,71,60),
(341,3,'classique',ARRAY['Eau']::text[],5.4,43,80,65,50,35,35),
(342,3,'classique',ARRAY['Eau','Ténèbres']::text[],7.6,63,120,85,90,55,55),
(343,3,'classique',ARRAY['Sol','Psy']::text[],5.3,40,40,55,40,70,55),
(344,3,'classique',ARRAY['Sol','Psy']::text[],8,60,70,105,70,120,75),
(345,3,'fossile',ARRAY['Roche','Plante']::text[],6.2,66,41,77,61,87,23),
(346,3,'fossile',ARRAY['Roche','Plante']::text[],7.9,86,81,97,81,107,43),
(347,3,'fossile',ARRAY['Roche','Insecte']::text[],6.2,45,95,50,40,50,75),
(348,3,'fossile',ARRAY['Roche','Insecte']::text[],7.9,75,125,100,70,80,45),
(349,3,'classique',ARRAY['Eau']::text[],2.9,20,15,20,10,55,80),
(350,3,'classique',ARRAY['Eau']::text[],8.4,95,60,79,100,125,81),
(351,3,'classique',ARRAY['Normal']::text[],7,70,70,70,70,70,70),
(352,3,'classique',ARRAY['Normal']::text[],7.3,60,90,70,60,120,40),
(353,3,'classique',ARRAY['Spectre']::text[],5.2,44,75,35,63,33,45),
(354,3,'classique',ARRAY['Spectre']::text[],7.5,64,115,65,83,63,65),
(355,3,'classique',ARRAY['Spectre']::text[],5.2,20,40,90,30,90,25),
(356,3,'classique',ARRAY['Spectre']::text[],7.5,40,70,130,60,130,25),
(357,3,'classique',ARRAY['Plante','Vol']::text[],7.5,99,68,83,72,87,51),
(358,3,'classique',ARRAY['Psy']::text[],7.5,75,50,80,95,90,65),
(359,3,'classique',ARRAY['Ténèbres']::text[],7.6,65,130,60,75,60,75),
(360,3,'bébé',ARRAY['Psy']::text[],4.6,95,23,48,23,48,23),
(361,3,'classique',ARRAY['Glace']::text[],5.3,50,50,50,50,50,50),
(362,3,'classique',ARRAY['Glace']::text[],7.7,80,80,80,80,80,80),
(363,3,'classique',ARRAY['Glace','Eau']::text[],5.1,70,40,50,55,50,25),
(364,3,'classique',ARRAY['Glace','Eau']::text[],6.9,90,60,70,75,70,45),
(365,3,'classique',ARRAY['Glace','Eau']::text[],8.3,110,80,90,95,90,65),
(366,3,'classique',ARRAY['Eau']::text[],6,35,64,85,74,55,32),
(367,3,'classique',ARRAY['Eau']::text[],7.8,55,104,105,94,75,52),
(368,3,'classique',ARRAY['Eau']::text[],7.8,55,84,105,114,75,52),
(369,3,'classique',ARRAY['Eau','Roche']::text[],7.8,100,90,130,45,65,55),
(370,3,'classique',ARRAY['Eau']::text[],5.8,43,30,55,40,65,97),
(371,3,'classique',ARRAY['Dragon']::text[],5.3,45,75,60,40,30,50),
(372,3,'classique',ARRAY['Dragon']::text[],7,65,95,100,60,50,50),
(373,3,'classique',ARRAY['Dragon','Vol']::text[],8.9,95,135,80,110,80,100),
(374,3,'classique',ARRAY['Acier','Psy']::text[],5.3,40,55,80,35,60,30),
(375,3,'classique',ARRAY['Acier','Psy']::text[],7,60,75,100,55,80,50),
(376,3,'pseudo-légendaire',ARRAY['Acier','Psy']::text[],8.9,80,135,130,95,90,70),
(377,3,'légendaire',ARRAY['Roche']::text[],8.8,80,100,200,50,100,50),
(378,3,'légendaire',ARRAY['Glace']::text[],8.8,80,50,100,100,200,50),
(379,3,'légendaire',ARRAY['Acier']::text[],8.8,80,75,150,75,150,50),
(380,3,'légendaire',ARRAY['Dragon','Psy']::text[],8.9,80,80,90,110,130,110),
(381,3,'légendaire',ARRAY['Dragon','Psy']::text[],8.9,80,90,80,130,110,110),
(382,3,'légendaire',ARRAY['Eau']::text[],9.6,100,100,90,150,140,90),
(383,3,'légendaire',ARRAY['Sol']::text[],9.6,100,150,140,100,90,90),
(384,3,'légendaire',ARRAY['Dragon','Vol']::text[],9.7,105,150,90,150,90,95),
(385,3,'fabuleux',ARRAY['Acier','Psy']::text[],8.9,100,100,100,100,100,100),
(386,3,'fabuleux',ARRAY['Psy']::text[],8.9,50,150,50,150,50,150),
(387,4,'starter',ARRAY['Plante']::text[],5.6,55,68,64,45,55,31),
(388,4,'starter',ARRAY['Plante']::text[],6.8,75,89,85,55,65,36),
(389,4,'starter',ARRAY['Plante','Sol']::text[],8.2,95,109,105,75,85,56),
(390,4,'starter',ARRAY['Feu']::text[],5.5,44,58,44,58,44,61),
(391,4,'starter',ARRAY['Feu','Combat']::text[],6.8,64,78,52,78,52,81),
(392,4,'starter',ARRAY['Feu','Combat']::text[],8.3,76,104,71,104,71,108),
(393,4,'starter',ARRAY['Eau']::text[],5.5,53,51,53,61,56,40),
(394,4,'starter',ARRAY['Eau']::text[],6.8,64,66,68,81,76,50),
(395,4,'starter',ARRAY['Eau','Acier']::text[],8.3,84,86,88,111,101,60),
(396,4,'classique',ARRAY['Normal','Vol']::text[],4.2,40,55,30,30,30,60),
(397,4,'classique',ARRAY['Normal','Vol']::text[],6,55,75,50,40,40,80),
(398,4,'classique',ARRAY['Normal','Vol']::text[],7.8,85,120,70,50,60,100),
(399,4,'classique',ARRAY['Normal']::text[],4.3,59,45,40,35,40,31),
(400,4,'classique',ARRAY['Normal','Eau']::text[],6.9,79,85,60,55,60,71),
(401,4,'classique',ARRAY['Insecte']::text[],2.7,37,25,41,25,41,25),
(402,4,'classique',ARRAY['Insecte']::text[],6.6,77,85,51,55,51,65),
(403,4,'classique',ARRAY['Électrik']::text[],4.6,45,65,34,40,34,45),
(404,4,'classique',ARRAY['Électrik']::text[],6.3,60,85,49,60,49,60),
(405,4,'classique',ARRAY['Électrik']::text[],8.2,80,120,79,95,79,70),
(406,4,'bébé',ARRAY['Plante','Poison']::text[],5,40,30,35,50,70,55),
(407,4,'classique',ARRAY['Plante','Poison']::text[],8.1,60,70,65,125,105,90),
(408,4,'fossile',ARRAY['Roche']::text[],6.1,67,125,40,30,30,58),
(409,4,'fossile',ARRAY['Roche']::text[],7.9,97,165,60,65,50,58),
(410,4,'fossile',ARRAY['Roche','Acier']::text[],6.1,30,42,118,42,88,30),
(411,4,'fossile',ARRAY['Roche','Acier']::text[],7.9,60,52,168,47,138,30),
(412,4,'classique',ARRAY['Insecte']::text[],3.7,40,29,45,29,45,36),
(413,4,'classique',ARRAY['Insecte','Plante']::text[],7.1,60,59,85,79,105,36),
(414,4,'classique',ARRAY['Insecte','Vol']::text[],7.1,70,94,50,94,50,66),
(415,4,'classique',ARRAY['Insecte','Vol']::text[],4.2,30,30,42,30,42,70),
(416,4,'classique',ARRAY['Insecte','Vol']::text[],7.7,70,80,102,80,102,40),
(417,4,'classique',ARRAY['Électrik']::text[],6.8,60,45,70,45,90,95),
(418,4,'classique',ARRAY['Eau']::text[],5.8,55,65,35,60,30,85),
(419,4,'classique',ARRAY['Eau']::text[],7.9,85,105,55,85,50,115),
(420,4,'classique',ARRAY['Plante']::text[],4.9,45,35,45,62,53,35),
(421,4,'classique',ARRAY['Plante']::text[],7.4,70,60,70,87,78,85),
(422,4,'classique',ARRAY['Eau']::text[],5.7,76,48,48,57,62,34),
(423,4,'classique',ARRAY['Eau','Sol']::text[],7.7,111,83,68,92,82,39),
(424,4,'classique',ARRAY['Normal']::text[],7.8,75,100,66,60,66,115),
(425,4,'classique',ARRAY['Spectre','Vol']::text[],6.1,90,50,34,60,44,70),
(426,4,'classique',ARRAY['Spectre','Vol']::text[],7.9,150,80,44,90,54,80),
(427,4,'classique',ARRAY['Normal']::text[],6.1,55,66,44,44,56,85),
(428,4,'classique',ARRAY['Normal']::text[],7.7,65,76,84,54,96,105),
(429,4,'classique',ARRAY['Spectre']::text[],7.9,60,60,60,105,105,105),
(430,4,'classique',ARRAY['Ténèbres','Vol']::text[],8,100,125,52,105,52,71),
(431,4,'classique',ARRAY['Normal']::text[],5.5,49,55,42,42,37,85),
(432,4,'classique',ARRAY['Normal']::text[],7.4,71,82,64,64,59,112),
(433,4,'bébé',ARRAY['Psy']::text[],5,45,30,50,65,50,45),
(434,4,'classique',ARRAY['Poison','Ténèbres']::text[],5.8,63,63,47,41,41,74),
(435,4,'classique',ARRAY['Poison','Ténèbres']::text[],7.7,103,93,67,71,61,84),
(436,4,'classique',ARRAY['Acier','Psy']::text[],5.3,57,24,86,24,86,23),
(437,4,'classique',ARRAY['Acier','Psy']::text[],8,67,89,116,79,116,33),
(438,4,'bébé',ARRAY['Roche']::text[],5.1,50,80,95,10,45,10),
(439,4,'bébé',ARRAY['Psy','Fée']::text[],5.5,20,25,45,70,90,60),
(440,4,'bébé',ARRAY['Normal']::text[],3.6,100,5,5,15,65,30),
(441,4,'classique',ARRAY['Normal','Vol']::text[],6.9,76,65,45,92,42,91),
(442,4,'classique',ARRAY['Spectre','Ténèbres']::text[],7.8,50,92,108,92,108,35),
(443,4,'classique',ARRAY['Dragon','Sol']::text[],5.3,58,70,45,40,45,42),
(444,4,'classique',ARRAY['Dragon','Sol']::text[],6.9,68,90,65,50,55,82),
(445,4,'pseudo-légendaire',ARRAY['Dragon','Sol']::text[],8.9,108,130,95,80,85,102),
(446,4,'bébé',ARRAY['Normal']::text[],6.7,135,85,40,40,85,5),
(447,4,'bébé',ARRAY['Combat']::text[],5,40,70,40,35,40,60),
(448,4,'classique',ARRAY['Combat','Acier']::text[],8.2,70,110,70,115,70,90),
(449,4,'classique',ARRAY['Sol']::text[],5.8,68,72,78,38,42,32),
(450,4,'classique',ARRAY['Sol']::text[],8.2,108,112,118,68,72,47),
(451,4,'classique',ARRAY['Poison','Insecte']::text[],5.8,40,50,90,30,55,65),
(452,4,'classique',ARRAY['Poison','Ténèbres']::text[],8,70,90,110,60,75,95),
(453,4,'classique',ARRAY['Poison','Combat']::text[],5.3,48,61,40,61,40,50),
(454,4,'classique',ARRAY['Poison','Combat']::text[],7.8,83,106,65,86,65,85),
(455,4,'classique',ARRAY['Plante']::text[],7.4,74,100,72,90,72,46),
(456,4,'classique',ARRAY['Eau']::text[],5.8,49,49,56,49,61,66),
(457,4,'classique',ARRAY['Eau']::text[],7.5,69,69,76,69,86,91),
(458,4,'bébé',ARRAY['Eau','Vol']::text[],6,45,20,50,60,120,50),
(459,4,'classique',ARRAY['Plante','Glace']::text[],5.9,60,62,50,62,60,40),
(460,4,'classique',ARRAY['Plante','Glace']::text[],7.9,90,92,75,92,85,60),
(461,4,'classique',ARRAY['Ténèbres','Glace']::text[],8.1,70,120,65,45,85,125),
(462,4,'classique',ARRAY['Électrik','Acier']::text[],8.3,70,70,115,130,90,60),
(463,4,'classique',ARRAY['Normal']::text[],8.1,110,85,95,80,95,50),
(464,4,'classique',ARRAY['Sol','Roche']::text[],8.3,115,140,130,55,55,40),
(465,4,'classique',ARRAY['Plante']::text[],8.3,100,100,125,110,50,50),
(466,4,'classique',ARRAY['Électrik']::text[],8.4,75,123,67,95,85,95),
(467,4,'classique',ARRAY['Feu']::text[],8.4,75,95,67,125,95,83),
(468,4,'classique',ARRAY['Fée','Vol']::text[],8.4,85,50,95,120,115,80),
(469,4,'classique',ARRAY['Insecte','Vol']::text[],8.1,86,76,86,116,56,95),
(470,4,'classique',ARRAY['Plante']::text[],8.2,65,110,130,60,65,95),
(471,4,'classique',ARRAY['Glace']::text[],8.2,65,60,110,130,95,65),
(472,4,'classique',ARRAY['Sol','Vol']::text[],8.1,75,95,125,45,75,95),
(473,4,'classique',ARRAY['Glace','Sol']::text[],8.3,110,130,80,70,60,80),
(474,4,'classique',ARRAY['Normal']::text[],8.3,85,80,70,135,75,90),
(475,4,'classique',ARRAY['Psy','Combat']::text[],8.1,68,125,65,65,115,80),
(476,4,'classique',ARRAY['Roche','Acier']::text[],8.2,60,55,145,75,150,40),
(477,4,'classique',ARRAY['Spectre']::text[],8.2,45,100,135,65,135,45),
(478,4,'classique',ARRAY['Glace','Spectre']::text[],7.7,70,80,70,80,70,110),
(479,4,'classique',ARRAY['Électrik','Spectre']::text[],7.3,50,50,77,95,77,91),
(480,4,'légendaire',ARRAY['Psy']::text[],8.8,75,75,130,75,130,95),
(481,4,'légendaire',ARRAY['Psy']::text[],8.8,80,105,105,105,105,80),
(482,4,'légendaire',ARRAY['Psy']::text[],8.8,75,125,70,125,70,115),
(483,4,'légendaire',ARRAY['Acier','Dragon']::text[],9.7,100,120,120,150,100,90),
(484,4,'légendaire',ARRAY['Eau','Dragon']::text[],9.7,90,120,100,150,120,100),
(485,4,'légendaire',ARRAY['Feu','Acier']::text[],8.9,91,90,106,130,106,77),
(486,4,'légendaire',ARRAY['Normal']::text[],9.6,110,160,110,80,110,100),
(487,4,'légendaire',ARRAY['Spectre','Dragon']::text[],9.7,150,100,120,100,120,90),
(488,4,'légendaire',ARRAY['Psy']::text[],8.8,120,70,110,75,120,85),
(489,4,'fabuleux',ARRAY['Eau']::text[],7.7,80,80,80,80,80,80),
(490,4,'fabuleux',ARRAY['Eau']::text[],8.9,100,100,100,100,100,100),
(491,4,'fabuleux',ARRAY['Ténèbres']::text[],8.9,70,90,90,135,90,125),
(492,4,'fabuleux',ARRAY['Plante']::text[],8.9,100,100,100,100,100,100),
(493,4,'fabuleux',ARRAY['Normal']::text[],10,120,120,120,120,120,120),
(494,5,'fabuleux',ARRAY['Psy','Feu']::text[],8.9,100,100,100,100,100,100),
(495,5,'starter',ARRAY['Plante']::text[],5.4,45,45,55,45,55,63),
(496,5,'starter',ARRAY['Plante']::text[],6.9,60,60,75,60,75,83),
(497,5,'starter',ARRAY['Plante']::text[],8.2,75,75,95,75,95,113),
(498,5,'starter',ARRAY['Feu']::text[],5.4,65,63,45,45,45,45),
(499,5,'starter',ARRAY['Feu','Combat']::text[],7,90,93,55,70,55,55),
(500,5,'starter',ARRAY['Feu','Combat']::text[],8.2,110,123,65,100,65,65),
(501,5,'starter',ARRAY['Eau']::text[],5.4,55,55,45,63,45,45),
(502,5,'starter',ARRAY['Eau']::text[],6.9,75,75,60,83,60,60),
(503,5,'starter',ARRAY['Eau']::text[],8.2,95,100,85,108,70,70),
(504,5,'classique',ARRAY['Normal']::text[],4.4,45,55,39,35,39,42),
(505,5,'classique',ARRAY['Normal']::text[],7,60,85,69,60,69,77),
(506,5,'classique',ARRAY['Normal']::text[],4.9,45,60,45,25,45,55),
(507,5,'classique',ARRAY['Normal']::text[],6.4,65,80,65,35,65,60),
(508,5,'classique',ARRAY['Normal']::text[],8,85,110,90,45,90,80),
(509,5,'classique',ARRAY['Ténèbres']::text[],5,41,50,37,50,37,66),
(510,5,'classique',ARRAY['Ténèbres']::text[],7.3,64,88,50,88,50,106),
(511,5,'classique',ARRAY['Plante']::text[],5.6,50,53,48,53,48,64),
(512,5,'classique',ARRAY['Plante']::text[],7.9,75,98,63,98,63,101),
(513,5,'classique',ARRAY['Feu']::text[],5.6,50,53,48,53,48,64),
(514,5,'classique',ARRAY['Feu']::text[],7.9,75,98,63,98,63,101),
(515,5,'classique',ARRAY['Eau']::text[],5.6,50,53,48,53,48,64),
(516,5,'classique',ARRAY['Eau']::text[],7.9,75,98,63,98,63,101),
(517,5,'classique',ARRAY['Psy']::text[],5.2,76,25,45,67,55,24),
(518,5,'classique',ARRAY['Psy']::text[],7.8,116,55,85,107,95,29),
(519,5,'classique',ARRAY['Normal','Vol']::text[],4.6,50,55,50,36,30,43),
(520,5,'classique',ARRAY['Normal','Vol']::text[],6.2,62,77,62,50,42,65),
(521,5,'classique',ARRAY['Normal','Vol']::text[],7.8,80,115,80,65,55,93),
(522,5,'classique',ARRAY['Électrik']::text[],5.2,45,60,32,50,32,76),
(523,5,'classique',ARRAY['Électrik']::text[],7.9,75,100,63,80,63,116),
(524,5,'classique',ARRAY['Roche']::text[],5,55,75,85,25,25,15),
(525,5,'classique',ARRAY['Roche']::text[],6.7,70,105,105,50,40,20),
(526,5,'classique',ARRAY['Roche']::text[],8.1,85,135,130,60,80,25),
(527,5,'classique',ARRAY['Psy','Vol']::text[],5.7,65,45,43,55,43,72),
(528,5,'classique',ARRAY['Psy','Vol']::text[],7.1,67,57,55,77,55,114),
(529,5,'classique',ARRAY['Sol']::text[],5.8,60,85,40,30,45,68),
(530,5,'classique',ARRAY['Sol','Acier']::text[],8,110,135,60,50,65,88),
(531,5,'classique',ARRAY['Normal']::text[],7.3,103,60,86,60,86,50),
(532,5,'classique',ARRAY['Combat']::text[],5.4,75,80,55,25,35,35),
(533,5,'classique',ARRAY['Combat']::text[],6.8,85,105,85,40,50,40),
(534,5,'classique',ARRAY['Combat']::text[],8,105,140,95,55,65,45),
(535,5,'classique',ARRAY['Eau']::text[],5.2,50,50,40,50,40,64),
(536,5,'classique',ARRAY['Eau','Sol']::text[],6.6,75,65,55,65,55,69),
(537,5,'classique',ARRAY['Eau','Sol']::text[],8,105,95,75,85,75,74),
(538,5,'classique',ARRAY['Combat']::text[],7.6,120,100,85,30,85,45),
(539,5,'classique',ARRAY['Combat']::text[],7.6,75,125,75,30,75,85),
(540,5,'classique',ARRAY['Insecte','Plante']::text[],5.5,45,53,70,40,60,42),
(541,5,'classique',ARRAY['Insecte','Plante']::text[],6.5,55,63,90,50,80,42),
(542,5,'classique',ARRAY['Insecte','Plante']::text[],8,75,103,80,70,80,92),
(543,5,'classique',ARRAY['Insecte','Poison']::text[],4.6,30,45,59,30,39,57),
(544,5,'classique',ARRAY['Insecte','Poison']::text[],6.2,40,55,99,40,79,47),
(545,5,'classique',ARRAY['Insecte','Poison']::text[],7.8,60,100,89,55,69,112),
(546,5,'classique',ARRAY['Plante','Fée']::text[],5,40,27,60,37,50,66),
(547,5,'classique',ARRAY['Plante','Fée']::text[],7.7,60,67,85,77,75,116),
(548,5,'classique',ARRAY['Plante']::text[],5,45,35,50,70,50,30),
(549,5,'classique',ARRAY['Plante']::text[],7.7,70,60,75,110,75,90),
(550,5,'classique',ARRAY['Eau']::text[],7.5,70,92,65,80,55,98),
(551,5,'classique',ARRAY['Sol','Ténèbres']::text[],5.2,50,72,35,35,35,65),
(552,5,'classique',ARRAY['Sol','Ténèbres']::text[],6.1,60,82,45,45,45,74),
(553,5,'classique',ARRAY['Sol','Ténèbres']::text[],8.2,95,117,80,65,70,92),
(554,5,'classique',ARRAY['Feu']::text[],5.6,70,90,45,15,45,50),
(555,5,'classique',ARRAY['Feu']::text[],7.7,105,140,55,30,55,95),
(556,5,'classique',ARRAY['Plante']::text[],7.5,75,86,67,106,67,60),
(557,5,'classique',ARRAY['Insecte','Roche']::text[],5.7,50,65,85,35,35,55),
(558,5,'classique',ARRAY['Insecte','Roche']::text[],7.8,70,105,125,65,75,45),
(559,5,'classique',ARRAY['Ténèbres','Combat']::text[],6.1,50,75,70,35,70,48),
(560,5,'classique',ARRAY['Ténèbres','Combat']::text[],7.8,65,90,115,45,115,58),
(561,5,'classique',ARRAY['Psy','Vol']::text[],7.8,72,58,80,103,80,97),
(562,5,'classique',ARRAY['Spectre']::text[],5.4,38,30,85,55,65,30),
(563,5,'classique',ARRAY['Spectre']::text[],7.8,58,50,145,95,105,30),
(564,5,'fossile',ARRAY['Eau','Roche']::text[],6.2,54,78,103,53,45,22),
(565,5,'fossile',ARRAY['Eau','Roche']::text[],7.9,74,108,133,83,65,32),
(566,5,'fossile',ARRAY['Roche','Vol']::text[],6.8,55,112,45,74,45,70),
(567,5,'fossile',ARRAY['Roche','Vol']::text[],8.6,75,140,65,112,65,110),
(568,5,'classique',ARRAY['Poison']::text[],5.8,50,50,62,40,62,65),
(569,5,'classique',ARRAY['Poison']::text[],7.7,80,95,82,60,82,75),
(570,5,'classique',ARRAY['Ténèbres']::text[],5.8,40,65,40,80,40,65),
(571,5,'classique',ARRAY['Ténèbres']::text[],8.1,60,105,60,120,60,105),
(572,5,'classique',ARRAY['Normal']::text[],5.3,55,50,40,40,40,75),
(573,5,'classique',ARRAY['Normal']::text[],7.6,75,95,60,65,60,115),
(574,5,'classique',ARRAY['Psy']::text[],5.1,45,30,50,55,65,45),
(575,5,'classique',ARRAY['Psy']::text[],6.7,60,45,70,75,85,55),
(576,5,'classique',ARRAY['Psy']::text[],7.8,70,55,95,95,110,65),
(577,5,'classique',ARRAY['Psy']::text[],5.1,45,30,40,105,50,20),
(578,5,'classique',ARRAY['Psy']::text[],6.4,65,40,50,125,60,30),
(579,5,'classique',ARRAY['Psy']::text[],7.8,110,65,75,125,85,30),
(580,5,'classique',ARRAY['Eau','Vol']::text[],5.4,62,44,50,44,50,55),
(581,5,'classique',ARRAY['Eau','Vol']::text[],7.7,75,87,63,87,63,98),
(582,5,'classique',ARRAY['Glace']::text[],5.4,36,50,50,65,60,44),
(583,5,'classique',ARRAY['Glace']::text[],6.7,51,65,65,80,75,59),
(584,5,'classique',ARRAY['Glace']::text[],8.3,71,95,85,110,95,79),
(585,5,'classique',ARRAY['Normal','Plante']::text[],5.9,60,60,50,40,50,75),
(586,5,'classique',ARRAY['Normal','Plante']::text[],7.7,80,100,70,60,70,95),
(587,5,'classique',ARRAY['Électrik','Vol']::text[],7.1,55,75,60,75,60,103),
(588,5,'classique',ARRAY['Insecte']::text[],5.6,50,75,45,40,45,60),
(589,5,'classique',ARRAY['Insecte','Acier']::text[],7.9,70,135,105,60,105,20),
(590,5,'classique',ARRAY['Plante','Poison']::text[],5.2,69,55,45,55,55,15),
(591,5,'classique',ARRAY['Plante','Poison']::text[],7.6,114,85,70,85,80,30),
(592,5,'classique',ARRAY['Eau','Spectre']::text[],5.9,55,40,50,65,85,40),
(593,5,'classique',ARRAY['Eau','Spectre']::text[],7.7,100,60,70,85,105,60),
(594,5,'classique',ARRAY['Eau']::text[],7.6,165,75,80,40,45,65),
(595,5,'classique',ARRAY['Insecte','Électrik']::text[],5.6,50,47,50,57,50,65),
(596,5,'classique',ARRAY['Insecte','Électrik']::text[],7.6,70,77,60,97,60,108),
(597,5,'classique',ARRAY['Plante','Acier']::text[],5.4,44,50,91,24,86,10),
(598,5,'classique',ARRAY['Plante','Acier']::text[],7.8,74,94,131,54,116,20),
(599,5,'classique',ARRAY['Acier']::text[],5.3,40,55,70,45,60,30),
(600,5,'classique',ARRAY['Acier']::text[],7.3,60,80,95,70,85,50),
(601,5,'classique',ARRAY['Acier']::text[],8.2,60,100,115,70,85,90),
(602,5,'classique',ARRAY['Électrik']::text[],4.9,35,55,40,45,40,60),
(603,5,'classique',ARRAY['Électrik']::text[],6.8,65,85,70,75,70,40),
(604,5,'classique',ARRAY['Électrik']::text[],8.1,85,115,80,105,80,50),
(605,5,'classique',ARRAY['Psy']::text[],5.9,55,55,55,85,55,30),
(606,5,'classique',ARRAY['Psy']::text[],7.8,75,75,75,125,95,40),
(607,5,'classique',ARRAY['Spectre','Feu']::text[],4.9,50,30,55,65,55,20),
(608,5,'classique',ARRAY['Spectre','Feu']::text[],6.4,60,40,60,95,60,55),
(609,5,'classique',ARRAY['Spectre','Feu']::text[],8.2,60,55,90,145,90,80),
(610,5,'classique',ARRAY['Dragon']::text[],5.6,46,87,60,30,40,57),
(611,5,'classique',ARRAY['Dragon']::text[],6.9,66,117,70,40,50,67),
(612,5,'classique',ARRAY['Dragon']::text[],8.4,76,147,90,60,70,97),
(613,5,'classique',ARRAY['Glace']::text[],5.4,55,70,40,60,40,40),
(614,5,'classique',ARRAY['Glace']::text[],8,95,130,80,70,80,50),
(615,5,'classique',ARRAY['Glace']::text[],8.1,80,50,50,95,135,105),
(616,5,'classique',ARRAY['Insecte']::text[],5.4,50,40,85,40,65,25),
(617,5,'classique',ARRAY['Insecte']::text[],7.9,80,70,40,100,60,145),
(618,5,'classique',ARRAY['Sol','Électrik']::text[],7.6,109,66,84,81,99,32),
(619,5,'classique',ARRAY['Combat']::text[],6.1,45,85,50,55,50,65),
(620,5,'classique',ARRAY['Combat']::text[],8.1,65,125,60,95,60,105),
(621,5,'classique',ARRAY['Dragon']::text[],7.8,77,120,90,60,90,48),
(622,5,'classique',ARRAY['Sol','Spectre']::text[],5.4,59,74,50,35,50,35),
(623,5,'classique',ARRAY['Sol','Spectre']::text[],7.8,89,124,80,55,80,55),
(624,5,'classique',ARRAY['Ténèbres','Acier']::text[],6,45,85,70,40,40,60),
(625,5,'classique',ARRAY['Ténèbres','Acier']::text[],7.8,65,125,100,60,70,70),
(626,5,'classique',ARRAY['Normal']::text[],7.8,95,110,95,40,95,55),
(627,5,'classique',ARRAY['Normal','Vol']::text[],6.1,70,83,50,37,50,60),
(628,5,'classique',ARRAY['Normal','Vol']::text[],8.1,100,123,75,57,75,80),
(629,5,'classique',ARRAY['Ténèbres','Vol']::text[],6.4,70,55,75,45,65,60),
(630,5,'classique',ARRAY['Ténèbres','Vol']::text[],8.1,110,65,105,55,95,80),
(631,5,'classique',ARRAY['Feu']::text[],7.8,85,97,66,105,66,65),
(632,5,'classique',ARRAY['Insecte','Acier']::text[],7.8,58,109,112,48,48,109),
(633,5,'classique',ARRAY['Ténèbres','Dragon']::text[],5.3,52,65,50,45,50,38),
(634,5,'classique',ARRAY['Ténèbres','Dragon']::text[],7,72,85,70,65,70,58),
(635,5,'pseudo-légendaire',ARRAY['Ténèbres','Dragon']::text[],8.9,92,105,90,125,90,98),
(636,5,'classique',ARRAY['Insecte','Feu']::text[],6.2,55,85,55,50,55,60),
(637,5,'classique',ARRAY['Insecte','Feu']::text[],8.5,85,60,65,135,105,100),
(638,5,'légendaire',ARRAY['Acier','Combat']::text[],8.8,91,90,129,90,72,108),
(639,5,'légendaire',ARRAY['Roche','Combat']::text[],8.8,91,129,90,72,90,108),
(640,5,'légendaire',ARRAY['Plante','Combat']::text[],8.8,91,90,72,90,129,108),
(641,5,'légendaire',ARRAY['Vol']::text[],8.8,79,115,70,125,80,111),
(642,5,'légendaire',ARRAY['Électrik','Vol']::text[],8.8,79,115,70,125,80,111),
(643,5,'légendaire',ARRAY['Dragon','Feu']::text[],9.7,100,120,100,150,120,90),
(644,5,'légendaire',ARRAY['Dragon','Électrik']::text[],9.7,100,150,120,120,100,90),
(645,5,'légendaire',ARRAY['Sol','Vol']::text[],8.9,89,125,90,115,80,101),
(646,5,'légendaire',ARRAY['Dragon','Glace']::text[],9.5,125,130,90,130,90,95),
(647,5,'fabuleux',ARRAY['Eau','Combat']::text[],8.8,91,72,90,129,90,108),
(648,5,'fabuleux',ARRAY['Normal','Psy']::text[],8.9,100,77,77,128,128,90),
(649,5,'fabuleux',ARRAY['Insecte','Acier']::text[],8.9,71,120,95,120,95,99),
(650,6,'starter',ARRAY['Plante']::text[],5.5,56,61,65,48,45,38),
(651,6,'starter',ARRAY['Plante']::text[],6.8,61,78,95,56,58,57),
(652,6,'starter',ARRAY['Plante','Combat']::text[],8.3,88,107,122,74,75,64),
(653,6,'starter',ARRAY['Feu']::text[],5.4,40,45,40,62,60,60),
(654,6,'starter',ARRAY['Feu']::text[],6.9,59,59,58,90,70,73),
(655,6,'starter',ARRAY['Feu','Psy']::text[],8.3,75,69,72,114,100,104),
(656,6,'starter',ARRAY['Eau']::text[],5.5,41,56,40,62,44,71),
(657,6,'starter',ARRAY['Eau']::text[],6.8,54,63,52,83,56,97),
(658,6,'starter',ARRAY['Eau','Ténèbres']::text[],8.3,72,95,67,103,71,122),
(659,6,'classique',ARRAY['Normal']::text[],4,38,36,38,32,36,57),
(660,6,'classique',ARRAY['Normal','Sol']::text[],7.1,85,56,77,50,77,78),
(661,6,'classique',ARRAY['Normal','Vol']::text[],4.9,45,50,43,40,38,62),
(662,6,'classique',ARRAY['Feu','Vol']::text[],6.5,62,73,55,56,52,84),
(663,6,'classique',ARRAY['Feu','Vol']::text[],7.9,78,81,71,74,69,126),
(664,6,'classique',ARRAY['Insecte']::text[],2.9,38,35,40,27,25,35),
(665,6,'classique',ARRAY['Insecte']::text[],3.4,45,22,60,27,30,29),
(666,6,'classique',ARRAY['Insecte','Vol']::text[],6.9,80,52,50,90,50,89),
(667,6,'classique',ARRAY['Feu','Normal']::text[],6.4,62,50,58,73,54,72),
(668,6,'classique',ARRAY['Feu','Normal']::text[],8,86,68,72,109,66,106),
(669,6,'classique',ARRAY['Fée']::text[],5.4,44,38,39,61,79,42),
(670,6,'classique',ARRAY['Fée']::text[],6.4,54,45,47,75,98,52),
(671,6,'classique',ARRAY['Fée']::text[],8.5,78,65,68,112,154,75),
(672,6,'classique',ARRAY['Plante']::text[],6.1,66,65,48,62,57,52),
(673,6,'classique',ARRAY['Plante']::text[],8.3,123,100,62,97,81,68),
(674,6,'classique',ARRAY['Combat']::text[],6.1,67,82,62,46,48,43),
(675,6,'classique',ARRAY['Combat','Ténèbres']::text[],7.9,95,124,78,69,71,58),
(676,6,'classique',ARRAY['Normal']::text[],7.6,75,80,60,65,90,102),
(677,6,'classique',ARRAY['Psy']::text[],6.2,62,48,54,63,60,68),
(678,6,'classique',ARRAY['Psy']::text[],7.6,74,48,76,83,81,104),
(679,6,'classique',ARRAY['Acier','Spectre']::text[],5.7,45,80,100,35,37,28),
(680,6,'classique',ARRAY['Acier','Spectre']::text[],7.4,59,110,150,45,49,35),
(681,6,'classique',ARRAY['Acier','Spectre']::text[],8,60,50,140,50,140,60),
(682,6,'classique',ARRAY['Fée']::text[],6,78,52,60,63,65,23),
(683,6,'classique',ARRAY['Fée']::text[],7.5,101,72,72,99,89,29),
(684,6,'classique',ARRAY['Fée']::text[],6,62,48,66,59,57,49),
(685,6,'classique',ARRAY['Fée']::text[],7.7,82,80,86,85,75,72),
(686,6,'classique',ARRAY['Ténèbres','Psy']::text[],5.1,53,54,53,37,46,45),
(687,6,'classique',ARRAY['Ténèbres','Psy']::text[],7.8,86,92,88,68,75,73),
(688,6,'classique',ARRAY['Roche','Eau']::text[],5.4,42,52,67,39,56,50),
(689,6,'classique',ARRAY['Roche','Eau']::text[],8,72,105,115,54,86,68),
(690,6,'classique',ARRAY['Poison','Eau']::text[],5.6,50,60,60,60,60,30),
(691,6,'classique',ARRAY['Poison','Dragon']::text[],7.9,65,75,90,97,123,44),
(692,6,'classique',ARRAY['Eau']::text[],5.8,50,53,62,58,63,44),
(693,6,'classique',ARRAY['Eau']::text[],8,71,73,88,120,89,59),
(694,6,'classique',ARRAY['Électrik','Normal']::text[],5.1,44,38,33,61,43,70),
(695,6,'classique',ARRAY['Électrik','Normal']::text[],7.7,62,55,52,109,94,109),
(696,6,'fossile',ARRAY['Roche','Dragon']::text[],6.3,58,89,77,45,45,48),
(697,6,'fossile',ARRAY['Roche','Dragon']::text[],8.2,82,121,119,69,59,71),
(698,6,'fossile',ARRAY['Roche','Glace']::text[],6.3,77,59,50,67,63,46),
(699,6,'fossile',ARRAY['Roche','Glace']::text[],8.2,123,77,72,99,92,58),
(700,6,'classique',ARRAY['Fée']::text[],8.2,95,65,65,110,130,60),
(701,6,'classique',ARRAY['Combat','Vol']::text[],8,78,92,75,74,63,118),
(702,6,'classique',ARRAY['Électrik','Fée']::text[],7.2,67,58,57,81,67,101),
(703,6,'classique',ARRAY['Roche','Fée']::text[],8,50,50,150,50,150,50),
(704,6,'classique',ARRAY['Dragon']::text[],5.3,45,50,35,55,75,40),
(705,6,'classique',ARRAY['Dragon']::text[],7.4,68,75,53,83,113,60),
(706,6,'pseudo-légendaire',ARRAY['Dragon']::text[],8.9,90,100,70,110,150,80),
(707,6,'classique',ARRAY['Acier','Fée']::text[],7.6,57,80,91,80,87,75),
(708,6,'classique',ARRAY['Spectre','Plante']::text[],5.5,43,70,48,50,60,38),
(709,6,'classique',ARRAY['Spectre','Plante']::text[],7.7,85,110,76,65,82,56),
(710,6,'classique',ARRAY['Spectre','Plante']::text[],5.9,49,66,70,44,55,51),
(711,6,'classique',ARRAY['Spectre','Plante']::text[],7.9,65,90,122,58,75,84),
(712,6,'classique',ARRAY['Glace']::text[],5.4,55,69,85,32,35,28),
(713,6,'classique',ARRAY['Glace']::text[],8.1,95,117,184,44,46,28),
(714,6,'classique',ARRAY['Vol','Dragon']::text[],4.2,40,30,35,45,40,55),
(715,6,'classique',ARRAY['Vol','Dragon']::text[],8.3,85,70,80,97,80,123),
(716,6,'légendaire',ARRAY['Fée']::text[],9.7,126,131,95,131,98,99),
(717,6,'légendaire',ARRAY['Ténèbres','Vol']::text[],9.7,126,131,95,131,98,99),
(718,6,'légendaire',ARRAY['Dragon','Sol']::text[],8.9,108,100,121,81,95,95),
(719,6,'fabuleux',ARRAY['Roche','Fée']::text[],8.9,50,100,150,100,150,50),
(720,6,'fabuleux',ARRAY['Psy','Spectre']::text[],8.9,80,110,60,150,130,70),
(721,6,'fabuleux',ARRAY['Feu','Eau']::text[],8.9,80,110,120,130,90,70),
(722,7,'starter',ARRAY['Plante','Vol']::text[],5.6,68,55,55,50,50,42),
(723,7,'starter',ARRAY['Plante','Vol']::text[],7,78,75,75,70,70,52),
(724,7,'starter',ARRAY['Plante','Spectre']::text[],8.3,78,107,75,100,100,70),
(725,7,'starter',ARRAY['Feu']::text[],5.6,45,65,40,60,40,70),
(726,7,'starter',ARRAY['Feu']::text[],7,65,85,50,80,50,90),
(727,7,'starter',ARRAY['Feu','Ténèbres']::text[],8.3,95,115,90,80,90,60),
(728,7,'starter',ARRAY['Eau']::text[],5.6,50,54,54,66,56,40),
(729,7,'starter',ARRAY['Eau']::text[],7,60,69,69,91,81,50),
(730,7,'starter',ARRAY['Eau','Fée']::text[],8.3,80,74,74,126,116,60),
(731,7,'classique',ARRAY['Normal','Vol']::text[],4.7,35,75,30,30,30,65),
(732,7,'classique',ARRAY['Normal','Vol']::text[],6.2,55,85,50,40,50,75),
(733,7,'classique',ARRAY['Normal','Vol']::text[],7.8,80,120,75,75,75,60),
(734,7,'classique',ARRAY['Normal']::text[],4.4,48,70,30,30,30,45),
(735,7,'classique',ARRAY['Normal']::text[],7,88,110,60,55,60,45),
(736,7,'classique',ARRAY['Insecte']::text[],5.3,47,62,45,55,45,46),
(737,7,'classique',ARRAY['Insecte','Électrik']::text[],6.8,57,82,95,55,75,36),
(738,7,'classique',ARRAY['Insecte','Électrik']::text[],8,77,70,90,145,75,43),
(739,7,'classique',ARRAY['Combat']::text[],5.9,47,82,57,42,47,63),
(740,7,'classique',ARRAY['Combat','Glace']::text[],7.7,97,132,77,62,67,43),
(741,7,'classique',ARRAY['Feu','Vol']::text[],7.7,75,70,70,98,70,93),
(742,7,'classique',ARRAY['Insecte','Fée']::text[],5.4,40,45,40,55,40,84),
(743,7,'classique',ARRAY['Insecte','Fée']::text[],7.6,60,55,60,95,70,124),
(744,7,'classique',ARRAY['Roche']::text[],5,45,65,40,30,40,60),
(745,7,'classique',ARRAY['Roche']::text[],7.8,75,115,65,55,65,112),
(746,7,'classique',ARRAY['Eau']::text[],1,45,20,20,25,25,40),
(747,7,'classique',ARRAY['Poison','Eau']::text[],5.4,50,53,62,43,52,45),
(748,7,'classique',ARRAY['Poison','Eau']::text[],7.9,50,63,152,53,142,35),
(749,7,'classique',ARRAY['Sol']::text[],6.6,70,100,70,45,55,45),
(750,7,'classique',ARRAY['Sol']::text[],8,100,125,100,55,85,35),
(751,7,'classique',ARRAY['Eau','Insecte']::text[],4.7,38,40,52,40,72,27),
(752,7,'classique',ARRAY['Eau','Insecte']::text[],7.4,68,70,92,50,132,42),
(753,7,'classique',ARRAY['Plante']::text[],4.3,40,55,35,50,35,35),
(754,7,'classique',ARRAY['Plante']::text[],7.7,70,105,90,80,90,45),
(755,7,'classique',ARRAY['Plante','Fée']::text[],5,40,35,55,65,75,15),
(756,7,'classique',ARRAY['Plante','Fée']::text[],6.8,60,45,80,90,100,30),
(757,7,'classique',ARRAY['Poison','Feu']::text[],5.6,48,44,40,71,40,77),
(758,7,'classique',ARRAY['Poison','Feu']::text[],7.7,68,64,60,111,60,117),
(759,7,'classique',ARRAY['Normal','Combat']::text[],6,70,75,50,45,50,50),
(760,7,'classique',ARRAY['Normal','Combat']::text[],8,120,125,80,55,60,60),
(761,7,'classique',ARRAY['Plante']::text[],3.3,42,30,38,30,38,32),
(762,7,'classique',ARRAY['Plante']::text[],5.1,52,40,48,40,48,62),
(763,7,'classique',ARRAY['Plante']::text[],8.1,72,120,98,50,98,72),
(764,7,'classique',ARRAY['Fée']::text[],7.8,51,52,90,82,110,100),
(765,7,'classique',ARRAY['Normal','Psy']::text[],7.8,90,60,80,90,110,60),
(766,7,'classique',ARRAY['Combat']::text[],7.8,100,120,90,40,60,80),
(767,7,'classique',ARRAY['Insecte','Eau']::text[],3.9,25,35,40,20,30,80),
(768,7,'classique',ARRAY['Insecte','Eau']::text[],8.3,75,125,140,60,90,40),
(769,7,'classique',ARRAY['Spectre','Sol']::text[],5.6,55,55,80,70,45,15),
(770,7,'classique',ARRAY['Spectre','Sol']::text[],7.7,85,75,110,100,75,35),
(771,7,'classique',ARRAY['Eau']::text[],6.9,55,60,130,30,130,5),
(772,7,'légendaire',ARRAY['Normal']::text[],8.3,95,95,95,95,95,59),
(773,7,'légendaire',ARRAY['Normal']::text[],8.7,95,95,95,95,95,95),
(774,7,'classique',ARRAY['Roche','Vol']::text[],7.3,60,60,100,60,100,60),
(775,7,'classique',ARRAY['Normal']::text[],7.7,65,115,65,75,95,65),
(776,7,'classique',ARRAY['Feu','Dragon']::text[],7.8,60,78,135,91,85,36),
(777,7,'classique',ARRAY['Électrik','Acier']::text[],7.2,65,98,63,40,73,96),
(778,7,'classique',ARRAY['Spectre','Fée']::text[],7.7,55,90,80,50,105,96),
(779,7,'classique',ARRAY['Eau','Psy']::text[],7.7,68,105,70,70,70,92),
(780,7,'classique',ARRAY['Normal','Dragon']::text[],7.8,78,60,85,135,91,36),
(781,7,'classique',ARRAY['Spectre','Plante']::text[],8.1,70,131,100,86,90,40),
(782,7,'classique',ARRAY['Dragon']::text[],5.3,45,55,65,45,45,45),
(783,7,'classique',ARRAY['Dragon','Combat']::text[],7,55,75,90,65,70,65),
(784,7,'pseudo-légendaire',ARRAY['Dragon','Combat']::text[],8.9,75,110,125,100,105,85),
(785,7,'légendaire',ARRAY['Électrik','Fée']::text[],8.7,70,115,85,95,75,130),
(786,7,'légendaire',ARRAY['Psy','Fée']::text[],8.7,70,85,75,130,115,95),
(787,7,'légendaire',ARRAY['Plante','Fée']::text[],8.7,70,130,115,85,95,75),
(788,7,'légendaire',ARRAY['Eau','Fée']::text[],8.7,70,75,115,95,130,85),
(789,7,'légendaire',ARRAY['Psy']::text[],2.9,43,29,31,29,31,37),
(790,7,'légendaire',ARRAY['Psy']::text[],6.8,43,29,131,29,131,37),
(791,7,'légendaire',ARRAY['Psy','Acier']::text[],9.7,137,137,107,113,89,97),
(792,7,'légendaire',ARRAY['Psy','Spectre']::text[],9.7,137,113,89,137,107,97),
(793,7,'ultra-chimère',ARRAY['Roche','Poison']::text[],8.7,109,53,47,127,131,103),
(794,7,'ultra-chimère',ARRAY['Insecte','Combat']::text[],8.7,107,139,139,53,53,79),
(795,7,'ultra-chimère',ARRAY['Insecte','Combat']::text[],8.7,71,137,37,137,37,151),
(796,7,'ultra-chimère',ARRAY['Électrik']::text[],8.7,83,89,71,173,71,83),
(797,7,'ultra-chimère',ARRAY['Acier','Vol']::text[],8.7,97,101,103,107,101,61),
(798,7,'ultra-chimère',ARRAY['Plante','Acier']::text[],8.7,59,181,131,59,31,109),
(799,7,'ultra-chimère',ARRAY['Ténèbres','Dragon']::text[],8.7,223,101,53,97,53,43),
(800,7,'légendaire',ARRAY['Psy']::text[],8.9,97,107,101,127,89,79),
(801,7,'fabuleux',ARRAY['Acier','Fée']::text[],8.9,80,95,115,130,115,65),
(802,7,'fabuleux',ARRAY['Combat','Spectre']::text[],8.9,90,125,80,90,90,125),
(803,7,'ultra-chimère',ARRAY['Poison']::text[],7,67,73,67,73,67,73),
(804,7,'ultra-chimère',ARRAY['Poison','Dragon']::text[],8.4,73,73,73,127,73,121),
(805,7,'ultra-chimère',ARRAY['Roche','Acier']::text[],8.7,61,131,211,53,101,13),
(806,7,'ultra-chimère',ARRAY['Feu','Spectre']::text[],8.7,53,127,53,151,79,107),
(807,7,'fabuleux',ARRAY['Électrik']::text[],8.9,88,112,75,102,80,143),
(808,7,'fabuleux',ARRAY['Acier']::text[],5.3,46,65,65,55,35,34),
(809,7,'fabuleux',ARRAY['Acier']::text[],8.9,135,143,143,80,65,34),
(810,8,'starter',ARRAY['Plante']::text[],5.5,50,65,50,40,40,65),
(811,8,'starter',ARRAY['Plante']::text[],7,70,85,70,55,60,80),
(812,8,'starter',ARRAY['Plante']::text[],8.3,100,125,90,60,70,85),
(813,8,'starter',ARRAY['Feu']::text[],5.5,50,71,40,40,40,69),
(814,8,'starter',ARRAY['Feu']::text[],7,65,86,60,55,60,94),
(815,8,'starter',ARRAY['Feu']::text[],8.3,80,116,75,65,75,119),
(816,8,'starter',ARRAY['Eau']::text[],5.5,50,40,40,70,40,70),
(817,8,'starter',ARRAY['Eau']::text[],7,65,60,55,95,55,90),
(818,8,'starter',ARRAY['Eau']::text[],8.3,70,85,65,125,65,120),
(819,8,'classique',ARRAY['Normal']::text[],4.9,70,55,55,35,35,25),
(820,8,'classique',ARRAY['Normal']::text[],7.5,120,95,95,55,75,20),
(821,8,'classique',ARRAY['Vol']::text[],4.2,38,47,35,33,35,57),
(822,8,'classique',ARRAY['Vol']::text[],6.3,68,67,55,43,55,77),
(823,8,'classique',ARRAY['Vol','Acier']::text[],7.9,98,87,105,53,85,67),
(824,8,'classique',ARRAY['Insecte']::text[],1.9,25,20,20,25,45,45),
(825,8,'classique',ARRAY['Insecte','Psy']::text[],5.9,50,35,80,50,90,30),
(826,8,'classique',ARRAY['Insecte','Psy']::text[],8,60,45,110,80,120,90),
(827,8,'classique',ARRAY['Ténèbres']::text[],4.2,40,28,28,47,52,50),
(828,8,'classique',ARRAY['Ténèbres']::text[],7.5,70,58,58,87,92,90),
(829,8,'classique',ARRAY['Plante']::text[],4.3,40,40,60,40,60,10),
(830,8,'classique',ARRAY['Plante']::text[],7.5,60,50,90,80,120,60),
(831,8,'classique',ARRAY['Normal']::text[],4.8,42,40,55,40,45,48),
(832,8,'classique',ARRAY['Normal']::text[],7.8,72,80,100,60,90,88),
(833,8,'classique',ARRAY['Eau']::text[],5,50,64,50,38,38,44),
(834,8,'classique',ARRAY['Eau','Roche']::text[],7.8,90,115,90,48,68,74),
(835,8,'classique',ARRAY['Électrik']::text[],4.8,59,45,50,40,50,26),
(836,8,'classique',ARRAY['Électrik']::text[],7.8,69,90,60,90,60,121),
(837,8,'classique',ARRAY['Roche']::text[],4.1,30,40,50,40,50,30),
(838,8,'classique',ARRAY['Roche','Feu']::text[],6.9,80,60,90,60,70,50),
(839,8,'classique',ARRAY['Roche','Feu']::text[],8.1,110,80,120,80,90,30),
(840,8,'classique',ARRAY['Plante','Dragon']::text[],4.6,40,40,80,40,40,20),
(841,8,'classique',ARRAY['Plante','Dragon']::text[],7.8,70,110,80,95,60,70),
(842,8,'classique',ARRAY['Plante','Dragon']::text[],7.8,110,85,80,100,80,30),
(843,8,'classique',ARRAY['Sol']::text[],5.6,52,57,75,35,50,46),
(844,8,'classique',ARRAY['Sol']::text[],8.1,72,107,125,65,70,71),
(845,8,'classique',ARRAY['Vol','Eau']::text[],7.7,70,85,55,85,95,85),
(846,8,'classique',ARRAY['Eau']::text[],5,41,63,40,40,30,66),
(847,8,'classique',ARRAY['Eau']::text[],7.8,61,123,60,60,50,136),
(848,8,'classique',ARRAY['Électrik','Poison']::text[],4.2,40,38,35,54,35,40),
(849,8,'classique',ARRAY['Électrik','Poison']::text[],8,75,98,70,114,70,75),
(850,8,'classique',ARRAY['Feu','Insecte']::text[],5.4,50,65,45,50,50,45),
(851,8,'classique',ARRAY['Feu','Insecte']::text[],8.2,100,115,65,90,90,65),
(852,8,'classique',ARRAY['Combat']::text[],5.5,50,68,60,50,50,32),
(853,8,'classique',ARRAY['Combat']::text[],7.7,80,118,90,70,80,42),
(854,8,'classique',ARRAY['Spectre']::text[],5.4,40,45,45,74,54,50),
(855,8,'classique',ARRAY['Spectre']::text[],8,60,65,65,134,114,70),
(856,8,'classique',ARRAY['Psy']::text[],4.7,42,30,45,56,53,39),
(857,8,'classique',ARRAY['Psy']::text[],6.4,57,40,65,86,73,49),
(858,8,'classique',ARRAY['Psy','Fée']::text[],8.1,57,90,95,136,103,29),
(859,8,'classique',ARRAY['Ténèbres','Fée']::text[],4.7,45,45,30,55,40,50),
(860,8,'classique',ARRAY['Ténèbres','Fée']::text[],6.4,65,60,45,75,55,70),
(861,8,'classique',ARRAY['Ténèbres','Fée']::text[],8.1,95,120,65,95,75,60),
(862,8,'classique',ARRAY['Ténèbres','Normal']::text[],8.2,93,90,101,60,81,95),
(863,8,'classique',ARRAY['Acier']::text[],7.3,70,110,100,50,60,50),
(864,8,'classique',ARRAY['Spectre']::text[],8.1,60,95,50,145,130,30),
(865,8,'classique',ARRAY['Combat']::text[],8,62,135,95,68,82,65),
(866,8,'classique',ARRAY['Glace','Psy']::text[],8.2,80,85,75,110,100,70),
(867,8,'classique',ARRAY['Sol','Spectre']::text[],7.8,58,95,145,50,105,30),
(868,8,'classique',ARRAY['Fée']::text[],4.8,45,40,40,50,61,34),
(869,8,'classique',ARRAY['Fée']::text[],7.9,65,60,75,110,121,64),
(870,8,'classique',ARRAY['Combat']::text[],7.6,65,100,100,70,60,75),
(871,8,'classique',ARRAY['Électrik']::text[],7.2,48,101,95,91,85,15),
(872,8,'classique',ARRAY['Glace','Insecte']::text[],2.2,30,25,35,45,30,20),
(873,8,'classique',ARRAY['Glace','Insecte']::text[],7.7,70,65,60,125,90,65),
(874,8,'classique',ARRAY['Roche']::text[],7.6,100,125,135,20,20,70),
(875,8,'classique',ARRAY['Glace']::text[],7.6,75,80,110,65,90,50),
(876,8,'classique',ARRAY['Psy','Normal']::text[],7.7,60,65,55,105,95,95),
(877,8,'classique',ARRAY['Électrik','Ténèbres']::text[],7.2,58,95,58,70,58,97),
(878,8,'classique',ARRAY['Acier']::text[],5.8,72,80,49,40,49,40),
(879,8,'classique',ARRAY['Acier']::text[],8,122,130,69,80,69,30),
(880,8,'fossile',ARRAY['Électrik','Dragon']::text[],8,90,100,90,80,70,75),
(881,8,'fossile',ARRAY['Électrik','Glace']::text[],8,90,100,90,90,80,55),
(882,8,'fossile',ARRAY['Eau','Dragon']::text[],8,90,90,100,70,80,75),
(883,8,'fossile',ARRAY['Eau','Glace']::text[],8,90,90,100,80,90,55),
(884,8,'classique',ARRAY['Acier','Dragon']::text[],8.3,70,95,115,120,50,85),
(885,8,'classique',ARRAY['Dragon','Spectre']::text[],4.8,28,60,30,40,30,82),
(886,8,'classique',ARRAY['Dragon','Spectre']::text[],6.9,68,80,50,60,50,102),
(887,8,'pseudo-légendaire',ARRAY['Dragon','Spectre']::text[],8.9,88,120,75,100,75,142),
(888,8,'légendaire',ARRAY['Fée']::text[],9.5,92,120,115,80,115,138),
(889,8,'légendaire',ARRAY['Combat']::text[],9.5,92,120,115,80,115,138),
(890,8,'légendaire',ARRAY['Poison','Dragon']::text[],9.7,140,85,95,145,95,130),
(891,8,'légendaire',ARRAY['Combat']::text[],6.6,60,90,60,53,50,72),
(892,8,'légendaire',ARRAY['Combat','Ténèbres']::text[],8.5,100,130,100,63,60,97),
(893,8,'fabuleux',ARRAY['Ténèbres','Plante']::text[],8.9,105,120,105,70,95,105),
(894,8,'légendaire',ARRAY['Électrik']::text[],8.8,80,100,50,100,50,200),
(895,8,'légendaire',ARRAY['Dragon']::text[],8.8,200,100,50,100,50,80),
(896,8,'légendaire',ARRAY['Glace']::text[],8.8,100,145,130,65,110,30),
(897,8,'légendaire',ARRAY['Spectre']::text[],8.8,100,65,60,145,80,130),
(898,8,'légendaire',ARRAY['Psy','Plante']::text[],8,100,80,80,80,80,80),
(899,8,'classique',ARRAY['Normal','Psy']::text[],8.2,103,105,72,105,75,65),
(900,8,'classique',ARRAY['Insecte','Roche']::text[],8,70,135,95,45,70,85),
(901,8,'classique',ARRAY['Sol','Normal']::text[],8.5,130,140,105,45,80,50),
(902,8,'classique',ARRAY['Eau','Spectre']::text[],8.3,120,112,65,80,75,78),
(903,8,'classique',ARRAY['Combat','Poison']::text[],8.1,80,130,60,40,80,120),
(904,8,'classique',ARRAY['Ténèbres','Poison']::text[],8.1,85,115,95,65,65,85),
(905,8,'légendaire',ARRAY['Fée','Vol']::text[],8.8,74,115,70,135,80,106),
(906,9,'starter',ARRAY['Plante']::text[],5.5,40,61,54,45,45,65),
(907,9,'starter',ARRAY['Plante']::text[],6.9,61,80,63,60,63,83),
(908,9,'starter',ARRAY['Plante','Ténèbres']::text[],8.3,76,110,70,81,70,123),
(909,9,'starter',ARRAY['Feu']::text[],5.5,67,45,59,63,40,36),
(910,9,'starter',ARRAY['Feu']::text[],6.9,81,55,78,90,58,49),
(911,9,'starter',ARRAY['Feu','Spectre']::text[],8.3,104,75,100,110,75,66),
(912,9,'starter',ARRAY['Eau']::text[],5.5,55,65,45,50,45,50),
(913,9,'starter',ARRAY['Eau']::text[],6.9,70,85,65,65,60,65),
(914,9,'starter',ARRAY['Eau','Combat']::text[],8.3,85,120,80,85,75,85),
(915,9,'classique',ARRAY['Normal']::text[],4.4,54,45,40,35,45,35),
(916,9,'classique',ARRAY['Normal']::text[],7.8,110,100,75,59,80,65),
(917,9,'classique',ARRAY['Insecte']::text[],3.3,35,41,45,29,40,20),
(918,9,'classique',ARRAY['Insecte']::text[],6.8,60,79,92,52,86,35),
(919,9,'classique',ARRAY['Insecte']::text[],3.3,33,46,40,21,25,45),
(920,9,'classique',ARRAY['Insecte','Ténèbres']::text[],7.4,71,102,78,52,55,92),
(921,9,'classique',ARRAY['Électrik']::text[],4.1,45,50,20,40,25,60),
(922,9,'classique',ARRAY['Électrik','Combat']::text[],6.1,60,75,40,50,40,85),
(923,9,'classique',ARRAY['Électrik','Combat']::text[],7.8,70,115,70,70,60,105),
(924,9,'classique',ARRAY['Normal']::text[],5.4,50,50,45,40,45,75),
(925,9,'classique',ARRAY['Normal']::text[],7.6,74,75,70,65,75,111),
(926,9,'classique',ARRAY['Fée']::text[],5.5,37,55,70,30,55,65),
(927,9,'classique',ARRAY['Fée']::text[],7.7,57,80,115,50,80,95),
(928,9,'classique',ARRAY['Plante','Normal']::text[],4.6,41,35,45,58,51,30),
(929,9,'classique',ARRAY['Plante','Normal']::text[],6.2,52,53,60,78,78,33),
(930,9,'classique',ARRAY['Plante','Normal']::text[],8.1,78,69,90,125,109,39),
(931,9,'classique',ARRAY['Normal','Vol']::text[],7,82,96,51,45,51,92),
(932,9,'classique',ARRAY['Roche']::text[],5,55,55,75,35,35,25),
(933,9,'classique',ARRAY['Roche']::text[],6.2,60,60,100,35,65,35),
(934,9,'classique',ARRAY['Roche']::text[],8,100,100,130,45,90,35),
(935,9,'classique',ARRAY['Feu']::text[],4.4,40,50,40,50,40,35),
(936,9,'classique',ARRAY['Feu','Psy']::text[],8.2,85,60,100,125,80,75),
(937,9,'classique',ARRAY['Feu','Spectre']::text[],8.2,75,125,80,60,100,85),
(938,9,'classique',ARRAY['Électrik']::text[],4.8,61,31,41,59,35,45),
(939,9,'classique',ARRAY['Électrik']::text[],7.9,109,64,91,103,83,45),
(940,9,'classique',ARRAY['Électrik','Vol']::text[],5,40,40,35,55,40,70),
(941,9,'classique',ARRAY['Électrik','Vol']::text[],7.8,70,70,60,105,60,125),
(942,9,'classique',ARRAY['Ténèbres']::text[],6,60,78,60,40,51,51),
(943,9,'classique',ARRAY['Ténèbres']::text[],8,80,120,90,60,70,85),
(944,9,'classique',ARRAY['Poison','Normal']::text[],5.1,40,65,35,40,35,75),
(945,9,'classique',ARRAY['Poison','Normal']::text[],7.8,63,95,65,80,72,110),
(946,9,'classique',ARRAY['Plante','Spectre']::text[],4.9,40,65,30,45,35,60),
(947,9,'classique',ARRAY['Plante','Spectre']::text[],7.7,55,115,70,80,70,90),
(948,9,'classique',ARRAY['Sol','Plante']::text[],5.9,40,40,35,50,100,70),
(949,9,'classique',ARRAY['Sol','Plante']::text[],8.1,80,70,65,80,120,100),
(950,9,'classique',ARRAY['Roche']::text[],7.4,70,100,115,35,55,75),
(951,9,'classique',ARRAY['Plante']::text[],5.4,50,62,40,62,40,50),
(952,9,'classique',ARRAY['Plante','Feu']::text[],7.8,65,108,65,108,65,75),
(953,9,'classique',ARRAY['Insecte']::text[],4.8,41,50,60,31,58,30),
(954,9,'classique',ARRAY['Insecte','Psy']::text[],7.6,75,50,85,115,100,45),
(955,9,'classique',ARRAY['Psy']::text[],4.4,30,35,30,55,30,75),
(956,9,'classique',ARRAY['Psy']::text[],7.7,95,60,60,101,60,105),
(957,9,'classique',ARRAY['Fée','Acier']::text[],5.3,50,45,45,35,64,58),
(958,9,'classique',ARRAY['Fée','Acier']::text[],6.5,65,55,55,45,82,78),
(959,9,'classique',ARRAY['Fée','Acier']::text[],8,85,75,77,70,105,94),
(960,9,'classique',ARRAY['Eau']::text[],4.2,10,55,25,35,25,95),
(961,9,'classique',ARRAY['Eau']::text[],7.1,35,100,50,50,70,120),
(962,9,'classique',ARRAY['Vol','Ténèbres']::text[],7.8,70,103,85,60,85,82),
(963,9,'classique',ARRAY['Eau']::text[],5.6,70,45,40,45,40,75),
(964,9,'classique',ARRAY['Eau']::text[],7.5,100,70,72,53,62,100),
(965,9,'classique',ARRAY['Acier','Poison']::text[],5.3,45,70,63,30,45,47),
(966,9,'classique',ARRAY['Acier','Poison']::text[],8,80,119,90,54,67,90),
(967,9,'classique',ARRAY['Dragon','Normal']::text[],8,70,95,65,85,65,121),
(968,9,'classique',ARRAY['Acier']::text[],7.7,70,85,145,60,55,65),
(969,9,'classique',ARRAY['Roche','Poison']::text[],6.1,48,35,42,105,60,60),
(970,9,'classique',ARRAY['Roche','Poison']::text[],8.2,83,55,90,130,81,86),
(971,9,'classique',ARRAY['Spectre']::text[],5.1,50,61,60,30,55,34),
(972,9,'classique',ARRAY['Spectre']::text[],7.8,72,101,100,50,97,68),
(973,9,'classique',ARRAY['Vol','Combat']::text[],8,82,115,74,75,64,90),
(974,9,'classique',ARRAY['Glace']::text[],5.9,108,68,45,30,40,43),
(975,9,'classique',ARRAY['Glace']::text[],8.2,170,113,65,45,55,73),
(976,9,'classique',ARRAY['Eau','Psy']::text[],7.7,90,102,73,78,65,70),
(977,9,'classique',ARRAY['Eau']::text[],8.3,150,100,115,65,65,35),
(978,9,'classique',ARRAY['Dragon','Eau']::text[],7.7,68,50,60,120,95,82),
(979,9,'classique',ARRAY['Combat','Spectre']::text[],8.3,110,115,80,50,90,90),
(980,9,'classique',ARRAY['Poison','Sol']::text[],7.2,130,75,60,45,100,20),
(981,9,'classique',ARRAY['Normal','Psy']::text[],8.2,120,90,70,110,70,60),
(982,9,'classique',ARRAY['Normal']::text[],8.2,125,100,80,85,75,55),
(983,9,'classique',ARRAY['Ténèbres','Acier']::text[],8.5,100,135,120,60,85,50),
(984,9,'paradoxe',ARRAY['Sol','Combat']::text[],8.7,115,131,131,53,53,87),
(985,9,'paradoxe',ARRAY['Fée','Psy']::text[],8.7,115,65,99,65,115,111),
(986,9,'paradoxe',ARRAY['Plante','Ténèbres']::text[],8.7,111,127,99,79,99,55),
(987,9,'paradoxe',ARRAY['Spectre','Fée']::text[],8.7,55,55,55,135,135,135),
(988,9,'paradoxe',ARRAY['Insecte','Combat']::text[],8.7,85,135,79,85,105,81),
(989,9,'paradoxe',ARRAY['Électrik','Sol']::text[],8.7,85,81,97,121,85,101),
(990,9,'paradoxe',ARRAY['Sol','Acier']::text[],8.7,90,112,120,72,70,106),
(991,9,'paradoxe',ARRAY['Glace','Eau']::text[],8.7,56,80,114,124,60,136),
(992,9,'paradoxe',ARRAY['Combat','Électrik']::text[],8.7,154,140,108,50,68,50),
(993,9,'paradoxe',ARRAY['Ténèbres','Vol']::text[],8.7,94,80,86,122,80,108),
(994,9,'paradoxe',ARRAY['Feu','Poison']::text[],8.7,80,70,60,140,110,110),
(995,9,'paradoxe',ARRAY['Roche','Électrik']::text[],8.7,100,134,110,70,84,72),
(996,9,'classique',ARRAY['Dragon','Glace']::text[],5.6,65,75,45,35,45,55),
(997,9,'classique',ARRAY['Dragon','Glace']::text[],7.1,90,95,66,45,65,62),
(998,9,'pseudo-légendaire',ARRAY['Dragon','Glace']::text[],8.9,115,145,92,75,86,87),
(999,9,'classique',ARRAY['Spectre']::text[],5.3,45,30,70,75,70,10),
(1000,9,'classique',ARRAY['Acier','Spectre']::text[],8.5,87,60,95,133,91,84),
(1001,9,'légendaire',ARRAY['Ténèbres','Plante']::text[],8.7,85,85,100,95,135,70),
(1002,9,'légendaire',ARRAY['Ténèbres','Glace']::text[],8.7,80,120,80,90,65,135),
(1003,9,'légendaire',ARRAY['Ténèbres','Sol']::text[],8.7,155,110,125,55,80,45),
(1004,9,'légendaire',ARRAY['Ténèbres','Feu']::text[],8.7,55,80,80,135,120,100),
(1005,9,'classique',ARRAY['Dragon','Ténèbres']::text[],8.9,105,139,71,55,101,119),
(1006,9,'paradoxe',ARRAY['Fée','Combat']::text[],8.9,74,130,90,120,60,116),
(1007,9,'légendaire',ARRAY['Combat','Dragon']::text[],9.6,100,135,115,85,100,135),
(1008,9,'légendaire',ARRAY['Électrik','Dragon']::text[],9.6,100,85,100,135,115,135),
(1009,9,'paradoxe',ARRAY['Eau','Dragon']::text[],8.9,99,83,91,125,83,109),
(1010,9,'paradoxe',ARRAY['Plante','Psy']::text[],8.9,90,130,88,70,108,104),
(1011,9,'classique',ARRAY['Plante','Dragon']::text[],7.8,80,80,110,95,80,40),
(1012,9,'classique',ARRAY['Plante','Spectre']::text[],5.4,40,45,45,74,54,50),
(1013,9,'classique',ARRAY['Plante','Spectre']::text[],8,71,60,106,121,80,70),
(1014,9,'légendaire',ARRAY['Poison','Combat']::text[],8.5,88,128,115,58,86,80),
(1015,9,'légendaire',ARRAY['Poison','Psy']::text[],8.5,88,75,66,130,90,106),
(1016,9,'légendaire',ARRAY['Poison','Fée']::text[],8.5,88,91,82,70,125,99),
(1017,9,'légendaire',ARRAY['Plante']::text[],8.5,80,120,84,60,96,110),
(1018,9,'classique',ARRAY['Acier','Dragon']::text[],8.9,90,105,130,125,65,85),
(1019,9,'classique',ARRAY['Plante','Dragon']::text[],8.4,106,80,110,120,80,44),
(1020,9,'paradoxe',ARRAY['Feu','Dragon']::text[],8.9,105,115,121,65,93,91),
(1021,9,'paradoxe',ARRAY['Électrik','Dragon']::text[],8.9,125,73,91,137,89,75),
(1022,9,'paradoxe',ARRAY['Roche','Psy']::text[],8.9,90,120,80,68,108,124),
(1023,9,'paradoxe',ARRAY['Acier','Psy']::text[],8.9,90,72,100,122,108,98),
(1024,9,'légendaire',ARRAY['Normal']::text[],7.4,90,65,85,65,85,60),
(1025,9,'fabuleux',ARRAY['Poison','Spectre']::text[],8.9,88,88,160,88,88,88)
ON CONFLICT (id) DO UPDATE SET
generation = EXCLUDED.generation, category = EXCLUDED.category, types = EXCLUDED.types, rating = EXCLUDED.rating, pv = EXCLUDED.pv,
attaque = EXCLUDED.attaque, defense = EXCLUDED.defense, atq_spe = EXCLUDED.atq_spe,
def_spe = EXCLUDED.def_spe, vitesse = EXCLUDED.vitesse;
-- POKEMON_CATALOG_DATA_END


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
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Le catalogue n'est accessible qu'aux fonctions SECURITY DEFINER.
ALTER TABLE public.pokemon_catalog ENABLE ROW LEVEL SECURITY;

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
-- GAME_RULE_HELPERS_START
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

-- GAME_RULE_HELPERS_END

-- Enchères Pokémon : tables, règles de jeu et permissions.
CREATE TABLE public.pokemon_auction_rooms (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  player1_id uuid NOT NULL REFERENCES auth.users(id), player2_id uuid REFERENCES auth.users(id),
  status text DEFAULT 'waiting' NOT NULL CHECK (status IN ('waiting','playing','finished')),
  settings jsonb, p1_team integer[] DEFAULT '{}' NOT NULL, p2_team integer[] DEFAULT '{}' NOT NULL,
  p1_balance integer DEFAULT 0 NOT NULL, p2_balance integer DEFAULT 0 NOT NULL,
  current_pokemon_id integer, used_pokemon_ids integer[] DEFAULT '{}' NOT NULL, requeue_pokemon_ids integer[] DEFAULT '{}' NOT NULL,
  round integer DEFAULT 0 NOT NULL, auction_start_at timestamptz, auction_end_at timestamptz,
  current_bid integer DEFAULT 0 NOT NULL, current_bidder text CHECK (current_bidder IN ('player1','player2')),
  current_turn text CHECK (current_turn IN ('player1','player2')),
  p1_passed boolean DEFAULT false NOT NULL, p2_passed boolean DEFAULT false NOT NULL,
  p1_bid_submitted boolean DEFAULT false NOT NULL, p2_bid_submitted boolean DEFAULT false NOT NULL,
  last_result jsonb,
  p1_stats_score numeric(3,1), p2_stats_score numeric(3,1), p1_coverage_score numeric(3,1), p2_coverage_score numeric(3,1),
  p1_final_score numeric(3,1), p2_final_score numeric(3,1), winner text CHECK (winner IN ('player1','player2','draw')),
  p1_ready boolean DEFAULT false NOT NULL, p2_ready boolean DEFAULT false NOT NULL,
  created_at timestamptz DEFAULT now() NOT NULL
);

CREATE TABLE public.pokemon_auction_bids (
  room_id uuid NOT NULL REFERENCES public.pokemon_auction_rooms(id) ON DELETE CASCADE,
  round integer NOT NULL, player_id uuid NOT NULL REFERENCES auth.users(id),
  amount integer NOT NULL CHECK (amount >= 0 AND amount % 10 = 0), created_at timestamptz DEFAULT now() NOT NULL,
  PRIMARY KEY (room_id, round, player_id)
);

-- Synchronisation des salons entre les deux joueurs via Supabase Realtime.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_publication WHERE pubname='supabase_realtime')
     AND NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_publication_tables
       WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='pokemon_auction_rooms'
     ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.pokemon_auction_rooms;
  END IF;
END $$;

ALTER TABLE public.pokemon_auction_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pokemon_auction_bids ENABLE ROW LEVEL SECURITY;
CREATE POLICY pokemon_auction_rooms_insert ON public.pokemon_auction_rooms FOR INSERT TO authenticated WITH CHECK (auth.uid() = player1_id);
CREATE POLICY pokemon_auction_rooms_select ON public.pokemon_auction_rooms FOR SELECT TO authenticated USING (
  auth.uid() = player1_id OR auth.uid() = player2_id OR EXISTS (
    SELECT 1 FROM public.game_invites invite
    WHERE invite.room_id = pokemon_auction_rooms.id
      AND invite.recipient_id = auth.uid()
      AND invite.game_mode = 'pokemon_auction'
      AND invite.status = 'pending'
  )
);
CREATE POLICY pokemon_auction_rooms_delete ON public.pokemon_auction_rooms FOR DELETE TO authenticated USING (auth.uid() = player1_id);
CREATE POLICY pokemon_auction_bids_select_own ON public.pokemon_auction_bids FOR SELECT TO authenticated USING (auth.uid() = player_id);
CREATE INDEX idx_pokemon_auction_rooms_players ON public.pokemon_auction_rooms(player1_id, player2_id);

CREATE OR REPLACE FUNCTION public.auction_begin_next(p_room_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE v_room public.pokemon_auction_rooms; v_next integer; v_queue integer[];
BEGIN
  SELECT * INTO v_room FROM public.pokemon_auction_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_room.status<>'playing' THEN RETURN; END IF;
  v_queue:=v_room.requeue_pokemon_ids;
  IF coalesce(cardinality(v_queue),0)>0 AND coalesce(v_room.last_result->>'outcome','')<>'tied' THEN
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
    auction_start_at=clock_timestamp()+interval '1 second', auction_end_at=clock_timestamp()+interval '31 seconds',
    current_bid=0,current_bidder=NULL,current_turn=CASE WHEN settings->>'auctionFormat'='turn_based' THEN CASE WHEN random()<.5 THEN 'player1' ELSE 'player2' END END,
    p1_passed=false,p2_passed=false,p1_bid_submitted=false,p2_bid_submitted=false WHERE id=p_room_id;
END; $$;

CREATE OR REPLACE FUNCTION public.join_pokemon_auction_room(p_room_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE v_room public.pokemon_auction_rooms; v_user uuid:=auth.uid();
BEGIN
  SELECT * INTO v_room FROM public.pokemon_auction_rooms WHERE id=p_room_id FOR UPDATE;
  IF v_user IS NULL OR NOT FOUND OR v_room.status<>'waiting' OR v_room.player2_id IS NOT NULL OR v_room.player1_id=v_user THEN RAISE EXCEPTION 'room_not_joinable'; END IF;
  UPDATE public.pokemon_auction_rooms SET player2_id=v_user WHERE id=p_room_id;
END; $$;

CREATE OR REPLACE FUNCTION public.set_pokemon_auction_settings(p_room_id uuid,p_settings jsonb) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE v_room public.pokemon_auction_rooms; v_budget integer;
BEGIN
  SELECT * INTO v_room FROM public.pokemon_auction_rooms WHERE id=p_room_id FOR UPDATE;
  v_budget:=(p_settings->>'startingBudget')::integer;
  IF auth.uid() IS DISTINCT FROM v_room.player1_id OR v_room.status<>'waiting' THEN RAISE EXCEPTION 'settings_locked'; END IF;
  IF p_settings->>'auctionFormat' IS NULL OR p_settings->>'auctionFormat' NOT IN ('live','sealed','turn_based') OR v_budget IS NULL OR v_budget<60 OR v_budget>100000 OR v_budget%10<>0 THEN RAISE EXCEPTION 'invalid_settings'; END IF;
  UPDATE public.pokemon_auction_rooms SET settings=p_settings WHERE id=p_room_id;
END; $$;

CREATE OR REPLACE FUNCTION public.launch_pokemon_auction_room(p_room_id uuid,p_settings jsonb) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
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

CREATE OR REPLACE FUNCTION public.auction_assert_bid_allowed(v_room public.pokemon_auction_rooms,v_role text,v_amount integer) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
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

CREATE OR REPLACE FUNCTION public.resolve_pokemon_auction(p_room_id uuid,p_force boolean DEFAULT false) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
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
    IF cardinality(v_room.p1_team)>=6 THEN v_winner:='player2'; ELSIF cardinality(v_room.p2_team)>=6 THEN v_winner:='player1'; ELSE v_winner:=CASE WHEN random()<.5 THEN 'player1' ELSE 'player2' END; END IF;
    v_outcome:='free';v_price:=0;
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

CREATE OR REPLACE FUNCTION public.place_pokemon_auction_bid(p_room_id uuid,p_amount integer) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
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
    auction_end_at=CASE WHEN settings->>'auctionFormat'='turn_based' THEN clock_timestamp()+interval '30 seconds' WHEN auction_end_at-clock_timestamp()<=interval '5 seconds' THEN clock_timestamp()+interval '5 seconds' ELSE auction_end_at END,
    current_turn=CASE WHEN settings->>'auctionFormat'='turn_based' THEN CASE WHEN v_role='player1' THEN 'player2' ELSE 'player1' END ELSE current_turn END WHERE id=p_room_id;
  IF v_other_passed THEN PERFORM public.resolve_pokemon_auction(p_room_id,true); END IF;
END; $$;

CREATE OR REPLACE FUNCTION public.pass_pokemon_auction_turn(p_room_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE v_room public.pokemon_auction_rooms; v_role text; v_other boolean;
BEGIN
  SELECT * INTO v_room FROM public.pokemon_auction_rooms WHERE id=p_room_id FOR UPDATE;
  v_role:=CASE WHEN auth.uid()=v_room.player1_id THEN 'player1' WHEN auth.uid()=v_room.player2_id THEN 'player2' END;
  IF v_role IS NULL OR v_room.status<>'playing' OR v_room.current_pokemon_id IS NULL OR v_room.settings->>'auctionFormat'<>'turn_based' OR v_room.current_turn<>v_role OR clock_timestamp() NOT BETWEEN v_room.auction_start_at AND v_room.auction_end_at THEN RAISE EXCEPTION 'pass_not_allowed'; END IF;
  v_other:=CASE WHEN v_role='player1' THEN v_room.p2_passed ELSE v_room.p1_passed END;
  UPDATE public.pokemon_auction_rooms SET p1_passed=CASE WHEN v_role='player1' THEN true ELSE p1_passed END,p2_passed=CASE WHEN v_role='player2' THEN true ELSE p2_passed END,current_turn=CASE WHEN v_role='player1' THEN 'player2' ELSE 'player1' END,auction_end_at=clock_timestamp()+interval '30 seconds' WHERE id=p_room_id;
  IF v_room.current_bid>0 OR v_other THEN PERFORM public.resolve_pokemon_auction(p_room_id,true); END IF;
END; $$;

CREATE OR REPLACE FUNCTION public.submit_pokemon_auction_sealed_bid(p_room_id uuid,p_amount integer) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
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

CREATE OR REPLACE FUNCTION public.finalize_pokemon_auction(p_room_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE v_room public.pokemon_auction_rooms; v_first_pass boolean;
BEGIN
  SELECT * INTO v_room FROM public.pokemon_auction_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND OR (auth.uid() IS DISTINCT FROM v_room.player1_id AND auth.uid() IS DISTINCT FROM v_room.player2_id) THEN RAISE EXCEPTION 'not_room_player'; END IF;
  IF v_room.status<>'playing' OR v_room.current_pokemon_id IS NULL OR clock_timestamp()<v_room.auction_end_at THEN RETURN; END IF;
  IF v_room.settings->>'auctionFormat'='turn_based' THEN
    v_first_pass:=v_room.p1_passed OR v_room.p2_passed;
    IF v_room.current_turn='player1' THEN UPDATE public.pokemon_auction_rooms SET p1_passed=true WHERE id=p_room_id; ELSE UPDATE public.pokemon_auction_rooms SET p2_passed=true WHERE id=p_room_id; END IF;
    IF v_room.current_bid=0 AND NOT v_first_pass THEN UPDATE public.pokemon_auction_rooms SET current_turn=CASE WHEN v_room.current_turn='player1' THEN 'player2' ELSE 'player1' END,auction_end_at=clock_timestamp()+interval '30 seconds' WHERE id=p_room_id; RETURN; END IF;
  END IF;
  PERFORM public.resolve_pokemon_auction(p_room_id,true);
END; $$;

CREATE OR REPLACE FUNCTION public.save_pokemon_auction_result(p_room_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
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

CREATE OR REPLACE FUNCTION public.request_pokemon_auction_replay(p_room_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
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

CREATE OR REPLACE FUNCTION public.cancel_pokemon_auction_room(p_room_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.pokemon_auction_rooms WHERE id=p_room_id AND (auth.uid()=player1_id OR auth.uid()=player2_id)) THEN RAISE EXCEPTION 'not_room_player'; END IF;
  UPDATE public.pokemon_auction_rooms SET status='finished',winner=NULL,p1_ready=false,p2_ready=false,current_pokemon_id=NULL WHERE id=p_room_id;
END $$;

REVOKE ALL ON FUNCTION public.auction_begin_next(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.auction_assert_bid_allowed(public.pokemon_auction_rooms,text,integer) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.resolve_pokemon_auction(uuid,boolean) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.auction_type_multiplier(text,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.auction_effective_multiplier(text[],text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.auction_coverage_score(integer[],integer[]) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.join_pokemon_auction_room(uuid),public.set_pokemon_auction_settings(uuid,jsonb),public.launch_pokemon_auction_room(uuid,jsonb),public.place_pokemon_auction_bid(uuid,integer),public.pass_pokemon_auction_turn(uuid),public.submit_pokemon_auction_sealed_bid(uuid,integer),public.finalize_pokemon_auction(uuid),public.save_pokemon_auction_result(uuid),public.request_pokemon_auction_replay(uuid),public.cancel_pokemon_auction_room(uuid) FROM PUBLIC,anon;
REVOKE ALL ON TABLE public.pokemon_auction_rooms,public.pokemon_auction_bids FROM PUBLIC,anon,authenticated;
GRANT SELECT ON TABLE public.pokemon_auction_rooms TO authenticated;
GRANT INSERT (player1_id) ON TABLE public.pokemon_auction_rooms TO authenticated;
GRANT SELECT ON TABLE public.pokemon_auction_bids TO authenticated;
GRANT EXECUTE ON FUNCTION public.join_pokemon_auction_room(uuid),public.set_pokemon_auction_settings(uuid,jsonb),public.launch_pokemon_auction_room(uuid,jsonb),public.place_pokemon_auction_bid(uuid,integer),public.pass_pokemon_auction_turn(uuid),public.submit_pokemon_auction_sealed_bid(uuid,integer),public.finalize_pokemon_auction(uuid),public.save_pokemon_auction_result(uuid),public.request_pokemon_auction_replay(uuid),public.cancel_pokemon_auction_room(uuid) TO authenticated;

-- Les fonctions SECURITY DEFINER historiques ne doivent jamais hériter du droit
-- d'exécution accordé à PUBLIC par défaut. Seuls les RPC utilisés par le client
-- sont exposés aux utilisateurs authentifiés.
REVOKE ALL ON FUNCTION
  public.append_stat_pick(uuid,text,jsonb),
  public.handle_new_user(),
  public.join_draft_duo_room(uuid),
  public.join_guess_pokemon_room(uuid),
  public.join_stat_duel_room(uuid),
  public.join_who_that_pokemon_room(uuid),
  public.rls_auto_enable(),
  public.set_defeated_trainer_username(),
  public.submit_guess_pokemon_guess(uuid,integer),
  public.submit_who_that_pokemon_guess(uuid,integer,integer),
  public.skip_who_that_pokemon_round(uuid,integer),
  public.update_draft_duo_room(uuid,jsonb),
  public.update_guess_pokemon_room(uuid,jsonb),
  public.update_stat_duel_room(uuid,jsonb),
  public.update_who_that_pokemon_room(uuid,jsonb)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
  public.append_stat_pick(uuid,text,jsonb),
  public.join_draft_duo_room(uuid),
  public.join_guess_pokemon_room(uuid),
  public.join_stat_duel_room(uuid),
  public.join_who_that_pokemon_room(uuid),
  public.submit_guess_pokemon_guess(uuid,integer),
  public.submit_who_that_pokemon_guess(uuid,integer,integer),
  public.skip_who_that_pokemon_round(uuid,integer),
  public.update_draft_duo_room(uuid,jsonb),
  public.update_guess_pokemon_room(uuid,jsonb),
  public.update_stat_duel_room(uuid,jsonb),
  public.update_who_that_pokemon_room(uuid,jsonb)
TO authenticated;


ALTER TABLE public.pokemon_catalog ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pokemon_catalog FROM anon, authenticated;

NOTIFY pgrst, 'reload schema';

-- Fin du schéma de référence.

--
