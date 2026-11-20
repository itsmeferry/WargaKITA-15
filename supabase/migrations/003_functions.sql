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
