-- Migration 006: Izinkan Role wakil_rt untuk Approve/Reject Transaksi & Lihat Data Persetujuan (sama seperti pak_rt)
BEGIN;

-- 1. Cash transactions: izinkan pak_rt, wakil_rt, developer_admin melakukan UPDATE approval_status
DROP POLICY IF EXISTS "approve_cash_authorized" ON public.cash_transactions;
CREATE POLICY "approve_cash_authorized" ON public.cash_transactions
  FOR UPDATE
  USING (public.current_user_role() IN ('pak_rt','wakil_rt','developer_admin'))
  WITH CHECK (public.current_user_role() IN ('pak_rt','wakil_rt','developer_admin'));

-- 2. Payments: izinkan wakil_rt membaca data pembayaran agar sinkron saat approval
DROP POLICY IF EXISTS "read_payments" ON public.payments;
CREATE POLICY "read_payments" ON public.payments
  FOR SELECT
  USING (public.current_user_role() IN ('pak_rt','wakil_rt','bendahara_rt','developer_admin'));

-- 3. Audit logs: izinkan wakil_rt membaca & mencatat log approval
DROP POLICY IF EXISTS "read_audit_logs" ON public.audit_logs;
CREATE POLICY "read_audit_logs" ON public.audit_logs
  FOR SELECT
  USING (public.current_user_role() IN ('pak_rt','wakil_rt','developer_admin'));

COMMIT;
