-- 프로필 사이즈 입력을 알파벳/숫자로 나누고 선호 핏을 추가한다.
--
-- 브랜드마다 표기 기준이 달라 유저가 기억하는 쪽이 다르다.
-- 한 칸을 강요하면 "M인데 100이기도 한" 상황에서 무엇을 넣을지 막힌다.

-- usual_size -> size_alpha 로 이름만 바꾼다.
-- 값을 새 컬럼에 복사하고 옛 컬럼을 지우는 방식보다 안전하다.
-- 복사 중 실패하면 데이터가 두 곳에 흩어지지만, 이름 변경은 그럴 여지가 없다.
do $$
begin
  if exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'user_profiles'
          and column_name = 'usual_size')
     and not exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'user_profiles'
          and column_name = 'size_alpha')
  then
    alter table user_profiles rename column usual_size to size_alpha;
  end if;
end $$;

-- 위 rename 이 이미 끝났으면 아래 size_alpha 는 no-op 이다.
alter table user_profiles
  add column if not exists size_alpha    text,
  add column if not exists size_numeric  integer,
  add column if not exists preferred_fit text;

-- 허용값은 CHECK 로 묶지 않고 주석으로 남긴다.
-- 사이즈 표기는 브랜드마다 다르고 인치(28, 30)나 FREE 가 추가될 수 있다.
comment on column user_profiles.size_alpha is
  '알파벳 사이즈. XS, S, M, L, XL, XXL 중 하나. null 허용';
comment on column user_profiles.size_numeric is
  '숫자 사이즈. 90, 95, 100, 105, 110 중 하나. null 허용';
comment on column user_profiles.preferred_fit is
  '선호 핏. 슬림핏, 레귤러핏, 세미오버핏, 오버핏, 상관없음 중 하나. null 허용. 현재는 저장만 한다';
