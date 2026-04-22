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
  IF TG_OP = 'UPDATE' OR TG_OP = 'DELETE' THEN
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
    updated_at timestamp(6) without time zone NOT NULL
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
-- Name: gl_accounts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gl_accounts ALTER COLUMN id SET DEFAULT nextval('public.gl_accounts_id_seq'::regclass);


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
-- Name: posting_batches id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posting_batches ALTER COLUMN id SET DEFAULT nextval('public.posting_batches_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: gl_accounts gl_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gl_accounts
    ADD CONSTRAINT gl_accounts_pkey PRIMARY KEY (id);


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
-- Name: index_gl_accounts_on_account_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_gl_accounts_on_account_number ON public.gl_accounts USING btree (account_number);


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
-- Name: index_operational_events_on_idempotency_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_operational_events_on_idempotency_key ON public.operational_events USING btree (idempotency_key);


--
-- Name: index_posting_batches_on_operational_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_posting_batches_on_operational_event_id ON public.posting_batches USING btree (operational_event_id);


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
-- Name: posting_batches fk_rails_1a3b38f450; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posting_batches
    ADD CONSTRAINT fk_rails_1a3b38f450 FOREIGN KEY (operational_event_id) REFERENCES public.operational_events(id);


--
-- Name: journal_entries fk_rails_3417d84ffc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT fk_rails_3417d84ffc FOREIGN KEY (reversing_journal_entry_id) REFERENCES public.journal_entries(id);


--
-- Name: journal_entries fk_rails_7f9a73cda9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT fk_rails_7f9a73cda9 FOREIGN KEY (operational_event_id) REFERENCES public.operational_events(id);


--
-- Name: journal_lines fk_rails_92eda40cad; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_lines
    ADD CONSTRAINT fk_rails_92eda40cad FOREIGN KEY (journal_entry_id) REFERENCES public.journal_entries(id);


--
-- Name: journal_entries fk_rails_d329a9d82b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT fk_rails_d329a9d82b FOREIGN KEY (posting_batch_id) REFERENCES public.posting_batches(id);


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
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260422120010'),
('20260422120005'),
('20260422120004'),
('20260422120003'),
('20260422120002'),
('20260422120001');

