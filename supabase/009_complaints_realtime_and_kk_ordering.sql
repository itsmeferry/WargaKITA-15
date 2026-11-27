-- ============================================================================
-- WargaKITA RT 17 / RW 03 Kebonagung
-- Migration 009: Perapihan & Pengurutan Hierarki Data KK Berbasis Tanggal Lahir
--                serta Aktivasi Supabase Realtime Inti
-- Cara pakai: Copy seluruh script ini -> Paste ke Supabase SQL Editor -> Run
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. PERAPIHAN DATABASE DATA KK & HUBUNGAN KELUARGA
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_con_name TEXT;
BEGIN
  FOR v_con_name IN
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'public.residents'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%family_relationship%'
  LOOP
    EXECUTE format('ALTER TABLE public.residents DROP CONSTRAINT IF EXISTS %I', v_con_name);
  END LOOP;
END;
$$;

-- Rapikan spasi nama, nomor KK, NIK, telepon & alamat
UPDATE public.households
SET
  address = TRIM(regexp_replace(COALESCE(address, ''), '\s+', ' ', 'g')),
  household_number = TRIM(COALESCE(household_number, '')),
  updated_at = NOW()
WHERE address IS NOT NULL OR household_number IS NOT NULL;

UPDATE public.residents
SET
  full_name = TRIM(regexp_replace(COALESCE(full_name, ''), '\s+', ' ', 'g')),
  nik = NULLIF(TRIM(COALESCE(nik, '')), ''),
  phone = NULLIF(TRIM(COALESCE(phone, '')), ''),
  updated_at = NOW()
WHERE full_name IS NOT NULL;

-- Normalisasi penulisan variasi hubungan keluarga (termasuk "Orangtua", "Ayah/Ibu", dll.)
UPDATE public.residents
SET family_relationship = CASE
  WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(family_relationship, '')), '[\s_-]+', '', 'g')) IN ('kepalakeluarga', 'kk') THEN 'Kepala Keluarga'
  WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(family_relationship, '')), '[\s_-]+', '', 'g')) = 'suami' THEN 'Suami'
  WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(family_relationship, '')), '[\s_-]+', '', 'g')) = 'istri' THEN 'Istri'
  WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(family_relationship, '')), '[\s_-]+', '', 'g')) IN ('pasangan', 'istrisuami', 'suamiistri') THEN
    CASE WHEN gender = 'Perempuan' THEN 'Istri' WHEN gender = 'Laki-laki' THEN 'Suami' ELSE 'Pasangan' END
  WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(family_relationship, '')), '[\s_-]+', '', 'g')) LIKE 'anak%' THEN 'Anak'
  WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(family_relationship, '')), '[\s_-]+', '', 'g')) LIKE 'menantu%' THEN 'Menantu'
  WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(family_relationship, '')), '[\s_-]+', '', 'g')) LIKE 'cucu%' THEN 'Cucu'
  WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(family_relationship, '')), '[\s_-]+', '', 'g')) IN ('orangtualakilaki', 'ayah', 'bapak') THEN 'Orang Tua Laki-laki'
  WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(family_relationship, '')), '[\s_-]+', '', 'g')) IN ('orangtuaperempuan', 'ibu') THEN 'Orang Tua Perempuan'
  WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(family_relationship, '')), '[\s_-]+', '', 'g')) LIKE 'orangtua%' THEN
    CASE WHEN gender = 'Laki-laki' THEN 'Orang Tua Laki-laki' WHEN gender = 'Perempuan' THEN 'Orang Tua Perempuan' ELSE 'Orang Tua' END
  WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(family_relationship, '')), '[\s_-]+', '', 'g')) LIKE 'mertua%' THEN 'Mertua'
  WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(family_relationship, '')), '[\s_-]+', '', 'g')) IN ('famililain', 'saudara', 'kakak', 'adik', 'keponakan', 'paman', 'bibi', 'kakek', 'nenek') THEN 'Famili Lain'
  ELSE 'Lainnya'
END,
updated_at = NOW();

ALTER TABLE public.residents
  ADD CONSTRAINT residents_family_relationship_check
  CHECK (
    family_relationship IN (
      'Kepala Keluarga',
      'Suami',
      'Istri',
      'Pasangan',
      'Anak',
      'Orang Tua',
      'Orang Tua Laki-laki',
      'Orang Tua Perempuan',
      'Mertua',
      'Menantu',
      'Cucu',
      'Famili Lain',
      'Lainnya'
    )
  );

