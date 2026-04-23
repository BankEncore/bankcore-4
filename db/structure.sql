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
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


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
-- Name: deposit_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposit_accounts (
    id bigint NOT NULL,
    account_number character varying NOT NULL,
    currency character varying DEFAULT 'USD'::character varying NOT NULL,
    status character varying NOT NULL,
    product_code character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
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
    CONSTRAINT holds_amount_positive CHECK ((amount_minor_units > 0)),
    CONSTRAINT holds_status_enum CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'released'::character varying, 'expired'::character varying])::text[])))
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
    CONSTRAINT journal_lines_side_enum CHECK (((side)::text = ANY ((ARRAY['debit'::character varying, 'credit'::character varying])::text[])))
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
    actor_id bigint
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
-- Name: operators; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.operators (
    id bigint NOT NULL,
    role character varying NOT NULL,
    display_name character varying,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT operators_role_check CHECK (((role)::text = ANY ((ARRAY['teller'::character varying, 'supervisor'::character varying])::text[])))
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
    CONSTRAINT teller_sessions_status_enum CHECK (((status)::text = ANY ((ARRAY['open'::character varying, 'closed'::character varying, 'pending_supervisor'::character varying])::text[])))
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
-- Name: core_business_date_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.core_business_date_settings ALTER COLUMN id SET DEFAULT nextval('public.core_business_date_settings_id_seq'::regclass);


--
-- Name: deposit_account_parties id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_account_parties ALTER COLUMN id SET DEFAULT nextval('public.deposit_account_parties_id_seq'::regclass);


--
-- Name: deposit_accounts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_accounts ALTER COLUMN id SET DEFAULT nextval('public.deposit_accounts_id_seq'::regclass);


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
-- Name: operational_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operational_events ALTER COLUMN id SET DEFAULT nextval('public.operational_events_id_seq'::regclass);


--
-- Name: operators id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operators ALTER COLUMN id SET DEFAULT nextval('public.operators_id_seq'::regclass);


--
-- Name: party_individual_profiles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_individual_profiles ALTER COLUMN id SET DEFAULT nextval('public.party_individual_profiles_id_seq'::regclass);


--
-- Name: party_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_records ALTER COLUMN id SET DEFAULT nextval('public.party_records_id_seq'::regclass);


--
-- Name: posting_batches id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posting_batches ALTER COLUMN id SET DEFAULT nextval('public.posting_batches_id_seq'::regclass);


--
-- Name: teller_sessions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teller_sessions ALTER COLUMN id SET DEFAULT nextval('public.teller_sessions_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: core_business_date_settings core_business_date_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.core_business_date_settings
    ADD CONSTRAINT core_business_date_settings_pkey PRIMARY KEY (id);


--
-- Name: deposit_account_parties deposit_account_parties_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_account_parties
    ADD CONSTRAINT deposit_account_parties_pkey PRIMARY KEY (id);


--
-- Name: deposit_accounts deposit_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_accounts
    ADD CONSTRAINT deposit_accounts_pkey PRIMARY KEY (id);


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
-- Name: operational_events operational_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operational_events
    ADD CONSTRAINT operational_events_pkey PRIMARY KEY (id);


--
-- Name: operators operators_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operators
    ADD CONSTRAINT operators_pkey PRIMARY KEY (id);


--
-- Name: party_individual_profiles party_individual_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_individual_profiles
    ADD CONSTRAINT party_individual_profiles_pkey PRIMARY KEY (id);


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
-- Name: index_dap_unique_open_active_per_account_party_role; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_dap_unique_open_active_per_account_party_role ON public.deposit_account_parties USING btree (deposit_account_id, party_record_id, role) WHERE (((status)::text = 'active'::text) AND (ended_on IS NULL));


--
-- Name: index_deposit_account_parties_on_deposit_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_deposit_account_parties_on_deposit_account_id ON public.deposit_account_parties USING btree (deposit_account_id);


--
-- Name: index_deposit_account_parties_on_party_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_deposit_account_parties_on_party_record_id ON public.deposit_account_parties USING btree (party_record_id);


--
-- Name: index_deposit_accounts_on_account_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_deposit_accounts_on_account_number ON public.deposit_accounts USING btree (account_number);


--
-- Name: index_gl_accounts_on_account_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_gl_accounts_on_account_number ON public.gl_accounts USING btree (account_number);


--
-- Name: index_holds_on_deposit_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_holds_on_deposit_account_id ON public.holds USING btree (deposit_account_id);


--
-- Name: index_holds_on_placed_by_operational_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_holds_on_placed_by_operational_event_id ON public.holds USING btree (placed_by_operational_event_id);


--
-- Name: index_holds_on_released_by_operational_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_holds_on_released_by_operational_event_id ON public.holds USING btree (released_by_operational_event_id);


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
-- Name: index_operational_events_on_channel_and_idempotency_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_operational_events_on_channel_and_idempotency_key ON public.operational_events USING btree (channel, idempotency_key);


--
-- Name: index_operational_events_on_destination_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_operational_events_on_destination_account_id ON public.operational_events USING btree (destination_account_id);


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
-- Name: index_party_individual_profiles_on_party_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_party_individual_profiles_on_party_record_id ON public.party_individual_profiles USING btree (party_record_id);


--
-- Name: index_posting_batches_on_operational_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_posting_batches_on_operational_event_id ON public.posting_batches USING btree (operational_event_id);


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
-- Name: deposit_account_parties fk_rails_0245a491be; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_account_parties
    ADD CONSTRAINT fk_rails_0245a491be FOREIGN KEY (party_record_id) REFERENCES public.party_records(id);


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
-- Name: party_individual_profiles fk_rails_22a835d5da; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_individual_profiles
    ADD CONSTRAINT fk_rails_22a835d5da FOREIGN KEY (party_record_id) REFERENCES public.party_records(id);


--
-- Name: operational_events fk_rails_29073cc426; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operational_events
    ADD CONSTRAINT fk_rails_29073cc426 FOREIGN KEY (teller_session_id) REFERENCES public.teller_sessions(id);


--
-- Name: journal_lines fk_rails_2b0c279a73; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_lines
    ADD CONSTRAINT fk_rails_2b0c279a73 FOREIGN KEY (deposit_account_id) REFERENCES public.deposit_accounts(id);


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
-- Name: holds fk_rails_4c0c5bf773; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.holds
    ADD CONSTRAINT fk_rails_4c0c5bf773 FOREIGN KEY (placed_by_operational_event_id) REFERENCES public.operational_events(id);


--
-- Name: journal_entries fk_rails_7f9a73cda9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT fk_rails_7f9a73cda9 FOREIGN KEY (operational_event_id) REFERENCES public.operational_events(id);


--
-- Name: teller_sessions fk_rails_86b8203f6d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teller_sessions
    ADD CONSTRAINT fk_rails_86b8203f6d FOREIGN KEY (supervisor_operator_id) REFERENCES public.operators(id);


--
-- Name: operational_events fk_rails_8cf89c2939; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operational_events
    ADD CONSTRAINT fk_rails_8cf89c2939 FOREIGN KEY (reversal_of_event_id) REFERENCES public.operational_events(id);


--
-- Name: journal_lines fk_rails_92eda40cad; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_lines
    ADD CONSTRAINT fk_rails_92eda40cad FOREIGN KEY (journal_entry_id) REFERENCES public.journal_entries(id);


--
-- Name: operational_events fk_rails_a650da481b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operational_events
    ADD CONSTRAINT fk_rails_a650da481b FOREIGN KEY (actor_id) REFERENCES public.operators(id);


--
-- Name: deposit_account_parties fk_rails_bf2b31365a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_account_parties
    ADD CONSTRAINT fk_rails_bf2b31365a FOREIGN KEY (deposit_account_id) REFERENCES public.deposit_accounts(id);


--
-- Name: journal_entries fk_rails_d329a9d82b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT fk_rails_d329a9d82b FOREIGN KEY (posting_batch_id) REFERENCES public.posting_batches(id);


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
-- Name: journal_lines fk_rails_e8118864ce; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_lines
    ADD CONSTRAINT fk_rails_e8118864ce FOREIGN KEY (gl_account_id) REFERENCES public.gl_accounts(id);


--
-- Name: holds fk_rails_ecf3d13b03; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.holds
    ADD CONSTRAINT fk_rails_ecf3d13b03 FOREIGN KEY (deposit_account_id) REFERENCES public.deposit_accounts(id);


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

