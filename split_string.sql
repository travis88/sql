CREATE OR REPLACE FUNCTION common.split_string(str character varying, _length integer)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$
DECLARE res CHARACTER VARYING; 
BEGIN
	str := trim(str);

	SELECT LEFT(LEFT(str, _length),
			_length - POSITION(' ' IN reverse(LEFT(str, _length))))
	INTO res;

	RETURN res;
END;
$function$
;
