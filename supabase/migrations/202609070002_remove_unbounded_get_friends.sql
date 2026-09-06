-- Every current client reads its own list through get_friends_page().
-- Removing the former all-rows RPC prevents an old or modified client from
-- bypassing cursor pagination and requesting an arbitrarily large friend graph.

drop function if exists public.get_friends();
drop function if exists private.get_friends_impl();

notify pgrst, 'reload schema';
