-- À exécuter une fois dans l'éditeur SQL Supabase pour rendre la progression
-- de chaque joueur indépendante dans Who's That Pokémon.

CREATE OR REPLACE FUNCTION public.submit_who_that_pokemon_guess(
  p_room_id uuid,
  p_round integer,
  p_pokemon_id integer
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
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
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO v_room
  FROM public.who_that_pokemon_rooms
  WHERE id = p_room_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'room_not_found'; END IF;
  IF v_room.status <> 'playing' THEN RAISE EXCEPTION 'room_not_playing'; END IF;
  IF p_round <> v_room.round THEN RAISE EXCEPTION 'stale_round'; END IF;

  IF v_user = v_room.player1_id THEN
    v_is_p1 := true;
  ELSIF v_user = v_room.player2_id THEN
    v_is_p1 := false;
  ELSE
    RAISE EXCEPTION 'not_room_player';
  END IF;

  v_p1_lives := v_room.p1_lives;
  v_p2_lives := v_room.p2_lives;
  v_p1_score := v_room.p1_score;
  v_p2_score := v_room.p2_score;
  v_p1_ready := v_room.p1_ready;
  v_p2_ready := v_room.p2_ready;
  v_round := v_room.round;
  v_target := v_room.target_pokemon_id;
  v_used := v_room.used_pokemon_ids;

  IF (v_is_p1 AND v_p1_ready) OR (NOT v_is_p1 AND v_p2_ready) THEN
    RAISE EXCEPTION 'round_already_completed';
  END IF;

  -- 0 = passer, NULL = révéler un indice, tout autre identifiant = proposition.
  IF p_pokemon_id = 0 THEN
    IF v_is_p1 THEN v_p1_ready := true;
    ELSE v_p2_ready := true;
    END IF;
  ELSIF p_pokemon_id IS NULL THEN
    IF (v_is_p1 AND v_p1_lives >= 3) OR (NOT v_is_p1 AND v_p2_lives >= 3) THEN
      RAISE EXCEPTION 'all_hints_revealed';
    END IF;
    IF v_is_p1 THEN v_p1_lives := least(3, v_p1_lives + 1);
    ELSE v_p2_lives := least(3, v_p2_lives + 1);
    END IF;
  ELSIF p_pokemon_id = v_target THEN
    IF v_is_p1 THEN
      v_p1_score := v_p1_score + greatest(0, 5 - v_p1_lives);
      v_p1_ready := true;
    ELSE
      v_p2_score := v_p2_score + greatest(0, 5 - v_p2_lives);
      v_p2_ready := true;
    END IF;
  ELSE
    IF v_is_p1 THEN v_p1_lives := least(3, v_p1_lives + 1);
    ELSE v_p2_lives := least(3, v_p2_lives + 1);
    END IF;
  END IF;

  IF v_p1_ready AND v_p2_ready THEN
    v_round := v_round + 1;
  END IF;

  IF v_round > 10 THEN
    v_status := 'finished';
    v_target := null;
    v_p1_ready := false;
    v_p2_ready := false;
    IF v_p1_score > v_p2_score THEN v_winner := 'player1';
    ELSIF v_p2_score > v_p1_score THEN v_winner := 'player2';
    ELSE v_winner := 'draw';
    END IF;
  ELSIF v_round <> v_room.round THEN
    SELECT p.id INTO v_target
    FROM public.pokemon_catalog p
    WHERE (coalesce(jsonb_array_length(v_room.settings->'generations'), 0) = 0
           OR p.generation IN (SELECT value::integer FROM jsonb_array_elements_text(v_room.settings->'generations')))
      AND (coalesce(jsonb_array_length(v_room.settings->'categories'), 0) = 0
           OR p.category IN (SELECT value FROM jsonb_array_elements_text(v_room.settings->'categories')))
      AND NOT (p.id = ANY(v_used))
    ORDER BY random()
    LIMIT 1;

    IF v_target IS NULL THEN
      SELECT p.id INTO v_target
      FROM public.pokemon_catalog p
      WHERE (coalesce(jsonb_array_length(v_room.settings->'generations'), 0) = 0
             OR p.generation IN (SELECT value::integer FROM jsonb_array_elements_text(v_room.settings->'generations')))
        AND (coalesce(jsonb_array_length(v_room.settings->'categories'), 0) = 0
             OR p.category IN (SELECT value FROM jsonb_array_elements_text(v_room.settings->'categories')))
      ORDER BY random()
      LIMIT 1;
    END IF;

    IF v_target IS NULL THEN RAISE EXCEPTION 'empty_pokemon_pool'; END IF;
    v_used := array_append(v_used, v_target);
    v_p1_lives := 0;
    v_p2_lives := 0;
    v_p1_ready := false;
    v_p2_ready := false;
  END IF;

  UPDATE public.who_that_pokemon_rooms
  SET round = v_round,
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
  WHERE id = p_room_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.skip_who_that_pokemon_round(
  p_room_id uuid,
  p_round integer
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  PERFORM public.submit_who_that_pokemon_guess(p_room_id, p_round, 0);
END;
$$;
