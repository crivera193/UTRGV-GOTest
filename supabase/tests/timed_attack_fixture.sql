-- Isolated timed-combat fixtures; no real spot, profile or permanent team reset.
begin;
update auth.users set raw_app_meta_data=coalesce(raw_app_meta_data,'{}'::jsonb)||'{"live_game_test":true}'::jsonb where email in ('team-e2e-a-r1792678030@example.edu','team-e2e-b-r1792678030@example.edu','team-e2e-c-r1792678030@example.edu','team-e2e-d-r1792678030@example.edu');
insert into public.game_spots(id,name,latitude,longitude,is_test) values
('qa-timed-capture-v2-20261022','QA timed capture',0,0,true),
('qa-timed-partial-20261022','QA timed partial',0,0,true),
('qa-timed-race-20261022','QA timed race',0,0,true),
('qa-timed-native-v2-20261022','QA timed native',0,0,true),
('qa-timed-boundary-20261022','QA timed boundary',0,0,true);
commit;
select id,hp,owner_team_id from public.game_spots where id like 'qa-timed-%';
