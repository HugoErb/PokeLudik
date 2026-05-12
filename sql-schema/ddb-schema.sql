--
-- PostgreSQL database dump
--

\restrict 9R0xZdA5nJ47f86ejs3dmkkf0AEmd3XKmjkgN288Ote1ZatYk92OXrGsqfRadtL

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
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_room FROM public.draft_duo_rooms WHERE id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_user IS DISTINCT FROM v_room.player1_id AND v_user IS DISTINCT FROM v_room.player2_id THEN RAISE EXCEPTION 'not_room_player'; END IF;

  SELECT array_agg(key) INTO v_bad_keys
  FROM jsonb_object_keys(p_patch) AS key
  WHERE key <> ALL (ARRAY['status','p1_team','p2_team','winner','p1_ready','p2_ready','player2_id']);
  IF v_bad_keys IS NOT NULL THEN RAISE EXCEPTION 'forbidden_fields: %', v_bad_keys; END IF;

  -- Équipes : propriétaires respectifs + limite de 6 Pokémon
  IF p_patch ? 'p1_team' AND v_user <> v_room.player1_id THEN RAISE EXCEPTION 'forbidden_p1_team'; END IF;
  IF p_patch ? 'p1_team' AND jsonb_array_length(p_patch->'p1_team') > 6 THEN RAISE EXCEPTION 'p1_team_too_large'; END IF;
  IF p_patch ? 'p2_team' AND v_user IS DISTINCT FROM v_room.player2_id AND NOT (v_user = v_room.player1_id AND p_patch->'p2_team' = '[]'::jsonb) THEN RAISE EXCEPTION 'forbidden_p2_team'; END IF;
  IF p_patch ? 'p2_team' AND jsonb_array_length(p_patch->'p2_team') > 6 THEN RAISE EXCEPTION 'p2_team_too_large'; END IF;

  -- winner : les deux joueurs peuvent le définir, mais seulement quand les deux équipes ont 6 Pokémon
  IF p_patch ? 'winner' THEN
    IF NULLIF(p_patch->>'winner', '') IS NOT NULL THEN
      IF v_room.status <> 'playing' THEN RAISE EXCEPTION 'room_not_playing_for_winner'; END IF;
      IF COALESCE(array_length(v_room.p1_team, 1), 0) < 6 OR COALESCE(array_length(v_room.p2_team, 1), 0) < 6 THEN RAISE EXCEPTION 'teams_incomplete'; END IF;
      IF p_patch->>'winner' NOT IN ('player1','player2','draw') THEN RAISE EXCEPTION 'invalid_winner_value'; END IF;
    ELSE
      -- Effacement (revanche) : seul player1
      IF v_user <> v_room.player1_id THEN RAISE EXCEPTION 'only_player1_can_clear_winner'; END IF;
    END IF;
  END IF;

  -- status = 'finished' exige winner dans le même appel
  IF p_patch ? 'status' AND p_patch->>'status' = 'finished' THEN
    IF NOT (p_patch ? 'winner') OR NULLIF(p_patch->>'winner', '') IS NULL THEN RAISE EXCEPTION 'finished_requires_winner'; END IF;
  END IF;

  IF p_patch ? 'p1_ready' AND v_user <> v_room.player1_id THEN RAISE EXCEPTION 'forbidden_p1_ready'; END IF;
  IF p_patch ? 'p2_ready' AND v_user IS DISTINCT FROM v_room.player2_id AND NOT (v_user = v_room.player1_id AND ((p_patch->>'p2_ready')::boolean = false OR v_room.player2_id IS NULL)) THEN RAISE EXCEPTION 'forbidden_p2_ready'; END IF;
  IF p_patch ? 'player2_id' AND NOT (v_user = v_room.player1_id AND p_patch->>'player2_id' IS NULL AND v_room.status = 'waiting') THEN RAISE EXCEPTION 'forbidden_player2_update'; END IF;

  UPDATE public.draft_duo_rooms
  SET
    status = CASE WHEN p_patch ? 'status' THEN p_patch->>'status' ELSE status END,
    p1_team = CASE WHEN p_patch ? 'p1_team' THEN ARRAY(SELECT jsonb_array_elements_text(p_patch->'p1_team')::integer) ELSE p1_team END,
    p2_team = CASE WHEN p_patch ? 'p2_team' THEN ARRAY(SELECT jsonb_array_elements_text(p_patch->'p2_team')::integer) ELSE p2_team END,
    winner = CASE WHEN p_patch ? 'winner' THEN p_patch->>'winner' ELSE winner END,
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
  WHERE key <> ALL (ARRAY['status','pokemon_ids','p1_picks','p2_picks','round_start_at','winner','p1_ready','p2_ready','player2_id']);
  IF v_bad_keys IS NOT NULL THEN RAISE EXCEPTION 'forbidden_fields: %', v_bad_keys; END IF;

  IF (p_patch ? 'pokemon_ids' OR p_patch ? 'round_start_at') AND v_user <> v_room.player1_id THEN RAISE EXCEPTION 'only_player1_can_launch'; END IF;

  -- p1_picks / p2_picks : uniquement reset à [] par player1 (lancement / revanche)
  IF p_patch ? 'p1_picks' THEN
    IF v_user <> v_room.player1_id THEN RAISE EXCEPTION 'forbidden_p1_picks'; END IF;
    IF p_patch->'p1_picks' <> '[]'::jsonb THEN RAISE EXCEPTION 'p1_picks_must_be_empty_array'; END IF;
  END IF;
  IF p_patch ? 'p2_picks' THEN
    IF v_user <> v_room.player1_id THEN RAISE EXCEPTION 'forbidden_p2_picks_reset'; END IF;
    IF p_patch->'p2_picks' <> '[]'::jsonb THEN RAISE EXCEPTION 'p2_picks_must_be_empty_array'; END IF;
  END IF;

  -- winner : seul player1, uniquement quand les 6 manches sont terminées
  IF p_patch ? 'winner' THEN
    IF v_user <> v_room.player1_id THEN RAISE EXCEPTION 'only_player1_can_set_winner'; END IF;
    IF NULLIF(p_patch->>'winner', '') IS NOT NULL THEN
      IF v_room.status <> 'playing' THEN RAISE EXCEPTION 'room_not_playing_for_winner'; END IF;
      IF jsonb_array_length(v_room.p1_picks) < 6 OR jsonb_array_length(v_room.p2_picks) < 6 THEN RAISE EXCEPTION 'picks_incomplete'; END IF;
      IF p_patch->>'winner' NOT IN ('player1','player2','draw') THEN RAISE EXCEPTION 'invalid_winner_value'; END IF;
    END IF;
  END IF;

  -- status = 'finished' exige winner dans le même appel
  IF p_patch ? 'status' AND p_patch->>'status' = 'finished' THEN
    IF NOT (p_patch ? 'winner') OR NULLIF(p_patch->>'winner', '') IS NULL THEN RAISE EXCEPTION 'finished_requires_winner'; END IF;
  END IF;

  IF p_patch ? 'p1_ready' AND v_user <> v_room.player1_id THEN RAISE EXCEPTION 'forbidden_p1_ready'; END IF;
  IF p_patch ? 'p2_ready' AND v_user IS DISTINCT FROM v_room.player2_id AND NOT (v_user = v_room.player1_id AND ((p_patch->>'p2_ready')::boolean = false OR v_room.player2_id IS NULL)) THEN RAISE EXCEPTION 'forbidden_p2_ready'; END IF;
  IF p_patch ? 'player2_id' AND NOT (v_user = v_room.player1_id AND p_patch->>'player2_id' IS NULL AND v_room.status = 'waiting') THEN RAISE EXCEPTION 'forbidden_player2_update'; END IF;

  UPDATE public.stat_duel_rooms
  SET
    status = CASE WHEN p_patch ? 'status' THEN p_patch->>'status' ELSE status END,
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
  IF p_patch ? 'player2_id' AND NOT (v_user = v_room.player1_id AND p_patch->>'player2_id' IS NULL AND v_room.status = 'waiting') THEN RAISE EXCEPTION 'forbidden_player2_update'; END IF;
  IF (p_patch ? 'round' OR p_patch ? 'target_pokemon_id' OR p_patch ? 'used_pokemon_ids' OR p_patch ? 'p1_score' OR p_patch ? 'p2_score' OR p_patch ? 'p1_lives' OR p_patch ? 'p2_lives') AND v_user <> v_room.player1_id THEN RAISE EXCEPTION 'only_player1_can_control_game'; END IF;
  IF p_patch ? 'p1_ready' AND v_user <> v_room.player1_id THEN RAISE EXCEPTION 'forbidden_p1_ready'; END IF;
  IF p_patch ? 'p2_ready' AND v_user IS DISTINCT FROM v_room.player2_id THEN RAISE EXCEPTION 'forbidden_p2_ready'; END IF;

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

CREATE POLICY game_invites_insert ON public.game_invites FOR INSERT TO authenticated WITH CHECK (((auth.uid() = sender_id) AND (status = 'pending'::text) AND (sender_id <> recipient_id) AND (game_mode = ANY (ARRAY['guess_my_pokemon'::text, 'stat_duel'::text, 'draft_duo'::text, 'who_that_pokemon'::text]))));


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

\unrestrict 9R0xZdA5nJ47f86ejs3dmkkf0AEmd3XKmjkgN288Ote1ZatYk92OXrGsqfRadtL

