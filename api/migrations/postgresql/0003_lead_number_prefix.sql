-- Keep the internal L counter separate from the student ECC counter.
-- Preserve each lead's year and sequence, including archived and converted leads.
UPDATE leads SET lead_number='ECC-'||substr(lead_number,3)
WHERE lead_number ~ '^L-[0-9]{4}-[0-9]+$';

INSERT INTO reference_counters(prefix,year,value)
SELECT 'L',CAST(substr(lead_number,5,4) AS INTEGER),max(CAST(substr(lead_number,10) AS BIGINT))
FROM leads WHERE lead_number ~ '^ECC-[0-9]{4}-[0-9]+$'
GROUP BY 2
ON CONFLICT(prefix,year) DO UPDATE SET value=greatest(reference_counters.value,excluded.value);
