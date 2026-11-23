-- WargaKITA RT 17 / RW 03 Kebonagung — PostgreSQL Schema (Supabase)
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
