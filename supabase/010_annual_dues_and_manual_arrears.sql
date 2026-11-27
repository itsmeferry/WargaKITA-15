-- ============================================================================
-- WargaKITA RT 17 / RW 03 Kebonagung
-- Migration 010: Sistem Iuran Tahunan (1 Tagihan/Tahun/Kategori, Cicilan Lintas Bulan),
--                Input Tunggakan Manual Beda Tahun & Sinkronisasi Custom Permissions RLS
-- Jalankan di Supabase SQL Editor (aman dijalankan berulang / idempotent)
-- ============================================================================
BEGIN;

-- 1. Izinkan tahun tagihan historis mulai 2020 untuk pencatatan tunggakan lintas tahun
DO $$
DECLARE
  v_con TEXT;
BEGIN
  FOR v_con IN
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'public.household_dues'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%period_year%'
  LOOP
    EXECUTE format('ALTER TABLE public.household_dues DROP CONSTRAINT IF EXISTS %I', v_con);
  END LOOP;
END $$;

ALTER TABLE public.household_dues
  ADD CONSTRAINT household_dues_period_year_check CHECK (period_year >= 2020);

-- Pastikan kolom custom_permissions tersedia sebelum dipakai oleh fungsi/RLS
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS custom_permissions JSONB DEFAULT NULL;

