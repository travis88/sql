CREATE OR REPLACE FUNCTION common.to_left(prefix character varying, str character varying, max_length integer)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$
DECLARE res CHARACTER VARYING := ''; -- результат
		pref_len integer := length(prefix); -- длина префикса
		str_len integer := length(str); -- длина строки
		_str CHARACTER VARYING := prefix || str; -- редактируемая строка
		_res_counter CHARACTER VARYING := ''; -- конкатенируемая строка для проверки
		_counter integer := 0; -- счётчик
BEGIN
	IF pref_len + str_len > max_length THEN
		LOOP 
			_str := (SELECT common.split_string(_str, max_length - pref_len, FALSE));
			_res_counter := _res_counter || _str;
			res := res || _str || chr(10);
			
			IF length(_res_counter) >= pref_len + str_len THEN
				EXIT;
			END IF;
			_counter := _counter + length(_str);
			_str := ltrim(RIGHT(prefix || str, length(prefix || str) - length(_res_counter)));
--			_str := ltrim(RIGHT(str, length(str) - length(_res_counter) - pref_len));
			_str := rpad(lpad(_str, pref_len + length(_str), ' '), max_length, ' ');
		END LOOP;
	ELSE 
		res := rpad(COALESCE(prefix || str, ' '), max_length);
	END IF;
	RETURN res;
END;
$function$
;
