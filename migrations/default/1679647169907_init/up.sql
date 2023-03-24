SET check_function_bodies = false;
CREATE SCHEMA IF NOT EXISTS hdb_catalog;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;
COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';
CREATE OR REPLACE FUNCTION hdb_catalog.gen_hasura_uuid() RETURNS uuid
    LANGUAGE sql
    AS $$select gen_random_uuid()$$;
CREATE OR REPLACE FUNCTION public."set_current_timestamp_updatedAt"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updatedAt" = NOW();
  RETURN _new;
END;
$$;
CREATE TABLE IF NOT EXISTS hdb_catalog.hdb_action_log (
    id uuid DEFAULT hdb_catalog.gen_hasura_uuid() NOT NULL,
    action_name text,
    input_payload jsonb NOT NULL,
    request_headers jsonb NOT NULL,
    session_variables jsonb NOT NULL,
    response_payload jsonb,
    errors jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    response_received_at timestamp with time zone,
    status text NOT NULL,
    CONSTRAINT hdb_action_log_status_check CHECK ((status = ANY (ARRAY['created'::text, 'processing'::text, 'completed'::text, 'error'::text])))
);
CREATE TABLE IF NOT EXISTS hdb_catalog.hdb_cron_event_invocation_logs (
    id text DEFAULT hdb_catalog.gen_hasura_uuid() NOT NULL,
    event_id text,
    status integer,
    request json,
    response json,
    created_at timestamp with time zone DEFAULT now()
);
CREATE TABLE IF NOT EXISTS hdb_catalog.hdb_cron_events (
    id text DEFAULT hdb_catalog.gen_hasura_uuid() NOT NULL,
    trigger_name text NOT NULL,
    scheduled_time timestamp with time zone NOT NULL,
    status text DEFAULT 'scheduled'::text NOT NULL,
    tries integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    next_retry_at timestamp with time zone,
    CONSTRAINT valid_status CHECK ((status = ANY (ARRAY['scheduled'::text, 'locked'::text, 'delivered'::text, 'error'::text, 'dead'::text])))
);
CREATE TABLE IF NOT EXISTS hdb_catalog.hdb_metadata (
    id integer NOT NULL,
    metadata json NOT NULL,
    resource_version integer DEFAULT 1 NOT NULL
);
CREATE TABLE IF NOT EXISTS hdb_catalog.hdb_scheduled_event_invocation_logs (
    id text DEFAULT hdb_catalog.gen_hasura_uuid() NOT NULL,
    event_id text,
    status integer,
    request json,
    response json,
    created_at timestamp with time zone DEFAULT now()
);
CREATE TABLE IF NOT EXISTS hdb_catalog.hdb_scheduled_events (
    id text DEFAULT hdb_catalog.gen_hasura_uuid() NOT NULL,
    webhook_conf json NOT NULL,
    scheduled_time timestamp with time zone NOT NULL,
    retry_conf json,
    payload json,
    header_conf json,
    status text DEFAULT 'scheduled'::text NOT NULL,
    tries integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    next_retry_at timestamp with time zone,
    comment text,
    CONSTRAINT valid_status CHECK ((status = ANY (ARRAY['scheduled'::text, 'locked'::text, 'delivered'::text, 'error'::text, 'dead'::text])))
);
CREATE TABLE IF NOT EXISTS hdb_catalog.hdb_schema_notifications (
    id integer NOT NULL,
    notification json NOT NULL,
    resource_version integer DEFAULT 1 NOT NULL,
    instance_id uuid NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT hdb_schema_notifications_id_check CHECK ((id = 1))
);
CREATE TABLE IF NOT EXISTS hdb_catalog.hdb_version (
    hasura_uuid uuid DEFAULT hdb_catalog.gen_hasura_uuid() NOT NULL,
    version text NOT NULL,
    upgraded_on timestamp with time zone NOT NULL,
    cli_state jsonb DEFAULT '{}'::jsonb NOT NULL,
    console_state jsonb DEFAULT '{}'::jsonb NOT NULL
);
CREATE TABLE public.audit (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    "createdAt" timestamp with time zone DEFAULT now() NOT NULL,
    "updatedAt" timestamp with time zone DEFAULT now() NOT NULL,
    "operationType" text NOT NULL,
    "healthRecordId" uuid NOT NULL,
    "newRecord" jsonb,
    "oldRecord" uuid,
    "organizationId" uuid,
    "modifiedByUser" uuid,
    "userRole" text
);
COMMENT ON TABLE public.audit IS 'Audit and review trails for the health records';
CREATE TABLE public.health_records (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    "createdAt" timestamp with time zone DEFAULT now() NOT NULL,
    "updatedAt" timestamp with time zone DEFAULT now() NOT NULL,
    "recordType" text NOT NULL,
    "recordData" jsonb,
    "organizationId" uuid,
    patient uuid,
    env text
);
COMMENT ON TABLE public.health_records IS 'Patient Health Records';
-- ALTER TABLE ONLY hdb_catalog.hdb_action_log ADD CONSTRAINT hdb_action_log_pkey PRIMARY KEY (id) ON CONFLICT DO NOTHING;
-- ALTER TABLE ONLY hdb_catalog.hdb_cron_event_invocation_logs
--     ADD CONSTRAINT hdb_cron_event_invocation_logs_pkey PRIMARY KEY (id);
-- ALTER TABLE ONLY hdb_catalog.hdb_cron_events
--     ADD CONSTRAINT hdb_cron_events_pkey PRIMARY KEY (id);
-- ALTER TABLE ONLY hdb_catalog.hdb_metadata
--     ADD CONSTRAINT hdb_metadata_pkey PRIMARY KEY (id);
-- ALTER TABLE ONLY hdb_catalog.hdb_metadata
--     ADD CONSTRAINT hdb_metadata_resource_version_key UNIQUE (resource_version);
-- ALTER TABLE ONLY hdb_catalog.hdb_scheduled_event_invocation_logs
--     ADD CONSTRAINT hdb_scheduled_event_invocation_logs_pkey PRIMARY KEY (id);
-- ALTER TABLE ONLY hdb_catalog.hdb_scheduled_events
--     ADD CONSTRAINT hdb_scheduled_events_pkey PRIMARY KEY (id);
-- ALTER TABLE ONLY hdb_catalog.hdb_schema_notifications
--     ADD CONSTRAINT hdb_schema_notifications_pkey PRIMARY KEY (id);
-- ALTER TABLE ONLY hdb_catalog.hdb_version
--     ADD CONSTRAINT hdb_version_pkey PRIMARY KEY (hasura_uuid);
ALTER TABLE ONLY public.audit
    ADD CONSTRAINT audit_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.health_records
    ADD CONSTRAINT health_records_pkey PRIMARY KEY (id);
