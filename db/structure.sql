SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: ledger_journal_entries_reject_mutations(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ledger_journal_entries_reject_mutations() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'journal_entries are append-only (immutable)';
  END IF;
  IF TG_OP = 'UPDATE' THEN
    IF OLD.reversing_journal_entry_id IS NULL
       AND NEW.reversing_journal_entry_id IS NOT NULL
       AND OLD.id = NEW.id
       AND OLD.posting_batch_id IS NOT DISTINCT FROM NEW.posting_batch_id
       AND OLD.operational_event_id IS NOT DISTINCT FROM NEW.operational_event_id
       AND OLD.business_date IS NOT DISTINCT FROM NEW.business_date
       AND OLD.currency IS NOT DISTINCT FROM NEW.currency
       AND OLD.narrative IS NOT DISTINCT FROM NEW.narrative
       AND OLD.effective_at IS NOT DISTINCT FROM NEW.effective_at
       AND OLD.status IS NOT DISTINCT FROM NEW.status
       AND OLD.reverses_journal_entry_id IS NOT DISTINCT FROM NEW.reverses_journal_entry_id
       AND OLD.created_at IS NOT DISTINCT FROM NEW.created_at
    THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'journal_entries are append-only (immutable)';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: ledger_journal_lines_reject_mutations(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ledger_journal_lines_reject_mutations() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'UPDATE' OR TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'journal_lines are append-only (immutable)';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: ledger_validate_journal_entry_balanced(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ledger_validate_journal_entry_balanced() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  jid bigint;
  sum_debits bigint;
  sum_credits bigint;
BEGIN
  IF TG_OP = 'DELETE' THEN
    jid := OLD.journal_entry_id;
  ELSE
    jid := NEW.journal_entry_id;
  END IF;

  SELECT
    COALESCE(SUM(amount_minor_units) FILTER (WHERE side = 'debit'), 0),
    COALESCE(SUM(amount_minor_units) FILTER (WHERE side = 'credit'), 0)
  INTO sum_debits, sum_credits
  FROM journal_lines
  WHERE journal_entry_id = jid;

  IF sum_debits != sum_credits THEN
    RAISE EXCEPTION 'Journal entry % is not balanced (debits % vs credits %)',
      jid, sum_debits, sum_credits;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: account_lifecycle_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.account_lifecycle_events (
    id bigint NOT NULL,
    deposit_account_id bigint NOT NULL,
    action character varying NOT NULL,
    channel character varying NOT NULL,
    idempotency_key character varying NOT NULL,
    business_date date NOT NULL,
    actor_id bigint NOT NULL,
    operational_event_id bigint,
    reason_code character varying NOT NULL,
    reason_description text,
    effective_on date NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT account_lifecycle_events_action_check CHECK (((action)::text = 'closed'::text)),
    CONSTRAINT account_lifecycle_events_channel_check CHECK (((channel)::text = 'branch'::text))
);


--
-- Name: account_lifecycle_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.account_lifecycle_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: account_lifecycle_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.account_lifecycle_events_id_seq OWNED BY public.account_lifecycle_events.id;


--
-- Name: account_restrictions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.account_restrictions (
    id bigint NOT NULL,
    deposit_account_id bigint NOT NULL,
    restriction_type character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    channel character varying NOT NULL,
    idempotency_key character varying NOT NULL,
    business_date date NOT NULL,
    actor_id bigint NOT NULL,
    released_by_actor_id bigint,
    restricted_operational_event_id bigint,
    unrestricted_operational_event_id bigint,
    reason_code character varying NOT NULL,
    reason_description text,
    effective_on date NOT NULL,
    released_on date,
    release_idempotency_key character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT account_restrictions_channel_check CHECK (((channel)::text = 'branch'::text)),
    CONSTRAINT account_restrictions_release_fields_check CHECK ((((status)::text <> 'released'::text) OR ((released_on IS NOT NULL) AND (released_by_actor_id IS NOT NULL)))),
    CONSTRAINT account_restrictions_status_check CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'released'::character varying])::text[]))),
    CONSTRAINT account_restrictions_type_check CHECK (((restriction_type)::text = ANY ((ARRAY['debit_block'::character varying, 'full_freeze'::character varying, 'close_block'::character varying, 'watch_only'::character varying])::text[])))
);


--
-- Name: account_restrictions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.account_restrictions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: account_restrictions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.account_restrictions_id_seq OWNED BY public.account_restrictions.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: capabilities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.capabilities (
    id bigint NOT NULL,
    code character varying NOT NULL,
    name character varying NOT NULL,
    description text,
    category character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT capabilities_category_present_check CHECK ((btrim((category)::text) <> ''::text)),
    CONSTRAINT capabilities_code_present_check CHECK ((btrim((code)::text) <> ''::text)),
    CONSTRAINT capabilities_name_present_check CHECK ((btrim((name)::text) <> ''::text))
);


--
-- Name: capabilities_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.capabilities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: capabilities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.capabilities_id_seq OWNED BY public.capabilities.id;


--
-- Name: cash_balances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cash_balances (
    id bigint NOT NULL,
    cash_location_id bigint NOT NULL,
    currency character varying DEFAULT 'USD'::character varying NOT NULL,
    amount_minor_units bigint DEFAULT 0 NOT NULL,
    last_cash_movement_id bigint,
    last_cash_count_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT cash_balances_currency_usd_check CHECK (((currency)::text = 'USD'::text))
);


--
-- Name: cash_balances_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cash_balances_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cash_balances_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cash_balances_id_seq OWNED BY public.cash_balances.id;


--
-- Name: cash_counts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cash_counts (
    id bigint NOT NULL,
    cash_location_id bigint NOT NULL,
    operating_unit_id bigint NOT NULL,
    actor_id bigint NOT NULL,
    operational_event_id bigint,
    counted_amount_minor_units bigint NOT NULL,
    expected_amount_minor_units bigint NOT NULL,
    currency character varying DEFAULT 'USD'::character varying NOT NULL,
    business_date date NOT NULL,
    status character varying DEFAULT 'recorded'::character varying NOT NULL,
    idempotency_key character varying NOT NULL,
    request_fingerprint character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT cash_counts_currency_usd_check CHECK (((currency)::text = 'USD'::text)),
    CONSTRAINT cash_counts_nonnegative_counted_check CHECK ((counted_amount_minor_units >= 0)),
    CONSTRAINT cash_counts_nonnegative_expected_check CHECK ((expected_amount_minor_units >= 0)),
    CONSTRAINT cash_counts_status_check CHECK (((status)::text = 'recorded'::text))
);


--
-- Name: cash_counts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cash_counts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cash_counts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cash_counts_id_seq OWNED BY public.cash_counts.id;


--
-- Name: cash_locations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cash_locations (
    id bigint NOT NULL,
    location_type character varying NOT NULL,
    operating_unit_id bigint NOT NULL,
    responsible_operator_id bigint,
    parent_cash_location_id bigint,
    drawer_code character varying,
    name character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    currency character varying DEFAULT 'USD'::character varying NOT NULL,
    balancing_required boolean DEFAULT true NOT NULL,
    external_reference character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT cash_locations_currency_usd_check CHECK (((currency)::text = 'USD'::text)),
    CONSTRAINT cash_locations_parent_not_self_check CHECK (((parent_cash_location_id IS NULL) OR (parent_cash_location_id <> id))),
    CONSTRAINT cash_locations_status_check CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('inactive'::character varying)::text]))),
    CONSTRAINT cash_locations_type_check CHECK (((location_type)::text = ANY (ARRAY[('branch_vault'::character varying)::text, ('teller_drawer'::character varying)::text, ('internal_transit'::character varying)::text])))
);


--
-- Name: cash_locations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cash_locations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cash_locations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cash_locations_id_seq OWNED BY public.cash_locations.id;


--
-- Name: cash_movements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cash_movements (
    id bigint NOT NULL,
    source_cash_location_id bigint,
    destination_cash_location_id bigint,
    operating_unit_id bigint NOT NULL,
    actor_id bigint NOT NULL,
    approving_actor_id bigint,
    operational_event_id bigint,
    amount_minor_units bigint NOT NULL,
    currency character varying DEFAULT 'USD'::character varying NOT NULL,
    business_date date NOT NULL,
    status character varying DEFAULT 'completed'::character varying NOT NULL,
    movement_type character varying NOT NULL,
    reason_code character varying,
    idempotency_key character varying NOT NULL,
    request_fingerprint character varying NOT NULL,
    approved_at timestamp(6) without time zone,
    completed_at timestamp(6) without time zone,
    cancelled_at timestamp(6) without time zone,
    rejected_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    external_source character varying,
    shipment_reference character varying,
    CONSTRAINT cash_movements_currency_usd_check CHECK (((currency)::text = 'USD'::text)),
    CONSTRAINT cash_movements_external_shipment_required_fields_check CHECK ((((movement_type)::text <> 'external_shipment_received'::text) OR ((source_cash_location_id IS NULL) AND (destination_cash_location_id IS NOT NULL) AND (external_source IS NOT NULL) AND (length(TRIM(BOTH FROM external_source)) > 0) AND (shipment_reference IS NOT NULL) AND (length(TRIM(BOTH FROM shipment_reference)) > 0)))),
    CONSTRAINT cash_movements_location_present_check CHECK (((source_cash_location_id IS NOT NULL) OR (destination_cash_location_id IS NOT NULL))),
    CONSTRAINT cash_movements_positive_amount_check CHECK ((amount_minor_units > 0)),
    CONSTRAINT cash_movements_status_check CHECK (((status)::text = ANY (ARRAY[('pending_approval'::character varying)::text, ('approved'::character varying)::text, ('completed'::character varying)::text, ('cancelled'::character varying)::text, ('rejected'::character varying)::text]))),
    CONSTRAINT cash_movements_type_check CHECK (((movement_type)::text = ANY (ARRAY[('vault_to_drawer'::character varying)::text, ('drawer_to_vault'::character varying)::text, ('internal_transfer'::character varying)::text, ('adjustment'::character varying)::text, ('external_shipment_received'::character varying)::text])))
);


--
-- Name: cash_movements_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cash_movements_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cash_movements_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cash_movements_id_seq OWNED BY public.cash_movements.id;


--
-- Name: cash_variances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cash_variances (
    id bigint NOT NULL,
    cash_location_id bigint NOT NULL,
    cash_count_id bigint NOT NULL,
    operating_unit_id bigint NOT NULL,
    actor_id bigint NOT NULL,
    approving_actor_id bigint,
    cash_variance_posted_event_id bigint,
    amount_minor_units bigint NOT NULL,
    currency character varying DEFAULT 'USD'::character varying NOT NULL,
    business_date date NOT NULL,
    status character varying DEFAULT 'pending_approval'::character varying NOT NULL,
    approved_at timestamp(6) without time zone,
    posted_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT cash_variances_currency_usd_check CHECK (((currency)::text = 'USD'::text)),
    CONSTRAINT cash_variances_nonzero_amount_check CHECK ((amount_minor_units <> 0)),
    CONSTRAINT cash_variances_status_check CHECK (((status)::text = ANY (ARRAY[('pending_approval'::character varying)::text, ('approved'::character varying)::text, ('posted'::character varying)::text])))
);


