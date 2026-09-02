-- Enforce the withdrawal operating window in Nigeria time (Africa/Lagos).
-- 12:00:00 is inclusive; 17:00:00 is exclusive.
create or replace function public.request_withdrawal(
  p_user_id uuid,
  p_amount numeric,
  p_bank_name text,
  p_account_number text,
  p_account_name text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wallet public.wallets%rowtype;
  v_min numeric(18,2);
  v_max numeric(18,2);
  v_fee_percent numeric(7,4);
  v_fee numeric(18,2);
  v_net numeric(18,2);
  v_withdrawal_id uuid;
  v_requires_product boolean;
  v_requires_referral boolean;
  v_lagos_time time;
begin
  if auth.uid() is not null and auth.uid() <> p_user_id then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;

  v_lagos_time := (now() at time zone 'Africa/Lagos')::time;
  if v_lagos_time < time '12:00:00' or v_lagos_time >= time '17:00:00' then
    return jsonb_build_object(
      'ok', false,
      'error', 'withdrawal_window_closed',
      'opens_at', '12:00',
      'closes_at', '17:00',
      'timezone', 'Africa/Lagos'
    );
  end if;

  if coalesce(public.setting_value('withdrawals_locked', 'false') = 'true', false) then
    return jsonb_build_object('ok', false, 'error', 'withdrawals_locked');
  end if;

  v_min := coalesce(public.setting_value('min_withdraw', '1000')::numeric, 1000);
  v_max := coalesce(public.setting_value('max_withdraw', '0')::numeric, 0);
  if p_amount < v_min then
    return jsonb_build_object('ok', false, 'error', 'below_minimum', 'min', v_min);
  end if;
  if v_max > 0 and p_amount > v_max then
    return jsonb_build_object('ok', false, 'error', 'above_maximum', 'max', v_max);
  end if;

  v_requires_product := coalesce(public.setting_value('require_invest_before_withdraw', 'false') = 'true', false);
  if v_requires_product and not exists (
    select 1 from public.user_products where user_id = p_user_id and status = 'active'
  ) then
    return jsonb_build_object('ok', false, 'error', 'investment_required');
  end if;

  v_requires_referral := coalesce(public.setting_value('require_active_referral_to_withdraw', 'false') = 'true', false);
  if v_requires_referral and not exists (
    select 1
    from public.profiles p
    where p.referred_by = p_user_id
      and exists (select 1 from public.user_products up where up.user_id = p.id)
  ) then
    return jsonb_build_object('ok', false, 'error', 'active_referral_required');
  end if;

  select * into v_wallet from public.wallets where user_id = p_user_id for update;
  if not found or v_wallet.balance < p_amount then
    return jsonb_build_object('ok', false, 'error', 'insufficient_balance');
  end if;

  v_fee_percent := coalesce(public.setting_value('withdrawal_fee_percent', '0')::numeric, 0);
  v_fee := round(p_amount * v_fee_percent / 100, 2);
  v_net := p_amount - v_fee;

  update public.wallets set balance = balance - p_amount where user_id = p_user_id;

  insert into public.withdrawals (user_id, amount, fee_amount, net_amount, bank_name, account_number, account_name)
  values (p_user_id, p_amount, v_fee, v_net, trim(p_bank_name), trim(p_account_number), trim(p_account_name))
  returning id into v_withdrawal_id;

  insert into public.wallet_transactions (
    user_id, type, amount, balance_after, description, external_reference, metadata
  ) values (
    p_user_id, 'withdrawal_request', -p_amount, v_wallet.balance - p_amount,
    'Withdrawal request submitted', 'withdrawal:' || v_withdrawal_id::text,
    jsonb_build_object('withdrawal_id', v_withdrawal_id, 'fee_amount', v_fee, 'net_amount', v_net)
  );

  return jsonb_build_object('ok', true, 'withdrawal_id', v_withdrawal_id, 'amount', p_amount, 'fee', v_fee, 'net', v_net);
end;
$$;
