-- Alinco Oil package-income repair
-- Run once in Supabase SQL Editor after alinco_oil_setup.sql and prior repairs.
-- This adds the missing due-income collector used by the package page/API.

begin;

create or replace function public.collect_package_income_for_user(
  p_user_id uuid,
  p_collection_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wallet public.wallets%rowtype;
  v_package public.user_products%rowtype;
  v_amount numeric(18,2);
  v_balance numeric(18,2);
  v_collected integer := 0;
  v_total numeric(18,2) := 0;
  v_reference text;
  v_inserted uuid;
  v_credit_date date;
begin
  if p_user_id is null then
    return jsonb_build_object('ok', false, 'error', 'user_id_required');
  end if;

  insert into public.wallets(user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;

  select * into v_wallet
  from public.wallets
  where user_id = p_user_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'wallet_not_found');
  end if;

  for v_package in
    select *
    from public.user_products
    where user_id = p_user_id
      and status = 'active'
      and next_collection_on <= p_collection_date
      and days_collected < duration_days
    order by next_collection_on, created_at
    for update
  loop
    v_amount := round(coalesce(v_package.daily_income, 0), 2);

    while v_package.next_collection_on <= p_collection_date
      and v_package.days_collected < v_package.duration_days
    loop
      v_credit_date := v_package.next_collection_on;
      v_reference := 'daily-income:' || v_package.id::text || ':' || v_credit_date::text;
      v_inserted := null;

      if v_amount > 0 then
        -- The unique reference makes retries safe. Only a newly inserted ledger
        -- row is allowed to change the wallet and package totals.
        insert into public.wallet_transactions (
          user_id, type, amount, description, external_reference, metadata
        ) values (
          p_user_id,
          'daily_income',
          v_amount,
          'Package income: ' || v_package.id::text,
          v_reference,
          jsonb_build_object('user_product_id', v_package.id, 'collection_date', v_credit_date)
        )
        on conflict (external_reference) do nothing
        returning id into v_inserted;
      end if;

      if v_inserted is not null then
        v_balance := v_wallet.balance + v_amount;
        update public.wallets
        set balance = v_balance,
            total_profit = total_profit + v_amount
        where user_id = p_user_id;

        update public.wallet_transactions
        set balance_after = v_balance
        where id = v_inserted;

        v_wallet.balance := v_balance;
        v_collected := v_collected + 1;
        v_total := v_total + v_amount;
      end if;

      -- Advance state for both a new credit and a previously recorded credit.
      -- This also repairs a retry interrupted after the ledger insert.
      update public.user_products
      set days_collected = days_collected + 1,
          total_collected = total_collected + case when v_inserted is not null then v_amount else 0 end,
          last_collected_on = v_credit_date,
          next_collection_on = v_credit_date + 1,
          status = case when days_collected + 1 >= duration_days then 'completed' else status end,
          completed_at = case when days_collected + 1 >= duration_days then coalesce(completed_at, timezone('utc', now())) else completed_at end
      where id = v_package.id;

      v_package.days_collected := v_package.days_collected + 1;
      v_package.total_collected := v_package.total_collected + case when v_inserted is not null then v_amount else 0 end;
      v_package.last_collected_on := v_credit_date;
      v_package.next_collection_on := v_credit_date + 1;
      if v_package.days_collected >= v_package.duration_days then
        v_package.status := 'completed';
      end if;
    end loop;
  end loop;

  return jsonb_build_object('ok', true, 'amount', v_total, 'packages', v_collected, 'date', p_collection_date);
end;
$$;

drop function if exists public.collect_due_package_income(date);

create or replace function public.collect_due_package_income(p_collection_date date default current_date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user record;
  v_result jsonb;
  v_users integer := 0;
  v_amount numeric(18,2) := 0;
  v_packages integer := 0;
begin
  for v_user in
    select distinct user_id
    from public.user_products
    where status = 'active'
      and next_collection_on <= p_collection_date
      and days_collected < duration_days
  loop
    v_result := public.collect_package_income_for_user(v_user.user_id, p_collection_date);
    if coalesce((v_result->>'ok')::boolean, false) then
      v_users := v_users + case when coalesce((v_result->>'packages')::integer, 0) > 0 then 1 else 0 end;
      v_amount := v_amount + coalesce((v_result->>'amount')::numeric, 0);
      v_packages := v_packages + coalesce((v_result->>'packages')::integer, 0);
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'users', v_users, 'packages', v_packages, 'amount', v_amount, 'date', p_collection_date);
end;
$$;

revoke all on function public.collect_package_income_for_user(uuid, date) from public;
revoke all on function public.collect_due_package_income(date) from public;
grant execute on function public.collect_package_income_for_user(uuid, date) to service_role;
grant execute on function public.collect_due_package_income(date) to service_role;

commit;