-- 2. Helper permission yang menghormati custom_permissions dari Panel Developer
CREATE OR REPLACE FUNCTION public.user_has_permission(p_perm_key TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
  v_custom JSONB;
BEGIN
  SELECT role, custom_permissions
  INTO v_role, v_custom
  FROM public.profiles
  WHERE id = auth.uid() AND is_active = TRUE;

  IF v_role IS NULL THEN
    RETURN FALSE;
  END IF;
  IF v_role = 'developer_admin' THEN
    RETURN TRUE;
  END IF;

  IF v_custom IS NOT NULL
     AND jsonb_typeof(v_custom) = 'object'
     AND v_custom ? p_perm_key
     AND jsonb_typeof(v_custom -> p_perm_key) = 'boolean' THEN
    RETURN (v_custom ->> p_perm_key)::BOOLEAN;
  END IF;

  RETURN CASE p_perm_key
    WHEN 'canViewWarga' THEN TRUE
    WHEN 'canAddWarga' THEN v_role IN ('pak_rt', 'wakil_rt', 'sekretaris_rt')
    WHEN 'canEditWarga' THEN v_role IN ('pak_rt')
    WHEN 'canDeleteWarga' THEN v_role IN ('pak_rt', 'wakil_rt')
    WHEN 'canPay' THEN v_role IN ('pak_rt', 'bendahara_rt')
    WHEN 'canCash' THEN v_role IN ('pak_rt', 'bendahara_rt')
    WHEN 'canApprove' THEN v_role IN ('pak_rt', 'wakil_rt')
    WHEN 'canEditOpening' THEN v_role IN ('pak_rt')
    WHEN 'canEditCalendar' THEN v_role IN ('pak_rt', 'wakil_rt')
    WHEN 'canUnmaskNik' THEN v_role IN ('pak_rt', 'sekretaris_rt')
    WHEN 'canBroadcastInfo' THEN v_role IN ('pak_rt', 'wakil_rt')
    WHEN 'canEditBirthdayCard' THEN v_role IN ('pak_rt', 'wakil_rt')
    WHEN 'canManageManualArrears' THEN v_role IN ('pak_rt', 'wakil_rt', 'bendahara_rt')
    WHEN 'canExportReports' THEN v_role IN ('pak_rt', 'wakil_rt', 'bendahara_rt', 'sekretaris_rt')
    ELSE FALSE
  END;
END;
$$;

GRANT EXECUTE ON FUNCTION public.user_has_permission(TEXT) TO authenticated;

-- 3. Konsolidasi aman duplikat bulanan dalam 1 tahun menjadi 1 baris tahunan kanonik
DO $$
DECLARE
  rec RECORD;
  v_canonical_id UUID;
  v_max_due BIGINT;
BEGIN
  FOR rec IN
    SELECT household_id, fee_category_id, period_year
    FROM public.household_dues
    GROUP BY household_id, fee_category_id, period_year
    HAVING COUNT(*) > 1
  LOOP
    -- Pilih baris kanonik: utamakan yang sudah memiliki alokasi pembayaran, lalu period_month terkecil
    SELECT d.id
    INTO v_canonical_id
    FROM public.household_dues d
    LEFT JOIN public.payment_allocations pa ON pa.household_due_id = d.id
    WHERE d.household_id = rec.household_id
      AND d.fee_category_id = rec.fee_category_id
      AND d.period_year = rec.period_year
    GROUP BY d.id, d.period_month
    ORDER BY COUNT(pa.id) DESC, d.period_month ASC
    LIMIT 1;

    SELECT MAX(amount_due)
    INTO v_max_due
    FROM public.household_dues
    WHERE household_id = rec.household_id
      AND fee_category_id = rec.fee_category_id
      AND period_year = rec.period_year;

    -- Pindahkan semua alokasi pembayaran tahun tersebut ke baris kanonik
    UPDATE public.payment_allocations pa
    SET household_due_id = v_canonical_id
    FROM public.household_dues d
    WHERE pa.household_due_id = d.id
      AND d.household_id = rec.household_id
      AND d.fee_category_id = rec.fee_category_id
      AND d.period_year = rec.period_year
      AND d.id <> v_canonical_id;

    UPDATE public.household_dues
    SET amount_due = COALESCE(v_max_due, amount_due)
    WHERE id = v_canonical_id;

    -- Hapus baris duplikat bulanan yang kini sudah kosong
    DELETE FROM public.household_dues d
    WHERE d.household_id = rec.household_id
      AND d.fee_category_id = rec.fee_category_id
      AND d.period_year = rec.period_year
      AND d.id <> v_canonical_id
      AND NOT EXISTS (
        SELECT 1 FROM public.payment_allocations pa WHERE pa.household_due_id = d.id
      );
  END LOOP;
END $$;

-- 4. Perbarui ensure_period_dues agar selalu 1 tagihan per tahun per kategori (period_month = 1)
CREATE OR REPLACE FUNCTION public.ensure_period_dues(p_month INT, p_year INT)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
  v_rukem_id UUID;
  v_inserted INT := 0;
  v_count_step INT := 0;
BEGIN
  v_role := public.current_user_role();
  IF v_role IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT id INTO v_rukem_id
  FROM public.fee_categories
  WHERE is_active = TRUE AND LOWER(name) LIKE '%rukem%'
  LIMIT 1;

  -- A. KK Janda (selain pengecualian bayar penuh): hanya wajib Rukem
  IF v_rukem_id IS NOT NULL THEN
    INSERT INTO public.household_dues (
      household_id, fee_category_id, period_month, period_year, amount_due
    )
    SELECT h.id, fc.id, 1, p_year, fc.default_amount
    FROM public.households h
    JOIN public.fee_categories fc ON fc.id = v_rukem_id
    WHERE h.is_active = TRUE
      AND COALESCE(h.residence_status, 'Permanen') NOT IN ('Kost', 'Pindah')
      AND EXISTS (SELECT 1 FROM public.residents r WHERE r.household_id = h.id AND r.is_active = TRUE)
      AND COALESCE(h.notes, '') NOT ILIKE '%[KECUALI_JANDA]%'
      AND (
        COALESCE(h.notes, '') ILIKE '%[TIPE:JANDA]%'
        OR EXISTS (SELECT 1 FROM public.residents r WHERE r.household_id = h.id AND r.is_active = TRUE AND COALESCE(r.notes, '') ILIKE '%janda%')
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.household_dues d
        WHERE d.household_id = h.id AND d.fee_category_id = fc.id AND d.period_year = p_year
      )
    ON CONFLICT (household_id, fee_category_id, period_month, period_year) DO NOTHING;
    GET DIAGNOSTICS v_count_step = ROW_COUNT;
    v_inserted := v_inserted + v_count_step;
  END IF;

  -- B. KK Reguler & Kasus Khusus Bayar Penuh: 4 kategori wajib per tahun
  INSERT INTO public.household_dues (
    household_id, fee_category_id, period_month, period_year, amount_due
  )
  SELECT h.id, fc.id, 1, p_year, fc.default_amount
  FROM public.households h
  CROSS JOIN public.fee_categories fc
  WHERE fc.is_active = TRUE
    AND h.is_active = TRUE
    AND COALESCE(h.residence_status, 'Permanen') NOT IN ('Kost', 'Pindah')
    AND EXISTS (SELECT 1 FROM public.residents r WHERE r.household_id = h.id AND r.is_active = TRUE)
    AND (
      COALESCE(h.notes, '') ILIKE '%[KECUALI_JANDA]%'
      OR NOT (
        COALESCE(h.notes, '') ILIKE '%[TIPE:JANDA]%'
        OR EXISTS (SELECT 1 FROM public.residents r WHERE r.household_id = h.id AND r.is_active = TRUE AND COALESCE(r.notes, '') ILIKE '%janda%')
      )
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.household_dues d
      WHERE d.household_id = h.id AND d.fee_category_id = fc.id AND d.period_year = p_year
    )
  ON CONFLICT (household_id, fee_category_id, period_month, period_year) DO NOTHING;
  GET DIAGNOSTICS v_count_step = ROW_COUNT;
  v_inserted := v_inserted + v_count_step;

  RETURN v_inserted;
END;
$$;

GRANT EXECUTE ON FUNCTION public.ensure_period_dues(INT, INT) TO authenticated;

-- 5. Perbarui trigger KK baru agar membuat 1 tagihan tahunan pada period_month = 1
CREATE OR REPLACE FUNCTION public.fn_auto_create_dues_for_new_household()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_year INT := EXTRACT(YEAR FROM (NOW() AT TIME ZONE 'Asia/Jakarta'))::INT;
BEGIN
  IF NEW.is_active = TRUE AND COALESCE(NEW.residence_status, 'Permanen') NOT IN ('Kost', 'Pindah') THEN
    IF COALESCE(NEW.notes, '') ILIKE '%[TIPE:JANDA]%' AND COALESCE(NEW.notes, '') NOT ILIKE '%[KECUALI_JANDA]%' THEN
      INSERT INTO public.household_dues (household_id, fee_category_id, period_month, period_year, amount_due)
      SELECT NEW.id, fc.id, 1, v_year, fc.default_amount
      FROM public.fee_categories fc
      WHERE fc.is_active = TRUE AND LOWER(fc.name) LIKE '%rukem%'
      ON CONFLICT (household_id, fee_category_id, period_month, period_year) DO NOTHING;
    ELSE
      INSERT INTO public.household_dues (household_id, fee_category_id, period_month, period_year, amount_due)
      SELECT NEW.id, fc.id, 1, v_year, fc.default_amount
      FROM public.fee_categories fc
      WHERE fc.is_active = TRUE
      ON CONFLICT (household_id, fee_category_id, period_month, period_year) DO NOTHING;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- 6. RPC Input / Penyesuaian Tunggakan Manual Beda Tahun oleh Petugas Berwenang
CREATE OR REPLACE FUNCTION public.upsert_manual_household_due(
  p_household_id UUID,
  p_fee_category_id UUID,
  p_period_year INT,
  p_amount_due BIGINT,
  p_notes TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_due_id UUID;
  v_paid BIGINT := 0;
  v_final_due BIGINT;
BEGIN
  IF NOT public.user_has_permission('canManageManualArrears') THEN
    RAISE EXCEPTION 'Akses ditolak: Anda tidak memiliki izin mengatur tunggakan manual.';
  END IF;

  IF p_period_year < 2020 OR p_period_year > 2099 THEN
    RAISE EXCEPTION 'Tahun periode tagihan tidak valid.';
  END IF;
  IF p_amount_due < 0 THEN
    RAISE EXCEPTION 'Nominal tagihan tidak boleh negatif.';
  END IF;

  SELECT d.id
  INTO v_due_id
  FROM public.household_dues d
  WHERE d.household_id = p_household_id
    AND d.fee_category_id = p_fee_category_id
    AND d.period_year = p_period_year
  ORDER BY d.period_month ASC
  LIMIT 1;

  IF v_due_id IS NOT NULL THEN
    SELECT COALESCE(SUM(pa.amount_allocated), 0)
    INTO v_paid
    FROM public.payment_allocations pa
    JOIN public.payments p ON p.id = pa.payment_id
    WHERE pa.household_due_id = v_due_id AND p.status <> 'voided';

    IF p_amount_due = 0 AND v_paid = 0 THEN
      DELETE FROM public.household_dues WHERE id = v_due_id;
      INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, reason)
      VALUES (auth.uid(), 'HAPUS_TUNGGAKAN_MANUAL', 'household_dues', v_due_id,
              COALESCE(p_notes, 'Hapus tagihan tahun ' || p_period_year::TEXT));
      RETURN NULL;
    END IF;

    v_final_due := GREATEST(p_amount_due, v_paid);
    UPDATE public.household_dues
    SET amount_due = v_final_due
    WHERE id = v_due_id;
  ELSE
    IF p_amount_due = 0 THEN
      RETURN NULL;
    END IF;
    INSERT INTO public.household_dues (
      household_id, fee_category_id, period_month, period_year, amount_due, created_by
    )
    VALUES (
      p_household_id, p_fee_category_id, 1, p_period_year, p_amount_due, auth.uid()
    )
    RETURNING id INTO v_due_id;
    v_final_due := p_amount_due;
  END IF;

  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, reason)
  VALUES (
    auth.uid(),
    'ATUR_TUNGGAKAN_MANUAL',
    'household_dues',
    v_due_id,
    'Tahun ' || p_period_year::TEXT || ' = Rp ' || v_final_due::TEXT ||
    CASE WHEN COALESCE(TRIM(p_notes), '') <> '' THEN ' (' || TRIM(p_notes) || ')' ELSE '' END
  );

  RETURN v_due_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_manual_household_due(UUID, UUID, INT, BIGINT, TEXT) TO authenticated;

