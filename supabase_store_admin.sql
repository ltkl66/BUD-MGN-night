-- ============================================================
-- 黑金之夜 · 门店清单 + 改门店名 升级脚本（v6）
-- 使用方法：登录 Supabase → 左侧 SQL Editor → 全部复制粘贴 → 点 Run
-- 运行一次即可，可重复运行（幂等）。
--
-- 本脚本做三件事：
--   1) 新建「门店清单」表 store_master —— 管理员在网页上维护，SPR 填报时只能从清单里选门店
--   2) 三个管理函数：新增/修改门店、删除门店、批量导入门店
--   3) update_spr_record2 —— 看板改数时「门店名」也能改（原 update_spr_record 保留，旧逻辑不受影响）
--
-- 门店清单为空时，填报页会自动退回原来的「历史门店联想」模式，不会把 SPR 卡住。
-- ============================================================

-- ============================================================
-- ★★★ 管理密码：写在下面 assert_admin_pin 函数里（只有这一处）★★★
-- ============================================================

-- ------------------------------------------------------------
-- 0) 统一的密码校验函数（所有管理操作都走它）
--    安全起见，收回 anon 的直接调用权限：网页只能通过下面各管理函数间接使用它。
-- ------------------------------------------------------------
create or replace function public.assert_admin_pin(p_pin text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pin_expected constant text := '9527';   -- ★ 改密码处（只此一处）
begin
  if p_pin is null or p_pin <> v_pin_expected then
    raise exception '管理密码错误，无法执行该操作';
  end if;
end;
$$;

revoke all on function public.assert_admin_pin(text) from public;
revoke all on function public.assert_admin_pin(text) from anon;

-- 登录校验用：密码对返回 true，不对直接报错（不动任何数据）
create or replace function public.admin_check_pin(p_pin text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_admin_pin(p_pin);
  return true;
end;
$$;

grant execute on function public.admin_check_pin(text) to anon;

-- ------------------------------------------------------------
-- 1) 门店清单表：一个门店可以挂在多个 M3 下（主键 = 门店 + M3）
-- ------------------------------------------------------------
create table if not exists public.store_master (
  store_name  text        not null,
  m3          text        not null,
  active      boolean     not null default true,   -- 停用后不在填报页出现，但历史数据仍可查
  note        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  primary key (store_name, m3)
);

comment on table public.store_master is 'SPR 填报可选的门店清单（按 M3 分区），由管理员维护';

-- 只开放读取，写入一律走下面的 security definer 函数
alter table public.store_master enable row level security;

drop policy if exists store_master_read on public.store_master;
create policy store_master_read on public.store_master for select using (true);

grant select on table public.store_master to anon;

-- ------------------------------------------------------------
-- 2) 新增 / 修改一个门店（同名同 M3 视为修改）
-- ------------------------------------------------------------
create or replace function public.admin_upsert_store(
  p_pin        text,
  p_store_name text,
  p_m3         text,
  p_active     boolean default true,
  p_note       text    default null
) returns public.store_master
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.store_master;
  v_name text := btrim(coalesce(p_store_name, ''));
  v_m3   text := btrim(coalesce(p_m3, ''));
begin
  perform public.assert_admin_pin(p_pin);

  if v_name = '' then
    raise exception '门店名不能为空';
  end if;
  if v_m3 = '' then
    raise exception 'M3 不能为空';
  end if;

  insert into public.store_master as t (store_name, m3, active, note)
  values (v_name, v_m3, coalesce(p_active, true), nullif(btrim(coalesce(p_note, '')), ''))
  on conflict (store_name, m3) do update
    set active     = excluded.active,
        note       = excluded.note,
        updated_at = now()
  returning * into r;

  return r;
end;
$$;

