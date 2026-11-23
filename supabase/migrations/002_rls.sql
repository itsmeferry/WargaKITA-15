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
