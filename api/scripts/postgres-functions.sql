-- Shared expression functions preserve the existing ISO text dates in API JSON.
-- All instants are UTC. Business dates use the session's validated CRM zone.
CREATE FUNCTION business_offset() RETURNS text LANGUAGE sql STABLE AS $$
 SELECT CASE coalesce(current_setting('ecc.timezone',true),'Asia/Manila')
 WHEN 'UTC' THEN '0 minutes' ELSE '480 minutes' END
$$;

CREATE FUNCTION ecc_instant(VARIADIC args text[]) RETURNS timestamp
LANGUAGE plpgsql STABLE AS $$
DECLARE instant timestamp; modifier text; i integer;
BEGIN
 IF args[1] IS NULL THEN RETURN NULL; END IF;
 instant := CASE WHEN args[1]='now' THEN clock_timestamp() AT TIME ZONE 'UTC'
                 ELSE replace(args[1],'T',' ')::timestamp END;
 FOR i IN 2..coalesce(array_length(args,1),1) LOOP
  modifier:=args[i];
  IF modifier='start of month' THEN instant:=date_trunc('month',instant);
  ELSIF modifier='start of year' THEN instant:=date_trunc('year',instant);
  ELSIF modifier='start of day' THEN instant:=date_trunc('day',instant);
  ELSE instant:=instant+modifier::interval; END IF;
 END LOOP;
 RETURN instant;
END $$;

CREATE FUNCTION ecc_datetime(VARIADIC args text[]) RETURNS text LANGUAGE sql STABLE AS $$
 SELECT to_char(ecc_instant(VARIADIC args),'YYYY-MM-DD HH24:MI:SS')
$$;
CREATE FUNCTION ecc_date(VARIADIC args text[]) RETURNS text LANGUAGE sql STABLE AS $$
 SELECT to_char(ecc_instant(VARIADIC args),'YYYY-MM-DD')
$$;
CREATE FUNCTION ecc_strftime(pattern text, VARIADIC args text[]) RETURNS text LANGUAGE sql STABLE AS $$
 SELECT to_char(ecc_instant(VARIADIC args),replace(replace(replace(replace(replace(replace(replace(pattern,
 '%Y','YYYY'),'%m','MM'),'%d','DD'),'%H','HH24'),'%M','MI'),'%S','SS'),'T','"T"'))
$$;
CREATE FUNCTION ecc_julianday(VARIADIC args text[]) RETURNS numeric LANGUAGE sql STABLE AS $$
 SELECT extract(epoch FROM ecc_instant(VARIADIC args))/86400+2440587.5
$$;
CREATE FUNCTION ecc_printf(pattern text, value text) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
 IF value IS NULL THEN value:='0'; END IF;
 IF pattern='%.2f' THEN RETURN to_char(value::numeric,'FM999999999999999999999999999990.00');
 ELSIF pattern='%06d' THEN RETURN lpad(value,6,'0');
 ELSE RAISE EXCEPTION 'Unsupported numeric format' USING ERRCODE='22023'; END IF;
END $$;

CREATE FUNCTION ecc_printf(pattern text, value numeric) RETURNS text LANGUAGE sql IMMUTABLE AS $$
 SELECT ecc_printf(pattern,value::text)
$$;

CREATE FUNCTION ecc_json_valid(value text) RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN PERFORM value::jsonb; RETURN true; EXCEPTION WHEN invalid_text_representation THEN RETURN false; END $$;
CREATE FUNCTION ecc_json(value text) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$ SELECT value::jsonb $$;
CREATE FUNCTION ecc_json(value jsonb) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$ SELECT value $$;
CREATE FUNCTION ecc_json_extract(value jsonb, path text) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
 SELECT nullif(value #> string_to_array(substr(path,3),'.'),'null'::jsonb)
$$;
CREATE FUNCTION ecc_json_each(value text) RETURNS TABLE(key text,value jsonb) LANGUAGE sql IMMUTABLE AS $$
 SELECT k,v FROM jsonb_each(CASE WHEN jsonb_typeof(value::jsonb)='object' THEN value::jsonb ELSE '{}'::jsonb END) t(k,v)
 UNION ALL
 SELECT (n-1)::text,v FROM jsonb_array_elements(CASE WHEN jsonb_typeof(value::jsonb)='array' THEN value::jsonb ELSE '[]'::jsonb END) WITH ORDINALITY t(v,n)
$$;
CREATE FUNCTION ecc_json_each(value jsonb) RETURNS TABLE(key text,value jsonb) LANGUAGE sql IMMUTABLE AS $$
 SELECT * FROM ecc_json_each(value::text)
$$;
CREATE FUNCTION ecc_json_array_step(state jsonb, value jsonb) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
 SELECT state || jsonb_build_array(value)
$$;
CREATE AGGREGATE ecc_json_group_array(jsonb) (SFUNC=ecc_json_array_step,STYPE=jsonb,INITCOND='[]');
CREATE FUNCTION ecc_sum_bool(state bigint, value boolean) RETURNS bigint LANGUAGE sql IMMUTABLE AS $$
 SELECT state + CASE WHEN value THEN 1 ELSE 0 END
$$;
CREATE AGGREGATE sum(boolean) (SFUNC=ecc_sum_bool,STYPE=bigint,INITCOND='0');

-- Each statement takes the same transaction lock as API mutations. This also
-- covers workers and direct SQL, preserving cross-row ledger/revision rules.
CREATE FUNCTION ecc_write_lock() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN PERFORM pg_advisory_xact_lock(1162036050); RETURN NULL; END $$;