--
-- Name: cash_variances_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cash_variances_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cash_variances_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cash_variances_id_seq OWNED BY public.cash_variances.id;


--
-- Name: core_business_date_close_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.core_business_date_close_events (
    id bigint NOT NULL,
    closed_on date NOT NULL,
    closed_at timestamp(6) without time zone NOT NULL,
    closed_by_operator_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: core_business_date_close_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.core_business_date_close_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: core_business_date_close_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.core_business_date_close_events_id_seq OWNED BY public.core_business_date_close_events.id;


--
-- Name: core_business_date_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.core_business_date_settings (
    id bigint NOT NULL,
    current_business_on date NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: core_business_date_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.core_business_date_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: core_business_date_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.core_business_date_settings_id_seq OWNED BY public.core_business_date_settings.id;


--
-- Name: deposit_account_balance_projections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposit_account_balance_projections (
    id bigint NOT NULL,
    deposit_account_id bigint NOT NULL,
    ledger_balance_minor_units bigint DEFAULT 0 NOT NULL,
    hold_balance_minor_units bigint DEFAULT 0 NOT NULL,
    available_balance_minor_units bigint DEFAULT 0 NOT NULL,
    collected_balance_minor_units bigint,
    last_journal_entry_id bigint,
    last_operational_event_id bigint,
    as_of_business_date date,
    last_calculated_at timestamp(6) without time zone,
    stale boolean DEFAULT false NOT NULL,
    stale_from_date date,
    calculation_version integer DEFAULT 1 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_deposit_balance_proj_calculation_version_positive CHECK ((calculation_version > 0)),
    CONSTRAINT chk_deposit_balance_proj_hold_non_negative CHECK ((hold_balance_minor_units >= 0))
);


--
-- Name: deposit_account_balance_projections_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.deposit_account_balance_projections_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: deposit_account_balance_projections_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.deposit_account_balance_projections_id_seq OWNED BY public.deposit_account_balance_projections.id;


--
-- Name: deposit_account_number_allocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposit_account_number_allocations (
    id bigint NOT NULL,
    allocation_key character varying NOT NULL,
    last_sequence integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_deposit_account_number_allocations_sequence_range CHECK (((last_sequence >= 0) AND (last_sequence <= 999999)))
);


--
-- Name: deposit_account_number_allocations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.deposit_account_number_allocations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: deposit_account_number_allocations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.deposit_account_number_allocations_id_seq OWNED BY public.deposit_account_number_allocations.id;


--
-- Name: deposit_account_parties; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposit_account_parties (
    id bigint NOT NULL,
    deposit_account_id bigint NOT NULL,
    party_record_id bigint NOT NULL,
    role character varying NOT NULL,
    status character varying NOT NULL,
    effective_on date NOT NULL,
    ended_on date,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: deposit_account_parties_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.deposit_account_parties_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: deposit_account_parties_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.deposit_account_parties_id_seq OWNED BY public.deposit_account_parties.id;


--
-- Name: deposit_account_party_maintenance_audits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposit_account_party_maintenance_audits (
    id bigint NOT NULL,
    action character varying NOT NULL,
    channel character varying NOT NULL,
    idempotency_key character varying NOT NULL,
    business_date date NOT NULL,
    deposit_account_id bigint NOT NULL,
    party_record_id bigint NOT NULL,
    deposit_account_party_id bigint NOT NULL,
    actor_id bigint NOT NULL,
    role character varying NOT NULL,
    effective_on date NOT NULL,
    ended_on date,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT dap_maintenance_audits_action_check CHECK (((action)::text = ANY (ARRAY[('authorized_signer.added'::character varying)::text, ('authorized_signer.ended'::character varying)::text]))),
    CONSTRAINT dap_maintenance_audits_channel_check CHECK (((channel)::text = 'branch'::text)),
    CONSTRAINT dap_maintenance_audits_role_check CHECK (((role)::text = 'authorized_signer'::text))
);


--
-- Name: deposit_account_party_maintenance_audits_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.deposit_account_party_maintenance_audits_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: deposit_account_party_maintenance_audits_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.deposit_account_party_maintenance_audits_id_seq OWNED BY public.deposit_account_party_maintenance_audits.id;


--
-- Name: deposit_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposit_accounts (
    id bigint NOT NULL,
    account_number character varying NOT NULL,
    currency character varying DEFAULT 'USD'::character varying NOT NULL,
    status character varying NOT NULL,
    product_code character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    deposit_product_id bigint NOT NULL,
    CONSTRAINT chk_deposit_accounts_account_number_12_digits CHECK (((account_number)::text ~ '^1[0-9]{11}$'::text))
);


--
-- Name: deposit_accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.deposit_accounts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: deposit_accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.deposit_accounts_id_seq OWNED BY public.deposit_accounts.id;


--
-- Name: deposit_product_fee_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposit_product_fee_rules (
    id bigint NOT NULL,
    deposit_product_id bigint NOT NULL,
    fee_code character varying NOT NULL,
    amount_minor_units bigint NOT NULL,
    currency character varying DEFAULT 'USD'::character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    effective_on date NOT NULL,
    ended_on date,
    description character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT deposit_product_fee_rules_amount_positive CHECK ((amount_minor_units > 0)),
    CONSTRAINT deposit_product_fee_rules_ended_on_after_effective_on CHECK (((ended_on IS NULL) OR (ended_on >= effective_on))),
    CONSTRAINT deposit_product_fee_rules_status_enum CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('inactive'::character varying)::text])))
);


--
-- Name: deposit_product_fee_rules_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.deposit_product_fee_rules_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: deposit_product_fee_rules_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.deposit_product_fee_rules_id_seq OWNED BY public.deposit_product_fee_rules.id;


--
-- Name: deposit_product_overdraft_policies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposit_product_overdraft_policies (
    id bigint NOT NULL,
    deposit_product_id bigint NOT NULL,
    mode character varying NOT NULL,
    nsf_fee_minor_units bigint NOT NULL,
    currency character varying DEFAULT 'USD'::character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    effective_on date NOT NULL,
    ended_on date,
    description character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT deposit_product_od_policies_ended_on_after_effective_on CHECK (((ended_on IS NULL) OR (ended_on >= effective_on))),
    CONSTRAINT deposit_product_od_policies_mode_enum CHECK (((mode)::text = 'deny_nsf'::text)),
    CONSTRAINT deposit_product_od_policies_nsf_fee_positive CHECK ((nsf_fee_minor_units > 0)),
    CONSTRAINT deposit_product_od_policies_status_enum CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('inactive'::character varying)::text])))
);


--
-- Name: deposit_product_overdraft_policies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.deposit_product_overdraft_policies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: deposit_product_overdraft_policies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.deposit_product_overdraft_policies_id_seq OWNED BY public.deposit_product_overdraft_policies.id;


--
-- Name: deposit_product_statement_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposit_product_statement_profiles (
    id bigint NOT NULL,
    deposit_product_id bigint NOT NULL,
    frequency character varying NOT NULL,
    cycle_day integer NOT NULL,
    currency character varying DEFAULT 'USD'::character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    effective_on date NOT NULL,
    ended_on date,
    description character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT deposit_product_statement_profiles_cycle_day_range CHECK (((cycle_day >= 1) AND (cycle_day <= 31))),
    CONSTRAINT deposit_product_statement_profiles_ended_on_after_effective_on CHECK (((ended_on IS NULL) OR (ended_on >= effective_on))),
    CONSTRAINT deposit_product_statement_profiles_frequency_enum CHECK (((frequency)::text = 'monthly'::text)),
    CONSTRAINT deposit_product_statement_profiles_status_enum CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('inactive'::character varying)::text])))
);


--
-- Name: deposit_product_statement_profiles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.deposit_product_statement_profiles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: deposit_product_statement_profiles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.deposit_product_statement_profiles_id_seq OWNED BY public.deposit_product_statement_profiles.id;


--
-- Name: deposit_products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposit_products (
    id bigint NOT NULL,
    product_code character varying NOT NULL,
    name character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    currency character varying DEFAULT 'USD'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: deposit_products_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.deposit_products_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: deposit_products_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.deposit_products_id_seq OWNED BY public.deposit_products.id;


--
-- Name: deposit_statements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposit_statements (
    id bigint NOT NULL,
    deposit_account_id bigint NOT NULL,
    deposit_product_statement_profile_id bigint NOT NULL,
    period_start_on date NOT NULL,
    period_end_on date NOT NULL,
    currency character varying DEFAULT 'USD'::character varying NOT NULL,
    opening_ledger_balance_minor_units bigint NOT NULL,
    closing_ledger_balance_minor_units bigint NOT NULL,
    total_debits_minor_units bigint DEFAULT 0 NOT NULL,
    total_credits_minor_units bigint DEFAULT 0 NOT NULL,
    line_items jsonb DEFAULT '[]'::jsonb NOT NULL,
    status character varying DEFAULT 'generated'::character varying NOT NULL,
    generated_on date NOT NULL,
    generated_at timestamp(6) without time zone NOT NULL,
    idempotency_key character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT deposit_statements_period_valid CHECK ((period_start_on <= period_end_on)),
    CONSTRAINT deposit_statements_status_enum CHECK (((status)::text = 'generated'::text)),
    CONSTRAINT deposit_statements_total_credits_non_negative CHECK ((total_credits_minor_units >= 0)),
    CONSTRAINT deposit_statements_total_debits_non_negative CHECK ((total_debits_minor_units >= 0))
);


--
-- Name: deposit_statements_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.deposit_statements_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: deposit_statements_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.deposit_statements_id_seq OWNED BY public.deposit_statements.id;


--
-- Name: gl_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gl_accounts (
    id bigint NOT NULL,
    account_number character varying NOT NULL,
    account_type character varying NOT NULL,
    natural_balance character varying NOT NULL,
    account_name character varying NOT NULL,
    currency character varying DEFAULT 'USD'::character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: gl_accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.gl_accounts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: gl_accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.gl_accounts_id_seq OWNED BY public.gl_accounts.id;


--
-- Name: holds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.holds (
    id bigint NOT NULL,
    deposit_account_id bigint NOT NULL,
    amount_minor_units bigint NOT NULL,
    currency character varying DEFAULT 'USD'::character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    placed_by_operational_event_id bigint,
    released_by_operational_event_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    placed_for_operational_event_id bigint,
    hold_type character varying DEFAULT 'administrative'::character varying NOT NULL,
    reason_code character varying DEFAULT 'manual_review'::character varying NOT NULL,
    reason_description character varying,
    expires_on date,
    expired_by_operational_event_id bigint,
    CONSTRAINT holds_amount_positive CHECK ((amount_minor_units > 0)),
    CONSTRAINT holds_hold_type_enum CHECK (((hold_type)::text = ANY (ARRAY[('administrative'::character varying)::text, ('deposit'::character varying)::text, ('legal'::character varying)::text, ('channel_authorization'::character varying)::text]))),
    CONSTRAINT holds_reason_code_enum CHECK (((reason_code)::text = ANY (ARRAY[('deposit_availability'::character varying)::text, ('customer_request'::character varying)::text, ('fraud_review'::character varying)::text, ('legal_order'::character varying)::text, ('manual_review'::character varying)::text, ('other'::character varying)::text]))),
    CONSTRAINT holds_status_enum CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('released'::character varying)::text, ('expired'::character varying)::text])))
);


