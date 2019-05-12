CREATE OR REPLACE FUNCTION common.to_left(prefix character varying, str character varying, max_length integer)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$
DECLARE res CHARACTER VARYING := ''; -- результат
		pref_len integer := length(prefix); -- длина префикса
		str_len integer := length(str); -- длина строки
		_str CHARACTER VARYING := str; -- редактируемая строка
		_counter integer := 0; -- счётчик
BEGIN
	IF pref_len + str_len > max_length THEN
		LOOP 
			_str := (SELECT common.split_string(_str, max_length - pref_len, FALSE));
			IF _counter > 0 THEN
				prefix := lpad('', pref_len, ' ');
			END IF;
			_counter := _counter + length(_str);
			res := res || prefix || trim(_str) || chr(10);
			_str := right(str, str_len - _counter);
			IF _counter >= str_len THEN
				EXIT;
			END IF;
		END LOOP;
	ELSE 
		res := rpad(COALESCE(prefix || str, ' '), max_length);
	END IF;
	RETURN res;
END;
$function$
;
