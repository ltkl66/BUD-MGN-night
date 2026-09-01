-- ============================================================
-- 8.26 黑金之夜 · SPR 数据收集（v3：黑金拆4个SKU版）
-- 使用方法：登录 Supabase → 左侧 SQL Editor → 全部复制粘贴 → 点 Run
-- 运行一次即可，之后不需要再运行
-- ============================================================

-- 1) 建表：每个「门店 + 活动日期」一条记录
--    说明：gift_255_cans / blackgold_total / abi_total /
--          competitor_total / beer_total 由提交函数自动计算
create table if not exists public.spr_records (
  store_name        text      not null,              -- 门店名称
  m3                text      not null default '',   -- M3（区域负责人）
  activity_date     date      not null,              -- 活动日期
  spr_name          text      not null,              -- SPR姓名（记录当天填写人，重复提交时取最新）
  mechanism1        integer   not null default 0,    -- 机制1：到店即赠（听）
  mechanism2        integer   not null default 0,    -- 机制2：1-6瓶点购即赠（听）
  mechanism3        integer   not null default 0,    -- 机制3：12瓶赠整箱（听）
  mechanism4        integer   not null default 0,    -- 机制4：大桌锁定（店内收银条核销）（听）
  gift_255_cans     integer   not null default 0,    -- 赠品黑金255罐数量（自动=机制1+2+3+4）
  bud_classic_gold  integer   not null default 0,    -- 当晚百威家族（不含黑金：经典/金尊/纯生）销量（瓶）
  blackgold_1l      integer   not null default 0,    -- 当晚黑金1L罐（瓶）
  blackgold_500     integer   not null default 0,    -- 当晚黑金500瓶（瓶）
  blackgold_330     integer   not null default 0,    -- 当晚黑金330罐（瓶）
  blackgold_250     integer   not null default 0,    -- 当晚黑金250瓶（瓶）
  blackgold_total   integer   not null default 0,    -- 当晚黑金销量合计（自动=4个SKU之和）
  other_abi         integer   not null default 0,    -- 当晚其他百威（科罗娜/哈啤等）销量（瓶）
  abi_total         integer   not null default 0,    -- 当晚ABI总销量（自动=百威家族+黑金+其他）
  key_competitor    integer   not null default 0,    -- 当晚重点竞品销量（喜力/乌苏/老雪）（瓶）
  other_competitor  integer   not null default 0,    -- 当晚其他竞品销量（瓶）
  competitor_total  integer   not null default 0,    -- 当晚竞品总销量（自动=重点+其他）
  beer_total        integer   not null default 0,    -- 当晚啤酒总销量（自动=ABI+竞品）
  updated_at        timestamptz not null default now(),
  primary key (store_name, activity_date)
);

-- 2) 开启行级安全（RLS），只允许读取，写入只能通过下面的函数
alter table public.spr_records enable row level security;

drop policy if exists "spr_records_select" on public.spr_records;
create policy "spr_records_select"
  on public.spr_records for select
  to anon
  using (true);

-- 3) 累加函数：同一门店+同一日期再次提交时，数字相加、姓名/M3 取最新
--    赠品、黑金、ABI、竞品、啤酒 合计在函数内自动计算
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

-- 4) 允许网页（anon 密钥）调用这个函数
grant execute on function public.submit_spr_record(
  text, text, date, text,
  integer, integer, integer, integer,
  integer, integer, integer, integer,
  integer, integer, integer, integer
) to anon;

-- 5) 完成提示
select '数据库创建成功！可以关闭本页面了。' as 提示;
