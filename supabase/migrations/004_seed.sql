-- 4 Kategori Iuran Awal WargaKITA
INSERT INTO public.fee_categories (name, default_amount, allow_partial, is_active) VALUES
  ('Pembangunan + Voging', 50000, TRUE, TRUE),
  ('Rukem + Juri Kunci', 30000, TRUE, TRUE),
  ('Keuangan Social', 20000, TRUE, TRUE),
  ('17 Agustus', 15000, TRUE, TRUE)
ON CONFLICT (name) DO NOTHING;
