CREATE OR REPLACE FUNCTION common.to_left(str character varying, max_length integer)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$
DECLARE res CHARACTER VARYING;
BEGIN
	RETURN rpad(COALESCE(str, ' '), max_length);
END;
$function$
;
