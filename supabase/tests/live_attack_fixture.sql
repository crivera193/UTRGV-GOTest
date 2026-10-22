-- Isolated live-server fixtures. No real point or account membership changes.
begin;
update auth.users set raw_app_meta_data=coalesce(raw_app_meta_data,'{}'::jsonb)||'{"live_game_test":true}'::jsonb
where (id='f0d7d8b1-8e6b-49f3-b2c9-0031621c79cb' and email='team-e2e-a-r1792678030@example.edu')
or (id='a59df708-2fdf-4a27-9602-0664bd619ccd' and email='team-e2e-b-r1792678030@example.edu');
insert into public.game_spots(id,name,latitude,longitude,is_test) values('qa-live-attacks-20261022','QA live combat',0,0,true);
insert into app_private.question_bank(id,prompt,choices,correct_index,is_test) values
 ('qa-live-add','Test question: 2 + 2?',array['4','3','5','6'],0,true),
 ('qa-live-shape','Test question: triangle sides?',array['2','3','4','5'],1,true),
 ('qa-live-light','Test question: primary color of light?',array['Brown','Black','Red','Gray'],2,true),
 ('qa-live-safe','Test question: safe place to stop?',array['Road','Stairs','Traffic','Safe outdoor path'],3,true);
commit;
select id,hp,owner_team_id,is_test from public.game_spots;
