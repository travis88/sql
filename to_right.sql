CREATE OR REPLACE FUNCTION common.to_right(str character varying, max_length integer)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$
DECLARE res CHARACTER VARYING;
BEGIN
	RETURN lpad(COALESCE(str, ' '), max_length);
END;
$function$
;
