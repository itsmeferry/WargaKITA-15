-- ============================================================================
-- WargaKITA RT 17 / RW 03 Kebonagung
-- Migration 008: Performance Indexes & Query Optimization (Supabase)
-- Jalankan di Supabase SQL Editor (aman dijalankan berulang / idempotent)
-- ============================================================================

-- 1. Composite index untuk query iuran per KK & periode tahunan (deduplikasi & tunggakan lintas tahun)
CREATE INDEX IF NOT EXISTS idx_household_dues_hh_period
  ON public.household_dues (household_id, period_year DESC, period_month DESC);

CREATE INDEX IF NOT EXISTS idx_household_dues_period_cat
  ON public.household_dues (period_year, period_month, fee_category_id);

-- 2. Index alokasi pembayaran untuk join cepat ke household_dues dan payments
CREATE INDEX IF NOT EXISTS idx_payment_allocations_due_id
  ON public.payment_allocations (household_due_id);

CREATE INDEX IF NOT EXISTS idx_payment_allocations_payment_id
  ON public.payment_allocations (payment_id);

-- 3. Index transaksi kas RT untuk ringkasan bulanan, perbandingan MoM, dan filter approval
CREATE INDEX IF NOT EXISTS idx_cash_tx_date_status
  ON public.cash_transactions (transaction_date DESC, status, approval_status);

CREATE INDEX IF NOT EXISTS idx_cash_tx_type_approval
  ON public.cash_transactions (transaction_type, approval_status)
  WHERE status <> 'voided';

-- 4. Index data warga & KK untuk pencarian cepat, klasifikasi Janda/Kost/Kontrak, dan ulang tahun
CREATE INDEX IF NOT EXISTS idx_residents_hh_active_rel
  ON public.residents (household_id, is_active, family_relationship);

CREATE INDEX IF NOT EXISTS idx_households_active_status
  ON public.households (is_active, residence_status);

-- 5. Index kalender kegiatan & audit log per aktor
CREATE INDEX IF NOT EXISTS idx_community_events_date
  ON public.community_events (event_date ASC);

CREATE INDEX IF NOT EXISTS idx_audit_logs_actor_ts
  ON public.audit_logs (actor_id, timestamp DESC);

-- 6. Perbarui statistik planner PostgreSQL agar indeks langsung dipakai optimal
ANALYZE public.households;
ANALYZE public.residents;
ANALYZE public.household_dues;
ANALYZE public.payments;
ANALYZE public.payment_allocations;
ANALYZE public.cash_transactions;
ANALYZE public.community_events;
ANALYZE public.audit_logs;
