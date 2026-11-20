-- ============================================================================
-- SCHEMA & SEED AWAL DATABASE SUPABASE: WargaKITA 15 (com.wargakita.rt15)
-- Base Master: v1.14.2
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id UUID UNIQUE,
  full_name TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('ketua_rt', 'wakil_rt', 'bendahara', 'sekretaris', 'warga')),
  jabatan_label TEXT NOT NULL,
  login_username TEXT UNIQUE NOT NULL,
  phone_number TEXT,
  blok_rumah TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.rt_settings (
  id INT PRIMARY KEY DEFAULT 1,
  app_name TEXT NOT NULL DEFAULT 'WargaKITA 15',
  rt_number TEXT NOT NULL DEFAULT '15',
  ketua_rt_name TEXT NOT NULL DEFAULT 'Dwi Swandoko',
  iuran_kas_rt NUMERIC NOT NULL DEFAULT 25000,
  iuran_kebersihan NUMERIC NOT NULL DEFAULT 15000,
  iuran_keamanan NUMERIC NOT NULL DEFAULT 10000,
  qris_merchant_name TEXT DEFAULT 'KAS RT 15',
  qris_image_url TEXT,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO public.rt_settings (id, app_name, rt_number, ketua_rt_name)
VALUES (1, 'WargaKITA 15', '15', 'Dwi Swandoko')
ON CONFLICT (id) DO UPDATE SET
  app_name = EXCLUDED.app_name,
  rt_number = EXCLUDED.rt_number,
  ketua_rt_name = EXCLUDED.ketua_rt_name;

INSERT INTO public.profiles (full_name, role, jabatan_label, login_username, is_active)
VALUES
  ('Dwi Swandoko', 'ketua_rt', 'Ketua RT 15', 'ketua.rt15', TRUE),
  ('Wakil Ketua RT 15 (Menyusul)', 'wakil_rt', 'Wakil Ketua RT 15', 'wakil.rt15', TRUE),
  ('Bendahara RT 15 (Menyusul)', 'bendahara', 'Bendahara RT 15', 'bendahara.rt15', TRUE),
  ('Sekretaris RT 15 (Menyusul)', 'sekretaris', 'Sekretaris RT 15', 'sekretaris.rt15', TRUE)
ON CONFLICT (login_username) DO NOTHING;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rt_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read rt_settings" ON public.rt_settings;
CREATE POLICY "Public read rt_settings" ON public.rt_settings
  FOR SELECT USING (TRUE);

DROP POLICY IF EXISTS "Authenticated read profiles" ON public.profiles;
CREATE POLICY "Authenticated read profiles" ON public.profiles
  FOR SELECT USING (auth.role() = 'authenticated');