CREATE INDEX IF NOT EXISTS hdb_cron_event_invocation_event_id ON hdb_catalog.hdb_cron_event_invocation_logs USING btree (event_id);
CREATE INDEX IF NOT EXISTS hdb_cron_event_status ON hdb_catalog.hdb_cron_events USING btree (status);
CREATE UNIQUE INDEX IF NOT EXISTS hdb_cron_events_unique_scheduled ON hdb_catalog.hdb_cron_events USING btree (trigger_name, scheduled_time) WHERE (status = 'scheduled'::text);
CREATE INDEX IF NOT EXISTS hdb_scheduled_event_status ON hdb_catalog.hdb_scheduled_events USING btree (status);
CREATE UNIQUE INDEX IF NOT EXISTS hdb_version_one_row ON hdb_catalog.hdb_version USING btree (((version IS NOT NULL)));
CREATE TRIGGER "set_public_audit_updatedAt" BEFORE UPDATE ON public.audit FOR EACH ROW EXECUTE PROCEDURE public."set_current_timestamp_updatedAt"();
COMMENT ON TRIGGER "set_public_audit_updatedAt" ON public.audit IS 'trigger to set value of column "updatedAt" to current timestamp on row update';
CREATE TRIGGER "set_public_health_records_updatedAt" BEFORE UPDATE ON public.health_records FOR EACH ROW EXECUTE PROCEDURE public."set_current_timestamp_updatedAt"();
COMMENT ON TRIGGER "set_public_health_records_updatedAt" ON public.health_records IS 'trigger to set value of column "updatedAt" to current timestamp on row update';
-- ALTER TABLE ONLY hdb_catalog.hdb_cron_event_invocation_logs
--     ADD CONSTRAINT hdb_cron_event_invocation_logs_event_id_fkey FOREIGN KEY (event_id) REFERENCES hdb_catalog.hdb_cron_events(id) ON UPDATE CASCADE ON DELETE CASCADE;
-- ALTER TABLE ONLY hdb_catalog.hdb_scheduled_event_invocation_logs
--     ADD CONSTRAINT hdb_scheduled_event_invocation_logs_event_id_fkey FOREIGN KEY (event_id) REFERENCES hdb_catalog.hdb_scheduled_events(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY public.audit
    ADD CONSTRAINT "audit_healthRecordId_fkey" FOREIGN KEY ("healthRecordId") REFERENCES public.health_records(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE ONLY public.audit
    ADD CONSTRAINT "audit_oldRecord_fkey" FOREIGN KEY ("oldRecord") REFERENCES public.audit(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
