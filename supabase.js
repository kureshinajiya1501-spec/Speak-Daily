import { createClient } from '@supabase/supabase-js';
const url = import.meta.env.VITE_SUPABASE_URL || 'https://dtqaobcckyrdlmwfvabq.supabase.co';
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY || 'sb_publishable_cwcT2uFBJiB46MRPG7C1EQ_KkJoHLFS';
export const supabase = createClient(url, key);
