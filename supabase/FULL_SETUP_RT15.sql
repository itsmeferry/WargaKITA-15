-- FULL DATABASE SCHEMA WARGAKITA 15 (FROM MASTER v1.14.2)


-- === SOURCE: 001_schema.sql ===
-- WargaKITA RT 15 / RW 03 Kebonagung — PostgreSQL Schema (Supabase)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('pak_rt','wakil_rt','sekretaris_rt','bendahara_rt','developer_admin')),
  must_change_password BOOLEAN NOT NULL DEFAULT TRUE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.households (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_number TEXT UNIQUE NOT NULL CHECK (household_number ~ '^[0-9]{16}$'),
  head_resident_id UUID NULL,
  address TEXT NOT NULL,
  residence_status TEXT NOT NULL CHECK (residence_status IN ('Permanen','Kontrak','Kost')),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.residents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES public.households(id) ON DELETE RESTRICT,
  nik TEXT UNIQUE CHECK (nik IS NULL OR nik ~ '^[0-9]{16}$'),
  full_name TEXT NOT NULL,
  birth_place TEXT,
  birth_date DATE,
  gender TEXT CHECK (gender IN ('Laki-laki','Perempuan')),
  family_relationship TEXT NOT NULL CHECK (family_relationship IN ('Kepala Keluarga','Pasangan','Anak','Lainnya')),
  religion TEXT NOT NULL CHECK (religion IN ('Islam','Kristen','Hindu','Buddha')),
  phone TEXT,
  address_override TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.fee_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT UNIQUE NOT NULL,
  default_amount BIGINT NOT NULL DEFAULT 0 CHECK (default_amount >= 0),
  allow_partial BOOLEAN NOT NULL DEFAULT TRUE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.household_dues (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES public.households(id) ON DELETE RESTRICT,
  fee_category_id UUID NOT NULL REFERENCES public.fee_categories(id) ON DELETE RESTRICT,
  period_month INT NOT NULL CHECK (period_month BETWEEN 1 AND 12),
  period_year INT NOT NULL CHECK (period_year >= 2024),
  amount_due BIGINT NOT NULL CHECK (amount_due >= 0),
  due_date DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by UUID REFERENCES public.profiles(id),
  UNIQUE (household_id, fee_category_id, period_month, period_year)
);

CREATE TABLE IF NOT EXISTS public.payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES public.households(id) ON DELETE RESTRICT,
  payment_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  amount_received BIGINT NOT NULL CHECK (amount_received > 0),
  payment_method TEXT NOT NULL CHECK (payment_method IN ('Tunai','Transfer','QRIS')),
  receipt_number TEXT NOT NULL,
  idempotency_key TEXT UNIQUE NOT NULL,
  status TEXT NOT NULL DEFAULT 'valid' CHECK (status IN ('valid','voided')),
  notes TEXT,
  created_by UUID NOT NULL REFERENCES public.profiles(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.payment_allocations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id UUID NOT NULL REFERENCES public.payments(id) ON DELETE RESTRICT,
  household_due_id UUID NOT NULL REFERENCES public.household_dues(id) ON DELETE RESTRICT,
  amount_allocated BIGINT NOT NULL CHECK (amount_allocated > 0)
);

CREATE TABLE IF NOT EXISTS public.cash_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  transaction_type TEXT NOT NULL CHECK (transaction_type IN ('income','expense','adjustment')),
  category TEXT NOT NULL,
  description TEXT NOT NULL,
  amount BIGINT NOT NULL CHECK (amount > 0),
  payment_id UUID UNIQUE REFERENCES public.payments(id) ON DELETE RESTRICT,
  reference_number TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'valid' CHECK (status IN ('valid','voided')),
  created_by UUID NOT NULL REFERENCES public.profiles(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.cash_opening_balances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  period_month INT NOT NULL CHECK (period_month BETWEEN 1 AND 12),
  period_year INT NOT NULL CHECK (period_year >= 2024),
  amount BIGINT NOT NULL,
  notes TEXT,
  approved_by UUID NOT NULL REFERENCES public.profiles(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (period_month, period_year)
);

CREATE TABLE IF NOT EXISTS public.audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id UUID REFERENCES public.profiles(id),
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reason TEXT,
  metadata JSONB DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS public.import_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source_name TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('preview','confirmed','cancelled','failed')),
  total_records INT NOT NULL DEFAULT 0,
  accepted_records INT NOT NULL DEFAULT 0,
  rejected_records INT NOT NULL DEFAULT 0,
  created_by UUID NOT NULL REFERENCES public.profiles(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.app_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  setting_key TEXT UNIQUE NOT NULL,
  setting_value JSONB NOT NULL,
  updated_by UUID REFERENCES public.profiles(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- === SOURCE: 002_rls.sql ===
-- Row Level Security (RLS) untuk 5 Peran WargaKITA
CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid() AND is_active = TRUE;
$$;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.households ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.residents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fee_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.household_dues ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cash_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cash_opening_balances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.import_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

-- Semua pengurus aktif dapat membaca data operasional
CREATE POLICY "active_staff_read_households" ON public.households FOR SELECT
  USING (public.current_user_role() IS NOT NULL);

CREATE POLICY "active_staff_read_residents" ON public.residents FOR SELECT
  USING (public.current_user_role() IS NOT NULL);

CREATE POLICY "active_staff_read_fees" ON public.fee_categories FOR SELECT
  USING (public.current_user_role() IS NOT NULL);

CREATE POLICY "active_staff_read_dues" ON public.household_dues FOR SELECT
  USING (public.current_user_role() IS NOT NULL);

-- Tambah warga & KK: Pak RT, Wakil RT, Sekretaris, Developer
CREATE POLICY "insert_households_authorized" ON public.households FOR INSERT
  WITH CHECK (public.current_user_role() IN ('pak_rt','wakil_rt','sekretaris_rt','developer_admin'));

CREATE POLICY "insert_residents_authorized" ON public.residents FOR INSERT
  WITH CHECK (public.current_user_role() IN ('pak_rt','wakil_rt','sekretaris_rt','developer_admin'));

-- Edit warga & KK: Hanya Pak RT & Developer (Wakil, Sekretaris, Bendahara dilarang edit/hapus)
CREATE POLICY "update_households_pakrt" ON public.households FOR UPDATE
  USING (public.current_user_role() IN ('pak_rt','developer_admin'));

CREATE POLICY "update_residents_pakrt" ON public.residents FOR UPDATE
  USING (public.current_user_role() IN ('pak_rt','developer_admin'));

-- Pembayaran & Cash RT: Bendahara, Pak RT, Developer (read & insert via RPC, dilarang delete)
CREATE POLICY "read_payments" ON public.payments FOR SELECT
  USING (public.current_user_role() IN ('pak_rt','bendahara_rt','developer_admin'));

CREATE POLICY "read_cash" ON public.cash_transactions FOR SELECT
  USING (public.current_user_role() IS NOT NULL);

-- Audit log: hanya Pak RT & Developer yang dapat membaca
CREATE POLICY "read_audit_logs" ON public.audit_logs FOR SELECT
  USING (public.current_user_role() IN ('pak_rt','developer_admin'));


-- === SOURCE: 003_functions.sql ===
-- Transaksi Atomik Pembayaran + Alokasi + Cash RT + Audit Log
CREATE OR REPLACE FUNCTION public.record_payment_atomic(
  p_household_id UUID,
  p_due_id UUID,
  p_amount BIGINT,
  p_method TEXT,
  p_idempotency_key TEXT,
  p_notes TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_role TEXT;
  v_payment_id UUID;
  v_due_amount BIGINT;
  v_already_paid BIGINT;
  v_receipt TEXT;
BEGIN
  v_role := public.current_user_role();
  IF v_role NOT IN ('pak_rt','bendahara_rt','developer_admin') THEN
    RAISE EXCEPTION 'Akses ditolak untuk peran ini';
  END IF;

  -- Idempotensi: cegah transaksi ganda
  SELECT id INTO v_payment_id FROM public.payments WHERE idempotency_key = p_idempotency_key;
  IF v_payment_id IS NOT NULL THEN
    RETURN v_payment_id;
  END IF;

  SELECT amount_due INTO v_due_amount FROM public.household_dues WHERE id = p_due_id AND household_id = p_household_id;
  IF v_due_amount IS NULL THEN
    RAISE EXCEPTION 'Kewajiban tagihan tidak ditemukan';
  END IF;

  SELECT COALESCE(SUM(pa.amount_allocated), 0) INTO v_already_paid
  FROM public.payment_allocations pa
  JOIN public.payments p ON p.id = pa.payment_id
  WHERE pa.household_due_id = p_due_id AND p.status = 'valid';

  IF p_amount <= 0 OR (v_already_paid + p_amount) > v_due_amount THEN
    RAISE EXCEPTION 'Nominal pembayaran melebihi sisa tagihan';
  END IF;

  v_receipt := 'KWT-' || TO_CHAR(NOW(), 'YYYYMMDD-HH24MISS');

  INSERT INTO public.payments(household_id, amount_received, payment_method, receipt_number, idempotency_key, notes, created_by)
  VALUES (p_household_id, p_amount, p_method, v_receipt, p_idempotency_key, p_notes, auth.uid())
  RETURNING id INTO v_payment_id;

  INSERT INTO public.payment_allocations(payment_id, household_due_id, amount_allocated)
  VALUES (v_payment_id, p_due_id, p_amount);

  INSERT INTO public.cash_transactions(transaction_type, category, description, amount, payment_id, reference_number, created_by)
  VALUES ('income', 'Iuran Warga', 'Pembayaran iuran RT (' || v_receipt || ')', p_amount, v_payment_id, v_receipt, auth.uid());

  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, reason)
  VALUES (auth.uid(), 'RECORD_PAYMENT', 'payments', v_payment_id, p_notes);

  RETURN v_payment_id;
END;
$$;


-- === SOURCE: 004_seed.sql ===
-- 4 Kategori Iuran Awal WargaKITA
INSERT INTO public.fee_categories (name, default_amount, allow_partial, is_active) VALUES
  ('Pembangunan + Voging', 50000, TRUE, TRUE),
  ('Rukem + Juri Kunci', 30000, TRUE, TRUE),
  ('Keuangan Social', 20000, TRUE, TRUE),
  ('17 Agustus', 15000, TRUE, TRUE)
ON CONFLICT (name) DO NOTHING;


-- === PENGURUS AWAL RT 15 (KETUA RT: DWI SWANDOKO) ===
UPDATE public.profiles SET full_name = 'Dwi Swandoko', display_name = 'Dwi Swandoko' WHERE role = 'pak_rt';