--
-- Name: holds_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.holds_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: holds_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.holds_id_seq OWNED BY public.holds.id;


--
-- Name: journal_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.journal_entries (
    id bigint NOT NULL,
    posting_batch_id bigint NOT NULL,
    operational_event_id bigint NOT NULL,
    business_date date NOT NULL,
    currency character varying NOT NULL,
    narrative character varying,
    effective_at timestamp(6) without time zone NOT NULL,
    status character varying DEFAULT 'posted'::character varying NOT NULL,
    reverses_journal_entry_id bigint,
    reversing_journal_entry_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: journal_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.journal_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: journal_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.journal_entries_id_seq OWNED BY public.journal_entries.id;


--
-- Name: journal_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.journal_lines (
    id bigint NOT NULL,
    journal_entry_id bigint NOT NULL,
    sequence_no integer NOT NULL,
    side character varying NOT NULL,
    gl_account_id bigint NOT NULL,
    amount_minor_units bigint NOT NULL,
    narrative character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    deposit_account_id bigint,
    CONSTRAINT journal_lines_amount_non_negative CHECK ((amount_minor_units >= 0)),
    CONSTRAINT journal_lines_side_enum CHECK (((side)::text = ANY (ARRAY[('debit'::character varying)::text, ('credit'::character varying)::text])))
);


--
-- Name: journal_lines_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.journal_lines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: journal_lines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.journal_lines_id_seq OWNED BY public.journal_lines.id;


--
-- Name: operating_units; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.operating_units (
    id bigint NOT NULL,
    code character varying NOT NULL,
    name character varying NOT NULL,
    unit_type character varying NOT NULL,
    parent_operating_unit_id bigint,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    time_zone character varying DEFAULT 'Eastern Time (US & Canada)'::character varying NOT NULL,
    opened_on date,
    closed_on date,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT operating_units_closed_on_required_check CHECK ((((status)::text <> 'closed'::text) OR (closed_on IS NOT NULL))),
    CONSTRAINT operating_units_code_present_check CHECK ((btrim((code)::text) <> ''::text)),
    CONSTRAINT operating_units_name_present_check CHECK ((btrim((name)::text) <> ''::text)),
    CONSTRAINT operating_units_parent_not_self_check CHECK (((parent_operating_unit_id IS NULL) OR (parent_operating_unit_id <> id))),
    CONSTRAINT operating_units_status_check CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('inactive'::character varying)::text, ('closed'::character varying)::text]))),
    CONSTRAINT operating_units_unit_type_check CHECK (((unit_type)::text = ANY (ARRAY[('institution'::character varying)::text, ('branch'::character varying)::text, ('operations'::character varying)::text, ('department'::character varying)::text, ('region'::character varying)::text])))
);


--
-- Name: operating_units_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.operating_units_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: operating_units_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.operating_units_id_seq OWNED BY public.operating_units.id;


--
-- Name: operational_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.operational_events (
    id bigint NOT NULL,
    event_type character varying NOT NULL,
    status character varying NOT NULL,
    business_date date NOT NULL,
    idempotency_key character varying NOT NULL,
    amount_minor_units bigint,
    currency character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    channel character varying NOT NULL,
    source_account_id bigint,
    destination_account_id bigint,
    reversal_of_event_id bigint,
    reversed_by_event_id bigint,
    teller_session_id bigint,
    reference_id character varying,
    actor_id bigint,
    operating_unit_id bigint
);


--
-- Name: operational_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.operational_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: operational_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.operational_events_id_seq OWNED BY public.operational_events.id;


--
-- Name: operator_credentials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.operator_credentials (
    id bigint NOT NULL,
    operator_id bigint NOT NULL,
    username character varying NOT NULL,
    password_digest character varying NOT NULL,
    password_changed_at timestamp(6) without time zone,
    failed_login_attempts integer DEFAULT 0 NOT NULL,
    locked_at timestamp(6) without time zone,
    last_sign_in_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT operator_credentials_failed_attempts_nonnegative_check CHECK ((failed_login_attempts >= 0)),
    CONSTRAINT operator_credentials_username_present_check CHECK ((btrim((username)::text) <> ''::text))
);


--
-- Name: operator_credentials_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.operator_credentials_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: operator_credentials_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.operator_credentials_id_seq OWNED BY public.operator_credentials.id;


--
-- Name: operator_role_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.operator_role_assignments (
    id bigint NOT NULL,
    operator_id bigint NOT NULL,
    role_id bigint NOT NULL,
    scope_type character varying,
    scope_id bigint,
    active boolean DEFAULT true NOT NULL,
    starts_at timestamp(6) without time zone,
    ends_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT operator_role_assignments_scope_pair_check CHECK ((((scope_type IS NULL) AND (scope_id IS NULL)) OR ((scope_type IS NOT NULL) AND (scope_id IS NOT NULL)))),
    CONSTRAINT operator_role_assignments_scope_type_check CHECK (((scope_type IS NULL) OR ((scope_type)::text = 'operating_unit'::text))),
    CONSTRAINT operator_role_assignments_time_window_check CHECK (((starts_at IS NULL) OR (ends_at IS NULL) OR (starts_at < ends_at)))
);


--
-- Name: operator_role_assignments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.operator_role_assignments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: operator_role_assignments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.operator_role_assignments_id_seq OWNED BY public.operator_role_assignments.id;


--
-- Name: operators; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.operators (
    id bigint NOT NULL,
    role character varying NOT NULL,
    display_name character varying,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    default_operating_unit_id bigint,
    CONSTRAINT operators_role_check CHECK (((role)::text = ANY (ARRAY[('teller'::character varying)::text, ('supervisor'::character varying)::text, ('operations'::character varying)::text, ('admin'::character varying)::text])))
);


--
-- Name: operators_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.operators_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: operators_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.operators_id_seq OWNED BY public.operators.id;


--
-- Name: party_addresses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.party_addresses (
    id bigint NOT NULL,
    party_record_id bigint NOT NULL,
    line1 character varying NOT NULL,
    line2 character varying,
    city character varying NOT NULL,
    region character varying NOT NULL,
    postal_code character varying NOT NULL,
    country character varying DEFAULT 'US'::character varying NOT NULL,
    purpose character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    effective_on date NOT NULL,
    ended_on date,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT party_addresses_purpose_check CHECK (((purpose)::text = ANY ((ARRAY['residential'::character varying, 'mailing'::character varying])::text[]))),
    CONSTRAINT party_addresses_status_check CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'inactive'::character varying])::text[])))
);


--
-- Name: party_addresses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.party_addresses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: party_addresses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.party_addresses_id_seq OWNED BY public.party_addresses.id;


--
-- Name: party_contact_audits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.party_contact_audits (
    id bigint NOT NULL,
    party_record_id bigint NOT NULL,
    contact_table character varying NOT NULL,
    contact_id bigint NOT NULL,
    action character varying NOT NULL,
    channel character varying NOT NULL,
    idempotency_key character varying NOT NULL,
    business_date date NOT NULL,
    actor_id bigint NOT NULL,
    old_summary text,
    new_summary text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT party_contact_audits_action_check CHECK (((action)::text = ANY ((ARRAY['added'::character varying, 'ended'::character varying, 'superseded'::character varying])::text[]))),
    CONSTRAINT party_contact_audits_channel_check CHECK (((channel)::text = 'branch'::text)),
    CONSTRAINT party_contact_audits_contact_table_check CHECK (((contact_table)::text = ANY ((ARRAY['party_emails'::character varying, 'party_phones'::character varying, 'party_addresses'::character varying])::text[])))
);


--
-- Name: party_contact_audits_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.party_contact_audits_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: party_contact_audits_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.party_contact_audits_id_seq OWNED BY public.party_contact_audits.id;


--
-- Name: party_emails; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.party_emails (
    id bigint NOT NULL,
    party_record_id bigint NOT NULL,
    email character varying NOT NULL,
    purpose character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    effective_on date NOT NULL,
    ended_on date,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT party_emails_purpose_check CHECK (((purpose)::text = ANY ((ARRAY['primary'::character varying, 'secondary'::character varying])::text[]))),
    CONSTRAINT party_emails_status_check CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'inactive'::character varying])::text[])))
);


--
-- Name: party_emails_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.party_emails_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: party_emails_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.party_emails_id_seq OWNED BY public.party_emails.id;


--
-- Name: party_individual_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.party_individual_profiles (
    id bigint NOT NULL,
    party_record_id bigint NOT NULL,
    first_name character varying NOT NULL,
    middle_name character varying,
    last_name character varying NOT NULL,
    name_suffix character varying,
    preferred_first_name character varying,
    preferred_last_name character varying,
    date_of_birth date,
    occupation character varying,
    employer character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: party_individual_profiles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.party_individual_profiles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: party_individual_profiles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.party_individual_profiles_id_seq OWNED BY public.party_individual_profiles.id;


--
-- Name: party_phones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.party_phones (
    id bigint NOT NULL,
    party_record_id bigint NOT NULL,
    phone_number character varying NOT NULL,
    purpose character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    effective_on date NOT NULL,
    ended_on date,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT party_phones_purpose_check CHECK (((purpose)::text = ANY ((ARRAY['mobile'::character varying, 'home'::character varying, 'work'::character varying])::text[]))),
    CONSTRAINT party_phones_status_check CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'inactive'::character varying])::text[])))
);


--
-- Name: party_phones_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.party_phones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: party_phones_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.party_phones_id_seq OWNED BY public.party_phones.id;


