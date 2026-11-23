-- Migration 007: Klasifikasi Iuran RT 17 (Reguler, Janda Rukem Saja, Kost Gratis, Nonaktif) + Auto-Generate Bulan/Tahun Baru
BEGIN;

-- 1. RPC Auto-Generate Tagihan Periode (Bulan/Tahun) sesuai Aturan RT 17
CREATE OR REPLACE FUNCTION public.ensure_period_dues(p_month INT, p_year INT)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
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

  -- A. KK Klasifikasi Point 2 (Janda): HANYA wajib Rukem + Juru Kunci
  IF v_rukem_id IS NOT NULL THEN
    INSERT INTO public.household_dues (
      household_id, fee_category_id, period_month, period_year, amount_due
    )
    SELECT h.id, fc.id, p_month, p_year, fc.default_amount
    FROM public.households h
    JOIN public.fee_categories fc ON fc.id = v_rukem_id
    WHERE h.is_active = TRUE
      AND COALESCE(h.residence_status, 'Permanen') NOT IN ('Kost', 'Pindah')
      AND EXISTS (SELECT 1 FROM public.residents r WHERE r.household_id = h.id AND r.is_active = TRUE)
      AND (
        COALESCE(h.notes, '') ILIKE '%[TIPE:JANDA]%'
        OR EXISTS (SELECT 1 FROM public.residents r WHERE r.household_id = h.id AND r.is_active = TRUE AND COALESCE(r.notes, '') ILIKE '%janda%')
      )
    ON CONFLICT (household_id, fee_category_id, period_month, period_year) DO NOTHING;
    GET DIAGNOSTICS v_count_step = ROW_COUNT;
    v_inserted := v_inserted + v_count_step;
  END IF;

  -- B. KK Klasifikasi Point 1 (Reguler): Wajib Penuh 4 Kategori
  INSERT INTO public.household_dues (
    household_id, fee_category_id, period_month, period_year, amount_due
  )
  SELECT h.id, fc.id, p_month, p_year, fc.default_amount
  FROM public.households h
  CROSS JOIN public.fee_categories fc
  WHERE fc.is_active = TRUE
    AND h.is_active = TRUE
    AND COALESCE(h.residence_status, 'Permanen') NOT IN ('Kost', 'Pindah')
    AND EXISTS (SELECT 1 FROM public.residents r WHERE r.household_id = h.id AND r.is_active = TRUE)
    AND NOT (
      COALESCE(h.notes, '') ILIKE '%[TIPE:JANDA]%'
      OR EXISTS (SELECT 1 FROM public.residents r WHERE r.household_id = h.id AND r.is_active = TRUE AND COALESCE(r.notes, '') ILIKE '%janda%')
    )
  ON CONFLICT (household_id, fee_category_id, period_month, period_year) DO NOTHING;
  GET DIAGNOSTICS v_count_step = ROW_COUNT;
  v_inserted := v_inserted + v_count_step;

  RETURN v_inserted;
END;
$$;

-- 2. Perbarui Trigger KK Baru agar menghormati Kost (Point 3) & Janda Rukem Saja (Point 2)
CREATE OR REPLACE FUNCTION public.fn_auto_create_dues_for_new_household()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_month INT := EXTRACT(MONTH FROM (NOW() AT TIME ZONE 'Asia/Jakarta'))::INT;
  v_year  INT := EXTRACT(YEAR  FROM (NOW() AT TIME ZONE 'Asia/Jakarta'))::INT;
BEGIN
  IF NEW.is_active = TRUE AND COALESCE(NEW.residence_status, 'Permanen') NOT IN ('Kost', 'Pindah') THEN
    IF COALESCE(NEW.notes, '') ILIKE '%[TIPE:JANDA]%' THEN
      INSERT INTO public.household_dues (household_id, fee_category_id, period_month, period_year, amount_due)
      SELECT NEW.id, fc.id, v_month, v_year, fc.default_amount
      FROM public.fee_categories fc
      WHERE fc.is_active = TRUE AND LOWER(fc.name) LIKE '%rukem%'
      ON CONFLICT (household_id, fee_category_id, period_month, period_year) DO NOTHING;
    ELSE
      INSERT INTO public.household_dues (household_id, fee_category_id, period_month, period_year, amount_due)
      SELECT NEW.id, fc.id, v_month, v_year, fc.default_amount
      FROM public.fee_categories fc
      WHERE fc.is_active = TRUE
      ON CONFLICT (household_id, fee_category_id, period_month, period_year) DO NOTHING;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- 3. Terapkan langsung aturan Point 2 (Rukem Saja) ke KK Janda yang sudah ada (seperti YAYUK KUWATIN)
UPDATE public.households h
SET notes = TRIM(COALESCE(h.notes, '') || ' [TIPE:JANDA]')
WHERE COALESCE(h.notes, '') NOT ILIKE '%[TIPE:JANDA]%'
  AND EXISTS (
    SELECT 1 FROM public.residents r
    WHERE r.household_id = h.id AND r.is_active = TRUE AND COALESCE(r.notes, '') ILIKE '%janda%'
  );

DELETE FROM public.household_dues d
USING public.households h, public.fee_categories fc
WHERE d.household_id = h.id
  AND d.fee_category_id = fc.id
  AND LOWER(fc.name) NOT LIKE '%rukem%'
  AND (
    COALESCE(h.notes, '') ILIKE '%[TIPE:JANDA]%'
    OR EXISTS (SELECT 1 FROM public.residents r WHERE r.household_id = h.id AND r.is_active = TRUE AND COALESCE(r.notes, '') ILIKE '%janda%')
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.payment_allocations pa WHERE pa.household_due_id = d.id
  );

COMMIT;