-- 7. Sinkronisasi RLS & RPC Pembayaran agar menghormati custom_permissions Panel Developer
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
SET search_path = public
AS $$
DECLARE
  v_payment_id UUID;
  v_due_amount BIGINT;
  v_already_paid BIGINT;
  v_receipt TEXT;
BEGIN
  IF NOT public.user_has_permission('canPay') THEN
    RAISE EXCEPTION 'Akses ditolak untuk peran ini';
  END IF;

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
  WHERE pa.household_due_id = p_due_id AND p.status <> 'voided';

  IF p_amount <= 0 OR (v_already_paid + p_amount) > v_due_amount THEN
    RAISE EXCEPTION 'Nominal pembayaran melebihi sisa tagihan';
  END IF;

  v_receipt := 'KWT-' || TO_CHAR(NOW() AT TIME ZONE 'Asia/Jakarta', 'YYYYMMDD-HH24MISS');

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

GRANT EXECUTE ON FUNCTION public.record_payment_atomic(UUID, UUID, BIGINT, TEXT, TEXT, TEXT) TO authenticated;

DROP POLICY IF EXISTS "insert_households_authorized" ON public.households;
CREATE POLICY "insert_households_authorized" ON public.households FOR INSERT
  WITH CHECK (public.user_has_permission('canAddWarga'));

