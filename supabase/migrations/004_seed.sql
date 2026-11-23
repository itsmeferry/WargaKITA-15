-- 4 Kategori Iuran Tahunan WargaKITA RT 17 (Total Rp 138.000 / Tahun)
INSERT INTO public.fee_categories (name, default_amount, allow_partial, is_active) VALUES
  ('Pembangunan + Fogging', 36000, TRUE, TRUE),
  ('Rukem + Juru Kunci', 42000, TRUE, TRUE),
  ('Keuangan Social', 30000, TRUE, TRUE),
  ('17 Agustus', 30000, TRUE, TRUE)
ON CONFLICT (name) DO NOTHING;
