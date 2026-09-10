// config.js
// ⚠️ 이 파일은 브라우저로 그대로 전송됩니다. 공개돼도 되는 값만 두세요.
// SUPABASE_PUBLISHABLE_KEY(sb_publishable_...)는 공개용 키라 여기 있어도 됩니다.
// Secret key(sb_secret_...) / OPENAI_API_KEY / SERPAPI_KEY 는 절대 두지 마세요.
// 그 값들은 Edge Function 시크릿으로만 관리합니다:
//   supabase secrets set --env-file <키만 담은 파일>
const SUPABASE_URL = 'https://rrhlxrunomduquxztsol.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_TeC1v-cjshumX1KkHFpOIA_Jz2SQxAu';
