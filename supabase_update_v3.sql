-- ============================================================
-- 8.26 黑金之夜 · 数据库更新脚本 v3（最终版，已经建过库的跑这个）
-- 作用：黑金销量拆成 4 个 SKU（1L罐/500瓶/330罐/250瓶），
--       黑金合计在数据库里自动计算
-- 使用方法：登录 Supabase → SQL Editor → 粘贴运行一次即可
-- 注意：本脚本包含之前所有更新（M3、销量拆分），
--       无论之前跑过哪个版本，直接跑这个就对了，一次到位
-- ============================================================

-- 1) 补齐所有可能缺少的字段（已存在则跳过，不会报错）
alter table public.spr_records add column if not exists m3                text    not null default '';
alter table public.spr_records add column if not exists bud_classic_gold  integer not null default 0;
alter table public.spr_records add column if not exists other_abi         integer not null default 0;
alter table public.spr_records add column if not exists other_competitor  integer not null default 0;
alter table public.spr_records add column if not exists blackgold_1l      integer not null default 0;
alter table public.spr_records add column if not exists blackgold_500     integer not null default 0;
alter table public.spr_records add column if not exists blackgold_330     integer not null default 0;
alter table public.spr_records add column if not exists blackgold_250     integer not null default 0;

-- 2) 升级累加函数（黑金4个SKU自动合计版）
create or replace function public.submit_spr_record(
  p_store_name        text,
  p_m3                text,
  p_activity_date     date,
  p_spr_name          text,
  p_mechanism1        integer,
  p_mechanism2        integer,
  p_mechanism3        integer,
  p_mechanism4        integer,
  p_bud_classic_gold  integer,
  p_blackgold_1l      integer,
  p_blackgold_500     integer,
  p_blackgold_330     integer,
  p_blackgold_250     integer,
  p_other_abi         integer,
  p_key_competitor    integer,
  p_other_competitor  integer
) returns public.spr_records
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.spr_records;
  v_gift integer;
  v_bg   integer;
  v_abi  integer;
  v_comp integer;
begin
  v_gift := coalesce(p_mechanism1,0) + coalesce(p_mechanism2,0) + coalesce(p_mechanism3,0) + coalesce(p_mechanism4,0);
  v_bg   := coalesce(p_blackgold_1l,0) + coalesce(p_blackgold_500,0) + coalesce(p_blackgold_330,0) + coalesce(p_blackgold_250,0);
  v_abi  := coalesce(p_bud_classic_gold,0) + v_bg + coalesce(p_other_abi,0);
  v_comp := coalesce(p_key_competitor,0) + coalesce(p_other_competitor,0);

  insert into public.spr_records as t (
    store_name, m3, activity_date, spr_name,
    mechanism1, mechanism2, mechanism3, mechanism4, gift_255_cans,
    bud_classic_gold, blackgold_1l, blackgold_500, blackgold_330, blackgold_250, blackgold_total,
    other_abi, abi_total,
    key_competitor, other_competitor, competitor_total, beer_total
  ) values (
    p_store_name, p_m3, p_activity_date, p_spr_name,
    p_mechanism1, p_mechanism2, p_mechanism3, p_mechanism4, v_gift,
    p_bud_classic_gold, p_blackgold_1l, p_blackgold_500, p_blackgold_330, p_blackgold_250, v_bg,
    p_other_abi, v_abi,
    p_key_competitor, p_other_competitor, v_comp, v_abi + v_comp
  )
  on conflict (store_name, activity_date) do update
    set spr_name          = excluded.spr_name,
        m3                = excluded.m3,
        mechanism1        = t.mechanism1        + excluded.mechanism1,
        mechanism2        = t.mechanism2        + excluded.mechanism2,
        mechanism3        = t.mechanism3        + excluded.mechanism3,
        mechanism4        = t.mechanism4        + excluded.mechanism4,
        gift_255_cans     = t.gift_255_cans     + excluded.gift_255_cans,
        bud_classic_gold  = t.bud_classic_gold  + excluded.bud_classic_gold,
        blackgold_1l      = t.blackgold_1l      + excluded.blackgold_1l,
        blackgold_500     = t.blackgold_500     + excluded.blackgold_500,
        blackgold_330     = t.blackgold_330     + excluded.blackgold_330,
        blackgold_250     = t.blackgold_250     + excluded.blackgold_250,
        blackgold_total   = t.blackgold_total   + excluded.blackgold_total,
        other_abi         = t.other_abi         + excluded.other_abi,
        abi_total         = t.abi_total         + excluded.abi_total,
        key_competitor    = t.key_competitor    + excluded.key_competitor,
        other_competitor  = t.other_competitor  + excluded.other_competitor,
        competitor_total  = t.competitor_total  + excluded.competitor_total,
        beer_total        = t.beer_total        + excluded.beer_total,
        updated_at        = now()
  returning * into r;
  return r;
end;
$$;

-- 3) 允许网页（anon 密钥）调用这个函数
grant execute on function public.submit_spr_record(
  text, text, date, text,
  integer, integer, integer, integer,
  integer, integer, integer, integer,
  integer, integer, integer, integer
) to anon;

-- 4) 完成提示
select '数据库更新成功！可以关闭本页面了。' as 提示;