DROP POLICY IF EXISTS "insert_residents_authorized" ON public.residents;
CREATE POLICY "insert_residents_authorized" ON public.residents FOR INSERT
  WITH CHECK (public.user_has_permission('canAddWarga'));

DROP POLICY IF EXISTS "update_households_pakrt" ON public.households;
CREATE POLICY "update_households_pakrt" ON public.households FOR UPDATE
  USING (public.user_has_permission('canEditWarga'));

DROP POLICY IF EXISTS "update_residents_pakrt" ON public.residents;
CREATE POLICY "update_residents_pakrt" ON public.residents FOR UPDATE
  USING (public.user_has_permission('canEditWarga'));

DROP POLICY IF EXISTS "approve_cash_authorized" ON public.cash_transactions;
CREATE POLICY "approve_cash_authorized" ON public.cash_transactions FOR UPDATE
  USING (public.user_has_permission('canApprove'))
  WITH CHECK (public.user_has_permission('canApprove'));

-- 8. Perbaiki Security Advisor CRITICAL: Security Definer View pada v_residents_kk_ordered & search_path fungsi
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_views
    WHERE schemaname = 'public' AND viewname = 'v_residents_kk_ordered'
  ) THEN
    EXECUTE 'ALTER VIEW public.v_residents_kk_ordered SET (security_invoker = true)';
    EXECUTE 'REVOKE ALL ON public.v_residents_kk_ordered FROM anon';
    EXECUTE 'GRANT SELECT ON public.v_residents_kk_ordered TO authenticated';
  END IF;
  IF to_regprocedure('public.get_family_role_rank(text, text)') IS NOT NULL THEN
    EXECUTE 'ALTER FUNCTION public.get_family_role_rank(TEXT, TEXT) SET search_path = public';
  END IF;
  IF to_regprocedure('public.current_user_role()') IS NOT NULL THEN
    EXECUTE 'ALTER FUNCTION public.current_user_role() SET search_path = public';
  END IF;
END $$;

COMMIT;