-- Sinkronisasi head_resident_id di tabel households ke Kepala Keluarga yang valid
UPDATE public.households h
SET head_resident_id = sub.head_id, updated_at = NOW()
FROM (
  SELECT DISTINCT ON (r.household_id)
    r.household_id,
    r.id AS head_id
  FROM public.residents r
  ORDER BY
    r.household_id,
    CASE WHEN r.is_active THEN 0 ELSE 1 END,
    CASE
      WHEN r.family_relationship = 'Kepala Keluarga' THEN 1
      WHEN r.family_relationship IN ('Suami','Istri','Pasangan') THEN 2
      ELSE 9
    END,
    r.birth_date ASC NULLS LAST,
    r.full_name ASC
) sub
WHERE h.id = sub.household_id
  AND h.head_resident_id IS DISTINCT FROM sub.head_id;

-- ----------------------------------------------------------------------------
-- 2. FUNGSI & VIEW URUTAN KK STANDAR (HIERARKI PERAN + TANGGAL LAHIR / NIK)
--    Urutan Resmi WargaKITA RT 17:
--    1. Kepala Keluarga
--    2. Suami / Istri / Pasangan
--    3. Anak (diurutkan tanggal lahir tertua -> termuda)
--    4. Menantu (tanggal lahir tertua -> termuda)
--    5. Cucu (tanggal lahir tertua -> termuda)
--    6. Orang Tua Laki-laki / Perempuan (tanggal lahir tertua -> termuda)
--    7. Mertua
--    8. Famili Lain
--    9. Lainnya
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_family_role_rank(p_rel TEXT, p_gender TEXT DEFAULT NULL)
RETURNS INT
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(p_rel, '')), '[\s_-]+', '', 'g')) IN ('kepalakeluarga', 'kk') THEN 1
    WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(p_rel, '')), '[\s_-]+', '', 'g')) IN ('suami', 'istri', 'pasangan', 'istrisuami', 'suamiistri') THEN 2
    WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(p_rel, '')), '[\s_-]+', '', 'g')) LIKE 'anak%' THEN 3
    WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(p_rel, '')), '[\s_-]+', '', 'g')) LIKE 'menantu%' THEN 4
    WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(p_rel, '')), '[\s_-]+', '', 'g')) LIKE 'cucu%' THEN 5
    WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(p_rel, '')), '[\s_-]+', '', 'g')) LIKE 'orangtua%'
      OR LOWER(REGEXP_REPLACE(TRIM(COALESCE(p_rel, '')), '[\s_-]+', '', 'g')) IN ('ayah', 'bapak', 'ibu') THEN 6
    WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(p_rel, '')), '[\s_-]+', '', 'g')) LIKE 'mertua%' THEN 7
    WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(p_rel, '')), '[\s_-]+', '', 'g')) IN ('famililain', 'saudara', 'kakak', 'adik', 'keponakan', 'paman', 'bibi', 'kakek', 'nenek') THEN 8
    ELSE 9
  END;
$$;

-- Lengkapi birth_date yang masih NULL secara aman dari 16-digit NIK (jika valid)
DO $$
DECLARE
  rec RECORD;
  v_dd INT;
  v_mm INT;
  v_yy INT;
  v_yyyy INT;
  v_cur_yy INT := (EXTRACT(YEAR FROM CURRENT_DATE)::INT % 100);
  v_rank INT;
  v_dob DATE;
BEGIN
  FOR rec IN
    SELECT id, nik, family_relationship, gender
    FROM public.residents
    WHERE birth_date IS NULL AND nik ~ '^\d{16}$'
  LOOP
    BEGIN
      v_dd := SUBSTRING(rec.nik FROM 7 FOR 2)::INT;
      v_mm := SUBSTRING(rec.nik FROM 9 FOR 2)::INT;
      v_yy := SUBSTRING(rec.nik FROM 11 FOR 2)::INT;
      IF v_dd > 40 THEN v_dd := v_dd - 40; END IF;
      IF v_dd BETWEEN 1 AND 31 AND v_mm BETWEEN 1 AND 12 THEN
        v_rank := public.get_family_role_rank(rec.family_relationship, rec.gender);
        IF v_yy > v_cur_yy THEN
          v_yyyy := 1900 + v_yy;
        ELSIF (2000 + v_yy) > (EXTRACT(YEAR FROM CURRENT_DATE)::INT - 20) AND v_rank IN (1, 2, 6, 7) THEN
          v_yyyy := 1900 + v_yy;
        ELSE
          v_yyyy := 2000 + v_yy;
        END IF;
        v_dob := make_date(v_yyyy, v_mm, v_dd);
        UPDATE public.residents SET birth_date = v_dob, updated_at = NOW() WHERE id = rec.id;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
