-- 약관 동의 이력, 익명 통계, 회원 탈퇴.

-- ---------------------------------------------------------------
-- 1. 동의 이력
--    UNIQUE(user_id, agreement_type) 이므로 재동의는 행을 추가하지 않고 갱신한다.
--    "현재 어느 버전에 동의했는가"만 알면 되고, 과거 버전 이력은 필요하지 않다.
-- ---------------------------------------------------------------
create table if not exists user_agreements (
  id             bigint generated always as identity primary key,
  user_id        uuid        not null references auth.users (id) on delete cascade,
  agreement_type text        not null,
  version        text        not null,
  agreed         boolean     not null default true,
  agreed_at      timestamptz not null default now(),
  unique (user_id, agreement_type)
);

comment on column user_agreements.agreement_type is
  'terms(필수) / privacy(필수) / marketing(선택). marketing 은 발송 채널이 생기면 사용한다';
comment on column user_agreements.version is
  '동의한 문서의 버전. 문서 버전이 오르면 해당 항목만 다시 받는다';

create index if not exists user_agreements_user_idx on user_agreements (user_id);

alter table user_agreements enable row level security;

drop policy if exists user_agreements_select on user_agreements;
drop policy if exists user_agreements_insert on user_agreements;
drop policy if exists user_agreements_update on user_agreements;
drop policy if exists user_agreements_delete on user_agreements;

create policy user_agreements_select on user_agreements
  for select using (auth.uid() = user_id);
create policy user_agreements_insert on user_agreements
  for insert with check (auth.uid() = user_id);
create policy user_agreements_update on user_agreements
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy user_agreements_delete on user_agreements
  for delete using (auth.uid() = user_id);

-- ---------------------------------------------------------------
-- 2. 익명 통계
--    user_id 를 지우는 게 아니라 처음부터 넣지 않는다. 되돌릴 대응표가 남지 않는다.
-- ---------------------------------------------------------------
create table if not exists look_save_stats (
  look_id    bigint primary key references pinterest_looks (id) on delete cascade,
  save_count integer     not null default 0,
  updated_at timestamptz not null default now()
);

comment on table look_save_stats is
  '코디별 누적 저장 횟수. 개인 식별자와 개별 저장 시각을 담지 않으므로 개인정보가 아니다.';
comment on column look_save_stats.updated_at is
  '카운터를 마지막으로 갱신한 시각. 특정 이용자의 행동 시점이 아니다';

-- 정책 없이 RLS 만 켠다 = 클라이언트에서 직접 읽고 쓸 수 없다.
alter table look_save_stats enable row level security;

-- ---------------------------------------------------------------
-- 3. 본인 계정 삭제
--    auth.users 삭제에는 secret 키가 필요해 브라우저에서 직접 할 수 없다.
--    SECURITY DEFINER 로 권한을 빌리되, auth.uid() 로 본인만 지우게 막는다.
-- ---------------------------------------------------------------
create or replace function delete_own_account() returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception '인증되지 않은 요청입니다';
  end if;

  -- 개인 식별자 없이 코디별 저장 횟수만 누적한다.
  insert into look_save_stats (look_id, save_count, updated_at)
  select look_id, count(*), now()
  from saved_looks
  where user_id = uid
  group by look_id
  on conflict (look_id) do update
    set save_count = look_save_stats.save_count + excluded.save_count,
        updated_at = now();

  delete from saved_looks     where user_id = uid;
  delete from user_profiles   where user_id = uid;
  delete from user_agreements where user_id = uid;

  -- 하드 삭제. 같은 이메일로 다시 가입해도 새 계정이 되며 이전 데이터는 복원되지 않는다.
  delete from auth.users where id = uid;
end $$;

revoke all on function delete_own_account() from public, anon;
grant execute on function delete_own_account() to authenticated;

comment on function delete_own_account() is
  '본인 계정과 개인정보를 삭제한다. 저장 기록은 개인 식별자 없이 look_save_stats 로만 남는다';
