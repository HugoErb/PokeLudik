-- Migration additive à appliquer après ddb-schema.sql.
-- Toute la progression d'une enchère est sérialisée par FOR UPDATE.

ALTER TABLE public.pokemon_catalog ADD COLUMN IF NOT EXISTS types text[] DEFAULT '{}'::text[] NOT NULL;
ALTER TABLE public.pokemon_catalog ADD COLUMN IF NOT EXISTS rating numeric(3,1) DEFAULT 0 NOT NULL;

CREATE TABLE IF NOT EXISTS public.pokemon_auction_rooms (
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

CREATE TABLE IF NOT EXISTS public.pokemon_auction_bids (
  room_id uuid NOT NULL REFERENCES public.pokemon_auction_rooms(id) ON DELETE CASCADE,
  round integer NOT NULL, player_id uuid NOT NULL REFERENCES auth.users(id),
  amount integer NOT NULL CHECK (amount >= 0 AND amount % 10 = 0), created_at timestamptz DEFAULT now() NOT NULL,
  PRIMARY KEY (room_id, round, player_id)
);

ALTER TABLE public.pokemon_auction_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pokemon_auction_bids ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pokemon_auction_rooms_insert ON public.pokemon_auction_rooms;
DROP POLICY IF EXISTS pokemon_auction_rooms_select ON public.pokemon_auction_rooms;
DROP POLICY IF EXISTS pokemon_auction_rooms_delete ON public.pokemon_auction_rooms;
DROP POLICY IF EXISTS pokemon_auction_bids_select_own ON public.pokemon_auction_bids;
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
CREATE INDEX IF NOT EXISTS idx_pokemon_auction_rooms_players ON public.pokemon_auction_rooms(player1_id, player2_id);

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
    auction_start_at=clock_timestamp()+interval '1 second', auction_end_at=clock_timestamp()+interval '16 seconds',
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
    auction_end_at=CASE WHEN settings->>'auctionFormat'='turn_based' THEN clock_timestamp()+interval '15 seconds' WHEN auction_end_at-clock_timestamp()<=interval '5 seconds' THEN clock_timestamp()+interval '5 seconds' ELSE auction_end_at END,
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
  UPDATE public.pokemon_auction_rooms SET p1_passed=CASE WHEN v_role='player1' THEN true ELSE p1_passed END,p2_passed=CASE WHEN v_role='player2' THEN true ELSE p2_passed END,current_turn=CASE WHEN v_role='player1' THEN 'player2' ELSE 'player1' END,auction_end_at=clock_timestamp()+interval '15 seconds' WHERE id=p_room_id;
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
    IF v_room.current_bid=0 AND NOT v_first_pass THEN UPDATE public.pokemon_auction_rooms SET current_turn=CASE WHEN v_room.current_turn='player1' THEN 'player2' ELSE 'player1' END,auction_end_at=clock_timestamp()+interval '15 seconds' WHERE id=p_room_id; RETURN; END IF;
  END IF;
  PERFORM public.resolve_pokemon_auction(p_room_id,true);
END; $$;

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
      FOREACH v_opponent_type IN ARRAY v_opponent_pokemon.types LOOP
        IF public.auction_type_multiplier(v_my_type,v_opponent_type)>1 THEN v_hit:=true; EXIT; END IF;
      END LOOP;
      IF v_hit THEN EXIT; END IF;
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

DROP FUNCTION IF EXISTS public.save_pokemon_auction_result(uuid,numeric,numeric,numeric,numeric);
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

DROP POLICY IF EXISTS game_invites_insert ON public.game_invites;
CREATE POLICY game_invites_insert ON public.game_invites FOR INSERT TO authenticated WITH CHECK (auth.uid()=sender_id AND status='pending' AND sender_id<>recipient_id AND game_mode IN ('guess_my_pokemon','stat_duel','draft_duo','who_that_pokemon','pokemon_auction'));