END;
$$;

DROP VIEW IF EXISTS public.v_residents_kk_ordered;

CREATE VIEW public.v_residents_kk_ordered
WITH (security_invoker = true) AS
SELECT
  r.*,
  h.household_number,
  h.address AS household_address,
  h.residence_status,
  CASE
    WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(r.family_relationship, '')), '[\s_-]+', '', 'g')) IN ('kepalakeluarga', 'kk') THEN 'Kepala Keluarga'
    WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(r.family_relationship, '')), '[\s_-]+', '', 'g')) IN ('orangtualakilaki', 'ayah', 'bapak') THEN 'Orang Tua Laki-laki'
    WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(r.family_relationship, '')), '[\s_-]+', '', 'g')) IN ('orangtuaperempuan', 'ibu') THEN 'Orang Tua Perempuan'
    WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(r.family_relationship, '')), '[\s_-]+', '', 'g')) = 'orangtua' AND r.gender = 'Laki-laki' THEN 'Orang Tua Laki-laki'
    WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(r.family_relationship, '')), '[\s_-]+', '', 'g')) = 'orangtua' AND r.gender = 'Perempuan' THEN 'Orang Tua Perempuan'
    WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(r.family_relationship, '')), '[\s_-]+', '', 'g')) = 'pasangan' AND r.gender = 'Perempuan' THEN 'Istri'
    WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(r.family_relationship, '')), '[\s_-]+', '', 'g')) = 'pasangan' AND r.gender = 'Laki-laki' THEN 'Suami'
    WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(r.family_relationship, '')), '[\s_-]+', '', 'g')) = 'famililain' THEN 'Famili Lain'
    ELSE r.family_relationship
  END AS display_relationship,
  public.get_family_role_rank(r.family_relationship, r.gender) AS kk_role_rank,
  ROW_NUMBER() OVER (
    PARTITION BY r.household_id
    ORDER BY
      public.get_family_role_rank(r.family_relationship, r.gender) ASC,
      CASE
        WHEN LOWER(TRIM(COALESCE(r.family_relationship, ''))) = 'suami' THEN 1
        WHEN LOWER(TRIM(COALESCE(r.family_relationship, ''))) = 'istri' THEN 2
        WHEN LOWER(TRIM(COALESCE(r.family_relationship, ''))) = 'pasangan' THEN 3
        ELSE 0
      END ASC,
      r.birth_date ASC NULLS LAST,
      CASE
        WHEN LOWER(REGEXP_REPLACE(TRIM(COALESCE(r.family_relationship, '')), '[\s_-]+', '', 'g')) LIKE 'orangtua%'
          OR LOWER(REGEXP_REPLACE(TRIM(COALESCE(r.family_relationship, '')), '[\s_-]+', '', 'g')) LIKE 'mertua%'
        THEN CASE WHEN r.gender = 'Laki-laki' THEN 0 WHEN r.gender = 'Perempuan' THEN 1 ELSE 2 END
        ELSE 0
      END ASC,
      r.full_name ASC
  ) AS kk_member_order
FROM public.residents r
JOIN public.households h ON h.id = r.household_id;

REVOKE ALL ON public.v_residents_kk_ordered FROM anon;
GRANT SELECT ON public.v_residents_kk_ordered TO authenticated;

CREATE INDEX IF NOT EXISTS idx_residents_kk_hierarchy_dob
  ON public.residents (household_id, family_relationship, birth_date ASC NULLS LAST, full_name ASC);

-- ----------------------------------------------------------------------------
-- 3. AKTIFKAN SUPABASE REALTIME PUBLICATION (DATA INTI WARGAKITA)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_tbl TEXT;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    FOREACH v_tbl IN ARRAY ARRAY[
      'cash_transactions',
      'payments',
      'households',
      'residents',
      'community_events'
    ]
    LOOP
      BEGIN
        EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', v_tbl);
      EXCEPTION WHEN duplicate_object THEN
        NULL;
      END;
    END LOOP;
  END IF;
END;
$$;

ANALYZE public.households;
ANALYZE public.residents;

COMMIT;
