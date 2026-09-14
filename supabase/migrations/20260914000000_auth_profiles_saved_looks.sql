-- 사용자 프로필과 저장 코디.
--
-- 배경: 설문 25건에서 결제 직전 망설임 요인이 사이즈·핏 52%, 어울릴지 24%로
--       핏 불확실성이 76%였다. 이를 다루려면 유저별 체형 정보가 필요하고,
--       그러려면 유저를 식별해야 한다. 로그인은 기능 추가가 아니라 전제 조건이다.
--
-- 범위: 기존 3개 테이블(pinterest_looks, looks_items_match, musinsa_items)은 건드리지 않는다.
--       그쪽 RLS 는 별도 작업이다.

-- ---------------------------------------------------------------
-- 1. 테이블
-- ---------------------------------------------------------------
create table if not exists user_profiles (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  height     integer,      -- 키(cm)
  weight     integer,      -- 몸무게(kg)
  usual_size text,         -- 평소 사이즈
  photo_path text,         -- 업로드 사진 경로 (다음 단계)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table user_profiles is
  '유저별 체형 정보. 전부 선택 입력이며 비어 있어도 서비스를 쓸 수 있다.';

create table if not exists saved_looks (
  id         bigint generated always as identity primary key,
  user_id    uuid   not null references auth.users (id)      on delete cascade,
  look_id    bigint not null references pinterest_looks (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_id, look_id)
);

comment on table saved_looks is
  '유저가 저장한 코디. 기존 localStorage 방식을 대체한다.';

create index if not exists saved_looks_user_idx on saved_looks (user_id, created_at desc);

-- ---------------------------------------------------------------
-- 2. updated_at 자동 갱신
--    클라이언트가 보내주길 기대하지 않는다. 빠뜨리면 값이 거짓이 된다.
-- ---------------------------------------------------------------
create or replace function set_updated_at() returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists user_profiles_set_updated_at on user_profiles;
create trigger user_profiles_set_updated_at
  before update on user_profiles
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------
-- 3. RLS — 본인 데이터만 접근
--    CREATE POLICY 에는 IF NOT EXISTS 가 없어 먼저 지운다(재실행 가능하게).
-- ---------------------------------------------------------------
alter table user_profiles enable row level security;
alter table saved_looks   enable row level security;

drop policy if exists user_profiles_select on user_profiles;
drop policy if exists user_profiles_insert on user_profiles;
drop policy if exists user_profiles_update on user_profiles;
drop policy if exists user_profiles_delete on user_profiles;

create policy user_profiles_select on user_profiles
  for select using (auth.uid() = user_id);
create policy user_profiles_insert on user_profiles
  for insert with check (auth.uid() = user_id);
create policy user_profiles_update on user_profiles
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy user_profiles_delete on user_profiles
  for delete using (auth.uid() = user_id);

drop policy if exists saved_looks_select on saved_looks;
drop policy if exists saved_looks_insert on saved_looks;
drop policy if exists saved_looks_update on saved_looks;
drop policy if exists saved_looks_delete on saved_looks;

create policy saved_looks_select on saved_looks
  for select using (auth.uid() = user_id);
create policy saved_looks_insert on saved_looks
  for insert with check (auth.uid() = user_id);
create policy saved_looks_update on saved_looks
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy saved_looks_delete on saved_looks
  for delete using (auth.uid() = user_id);