-- ------------------------------------------------------------
-- 3) 删除一个门店（只动清单，不动历史填报数据）
-- ------------------------------------------------------------
create or replace function public.admin_delete_store(
  p_pin        text,
  p_store_name text,
  p_m3         text
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  perform public.assert_admin_pin(p_pin);

  delete from public.store_master
   where store_name = btrim(coalesce(p_store_name, ''))
     and m3         = btrim(coalesce(p_m3, ''));
  get diagnostics n = row_count;
  return n;
end;
$$;

-- ------------------------------------------------------------
-- 4) 批量导入 / 更新门店
--    p_rows 形如：[{"store_name":"三两好友九堡店","m3":"肖志奇","active":true,"note":null}, ...]
-- ------------------------------------------------------------
create or replace function public.admin_bulk_upsert_stores(
  p_pin  text,
  p_rows jsonb
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  it     jsonb;
  n      integer := 0;
  v_name text;
  v_m3   text;
begin
  perform public.assert_admin_pin(p_pin);

  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'p_rows 必须是 JSON 数组';
  end if;

  for it in select * from jsonb_array_elements(p_rows) loop
    v_name := btrim(coalesce(it ->> 'store_name', ''));
    v_m3   := btrim(coalesce(it ->> 'm3', ''));
    if v_name = '' then
      continue;                       -- 跳过空行，方便直接粘贴文本
    end if;
    if v_m3 = '' then
      raise exception '门店「%」缺少 M3，请先选择 M3 再导入', v_name;
    end if;

    insert into public.store_master as t (store_name, m3, active, note)
    values (v_name, v_m3,
            -- 不用 jsonb 的 ? 运算符（会被某些驱动当成占位符）
            case when (it -> 'active') is null then true
                 else coalesce((it ->> 'active')::boolean, true) end,
            nullif(btrim(coalesce(it ->> 'note', '')), ''))
    on conflict (store_name, m3) do update
      set active     = excluded.active,
          note       = excluded.note,
          updated_at = now();

    n := n + 1;
  end loop;

  return n;
end;
$$;

-- ------------------------------------------------------------
-- 5) 看板改数 v2：门店名也能改
--    p_on_conflict = 'error'   目标门店当天已有记录 → 报错（前端会弹窗让管理员选覆盖）
--                  = 'replace' 目标门店当天已有记录 → 删掉那条，本条搬过去
--    门店名不变时行为与 update_spr_record 完全一致。
-- ------------------------------------------------------------
create or replace function public.update_spr_record2(
  p_pin               text,
  p_old_store_name    text,
  p_activity_date     date,
  p_new_store_name    text,
  p_on_conflict       text,
  p_m3                text,
  p_spr_name          text,
  p_mechanism1        integer,
  p_mechanism2        integer,
  p_mechanism3        integer,
  p_mechanism4        integer,
  p_bud_classic_gold  integer,
  p_blackgold_1l      integer,
  p_blackgold_500     integer,
  p_blackgold_600     integer,
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
  r        public.spr_records;
  v_old    text := btrim(coalesce(p_old_store_name, ''));
  v_new    text := btrim(coalesce(p_new_store_name, ''));
  v_mode   text := coalesce(nullif(btrim(coalesce(p_on_conflict, '')), ''), 'error');
  v_gift   integer;
  v_bg     integer;
  v_abi    integer;
  v_comp   integer;
begin
  perform public.assert_admin_pin(p_pin);

  if v_old = '' then
    raise exception '原门店名不能为空';
  end if;
  if v_new = '' then
    v_new := v_old;                    -- 没传新名字就当作不改
  end if;
  if v_mode not in ('error', 'replace') then
    raise exception 'p_on_conflict 必须是 error 或 replace';
  end if;

  -- 改名的冲突检查：目标「门店 + 日期」已被占用
  if v_new <> v_old and exists (
       select 1 from public.spr_records
        where store_name = v_new and activity_date = p_activity_date
     ) then
    if v_mode = 'replace' then
      delete from public.spr_records
       where store_name = v_new and activity_date = p_activity_date;
    else
      raise exception 'STORE_CONFLICT 目标门店「%」在 % 已有一条记录', v_new, p_activity_date;
    end if;
  end if;

  v_gift := coalesce(p_mechanism1,0) + coalesce(p_mechanism2,0) + coalesce(p_mechanism3,0) + coalesce(p_mechanism4,0);
  v_bg   := coalesce(p_blackgold_1l,0) + coalesce(p_blackgold_500,0) + coalesce(p_blackgold_600,0) + coalesce(p_blackgold_330,0) + coalesce(p_blackgold_250,0);
  v_abi  := coalesce(p_bud_classic_gold,0) + v_bg + coalesce(p_other_abi,0);
  v_comp := coalesce(p_key_competitor,0) + coalesce(p_other_competitor,0);

  update public.spr_records set
    store_name        = v_new,
    m3                = coalesce(p_m3, m3),
    spr_name          = coalesce(p_spr_name, spr_name),
    mechanism1        = coalesce(p_mechanism1, mechanism1),
    mechanism2        = coalesce(p_mechanism2, mechanism2),
    mechanism3        = coalesce(p_mechanism3, mechanism3),
    mechanism4        = coalesce(p_mechanism4, mechanism4),
    gift_255_cans     = v_gift,
    bud_classic_gold  = coalesce(p_bud_classic_gold, bud_classic_gold),
    blackgold_1l      = coalesce(p_blackgold_1l, blackgold_1l),
    blackgold_500     = coalesce(p_blackgold_500, blackgold_500),
    blackgold_600     = coalesce(p_blackgold_600, blackgold_600),
    blackgold_330     = coalesce(p_blackgold_330, blackgold_330),
    blackgold_250     = coalesce(p_blackgold_250, blackgold_250),
    blackgold_total   = v_bg,
    other_abi         = coalesce(p_other_abi, other_abi),
    abi_total         = v_abi,
    key_competitor    = coalesce(p_key_competitor, key_competitor),
    other_competitor  = coalesce(p_other_competitor, other_competitor),
    competitor_total  = v_comp,
    beer_total        = v_abi + v_comp,
    updated_at        = now()
  where store_name = v_old and activity_date = p_activity_date
  returning * into r;

  if not found then
    raise exception '记录不存在：% / %', v_old, p_activity_date;
  end if;
  return r;
end;
$$;

-- ------------------------------------------------------------
-- 6) 允许网页（anon 密钥）调用这些函数
--    ⚠️ 参数类型顺序必须与上面完全一致，改了函数签名要重发授权
-- ------------------------------------------------------------
grant execute on function public.admin_upsert_store(
  text, text, text, boolean, text
) to anon;

grant execute on function public.admin_delete_store(
  text, text, text
) to anon;

grant execute on function public.admin_bulk_upsert_stores(
  text, jsonb
) to anon;

grant execute on function public.update_spr_record2(
  text, text, date, text, text, text, text,
  integer, integer, integer, integer,
  integer, integer, integer, integer,
  integer, integer, integer, integer,
  integer
) to anon;

-- ------------------------------------------------------------
-- 7) 完成提示 + 当前清单概况
-- ------------------------------------------------------------
select
  '升级成功！' as 提示,
  '门店清单当前有 ' || (select count(*) from public.store_master) || ' 条，'
    || '涉及 ' || (select count(distinct m3) from public.store_master) || ' 个 M3。'
    || '清单为空时填报页会自动退回「历史门店联想」模式，SPR 不会被卡住。' as 现状,
  '接下来：打开网页的「门店清单管理」页，把该有的门店加进去（可批量粘贴或一键导入历史门店）。' as 下一步;
