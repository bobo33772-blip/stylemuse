-- 콘텐츠 테이블 RLS 적용과 관리자 판별.
--
-- 이 세 테이블(pinterest_looks, looks_items_match, musinsa_items)은 개인정보가 아니라
-- 서비스 콘텐츠다. 누구나 읽을 수 있어야 하고 쓰기는 관리자만 할 수 있어야 한다.

-- ---------------------------------------------------------------
-- 1. 관리자 명부
--    정책을 하나도 만들지 않는다 = API 로는 조회·추가·삭제가 전부 막힌다.
--    관리자 지정은 SQL(service role)로만 가능하므로 자기 승격이 불가능하다.
--
--    user_profiles 에 is_admin 컬럼을 두지 않은 이유:
--    그 테이블에는 "본인 행은 본인이 수정한다" 정책이 있어 자기 자신을 관리자로
--    올릴 수 있다. 컬럼 단위 권한 회수로 막을 수는 있으나, 보호막이 정책과 다른
--    곳에 숨어 나중에 grant 한 줄로 조용히 열릴 수 있다.
-- ---------------------------------------------------------------
create table if not exists admin_users (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  note       text,
  created_at timestamptz not null default now()
);

comment on table admin_users is
  '운영자 명부. RLS 를 켜고 정책을 두지 않아 API 로는 접근할 수 없다. SQL 로만 관리한다';

alter table admin_users enable row level security;

-- 정책에서 admin_users 를 읽으려면 그 테이블의 RLS 를 넘어야 하므로 SECURITY DEFINER 로 만든다.
create or replace function public.is_admin() returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from admin_users where user_id = auth.uid());
$$;

revoke all on function public.is_admin() from public;
-- 비로그인 이용자의 SELECT 정책도 이 함수를 평가한다. 권한이 없으면 갤러리 조회가 실패한다.
-- auth.uid() 가 null 이면 false 를 돌려주므로 anon 에게 줘도 안전하다.
grant execute on function public.is_admin() to authenticated, anon;

comment on function public.is_admin() is
  '현재 요청자가 운영자인지. RLS 정책에서 쓰기 위해 SECURITY DEFINER 로 둔다';

-- ---------------------------------------------------------------
-- 2. 코디 — 공개된 것만 읽힌다
-- ---------------------------------------------------------------
alter table pinterest_looks enable row level security;

drop policy if exists pinterest_looks_read  on pinterest_looks;
drop policy if exists pinterest_looks_admin on pinterest_looks;

create policy pinterest_looks_read on pinterest_looks
  for select using (is_public = true or public.is_admin());

create policy pinterest_looks_admin on pinterest_looks
  for all using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------
-- 3. 매칭 — 코디의 공개 여부를 따른다
--    "전체 허용"으로 두면 비공개 코디의 매칭 근거가 그대로 읽혀 공개 전환 통제가
--    무의미해진다. 매칭 근거는 사람이 작성한 정답 데이터다.
-- ---------------------------------------------------------------
alter table looks_items_match enable row level security;

drop policy if exists looks_items_match_read  on looks_items_match;
drop policy if exists looks_items_match_admin on looks_items_match;

create policy looks_items_match_read on looks_items_match
  for select using (
    exists (
      select 1 from pinterest_looks l
      where l.id = look_id and (l.is_public = true or public.is_admin())
    )
  );

create policy looks_items_match_admin on looks_items_match
  for all using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------
-- 4. 상품 — 공개 상품 정보이므로 전체 읽기 허용
-- ---------------------------------------------------------------
alter table musinsa_items enable row level security;

drop policy if exists musinsa_items_read  on musinsa_items;
drop policy if exists musinsa_items_admin on musinsa_items;

create policy musinsa_items_read on musinsa_items
  for select using (true);

create policy musinsa_items_admin on musinsa_items
  for all using (public.is_admin()) with check (public.is_admin());