--
-- Name: party_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.party_records (
    id bigint NOT NULL,
    name character varying NOT NULL,
    party_type character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: party_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.party_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: party_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.party_records_id_seq OWNED BY public.party_records.id;


--
-- Name: posting_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.posting_batches (
    id bigint NOT NULL,
    operational_event_id bigint NOT NULL,
    status character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: posting_batches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.posting_batches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: posting_batches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.posting_batches_id_seq OWNED BY public.posting_batches.id;


--
-- Name: role_capabilities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.role_capabilities (
    id bigint NOT NULL,
    role_id bigint NOT NULL,
    capability_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: role_capabilities_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.role_capabilities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: role_capabilities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.role_capabilities_id_seq OWNED BY public.role_capabilities.id;


--
-- Name: roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roles (
    id bigint NOT NULL,
    code character varying NOT NULL,
    name character varying NOT NULL,
    description text,
    active boolean DEFAULT true NOT NULL,
    system_role boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT roles_code_present_check CHECK ((btrim((code)::text) <> ''::text)),
    CONSTRAINT roles_name_present_check CHECK ((btrim((name)::text) <> ''::text))
);


--
-- Name: roles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.roles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.roles_id_seq OWNED BY public.roles.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: teller_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.teller_sessions (
    id bigint NOT NULL,
    status character varying DEFAULT 'open'::character varying NOT NULL,
    opened_at timestamp(6) without time zone NOT NULL,
    closed_at timestamp(6) without time zone,
    drawer_code character varying,
    expected_cash_minor_units bigint,
    actual_cash_minor_units bigint,
    variance_minor_units bigint,
    supervisor_approved_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    supervisor_operator_id bigint,
    operating_unit_id bigint NOT NULL,
    cash_location_id bigint,
    CONSTRAINT teller_sessions_status_enum CHECK (((status)::text = ANY (ARRAY[('open'::character varying)::text, ('closed'::character varying)::text, ('pending_supervisor'::character varying)::text])))
);


--
-- Name: teller_sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.teller_sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: teller_sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.teller_sessions_id_seq OWNED BY public.teller_sessions.id;


--
-- Name: account_lifecycle_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_lifecycle_events ALTER COLUMN id SET DEFAULT nextval('public.account_lifecycle_events_id_seq'::regclass);


--
-- Name: account_restrictions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_restrictions ALTER COLUMN id SET DEFAULT nextval('public.account_restrictions_id_seq'::regclass);


--
-- Name: capabilities id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.capabilities ALTER COLUMN id SET DEFAULT nextval('public.capabilities_id_seq'::regclass);


--
-- Name: cash_balances id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_balances ALTER COLUMN id SET DEFAULT nextval('public.cash_balances_id_seq'::regclass);


--
-- Name: cash_counts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_counts ALTER COLUMN id SET DEFAULT nextval('public.cash_counts_id_seq'::regclass);


--
-- Name: cash_locations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_locations ALTER COLUMN id SET DEFAULT nextval('public.cash_locations_id_seq'::regclass);


--
-- Name: cash_movements id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_movements ALTER COLUMN id SET DEFAULT nextval('public.cash_movements_id_seq'::regclass);


--
-- Name: cash_variances id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_variances ALTER COLUMN id SET DEFAULT nextval('public.cash_variances_id_seq'::regclass);


--
-- Name: core_business_date_close_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.core_business_date_close_events ALTER COLUMN id SET DEFAULT nextval('public.core_business_date_close_events_id_seq'::regclass);


--
-- Name: core_business_date_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.core_business_date_settings ALTER COLUMN id SET DEFAULT nextval('public.core_business_date_settings_id_seq'::regclass);


--
-- Name: deposit_account_balance_projections id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_account_balance_projections ALTER COLUMN id SET DEFAULT nextval('public.deposit_account_balance_projections_id_seq'::regclass);


--
-- Name: deposit_account_number_allocations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_account_number_allocations ALTER COLUMN id SET DEFAULT nextval('public.deposit_account_number_allocations_id_seq'::regclass);


--
-- Name: deposit_account_parties id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_account_parties ALTER COLUMN id SET DEFAULT nextval('public.deposit_account_parties_id_seq'::regclass);


--
-- Name: deposit_account_party_maintenance_audits id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_account_party_maintenance_audits ALTER COLUMN id SET DEFAULT nextval('public.deposit_account_party_maintenance_audits_id_seq'::regclass);


--
-- Name: deposit_accounts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_accounts ALTER COLUMN id SET DEFAULT nextval('public.deposit_accounts_id_seq'::regclass);


--
-- Name: deposit_product_fee_rules id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_product_fee_rules ALTER COLUMN id SET DEFAULT nextval('public.deposit_product_fee_rules_id_seq'::regclass);


--
-- Name: deposit_product_overdraft_policies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_product_overdraft_policies ALTER COLUMN id SET DEFAULT nextval('public.deposit_product_overdraft_policies_id_seq'::regclass);


--
-- Name: deposit_product_statement_profiles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_product_statement_profiles ALTER COLUMN id SET DEFAULT nextval('public.deposit_product_statement_profiles_id_seq'::regclass);


--
-- Name: deposit_products id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_products ALTER COLUMN id SET DEFAULT nextval('public.deposit_products_id_seq'::regclass);


--
-- Name: deposit_statements id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_statements ALTER COLUMN id SET DEFAULT nextval('public.deposit_statements_id_seq'::regclass);


--
-- Name: gl_accounts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gl_accounts ALTER COLUMN id SET DEFAULT nextval('public.gl_accounts_id_seq'::regclass);


--
-- Name: holds id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.holds ALTER COLUMN id SET DEFAULT nextval('public.holds_id_seq'::regclass);


--
-- Name: journal_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries ALTER COLUMN id SET DEFAULT nextval('public.journal_entries_id_seq'::regclass);


--
-- Name: journal_lines id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_lines ALTER COLUMN id SET DEFAULT nextval('public.journal_lines_id_seq'::regclass);


--
-- Name: operating_units id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operating_units ALTER COLUMN id SET DEFAULT nextval('public.operating_units_id_seq'::regclass);


--
-- Name: operational_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operational_events ALTER COLUMN id SET DEFAULT nextval('public.operational_events_id_seq'::regclass);


--
-- Name: operator_credentials id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operator_credentials ALTER COLUMN id SET DEFAULT nextval('public.operator_credentials_id_seq'::regclass);


--
-- Name: operator_role_assignments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operator_role_assignments ALTER COLUMN id SET DEFAULT nextval('public.operator_role_assignments_id_seq'::regclass);


--
-- Name: operators id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operators ALTER COLUMN id SET DEFAULT nextval('public.operators_id_seq'::regclass);


--
-- Name: party_addresses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_addresses ALTER COLUMN id SET DEFAULT nextval('public.party_addresses_id_seq'::regclass);


--
-- Name: party_contact_audits id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_contact_audits ALTER COLUMN id SET DEFAULT nextval('public.party_contact_audits_id_seq'::regclass);


--
-- Name: party_emails id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_emails ALTER COLUMN id SET DEFAULT nextval('public.party_emails_id_seq'::regclass);


--
-- Name: party_individual_profiles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_individual_profiles ALTER COLUMN id SET DEFAULT nextval('public.party_individual_profiles_id_seq'::regclass);


--
-- Name: party_phones id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_phones ALTER COLUMN id SET DEFAULT nextval('public.party_phones_id_seq'::regclass);


--
-- Name: party_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_records ALTER COLUMN id SET DEFAULT nextval('public.party_records_id_seq'::regclass);


--
-- Name: posting_batches id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posting_batches ALTER COLUMN id SET DEFAULT nextval('public.posting_batches_id_seq'::regclass);


--
-- Name: role_capabilities id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_capabilities ALTER COLUMN id SET DEFAULT nextval('public.role_capabilities_id_seq'::regclass);


--
-- Name: roles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles ALTER COLUMN id SET DEFAULT nextval('public.roles_id_seq'::regclass);


--
-- Name: teller_sessions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teller_sessions ALTER COLUMN id SET DEFAULT nextval('public.teller_sessions_id_seq'::regclass);


--
-- Name: account_lifecycle_events account_lifecycle_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_lifecycle_events
    ADD CONSTRAINT account_lifecycle_events_pkey PRIMARY KEY (id);


--
-- Name: account_restrictions account_restrictions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_restrictions
    ADD CONSTRAINT account_restrictions_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: capabilities capabilities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.capabilities
    ADD CONSTRAINT capabilities_pkey PRIMARY KEY (id);


--
-- Name: cash_balances cash_balances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_balances
    ADD CONSTRAINT cash_balances_pkey PRIMARY KEY (id);


--
-- Name: cash_counts cash_counts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_counts
    ADD CONSTRAINT cash_counts_pkey PRIMARY KEY (id);


--
-- Name: cash_locations cash_locations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_locations
    ADD CONSTRAINT cash_locations_pkey PRIMARY KEY (id);


--
-- Name: cash_movements cash_movements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_movements
    ADD CONSTRAINT cash_movements_pkey PRIMARY KEY (id);


--
-- Name: cash_variances cash_variances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_variances
    ADD CONSTRAINT cash_variances_pkey PRIMARY KEY (id);


--
-- Name: core_business_date_close_events core_business_date_close_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.core_business_date_close_events
    ADD CONSTRAINT core_business_date_close_events_pkey PRIMARY KEY (id);


--
-- Name: core_business_date_settings core_business_date_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.core_business_date_settings
    ADD CONSTRAINT core_business_date_settings_pkey PRIMARY KEY (id);


--
-- Name: deposit_account_balance_projections deposit_account_balance_projections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_account_balance_projections
    ADD CONSTRAINT deposit_account_balance_projections_pkey PRIMARY KEY (id);


--
-- Name: deposit_account_number_allocations deposit_account_number_allocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_account_number_allocations
    ADD CONSTRAINT deposit_account_number_allocations_pkey PRIMARY KEY (id);


--
-- Name: deposit_account_parties deposit_account_parties_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_account_parties
    ADD CONSTRAINT deposit_account_parties_pkey PRIMARY KEY (id);


--
-- Name: deposit_account_party_maintenance_audits deposit_account_party_maintenance_audits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_account_party_maintenance_audits
    ADD CONSTRAINT deposit_account_party_maintenance_audits_pkey PRIMARY KEY (id);


--
-- Name: deposit_accounts deposit_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_accounts
    ADD CONSTRAINT deposit_accounts_pkey PRIMARY KEY (id);


--
-- Name: deposit_product_fee_rules deposit_product_fee_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_product_fee_rules
    ADD CONSTRAINT deposit_product_fee_rules_pkey PRIMARY KEY (id);


--
-- Name: deposit_product_overdraft_policies deposit_product_overdraft_policies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_product_overdraft_policies
    ADD CONSTRAINT deposit_product_overdraft_policies_pkey PRIMARY KEY (id);


--
-- Name: deposit_product_statement_profiles deposit_product_statement_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_product_statement_profiles
    ADD CONSTRAINT deposit_product_statement_profiles_pkey PRIMARY KEY (id);


--
-- Name: deposit_products deposit_products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_products
    ADD CONSTRAINT deposit_products_pkey PRIMARY KEY (id);


--
-- Name: deposit_statements deposit_statements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_statements
    ADD CONSTRAINT deposit_statements_pkey PRIMARY KEY (id);


--
-- Name: gl_accounts gl_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gl_accounts
    ADD CONSTRAINT gl_accounts_pkey PRIMARY KEY (id);


--
-- Name: holds holds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.holds
    ADD CONSTRAINT holds_pkey PRIMARY KEY (id);


--
-- Name: journal_entries journal_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT journal_entries_pkey PRIMARY KEY (id);


--
-- Name: journal_lines journal_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_lines
    ADD CONSTRAINT journal_lines_pkey PRIMARY KEY (id);


--
-- Name: operating_units operating_units_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operating_units
    ADD CONSTRAINT operating_units_pkey PRIMARY KEY (id);


--
-- Name: operational_events operational_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operational_events
    ADD CONSTRAINT operational_events_pkey PRIMARY KEY (id);


--
-- Name: operator_credentials operator_credentials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operator_credentials
    ADD CONSTRAINT operator_credentials_pkey PRIMARY KEY (id);


--
-- Name: operator_role_assignments operator_role_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operator_role_assignments
    ADD CONSTRAINT operator_role_assignments_pkey PRIMARY KEY (id);


--
-- Name: operators operators_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operators
    ADD CONSTRAINT operators_pkey PRIMARY KEY (id);


--
-- Name: party_addresses party_addresses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_addresses
    ADD CONSTRAINT party_addresses_pkey PRIMARY KEY (id);


--
-- Name: party_contact_audits party_contact_audits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_contact_audits
    ADD CONSTRAINT party_contact_audits_pkey PRIMARY KEY (id);


--
-- Name: party_emails party_emails_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_emails
    ADD CONSTRAINT party_emails_pkey PRIMARY KEY (id);


--
-- Name: party_individual_profiles party_individual_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_individual_profiles
    ADD CONSTRAINT party_individual_profiles_pkey PRIMARY KEY (id);


--
-- Name: party_phones party_phones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_phones
    ADD CONSTRAINT party_phones_pkey PRIMARY KEY (id);


--
-- Name: party_records party_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_records
    ADD CONSTRAINT party_records_pkey PRIMARY KEY (id);


--
-- Name: posting_batches posting_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posting_batches
    ADD CONSTRAINT posting_batches_pkey PRIMARY KEY (id);


--
-- Name: role_capabilities role_capabilities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_capabilities
    ADD CONSTRAINT role_capabilities_pkey PRIMARY KEY (id);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: teller_sessions teller_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teller_sessions
    ADD CONSTRAINT teller_sessions_pkey PRIMARY KEY (id);


--
-- Name: idx_account_lifecycle_events_account_action_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_account_lifecycle_events_account_action_date ON public.account_lifecycle_events USING btree (deposit_account_id, action, business_date);


--
-- Name: idx_account_lifecycle_events_operational_event; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_account_lifecycle_events_operational_event ON public.account_lifecycle_events USING btree (operational_event_id);


--
-- Name: idx_account_restrictions_account_status_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_account_restrictions_account_status_type ON public.account_restrictions USING btree (deposit_account_id, status, restriction_type);


--
-- Name: idx_account_restrictions_restricted_event; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_account_restrictions_restricted_event ON public.account_restrictions USING btree (restricted_operational_event_id);


--
-- Name: idx_account_restrictions_unrestricted_event; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_account_restrictions_unrestricted_event ON public.account_restrictions USING btree (unrestricted_operational_event_id);


--
-- Name: idx_active_branch_vault_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_active_branch_vault_identity ON public.cash_locations USING btree (operating_unit_id, location_type) WHERE (((status)::text = 'active'::text) AND ((location_type)::text = 'branch_vault'::text));


--
-- Name: idx_active_cash_drawer_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_active_cash_drawer_identity ON public.cash_locations USING btree (operating_unit_id, location_type, drawer_code) WHERE (((status)::text = 'active'::text) AND ((location_type)::text = 'teller_drawer'::text));


--
-- Name: idx_cash_movements_external_shipment_reference; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cash_movements_external_shipment_reference ON public.cash_movements USING btree (external_source, shipment_reference);


--
-- Name: idx_dap_maintenance_audits_idempotency; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_dap_maintenance_audits_idempotency ON public.deposit_account_party_maintenance_audits USING btree (channel, idempotency_key);


--
-- Name: idx_dap_maintenance_audits_on_relationship_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dap_maintenance_audits_on_relationship_id ON public.deposit_account_party_maintenance_audits USING btree (deposit_account_party_id);


--
-- Name: idx_deposit_balance_proj_account_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_deposit_balance_proj_account_unique ON public.deposit_account_balance_projections USING btree (deposit_account_id);


--
-- Name: idx_deposit_balance_proj_as_of_business_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_deposit_balance_proj_as_of_business_date ON public.deposit_account_balance_projections USING btree (as_of_business_date);


--
-- Name: idx_deposit_balance_proj_last_journal_entry; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_deposit_balance_proj_last_journal_entry ON public.deposit_account_balance_projections USING btree (last_journal_entry_id);


--
-- Name: idx_deposit_balance_proj_last_operational_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_deposit_balance_proj_last_operational_event ON public.deposit_account_balance_projections USING btree (last_operational_event_id);


--
-- Name: idx_deposit_balance_proj_stale_from_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_deposit_balance_proj_stale_from_date ON public.deposit_account_balance_projections USING btree (stale, stale_from_date);


--
-- Name: idx_deposit_product_fee_rules_resolver; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_deposit_product_fee_rules_resolver ON public.deposit_product_fee_rules USING btree (deposit_product_id, fee_code, status, effective_on, ended_on);


--
-- Name: idx_deposit_product_od_policies_resolver; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_deposit_product_od_policies_resolver ON public.deposit_product_overdraft_policies USING btree (deposit_product_id, mode, status, effective_on, ended_on);


--
-- Name: idx_deposit_product_statement_profiles_resolver; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_deposit_product_statement_profiles_resolver ON public.deposit_product_statement_profiles USING btree (deposit_product_id, frequency, status, effective_on, ended_on);


--
-- Name: idx_deposit_statements_account_period_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_deposit_statements_account_period_unique ON public.deposit_statements USING btree (deposit_account_id, period_start_on, period_end_on);


--
-- Name: idx_deposit_statements_on_statement_profile_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_deposit_statements_on_statement_profile_id ON public.deposit_statements USING btree (deposit_product_statement_profile_id);


--
-- Name: idx_oe_actor_business_date_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_oe_actor_business_date_id ON public.operational_events USING btree (actor_id, business_date, id) WHERE (actor_id IS NOT NULL);


--
-- Name: idx_oe_business_date_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_oe_business_date_channel_id ON public.operational_events USING btree (business_date, channel, id);


--
-- Name: idx_oe_business_date_event_type_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_oe_business_date_event_type_id ON public.operational_events USING btree (business_date, event_type, id);


--
-- Name: idx_oe_business_date_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_oe_business_date_id ON public.operational_events USING btree (business_date, id);


--
-- Name: idx_oe_business_date_status_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_oe_business_date_status_id ON public.operational_events USING btree (business_date, status, id);


--
-- Name: idx_oe_idempotency_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_oe_idempotency_key ON public.operational_events USING btree (idempotency_key);


--
-- Name: idx_oe_reference_business_date_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_oe_reference_business_date_id ON public.operational_events USING btree (reference_id, business_date, id) WHERE (reference_id IS NOT NULL);


--
-- Name: idx_on_deposit_account_id_c32203628a; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_deposit_account_id_c32203628a ON public.deposit_account_party_maintenance_audits USING btree (deposit_account_id);


--
-- Name: idx_on_party_record_id_91aa95b618; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_party_record_id_91aa95b618 ON public.deposit_account_party_maintenance_audits USING btree (party_record_id);


--
-- Name: idx_on_party_record_id_status_purpose_6659aa2f25; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_party_record_id_status_purpose_6659aa2f25 ON public.party_addresses USING btree (party_record_id, status, purpose);


--
-- Name: index_account_lifecycle_events_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_account_lifecycle_events_on_actor_id ON public.account_lifecycle_events USING btree (actor_id);


--
-- Name: index_account_lifecycle_events_on_channel_and_idempotency_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_account_lifecycle_events_on_channel_and_idempotency_key ON public.account_lifecycle_events USING btree (channel, idempotency_key);


--
-- Name: index_account_lifecycle_events_on_deposit_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_account_lifecycle_events_on_deposit_account_id ON public.account_lifecycle_events USING btree (deposit_account_id);


--
-- Name: index_account_restrictions_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_account_restrictions_on_actor_id ON public.account_restrictions USING btree (actor_id);


--
-- Name: index_account_restrictions_on_channel_and_idempotency_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_account_restrictions_on_channel_and_idempotency_key ON public.account_restrictions USING btree (channel, idempotency_key);


--
-- Name: index_account_restrictions_on_deposit_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_account_restrictions_on_deposit_account_id ON public.account_restrictions USING btree (deposit_account_id);


--
-- Name: index_account_restrictions_on_release_idempotency_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_account_restrictions_on_release_idempotency_key ON public.account_restrictions USING btree (release_idempotency_key);


--
-- Name: index_account_restrictions_on_released_by_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_account_restrictions_on_released_by_actor_id ON public.account_restrictions USING btree (released_by_actor_id);


--
-- Name: index_capabilities_on_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_capabilities_on_code ON public.capabilities USING btree (code);


--
-- Name: index_cash_balances_on_cash_location_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cash_balances_on_cash_location_id ON public.cash_balances USING btree (cash_location_id);


--
-- Name: index_cash_balances_on_cash_location_id_and_currency; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_cash_balances_on_cash_location_id_and_currency ON public.cash_balances USING btree (cash_location_id, currency);


--
-- Name: index_cash_balances_on_last_cash_movement_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cash_balances_on_last_cash_movement_id ON public.cash_balances USING btree (last_cash_movement_id);


--
-- Name: index_cash_counts_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cash_counts_on_actor_id ON public.cash_counts USING btree (actor_id);


--
-- Name: index_cash_counts_on_business_date_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cash_counts_on_business_date_and_id ON public.cash_counts USING btree (business_date, id);


--
-- Name: index_cash_counts_on_cash_location_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cash_counts_on_cash_location_id ON public.cash_counts USING btree (cash_location_id);


--
-- Name: index_cash_counts_on_idempotency_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_cash_counts_on_idempotency_key ON public.cash_counts USING btree (idempotency_key);


--
-- Name: index_cash_counts_on_operating_unit_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cash_counts_on_operating_unit_id ON public.cash_counts USING btree (operating_unit_id);


--
-- Name: index_cash_counts_on_operational_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cash_counts_on_operational_event_id ON public.cash_counts USING btree (operational_event_id);


--
-- Name: index_cash_locations_on_operating_unit_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cash_locations_on_operating_unit_id ON public.cash_locations USING btree (operating_unit_id);


--
-- Name: index_cash_locations_on_parent_cash_location_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cash_locations_on_parent_cash_location_id ON public.cash_locations USING btree (parent_cash_location_id);


--
-- Name: index_cash_locations_on_responsible_operator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cash_locations_on_responsible_operator_id ON public.cash_locations USING btree (responsible_operator_id);


--
-- Name: index_cash_movements_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cash_movements_on_actor_id ON public.cash_movements USING btree (actor_id);


--
-- Name: index_cash_movements_on_approving_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cash_movements_on_approving_actor_id ON public.cash_movements USING btree (approving_actor_id);


--
-- Name: index_cash_movements_on_business_date_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cash_movements_on_business_date_and_id ON public.cash_movements USING btree (business_date, id);


--
-- Name: index_cash_movements_on_destination_cash_location_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cash_movements_on_destination_cash_location_id ON public.cash_movements USING btree (destination_cash_location_id);


--
-- Name: index_cash_movements_on_idempotency_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_cash_movements_on_idempotency_key ON public.cash_movements USING btree (idempotency_key);


--
-- Name: index_cash_movements_on_operating_unit_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cash_movements_on_operating_unit_id ON public.cash_movements USING btree (operating_unit_id);


--
-- Name: index_cash_movements_on_operational_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cash_movements_on_operational_event_id ON public.cash_movements USING btree (operational_event_id);


--
-- Name: index_cash_movements_on_source_cash_location_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cash_movements_on_source_cash_location_id ON public.cash_movements USING btree (source_cash_location_id);


--
-- Name: index_cash_variances_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cash_variances_on_actor_id ON public.cash_variances USING btree (actor_id);


--
-- Name: index_cash_variances_on_approving_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cash_variances_on_approving_actor_id ON public.cash_variances USING btree (approving_actor_id);


--
-- Name: index_cash_variances_on_cash_count_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_cash_variances_on_cash_count_id ON public.cash_variances USING btree (cash_count_id);


--
-- Name: index_cash_variances_on_cash_location_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cash_variances_on_cash_location_id ON public.cash_variances USING btree (cash_location_id);


--
-- Name: index_cash_variances_on_cash_variance_posted_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_cash_variances_on_cash_variance_posted_event_id ON public.cash_variances USING btree (cash_variance_posted_event_id);


--
-- Name: index_cash_variances_on_operating_unit_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cash_variances_on_operating_unit_id ON public.cash_variances USING btree (operating_unit_id);


--
-- Name: index_core_business_date_close_events_on_closed_by_operator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_core_business_date_close_events_on_closed_by_operator_id ON public.core_business_date_close_events USING btree (closed_by_operator_id);


--
-- Name: index_core_business_date_close_events_on_closed_on; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_core_business_date_close_events_on_closed_on ON public.core_business_date_close_events USING btree (closed_on);


--
-- Name: index_dap_unique_open_active_per_account_party_role; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_dap_unique_open_active_per_account_party_role ON public.deposit_account_parties USING btree (deposit_account_id, party_record_id, role) WHERE (((status)::text = 'active'::text) AND (ended_on IS NULL));


--
-- Name: index_deposit_account_number_allocations_on_allocation_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_deposit_account_number_allocations_on_allocation_key ON public.deposit_account_number_allocations USING btree (allocation_key);


--
-- Name: index_deposit_account_parties_on_deposit_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_deposit_account_parties_on_deposit_account_id ON public.deposit_account_parties USING btree (deposit_account_id);


--
-- Name: index_deposit_account_parties_on_party_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_deposit_account_parties_on_party_record_id ON public.deposit_account_parties USING btree (party_record_id);


--
-- Name: index_deposit_account_party_maintenance_audits_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_deposit_account_party_maintenance_audits_on_actor_id ON public.deposit_account_party_maintenance_audits USING btree (actor_id);


--
-- Name: index_deposit_accounts_on_account_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_deposit_accounts_on_account_number ON public.deposit_accounts USING btree (account_number);


--
-- Name: index_deposit_accounts_on_deposit_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_deposit_accounts_on_deposit_product_id ON public.deposit_accounts USING btree (deposit_product_id);


--
-- Name: index_deposit_product_fee_rules_on_deposit_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_deposit_product_fee_rules_on_deposit_product_id ON public.deposit_product_fee_rules USING btree (deposit_product_id);


--
-- Name: index_deposit_product_overdraft_policies_on_deposit_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_deposit_product_overdraft_policies_on_deposit_product_id ON public.deposit_product_overdraft_policies USING btree (deposit_product_id);


--
-- Name: index_deposit_product_statement_profiles_on_deposit_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_deposit_product_statement_profiles_on_deposit_product_id ON public.deposit_product_statement_profiles USING btree (deposit_product_id);


--
-- Name: index_deposit_products_on_product_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_deposit_products_on_product_code ON public.deposit_products USING btree (product_code);


--
-- Name: index_deposit_statements_on_deposit_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_deposit_statements_on_deposit_account_id ON public.deposit_statements USING btree (deposit_account_id);


--
-- Name: index_deposit_statements_on_idempotency_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_deposit_statements_on_idempotency_key ON public.deposit_statements USING btree (idempotency_key);


--
-- Name: index_gl_accounts_on_account_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_gl_accounts_on_account_number ON public.gl_accounts USING btree (account_number);


--
-- Name: index_holds_on_deposit_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_holds_on_deposit_account_id ON public.holds USING btree (deposit_account_id);


--
-- Name: index_holds_on_expired_by_operational_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_holds_on_expired_by_operational_event_id ON public.holds USING btree (expired_by_operational_event_id);


--
-- Name: index_holds_on_placed_by_operational_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_holds_on_placed_by_operational_event_id ON public.holds USING btree (placed_by_operational_event_id);


--
-- Name: index_holds_on_placed_for_oe_id_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_holds_on_placed_for_oe_id_active ON public.holds USING btree (placed_for_operational_event_id) WHERE (((status)::text = 'active'::text) AND (placed_for_operational_event_id IS NOT NULL));


--
-- Name: index_holds_on_placed_for_operational_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_holds_on_placed_for_operational_event_id ON public.holds USING btree (placed_for_operational_event_id);


--
-- Name: index_holds_on_released_by_operational_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_holds_on_released_by_operational_event_id ON public.holds USING btree (released_by_operational_event_id);


--
-- Name: index_journal_entries_on_business_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_journal_entries_on_business_date ON public.journal_entries USING btree (business_date);


--
-- Name: index_journal_entries_on_operational_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_journal_entries_on_operational_event_id ON public.journal_entries USING btree (operational_event_id);


--
-- Name: index_journal_entries_on_posting_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_journal_entries_on_posting_batch_id ON public.journal_entries USING btree (posting_batch_id);


--
-- Name: index_journal_entries_on_reverses_journal_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_journal_entries_on_reverses_journal_entry_id ON public.journal_entries USING btree (reverses_journal_entry_id);


--
-- Name: index_journal_entries_on_reversing_journal_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_journal_entries_on_reversing_journal_entry_id ON public.journal_entries USING btree (reversing_journal_entry_id);


--
-- Name: index_journal_lines_on_deposit_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_journal_lines_on_deposit_account_id ON public.journal_lines USING btree (deposit_account_id);


--
-- Name: index_journal_lines_on_gl_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_journal_lines_on_gl_account_id ON public.journal_lines USING btree (gl_account_id);


--
-- Name: index_journal_lines_on_journal_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_journal_lines_on_journal_entry_id ON public.journal_lines USING btree (journal_entry_id);


--
-- Name: index_journal_lines_on_journal_entry_id_and_sequence_no; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_journal_lines_on_journal_entry_id_and_sequence_no ON public.journal_lines USING btree (journal_entry_id, sequence_no);


--
-- Name: index_operating_units_on_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_operating_units_on_code ON public.operating_units USING btree (code);


--
-- Name: index_operating_units_on_parent_operating_unit_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_operating_units_on_parent_operating_unit_id ON public.operating_units USING btree (parent_operating_unit_id);


--
-- Name: index_operational_events_on_channel_and_idempotency_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_operational_events_on_channel_and_idempotency_key ON public.operational_events USING btree (channel, idempotency_key);


--
-- Name: index_operational_events_on_destination_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_operational_events_on_destination_account_id ON public.operational_events USING btree (destination_account_id);


--
-- Name: index_operational_events_on_operating_unit_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_operational_events_on_operating_unit_id ON public.operational_events USING btree (operating_unit_id);


--
-- Name: index_operational_events_on_source_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_operational_events_on_source_account_id ON public.operational_events USING btree (source_account_id);


--
-- Name: index_operational_events_on_teller_session_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_operational_events_on_teller_session_id ON public.operational_events USING btree (teller_session_id);


--
-- Name: index_operational_events_one_reversal_per_original; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_operational_events_one_reversal_per_original ON public.operational_events USING btree (reversal_of_event_id) WHERE (reversal_of_event_id IS NOT NULL);


--
-- Name: index_operator_credentials_on_lower_username; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_operator_credentials_on_lower_username ON public.operator_credentials USING btree (lower((username)::text));


--
-- Name: index_operator_credentials_on_operator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_operator_credentials_on_operator_id ON public.operator_credentials USING btree (operator_id);


--
-- Name: index_operator_role_assignments_on_global_role; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_operator_role_assignments_on_global_role ON public.operator_role_assignments USING btree (operator_id, role_id) WHERE ((scope_type IS NULL) AND (scope_id IS NULL));


--
-- Name: index_operator_role_assignments_on_operator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_operator_role_assignments_on_operator_id ON public.operator_role_assignments USING btree (operator_id);


--
-- Name: index_operator_role_assignments_on_role_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_operator_role_assignments_on_role_id ON public.operator_role_assignments USING btree (role_id);


--
-- Name: index_operator_role_assignments_on_scoped_role; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_operator_role_assignments_on_scoped_role ON public.operator_role_assignments USING btree (operator_id, role_id, scope_type, scope_id) WHERE ((scope_type IS NOT NULL) AND (scope_id IS NOT NULL));


--
-- Name: index_operators_on_default_operating_unit_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_operators_on_default_operating_unit_id ON public.operators USING btree (default_operating_unit_id);


--
-- Name: index_party_addresses_on_party_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_party_addresses_on_party_record_id ON public.party_addresses USING btree (party_record_id);


--
-- Name: index_party_contact_audits_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_party_contact_audits_on_actor_id ON public.party_contact_audits USING btree (actor_id);


--
-- Name: index_party_contact_audits_on_channel_and_idempotency_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_party_contact_audits_on_channel_and_idempotency_key ON public.party_contact_audits USING btree (channel, idempotency_key);


--
-- Name: index_party_contact_audits_on_party_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_party_contact_audits_on_party_record_id ON public.party_contact_audits USING btree (party_record_id);


--
-- Name: index_party_contact_audits_on_party_record_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_party_contact_audits_on_party_record_id_and_created_at ON public.party_contact_audits USING btree (party_record_id, created_at);


--
-- Name: index_party_emails_on_party_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_party_emails_on_party_record_id ON public.party_emails USING btree (party_record_id);


--
-- Name: index_party_emails_on_party_record_id_and_status_and_purpose; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_party_emails_on_party_record_id_and_status_and_purpose ON public.party_emails USING btree (party_record_id, status, purpose);


--
-- Name: index_party_individual_profiles_on_party_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_party_individual_profiles_on_party_record_id ON public.party_individual_profiles USING btree (party_record_id);


--
-- Name: index_party_phones_on_party_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_party_phones_on_party_record_id ON public.party_phones USING btree (party_record_id);


--
-- Name: index_party_phones_on_party_record_id_and_status_and_purpose; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_party_phones_on_party_record_id_and_status_and_purpose ON public.party_phones USING btree (party_record_id, status, purpose);


--
-- Name: index_posting_batches_on_operational_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_posting_batches_on_operational_event_id ON public.posting_batches USING btree (operational_event_id);


--
-- Name: index_role_capabilities_on_capability_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_role_capabilities_on_capability_id ON public.role_capabilities USING btree (capability_id);


--
-- Name: index_role_capabilities_on_role_and_capability; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_role_capabilities_on_role_and_capability ON public.role_capabilities USING btree (role_id, capability_id);


--
-- Name: index_role_capabilities_on_role_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_role_capabilities_on_role_id ON public.role_capabilities USING btree (role_id);


--
-- Name: index_roles_on_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_roles_on_code ON public.roles USING btree (code);


--
-- Name: index_teller_sessions_on_cash_location_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_teller_sessions_on_cash_location_id ON public.teller_sessions USING btree (cash_location_id);


--
-- Name: index_teller_sessions_on_operating_unit_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_teller_sessions_on_operating_unit_id ON public.teller_sessions USING btree (operating_unit_id);


--
-- Name: index_teller_sessions_on_supervisor_operator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_teller_sessions_on_supervisor_operator_id ON public.teller_sessions USING btree (supervisor_operator_id);


--
-- Name: journal_entries journal_entries_immutability_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER journal_entries_immutability_check BEFORE DELETE OR UPDATE ON public.journal_entries FOR EACH ROW EXECUTE FUNCTION public.ledger_journal_entries_reject_mutations();


--
-- Name: journal_lines journal_lines_balance_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER journal_lines_balance_check AFTER INSERT OR DELETE OR UPDATE ON public.journal_lines DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.ledger_validate_journal_entry_balanced();


--
-- Name: journal_lines journal_lines_immutability_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER journal_lines_immutability_check BEFORE DELETE OR UPDATE ON public.journal_lines FOR EACH ROW EXECUTE FUNCTION public.ledger_journal_lines_reject_mutations();


--
-- Name: operators fk_rails_003f73e909; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operators
    ADD CONSTRAINT fk_rails_003f73e909 FOREIGN KEY (default_operating_unit_id) REFERENCES public.operating_units(id);


--
-- Name: deposit_account_parties fk_rails_0245a491be; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_account_parties
    ADD CONSTRAINT fk_rails_0245a491be FOREIGN KEY (party_record_id) REFERENCES public.party_records(id);


--
-- Name: cash_movements fk_rails_04ebb9c7e5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_movements
    ADD CONSTRAINT fk_rails_04ebb9c7e5 FOREIGN KEY (source_cash_location_id) REFERENCES public.cash_locations(id);


--
-- Name: cash_balances fk_rails_0587c1eee8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_balances
    ADD CONSTRAINT fk_rails_0587c1eee8 FOREIGN KEY (last_cash_movement_id) REFERENCES public.cash_movements(id);


--
-- Name: deposit_account_party_maintenance_audits fk_rails_07cbf95209; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_account_party_maintenance_audits
    ADD CONSTRAINT fk_rails_07cbf95209 FOREIGN KEY (actor_id) REFERENCES public.operators(id);


--
-- Name: holds fk_rails_09b889824c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.holds
    ADD CONSTRAINT fk_rails_09b889824c FOREIGN KEY (placed_for_operational_event_id) REFERENCES public.operational_events(id);


--
-- Name: core_business_date_close_events fk_rails_0ba4d8ef2f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.core_business_date_close_events
    ADD CONSTRAINT fk_rails_0ba4d8ef2f FOREIGN KEY (closed_by_operator_id) REFERENCES public.operators(id);


--
-- Name: party_addresses fk_rails_0bfbaa2333; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_addresses
    ADD CONSTRAINT fk_rails_0bfbaa2333 FOREIGN KEY (party_record_id) REFERENCES public.party_records(id);


--
-- Name: cash_movements fk_rails_0c29c4f257; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_movements
    ADD CONSTRAINT fk_rails_0c29c4f257 FOREIGN KEY (actor_id) REFERENCES public.operators(id);


--
-- Name: cash_balances fk_rails_0ef5ce88e4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_balances
    ADD CONSTRAINT fk_rails_0ef5ce88e4 FOREIGN KEY (cash_location_id) REFERENCES public.cash_locations(id);


--
-- Name: operational_events fk_rails_0f986cd613; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operational_events
    ADD CONSTRAINT fk_rails_0f986cd613 FOREIGN KEY (source_account_id) REFERENCES public.deposit_accounts(id);


--
-- Name: posting_batches fk_rails_1a3b38f450; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posting_batches
    ADD CONSTRAINT fk_rails_1a3b38f450 FOREIGN KEY (operational_event_id) REFERENCES public.operational_events(id);


--
-- Name: cash_locations fk_rails_1aa4b9af7f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_locations
    ADD CONSTRAINT fk_rails_1aa4b9af7f FOREIGN KEY (parent_cash_location_id) REFERENCES public.cash_locations(id);


--
-- Name: operator_role_assignments fk_rails_2034e16c17; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operator_role_assignments
    ADD CONSTRAINT fk_rails_2034e16c17 FOREIGN KEY (role_id) REFERENCES public.roles(id);


--
-- Name: party_contact_audits fk_rails_20f5c22fa5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_contact_audits
    ADD CONSTRAINT fk_rails_20f5c22fa5 FOREIGN KEY (actor_id) REFERENCES public.operators(id);


--
-- Name: party_individual_profiles fk_rails_22a835d5da; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_individual_profiles
    ADD CONSTRAINT fk_rails_22a835d5da FOREIGN KEY (party_record_id) REFERENCES public.party_records(id);


--
-- Name: deposit_product_fee_rules fk_rails_23d035fa30; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_product_fee_rules
    ADD CONSTRAINT fk_rails_23d035fa30 FOREIGN KEY (deposit_product_id) REFERENCES public.deposit_products(id);


--
-- Name: operational_events fk_rails_29073cc426; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operational_events
    ADD CONSTRAINT fk_rails_29073cc426 FOREIGN KEY (teller_session_id) REFERENCES public.teller_sessions(id);


--
-- Name: account_restrictions fk_rails_2a8f88b07d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_restrictions
    ADD CONSTRAINT fk_rails_2a8f88b07d FOREIGN KEY (unrestricted_operational_event_id) REFERENCES public.operational_events(id);


--
-- Name: journal_lines fk_rails_2b0c279a73; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_lines
    ADD CONSTRAINT fk_rails_2b0c279a73 FOREIGN KEY (deposit_account_id) REFERENCES public.deposit_accounts(id);


--
-- Name: cash_movements fk_rails_2d6379f064; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_movements
    ADD CONSTRAINT fk_rails_2d6379f064 FOREIGN KEY (operating_unit_id) REFERENCES public.operating_units(id);


--
-- Name: account_restrictions fk_rails_33e1250290; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_restrictions
    ADD CONSTRAINT fk_rails_33e1250290 FOREIGN KEY (restricted_operational_event_id) REFERENCES public.operational_events(id);


--
-- Name: journal_entries fk_rails_3417d84ffc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT fk_rails_3417d84ffc FOREIGN KEY (reversing_journal_entry_id) REFERENCES public.journal_entries(id);


--
-- Name: holds fk_rails_4283210e70; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.holds
    ADD CONSTRAINT fk_rails_4283210e70 FOREIGN KEY (released_by_operational_event_id) REFERENCES public.operational_events(id);


--
-- Name: account_lifecycle_events fk_rails_43b7201b41; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_lifecycle_events
    ADD CONSTRAINT fk_rails_43b7201b41 FOREIGN KEY (deposit_account_id) REFERENCES public.deposit_accounts(id);


--
-- Name: deposit_account_party_maintenance_audits fk_rails_4749f6f4b0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_account_party_maintenance_audits
    ADD CONSTRAINT fk_rails_4749f6f4b0 FOREIGN KEY (party_record_id) REFERENCES public.party_records(id);


--
-- Name: holds fk_rails_4c0c5bf773; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.holds
    ADD CONSTRAINT fk_rails_4c0c5bf773 FOREIGN KEY (placed_by_operational_event_id) REFERENCES public.operational_events(id);


--
-- Name: cash_counts fk_rails_502e641448; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_counts
    ADD CONSTRAINT fk_rails_502e641448 FOREIGN KEY (actor_id) REFERENCES public.operators(id);


--
-- Name: operator_role_assignments fk_rails_54957937ed; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operator_role_assignments
    ADD CONSTRAINT fk_rails_54957937ed FOREIGN KEY (operator_id) REFERENCES public.operators(id);


--
-- Name: cash_movements fk_rails_54d48cd81d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_movements
    ADD CONSTRAINT fk_rails_54d48cd81d FOREIGN KEY (approving_actor_id) REFERENCES public.operators(id);


--
-- Name: operator_credentials fk_rails_580f3046fd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operator_credentials
    ADD CONSTRAINT fk_rails_580f3046fd FOREIGN KEY (operator_id) REFERENCES public.operators(id);


--
-- Name: account_restrictions fk_rails_589f352940; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_restrictions
    ADD CONSTRAINT fk_rails_589f352940 FOREIGN KEY (released_by_actor_id) REFERENCES public.operators(id);


--
-- Name: cash_counts fk_rails_58a51bad41; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_counts
    ADD CONSTRAINT fk_rails_58a51bad41 FOREIGN KEY (operational_event_id) REFERENCES public.operational_events(id);


--
-- Name: role_capabilities fk_rails_5a0544a242; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_capabilities
    ADD CONSTRAINT fk_rails_5a0544a242 FOREIGN KEY (role_id) REFERENCES public.roles(id);


--
-- Name: cash_variances fk_rails_5b15082de1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_variances
    ADD CONSTRAINT fk_rails_5b15082de1 FOREIGN KEY (actor_id) REFERENCES public.operators(id);


--
-- Name: deposit_product_overdraft_policies fk_rails_5d1e409444; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_product_overdraft_policies
    ADD CONSTRAINT fk_rails_5d1e409444 FOREIGN KEY (deposit_product_id) REFERENCES public.deposit_products(id);


--
-- Name: cash_counts fk_rails_65f53ad445; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_counts
    ADD CONSTRAINT fk_rails_65f53ad445 FOREIGN KEY (cash_location_id) REFERENCES public.cash_locations(id);


--
-- Name: party_emails fk_rails_669a5b6552; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_emails
    ADD CONSTRAINT fk_rails_669a5b6552 FOREIGN KEY (party_record_id) REFERENCES public.party_records(id);


--
-- Name: deposit_accounts fk_rails_71f0b9310a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_accounts
    ADD CONSTRAINT fk_rails_71f0b9310a FOREIGN KEY (deposit_product_id) REFERENCES public.deposit_products(id);


--
-- Name: holds fk_rails_75dfa621cd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.holds
    ADD CONSTRAINT fk_rails_75dfa621cd FOREIGN KEY (expired_by_operational_event_id) REFERENCES public.operational_events(id);


--
-- Name: deposit_statements fk_rails_761e21222b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_statements
    ADD CONSTRAINT fk_rails_761e21222b FOREIGN KEY (deposit_product_statement_profile_id) REFERENCES public.deposit_product_statement_profiles(id);


--
-- Name: cash_variances fk_rails_7ae7898fcc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_variances
    ADD CONSTRAINT fk_rails_7ae7898fcc FOREIGN KEY (cash_location_id) REFERENCES public.cash_locations(id);


--
-- Name: cash_balances fk_rails_7b3ae9d75e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_balances
    ADD CONSTRAINT fk_rails_7b3ae9d75e FOREIGN KEY (last_cash_count_id) REFERENCES public.cash_counts(id);


--
-- Name: journal_entries fk_rails_7f9a73cda9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT fk_rails_7f9a73cda9 FOREIGN KEY (operational_event_id) REFERENCES public.operational_events(id);


--
-- Name: deposit_product_statement_profiles fk_rails_7ffb1e7346; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_product_statement_profiles
    ADD CONSTRAINT fk_rails_7ffb1e7346 FOREIGN KEY (deposit_product_id) REFERENCES public.deposit_products(id);


--
-- Name: deposit_account_balance_projections fk_rails_863cf2fee9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_account_balance_projections
    ADD CONSTRAINT fk_rails_863cf2fee9 FOREIGN KEY (last_operational_event_id) REFERENCES public.operational_events(id);


--
-- Name: teller_sessions fk_rails_86b8203f6d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teller_sessions
    ADD CONSTRAINT fk_rails_86b8203f6d FOREIGN KEY (supervisor_operator_id) REFERENCES public.operators(id);


--
-- Name: teller_sessions fk_rails_896b8b6be7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teller_sessions
    ADD CONSTRAINT fk_rails_896b8b6be7 FOREIGN KEY (operating_unit_id) REFERENCES public.operating_units(id);


--
-- Name: deposit_account_balance_projections fk_rails_8a9a42a884; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_account_balance_projections
    ADD CONSTRAINT fk_rails_8a9a42a884 FOREIGN KEY (last_journal_entry_id) REFERENCES public.journal_entries(id);


--
-- Name: operational_events fk_rails_8cf89c2939; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operational_events
    ADD CONSTRAINT fk_rails_8cf89c2939 FOREIGN KEY (reversal_of_event_id) REFERENCES public.operational_events(id);


--
-- Name: cash_counts fk_rails_8eedd510c6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_counts
    ADD CONSTRAINT fk_rails_8eedd510c6 FOREIGN KEY (operating_unit_id) REFERENCES public.operating_units(id);


--
-- Name: deposit_statements fk_rails_916915f3bb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_statements
    ADD CONSTRAINT fk_rails_916915f3bb FOREIGN KEY (deposit_account_id) REFERENCES public.deposit_accounts(id);


--
-- Name: cash_variances fk_rails_92e09fc2fe; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_variances
    ADD CONSTRAINT fk_rails_92e09fc2fe FOREIGN KEY (operating_unit_id) REFERENCES public.operating_units(id);


--
-- Name: journal_lines fk_rails_92eda40cad; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_lines
    ADD CONSTRAINT fk_rails_92eda40cad FOREIGN KEY (journal_entry_id) REFERENCES public.journal_entries(id);


--
-- Name: cash_variances fk_rails_95110d8d04; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_variances
    ADD CONSTRAINT fk_rails_95110d8d04 FOREIGN KEY (cash_variance_posted_event_id) REFERENCES public.operational_events(id);


--
-- Name: party_phones fk_rails_96fe9f82d4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_phones
    ADD CONSTRAINT fk_rails_96fe9f82d4 FOREIGN KEY (party_record_id) REFERENCES public.party_records(id);


--
-- Name: deposit_account_party_maintenance_audits fk_rails_9f4e22e9ce; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_account_party_maintenance_audits
    ADD CONSTRAINT fk_rails_9f4e22e9ce FOREIGN KEY (deposit_account_party_id) REFERENCES public.deposit_account_parties(id);


--
-- Name: account_restrictions fk_rails_a18c9e00d3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_restrictions
    ADD CONSTRAINT fk_rails_a18c9e00d3 FOREIGN KEY (deposit_account_id) REFERENCES public.deposit_accounts(id);


--
-- Name: operational_events fk_rails_a650da481b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operational_events
    ADD CONSTRAINT fk_rails_a650da481b FOREIGN KEY (actor_id) REFERENCES public.operators(id);


--
-- Name: role_capabilities fk_rails_a6e4d08394; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_capabilities
    ADD CONSTRAINT fk_rails_a6e4d08394 FOREIGN KEY (capability_id) REFERENCES public.capabilities(id);


--
-- Name: cash_locations fk_rails_a92a9737fe; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_locations
    ADD CONSTRAINT fk_rails_a92a9737fe FOREIGN KEY (operating_unit_id) REFERENCES public.operating_units(id);


--
-- Name: cash_movements fk_rails_accd708689; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_movements
    ADD CONSTRAINT fk_rails_accd708689 FOREIGN KEY (operational_event_id) REFERENCES public.operational_events(id);


--
-- Name: deposit_account_balance_projections fk_rails_b59f66f0ab; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_account_balance_projections
    ADD CONSTRAINT fk_rails_b59f66f0ab FOREIGN KEY (deposit_account_id) REFERENCES public.deposit_accounts(id);


--
-- Name: cash_variances fk_rails_bcd59f239e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_variances
    ADD CONSTRAINT fk_rails_bcd59f239e FOREIGN KEY (cash_count_id) REFERENCES public.cash_counts(id);


--
-- Name: account_restrictions fk_rails_bde003deac; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_restrictions
    ADD CONSTRAINT fk_rails_bde003deac FOREIGN KEY (actor_id) REFERENCES public.operators(id);


--
-- Name: deposit_account_parties fk_rails_bf2b31365a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_account_parties
    ADD CONSTRAINT fk_rails_bf2b31365a FOREIGN KEY (deposit_account_id) REFERENCES public.deposit_accounts(id);


--
-- Name: cash_locations fk_rails_c294207840; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_locations
    ADD CONSTRAINT fk_rails_c294207840 FOREIGN KEY (responsible_operator_id) REFERENCES public.operators(id);


--
-- Name: cash_movements fk_rails_c2e5b0cf6a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_movements
    ADD CONSTRAINT fk_rails_c2e5b0cf6a FOREIGN KEY (destination_cash_location_id) REFERENCES public.cash_locations(id);


--
-- Name: cash_variances fk_rails_c8210a0cc2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_variances
    ADD CONSTRAINT fk_rails_c8210a0cc2 FOREIGN KEY (approving_actor_id) REFERENCES public.operators(id);


--
-- Name: operating_units fk_rails_cd3fabf476; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operating_units
    ADD CONSTRAINT fk_rails_cd3fabf476 FOREIGN KEY (parent_operating_unit_id) REFERENCES public.operating_units(id);


--
-- Name: party_contact_audits fk_rails_d30b9f4b1f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_contact_audits
    ADD CONSTRAINT fk_rails_d30b9f4b1f FOREIGN KEY (party_record_id) REFERENCES public.party_records(id);


--
-- Name: journal_entries fk_rails_d329a9d82b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT fk_rails_d329a9d82b FOREIGN KEY (posting_batch_id) REFERENCES public.posting_batches(id);


--
-- Name: deposit_account_party_maintenance_audits fk_rails_d66a4f93d8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_account_party_maintenance_audits
    ADD CONSTRAINT fk_rails_d66a4f93d8 FOREIGN KEY (deposit_account_id) REFERENCES public.deposit_accounts(id);


--
-- Name: operational_events fk_rails_e1fee9a69d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operational_events
    ADD CONSTRAINT fk_rails_e1fee9a69d FOREIGN KEY (reversed_by_event_id) REFERENCES public.operational_events(id);


--
-- Name: journal_entries fk_rails_e2ae198c7f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT fk_rails_e2ae198c7f FOREIGN KEY (reverses_journal_entry_id) REFERENCES public.journal_entries(id);


--
-- Name: operational_events fk_rails_e664629e17; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operational_events
    ADD CONSTRAINT fk_rails_e664629e17 FOREIGN KEY (operating_unit_id) REFERENCES public.operating_units(id);


--
-- Name: journal_lines fk_rails_e8118864ce; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_lines
    ADD CONSTRAINT fk_rails_e8118864ce FOREIGN KEY (gl_account_id) REFERENCES public.gl_accounts(id);


--
-- Name: account_lifecycle_events fk_rails_e93f7f5f7a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_lifecycle_events
    ADD CONSTRAINT fk_rails_e93f7f5f7a FOREIGN KEY (actor_id) REFERENCES public.operators(id);


--
-- Name: holds fk_rails_ecf3d13b03; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.holds
    ADD CONSTRAINT fk_rails_ecf3d13b03 FOREIGN KEY (deposit_account_id) REFERENCES public.deposit_accounts(id);


--
-- Name: teller_sessions fk_rails_f16ba359ec; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teller_sessions
    ADD CONSTRAINT fk_rails_f16ba359ec FOREIGN KEY (cash_location_id) REFERENCES public.cash_locations(id);


--
-- Name: account_lifecycle_events fk_rails_f3616f8538; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_lifecycle_events
    ADD CONSTRAINT fk_rails_f3616f8538 FOREIGN KEY (operational_event_id) REFERENCES public.operational_events(id);


--
-- Name: operational_events fk_rails_f4a7a6dc52; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operational_events
    ADD CONSTRAINT fk_rails_f4a7a6dc52 FOREIGN KEY (destination_account_id) REFERENCES public.deposit_accounts(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260502215000'),
('20260502160000'),
('20260430120000'),
('20260429223000'),
('20260429210200'),
('20260429190000'),
('20260424120017'),
('20260424120016'),
('20260424120015'),
('20260424120014'),
('20260424120013'),
('20260424120012'),
('20260424120011'),
('20260424120010'),
('20260424120009'),
('20260424120008'),
('20260424120007'),
('20260424120006'),
('20260424120005'),
('20260424120004'),
('20260424120003'),
('20260424120002'),
('20260424120001'),
('20260424120000'),
('20260423120005'),
('20260423120004'),
('20260423120003'),
('20260423120002'),
('20260423120001'),
('20260423120000'),
('20260422130007'),
('20260422130005'),
('20260422130004'),
('20260422130003'),
('20260422130002'),
('20260422130001'),
('20260422120011'),
('20260422120010'),
('20260422120005'),
('20260422120004'),
('20260422120003'),
('20260422120002'),
('20260422120001');

